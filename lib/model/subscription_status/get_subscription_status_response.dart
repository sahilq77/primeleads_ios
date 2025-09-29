// To parse this JSON data, do
//
//     final getSubscriptionStatusResponse = getSubscriptionStatusResponseFromJson(jsonString);

import 'dart:convert';

List<GetSubscriptionStatusResponse> getSubscriptionStatusResponseFromJson(
  String str,
) => List<GetSubscriptionStatusResponse>.from(
  json.decode(str).map((x) => GetSubscriptionStatusResponse.fromJson(x)),
);

String getSubscriptionStatusResponseToJson(
  List<GetSubscriptionStatusResponse> data,
) => json.encode(List<dynamic>.from(data.map((x) => x.toJson())));

class GetSubscriptionStatusResponse {
  String status;
  String message;
  Data data;

  GetSubscriptionStatusResponse({
    required this.status,
    required this.message,
    required this.data,
  });

  factory GetSubscriptionStatusResponse.fromJson(Map<String, dynamic> json) =>
      GetSubscriptionStatusResponse(
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
  String subscribedUserId;
  String hasExpired;

  Data({required this.subscribedUserId, required this.hasExpired});

  factory Data.fromJson(Map<String, dynamic> json) => Data(
    subscribedUserId: json["subscribed_user_id"] ?? "",
    hasExpired: json["has_expired"] ?? "",
  );

  Map<String, dynamic> toJson() => {
    "subscribed_user_id": subscribedUserId,
    "has_expired": hasExpired,
  };
}
