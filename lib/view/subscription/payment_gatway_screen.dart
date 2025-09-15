import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:get/get.dart';
import 'package:prime_leads/model/subscription/get_subscription_response.dart';
import 'package:prime_leads/utility/app_routes.dart';
import 'package:prime_leads/utility/app_utility.dart';

class RazorpayGateway extends StatefulWidget {
  final num totalPayable;
  final String subscriptionId;
  final num finalOrderPrice;

  const RazorpayGateway({
    super.key,
    required this.totalPayable,
    required this.subscriptionId,
    required this.finalOrderPrice,
  });

  @override
  State<RazorpayGateway> createState() => _RazorpayGatewayState();
}

class _RazorpayGatewayState extends State<RazorpayGateway> {
  late Razorpay _razorpay;

  // Test Credentials (Replace with production credentials as needed)
  // final String _keyId = 'rzp_live_R7zacfGtzhXGgs';
  // final String _keySecret = 'uJvnRhRllfqNuqqticemkVKX';
  final String _keyId = 'rzp_test_R7Swkdhjyig54S';
  final String _keySecret = 'jS36wByFlnpeVgyEicfK2AFb';

  String transactionId = "RT${DateTime.now().millisecondsSinceEpoch}";

  @override
  void initState() {
    super.initState();
    debugPrint('[RazorpayGateway] Initializing with:');
    debugPrint('[RazorpayGateway] totalPayable: ${widget.totalPayable}');
    debugPrint('[RazorpayGateway] subscriptionId: ${widget.subscriptionId}');
    debugPrint('[RazorpayGateway] finalOrderPrice: ${widget.finalOrderPrice}');
    debugPrint('[RazorpayGateway] transactionId: $transactionId');
    _initializeRazorpay();
    _createOrder();
  }

  void _initializeRazorpay() {
    debugPrint('[RazorpayGateway] Initializing Razorpay');
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  Future<void> _createOrder() async {
    try {
      // Validate amount
      if (widget.finalOrderPrice < 1) {
        debugPrint(
          '[RazorpayGateway] Error: finalOrderPrice (${widget.finalOrderPrice}) is less than minimum allowed (₹1.00)',
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showErrorSnackBar('Invalid amount: Minimum ₹1.00 required');
        });
        return;
      }

      final authString = base64Encode(utf8.encode('$_keyId:$_keySecret'));
      debugPrint('[RazorpayGateway] Auth String: $authString');

      final amountInPaise = (widget.finalOrderPrice * 100).toInt();
      debugPrint(
        '[RazorpayGateway] Sending amount to Razorpay: $amountInPaise paise (₹${widget.finalOrderPrice})',
      );

      final response = await http.post(
        Uri.parse('https://api.razorpay.com/v1/orders'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic $authString',
        },
        body: jsonEncode({
          'amount': amountInPaise,
          'currency': 'INR',
          'receipt': transactionId,
          'payment_capture': 1,
        }),
      );

      debugPrint(
        '[RazorpayGateway] Response Status Code: ${response.statusCode}',
      );
      debugPrint('[RazorpayGateway] Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final orderData = jsonDecode(response.body);
        debugPrint(
          '[RazorpayGateway] Order created successfully: ${orderData['id']}',
        );
        _openCheckout(orderData['id']);
      } else {
        debugPrint('[RazorpayGateway] Order creation failed: ${response.body}');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showErrorSnackBar('Order creation failed: ${response.body}');
        });
      }
    } catch (e) {
      debugPrint('[RazorpayGateway] Error creating order: $e');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showErrorSnackBar('Error creating order: $e');
      });
    }
  }

  void _openCheckout(String orderId) {
    final amountInPaise = (widget.finalOrderPrice * 100).toInt();
    debugPrint(
      '[RazorpayGateway] Opening checkout with orderId: $orderId, amount: $amountInPaise paise',
    );

    var options = {
      'key': _keyId,
      'amount': amountInPaise,
      'name': 'Prime Leads',
      'description': 'Payment for Subscription Package',
      'order_id': orderId,
      'prefill': {'contact': AppUtility.mobileNumber ?? '', 'email': ''},
      'theme': {'color': '#00A89F'},
    };

    try {
      _razorpay.open(options);
      debugPrint('[RazorpayGateway] Razorpay checkout opened');
    } catch (e) {
      debugPrint('[RazorpayGateway] Error opening Razorpay checkout: $e');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showErrorSnackBar('Error opening checkout: $e');
      });
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    debugPrint('[RazorpayGateway] Payment Success: ${response.paymentId}');
    debugPrint('[RazorpayGateway] Navigating to payment receipt with:');
    debugPrint('[RazorpayGateway] transactionId: $transactionId');
    debugPrint('[RazorpayGateway] subscriptionId: ${widget.subscriptionId}');
    debugPrint('[RazorpayGateway] amount: ${widget.finalOrderPrice}');
    Get.toNamed(
      AppRoutes.paymentRieceipt,
      arguments: {
        'transactionId': transactionId,
        'subscriptionId': widget.subscriptionId,
        'amount': widget.finalOrderPrice,
      },
    );
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    debugPrint(
      '[RazorpayGateway] Payment Error: ${response.code} | ${response.message}',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showErrorSnackBar(response.message ?? "Payment failed");
    });
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint(
      '[RazorpayGateway] External Wallet Selected: ${response.walletName}',
    );
  }

  void _showErrorSnackBar(String message) {
    debugPrint('[RazorpayGateway] Showing error snackbar: $message');
    Get.snackbar(
      'Payment Error',
      message,
      backgroundColor: Colors.red,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
    );
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    debugPrint('[RazorpayGateway] Disposing RazorpayGateway');
    _razorpay.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Processing Payment...'),
          ],
        ),
      ),
    );
  }
}
