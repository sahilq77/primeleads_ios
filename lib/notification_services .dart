import 'dart:math';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:prime_leads/controller/bottomnavigation/bottom_navigation_controller.dart';
import 'package:prime_leads/utility/app_routes.dart';
import 'package:prime_leads/utility/app_utility.dart';
import 'package:rxdart/rxdart.dart';
import 'dart:developer' as lg;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';

class NotificationServices {
  String? callId;
  FirebaseMessaging firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static final onNotifications = BehaviorSubject<String?>();

  // Initialize local notifications once during app startup
  Future<void> initLocalNotifications() async {
    try {
      const androidInitialization = AndroidInitializationSettings(
        '@mipmap/launcher_icon',
      );
      const iosInitialization = DarwinInitializationSettings();
      const initializationSettings = InitializationSettings(
        android: androidInitialization,
        iOS: iosInitialization,
      );

      await flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (response) {
          if (response.payload != null) {
            onNotifications.add(response.payload);
          }
        },
      );
      lg.log('Local notifications initialized successfully');
    } catch (e) {
      lg.log('Error initializing local notifications: $e');
    }
  }

  // Request notification permissions
  Future<void> requestNotificationPermission() async {
    try {
      NotificationSettings settings = await firebaseMessaging.requestPermission(
        alert: true,
        announcement: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        lg.log('User granted permission');
      } else if (settings.authorizationStatus ==
          AuthorizationStatus.provisional) {
        lg.log('User granted provisional permission');
      } else {
        lg.log('User declined or has not accepted permission');
      }
    } catch (e) {
      lg.log('Error requesting notification permission: $e');
    }
  }

  // Initialize Firebase messaging and handle foreground notifications
  void firebaseInit(BuildContext? context) {
    try {
      FirebaseMessaging.onMessage.listen((message) {
        lg.log('Received foreground message: ${message.data}');
        if (message.notification != null || message.data.isNotEmpty) {
          showNotification(message);
          if (context != null) {
            handleRemoteMessage(context, message);
          } else {
            lg.log('Context is null, skipping navigation');
          }
        }
      });
    } catch (e) {
      lg.log('Error in firebaseInit: $e');
    }
  }

  // Download image from URL
  Future<Uint8List?> loadImageFromUrl(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        throw Exception('Failed to load image from URL');
      }
    } catch (e) {
      lg.log('Error loading image: $e');
      return null;
    }
  }

  // Save image to file
  Future<String?> saveImageToFile(Uint8List bytes, String filename) async {
    try {
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/$filename';
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      return filePath;
    } catch (e) {
      lg.log('Error saving image: $e');
      return null;
    }
  }

  // Show local notification for foreground messages
  Future<void> showNotification(RemoteMessage message) async {
    try {
      const channel = AndroidNotificationChannel(
        'text_channel_id', // Use a fixed channel ID
        'Text Channel',
        description: 'Your channel description',
        importance: Importance.high,
      );

      // Create the notification channel
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);

      // Fetch and log image URL from message data
      String? imageUrl = message.data['image_url'];
      lg.log('Image URL: $imageUrl'); // Log the image URL

      String? imagePath;

      AndroidNotificationDetails androidNotificationDetails;
      if (imageUrl != null && imageUrl.isNotEmpty) {
        lg.log('Attempting to download image from: $imageUrl');
        // Download and save the image
        Uint8List? imageBytes = await loadImageFromUrl(imageUrl);
        if (imageBytes != null) {
          lg.log(
            'Image downloaded successfully, size: ${imageBytes.length} bytes',
          );
          imagePath = await saveImageToFile(
            imageBytes,
            'notification_image_${Random().nextInt(10000)}.jpg', // Unique filename
          );
          if (imagePath != null) {
            lg.log('Image saved to: $imagePath');
            androidNotificationDetails = AndroidNotificationDetails(
              'text_channel_id',
              'Text Channel',
              channelDescription: 'Your channel description',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              styleInformation: BigPictureStyleInformation(
                FilePathAndroidBitmap(imagePath),
                hideExpandedLargeIcon: true,
              ),
              ticker: 'ticker',
            );
          } else {
            lg.log('Failed to save image to file');
            androidNotificationDetails = const AndroidNotificationDetails(
              'text_channel_id',
              'Text Channel',
              channelDescription: 'Your channel description',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              styleInformation: BigTextStyleInformation(''),
              ticker: 'ticker',
            );
          }
        } else {
          lg.log('Failed to download image from URL');
          androidNotificationDetails = const AndroidNotificationDetails(
            'text_channel_id',
            'Text Channel',
            channelDescription: 'Your channel description',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            styleInformation: BigTextStyleInformation(''),
            ticker: 'ticker',
          );
        }
      } else {
        lg.log('No image URL provided in message data');
        androidNotificationDetails = const AndroidNotificationDetails(
          'text_channel_id',
          'Text Channel',
          channelDescription: 'Your channel description',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          styleInformation: BigTextStyleInformation(''),
          ticker: 'ticker',
        );
      }

      DarwinNotificationDetails darwinNotificationDetails;
      if (imagePath != null) {
        lg.log('Adding image attachment for iOS: $imagePath');
        darwinNotificationDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          attachments: [DarwinNotificationAttachment(imagePath)],
        );
      } else {
        lg.log('No image attachment for iOS');
        darwinNotificationDetails = const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        );
      }

      NotificationDetails notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: darwinNotificationDetails,
      );

      // Fetch title and body, prioritizing `message.notification`
      String? title = message.notification?.title ?? message.data['title'];
      String? body = message.notification?.body ?? message.data['body'];
      lg.log('Notification title: $title, body: $body'); // Log title and body

      // Display the notification if title or body is not null
      if (title != null || body != null) {
        await flutterLocalNotificationsPlugin.show(
          Random().nextInt(
            10000,
          ), // Use a random ID to avoid notification overwrite
          title ?? 'No Title',
          body ?? 'No Body',
          notificationDetails,
          payload: message.data['page_link']?.toString() ?? '',
        );
        lg.log('Notification shown: $title - $body');
      } else {
        lg.log('No title or body provided, skipping notification');
      }
    } catch (e) {
      lg.log('Error showing notification: $e');
    }
  }

  // Get FCM device token
  Future<String> getDevicetoken() async {
    try {
      String? token = await firebaseMessaging.getToken();
      lg.log('Device token: $token');
      return token ?? '';
    } catch (e) {
      lg.log('Error getting device token: $e');
      return '';
    }
  }

  // Handle token refresh
  void isTokenRefresh() {
    try {
      firebaseMessaging.onTokenRefresh.listen((token) {
        lg.log('Token refreshed: $token');
      });
    } catch (e) {
      lg.log('Error in token refresh: $e');
    }
  }

  // Handle notifications when app is terminated or in background
  Future<void> setInteractMessage(BuildContext context) async {
    try {
      // Handle app terminated state
      RemoteMessage? initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        lg.log('Handling initial message: ${initialMessage.data}');
        handleRemoteMessage(context, initialMessage);
      }

      // Handle app in background state
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        lg.log('Handling background message: ${message.data}');
        handleRemoteMessage(context, message);
      });
    } catch (e) {
      lg.log('Error in setInteractMessage: $e');
    }
  }

  // Handle navigation based on notification data
  void handleRemoteMessage(BuildContext context, RemoteMessage message) {
    try {
      BottomNavigationController controller = Get.put(
        BottomNavigationController(),
      );
      lg.log('Controller initialized: ${controller.selectedIndex}');

      String landingPage =
          message.data['page_link']?.toString().toLowerCase() ?? 'default';
      String batchId = message.data['batch_id']?.toString() ?? '';
      String body = message.data['body']?.toString() ?? '';

      RegExp regex = RegExp(r"result for '([^']*)'");
      Match? match = regex.firstMatch(body);
      String examName = match?.group(1) ?? '';

      lg.log('Message data: ${message.data}');
      lg.log('Landing page: $landingPage');
      lg.log('Current route: ${Get.currentRoute}');

      if (Get.currentRoute != AppRoutes.home) {
        lg.log('Navigating to Home');
        Get.offAllNamed(AppRoutes.home);
      } else {
        lg.log('Already on Home');
      }

      if (AppUtility.isLoggedIn) {
        lg.log('Processing landing page: $landingPage');
        switch (landingPage) {
          case 'upcoming test':
            controller.goToHome();
            break;
          case 'announcement':
            lg.log('Navigating to Announcement');
            Get.toNamed(AppRoutes.home);
            break;
          case 'lead_page':
            Get.toNamed(AppRoutes.leads);
            break;
          default:
            controller.goToHome();
            break;
        }
      } else {
        lg.log('User not logged in, navigating to Login');
        Get.offAllNamed(AppRoutes.login);
      }
    } catch (e) {
      lg.log('Error in handleRemoteMessage: $e');
    }
  }
}
