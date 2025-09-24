// To parse this JSON data, do
//
//     final getSetPaymentResponse = getSetPaymentResponseFromJson(jsonString);

import 'dart:convert';

List<GetSetPaymentResponse> getSetPaymentResponseFromJson(String str) => List<GetSetPaymentResponse>.from(json.decode(str).map((x) => GetSetPaymentResponse.fromJson(x)));

String getSetPaymentResponseToJson(List<GetSetPaymentResponse> data) => json.encode(List<dynamic>.from(data.map((x) => x.toJson())));

class GetSetPaymentResponse {
    String status;
    String message;
    Data data;

    GetSetPaymentResponse({
        required this.status,
        required this.message,
        required this.data,
    });

    factory GetSetPaymentResponse.fromJson(Map<String, dynamic> json) => GetSetPaymentResponse(
        status: json["status"],
        message: json["message"],
        data: Data.fromJson(json["data"]),
    );

    Map<String, dynamic> toJson() => {
        "status": status,
        "message": message,
        "data": data.toJson(),
    };
}

class Data {
    int subscribedUserId;

    Data({
        required this.subscribedUserId,
    });

    factory Data.fromJson(Map<String, dynamic> json) => Data(
        subscribedUserId: json["subscribed_user_id"]??"",
    );

    Map<String, dynamic> toJson() => {
        "subscribed_user_id": subscribedUserId,
    };
}
