import 'dart:async';
import 'dart:developer' as lg;
import 'dart:io';
import 'dart:typed_data';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';
import '../../core/db_helper.dart'; // Import DatabaseHelper
import 'package:flutter/material.dart'; // Added for navigation context

// Global navigator key for handling navigation in background/foreground handlers
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Top-level function for background notification handling
@pragma('vm:entry-point')
void backgroundNotificationHandler(NotificationResponse response) async {
  lg.log(
    'ReminderNotification: Background notification triggered, ID: ${response.id}, Payload: ${response.payload}, Action: ${response.actionId ?? "tap"}',
    time: DateTime.now(),
  );
  if (response.payload != null &&
      response.payload!.startsWith('lead_reminder_')) {
    final leadId = int.tryParse(response.payload!.split('_').last);
    if (leadId != null) {
      // Store leadId or perform lightweight processing
      // Note: Heavy operations like database initialization should be deferred to app startup
      lg.log(
        'ReminderNotification: Background handler processed leadId: $leadId',
        time: DateTime.now(),
      );
      // Navigation can be handled after app resumes (see main.dart setup)
    }
  }
  lg.log(
    'ReminderNotification: Background handler executed successfully',
    time: DateTime.now(),
  );
}

class ReminderNotification {
  static final ReminderNotification _instance =
      ReminderNotification._internal();
  factory ReminderNotification() => _instance;
  ReminderNotification._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Store scheduled notifications
  final Map<int, tz.TZDateTime> _scheduledNotifications = {};

  // Callback for remaining time updates
  Function(int id, Duration remainingTime)? onTimerUpdate;

  // Timer for updating remaining time
  Timer? _timer;

  Future<void> init() async {
    lg.log(
      'ReminderNotification: Starting initialization',
      time: DateTime.now(),
    );
    try {
      // Initialize timezone
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
      lg.log(
        'ReminderNotification: Timezone initialized to Asia/Kolkata',
        time: DateTime.now(),
      );
    } catch (e) {
      lg.log(
        'ReminderNotification: Error initializing timezone: $e',
        time: DateTime.now(),
      );
      tz.setLocalLocation(tz.getLocation('UTC')); // Fallback to UTC
      lg.log(
        'ReminderNotification: Fallback to UTC timezone',
        time: DateTime.now(),
      );
    }

    // Android initialization settings
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    // iOS initialization settings
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    // Create notification channel
    final channel = AndroidNotificationChannel(
      'lead_reminder_channel',
      'Lead Reminders',
      description: 'Channel for lead reminder notifications',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList(const [0, 1000, 500, 1000]),
      showBadge: true,
      audioAttributesUsage: AudioAttributesUsage.notificationEvent,
    );

    final androidPlugin =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    await androidPlugin?.createNotificationChannel(channel);
    lg.log(
      'ReminderNotification: Android notification channel created: lead_reminder_channel',
      time: DateTime.now(),
    );

    // Initialize plugin with handlers
    bool? initialized = await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        lg.log(
          'ReminderNotification: Notification triggered (foreground or tap), ID: ${response.id}, Payload: ${response.payload}, Action: ${response.actionId ?? "tap"}',
          time: DateTime.now(),
        );
        if (response.payload != null &&
            response.payload!.startsWith('lead_reminder_')) {
          final leadId = int.tryParse(response.payload!.split('_').last);
          if (leadId != null) {
            // Navigate to lead details screen
            navigatorKey.currentState?.pushNamed(
              '/lead_details',
              arguments: {'leadId': leadId},
            );
            lg.log(
              'ReminderNotification: Navigating to lead details for leadId: $leadId',
              time: DateTime.now(),
            );
          }
        }
        lg.log(
          'ReminderNotification: Foreground handler executed successfully',
          time: DateTime.now(),
        );
      },
      onDidReceiveBackgroundNotificationResponse: backgroundNotificationHandler,
    );
    lg.log(
      'ReminderNotification: Notification plugin initialized: $initialized',
      time: DateTime.now(),
    );

    // Request permissions
    if (Platform.isAndroid) {
      final notificationGranted = await requestNotificationPermission();
      lg.log(
        'ReminderNotification: Notification permission granted: $notificationGranted',
        time: DateTime.now(),
      );
      final exactAlarmGranted = await requestExactAlarmsPermission();
      lg.log(
        'ReminderNotification: Exact alarm permission granted: $exactAlarmGranted',
        time: DateTime.now(),
      );
      final batteryStatus =
          await Permission.ignoreBatteryOptimizations.request();
      lg.log(
        'ReminderNotification: Battery optimization exemption: ${batteryStatus.isGranted}',
        time: DateTime.now(),
      );
    } else if (Platform.isIOS) {
      final iosGranted = await requestIOSNotificationPermission();
      lg.log(
        'ReminderNotification: iOS notification permission granted: $iosGranted',
        time: DateTime.now(),
      );
    }

    // Clean old/orphaned notifications on init
    await cancelAllNotifications();
    lg.log(
      'ReminderNotification: Cleared old notifications on init',
      time: DateTime.now(),
    );

    // Log initial pending notifications
    final pendingNotifications =
        await flutterLocalNotificationsPlugin.pendingNotificationRequests();
    lg.log(
      'ReminderNotification: Initial pending notifications: ${pendingNotifications.map((n) => "ID: ${n.id}, Payload: ${n.payload}").toList()}',
      time: DateTime.now(),
    );

    _startTimer();
    lg.log(
      'ReminderNotification: Initialization completed',
      time: DateTime.now(),
    );
  }

  Future<bool> requestNotificationPermission() async {
    try {
      final androidPlugin =
          flutterLocalNotificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
      final granted =
          await androidPlugin?.requestNotificationsPermission() ?? false;
      lg.log(
        'ReminderNotification: Notification permission request result (Android): $granted',
        time: DateTime.now(),
      );
      return granted;
    } catch (e) {
      lg.log(
        'ReminderNotification: Error requesting notification permission (Android): $e',
        time: DateTime.now(),
      );
      return false;
    }
  }

  Future<bool> requestIOSNotificationPermission() async {
    try {
      final iosPlugin =
          flutterLocalNotificationsPlugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >();
      final granted =
          await iosPlugin?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
      lg.log(
        'ReminderNotification: Notification permission request result (iOS): $granted',
        time: DateTime.now(),
      );
      return granted;
    } catch (e) {
      lg.log(
        'ReminderNotification: Error requesting notification permission (iOS): $e',
        time: DateTime.now(),
      );
      return false;
    }
  }

  Future<bool> requestExactAlarmsPermission() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      lg.log(
        'ReminderNotification: Android SDK version: $sdkInt',
        time: DateTime.now(),
      );

      if (sdkInt >= 31) {
        final androidPlugin =
            flutterLocalNotificationsPlugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >();
        final canScheduleExact =
            await androidPlugin?.canScheduleExactNotifications() ?? false;
        lg.log(
          'ReminderNotification: Can schedule exact alarms: $canScheduleExact',
          time: DateTime.now(),
        );
        if (!canScheduleExact) {
          await androidPlugin?.requestExactAlarmsPermission();
          final updatedStatus =
              await androidPlugin?.canScheduleExactNotifications() ?? false;
          lg.log(
            'ReminderNotification: Exact alarm permission request result: $updatedStatus',
            time: DateTime.now(),
          );
          return updatedStatus;
        }
        return canScheduleExact;
      }
      return true;
    } catch (e) {
      lg.log(
        'ReminderNotification: Error checking/requesting exact alarm permission: $e',
        time: DateTime.now(),
      );
      return false;
    }
  }

  // Helper method to parse time string (supports both 12-hour and 24-hour formats)
  DateTime _parseTimeString(String timeString, DateTime date) {
    try {
      // Try 24-hour format (HH:mm) first
      try {
        final format = DateFormat('HH:mm');
        final parsedTime = format.parse(timeString);
        return DateTime(
          date.year,
          date.month,
          date.day,
          parsedTime.hour,
          parsedTime.minute,
        );
      } catch (_) {
        // Fallback to 12-hour format (h:mm a)
        final format = DateFormat('h:mm a');
        final parsedTime = format.parse(timeString);
        return DateTime(
          date.year,
          date.month,
          date.day,
          parsedTime.hour,
          parsedTime.minute,
        );
      }
    } catch (e) {
      lg.log(
        'ReminderNotification: Error parsing time string "$timeString": $e',
        time: DateTime.now(),
      );
      rethrow;
    }
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    try {
      lg.log(
        'ReminderNotification: Attempting to schedule notification, ID: $id, Title: $title, Body: $body, ScheduledDate: $scheduledDate',
        time: DateTime.now(),
      );

      // Check permissions
      if (Platform.isAndroid) {
        final status = await Permission.scheduleExactAlarm.request();
        if (!status.isGranted) {
          lg.log(
            'ReminderNotification: SCHEDULE_EXACT_ALARM permission not granted for ID: $id',
            time: DateTime.now(),
          );
          return;
        }
      }
      if (Platform.isIOS) {
        final granted = await requestIOSNotificationPermission();
        if (!granted) {
          lg.log(
            'ReminderNotification: iOS notification permissions not granted for ID: $id',
            time: DateTime.now(),
          );
          return;
        }
      }

      // Validate scheduled date
      final now = DateTime.now();
      if (scheduledDate.isBefore(now.add(const Duration(seconds: 10)))) {
        lg.log(
          'ReminderNotification: Error: Scheduled date ($scheduledDate) is too close to current time ($now) for ID: $id',
          time: DateTime.now(),
        );
        throw Exception(
          'Scheduled date must be at least 10 seconds in the future.',
        );
      }

      final tzScheduledDate = tz.TZDateTime.from(scheduledDate, tz.local);
      lg.log(
        'ReminderNotification: Converted to TZ Scheduled Date: $tzScheduledDate for ID: $id',
        time: DateTime.now(),
      );

      final AndroidNotificationDetails androidNotificationDetails =
          AndroidNotificationDetails(
            'lead_reminder_channel',
            'Lead Reminders',
            channelDescription: 'Channel for lead reminder notifications',
            importance: Importance.max,
            priority: Priority.high,
            showWhen: true,
            enableVibration: true,
            vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
            playSound: true,
            audioAttributesUsage: AudioAttributesUsage.notificationEvent,
          );

      final DarwinNotificationDetails iosNotificationDetails =
          DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: iosNotificationDetails,
      );

      final canScheduleExact = await requestExactAlarmsPermission();
      final androidScheduleMode =
          canScheduleExact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexact;
      lg.log(
        'ReminderNotification: Using schedule mode: $androidScheduleMode for ID: $id',
        time: DateTime.now(),
      );

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tzScheduledDate,
        notificationDetails,
        androidScheduleMode: androidScheduleMode,
        matchDateTimeComponents: DateTimeComponents.dateAndTime,
        payload: 'lead_reminder_$id',
      );

      // Store the scheduled notification
      _scheduledNotifications[id] = tzScheduledDate;
      lg.log(
        'ReminderNotification: Notification scheduled successfully: ID=$id, Date=$tzScheduledDate',
        time: DateTime.now(),
      );

      // Log pending notifications
      final pendingNotifications =
          await flutterLocalNotificationsPlugin.pendingNotificationRequests();
      if (pendingNotifications.any((notification) => notification.id == id)) {
        lg.log(
          'ReminderNotification: Notification with ID=$id is pending with payload: ${pendingNotifications.firstWhere((n) => n.id == id).payload}',
          time: DateTime.now(),
        );
      } else {
        lg.log(
          'ReminderNotification: No pending notification found with ID=$id',
          time: DateTime.now(),
        );
      }
    } catch (e, stackTrace) {
      lg.log(
        'ReminderNotification: Error scheduling notification for ID: $id: $e',
        time: DateTime.now(),
      );
      lg.log(
        'ReminderNotification: Stack trace: $stackTrace',
        time: DateTime.now(),
      );
    }
  }

  Future<void> showImmediateNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      lg.log(
        'ReminderNotification: Showing immediate notification: ID=$id, Title=$title, Body=$body',
        time: DateTime.now(),
      );

      final AndroidNotificationDetails androidNotificationDetails =
          AndroidNotificationDetails(
            'lead_reminder_channel',
            'Lead Reminders',
            channelDescription: 'Channel for lead reminder notifications',
            importance: Importance.max,
            priority: Priority.high,
            showWhen: true,
            enableVibration: true,
            vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
            playSound: true,
            audioAttributesUsage: AudioAttributesUsage.notificationEvent,
          );

      final DarwinNotificationDetails iosNotificationDetails =
          DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: iosNotificationDetails,
      );

      await flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        notificationDetails,
        payload: 'lead_reminder_$id',
      );
      lg.log(
        'ReminderNotification: Immediate notification shown: ID=$id',
        time: DateTime.now(),
      );
    } catch (e) {
      lg.log(
        'ReminderNotification: Error showing immediate notification for ID: $id: $e',
        time: DateTime.now(),
      );
    }
  }

  // Start a timer to periodically update remaining time
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateRemainingTime();
    });
    lg.log(
      'ReminderNotification: Timer started for remaining time updates',
      time: DateTime.now(),
    );
  }

  // Update remaining time for all scheduled notifications
  void _updateRemainingTime() {
    final now = tz.TZDateTime.now(tz.local);
    _scheduledNotifications.forEach((id, scheduledDate) {
      if (scheduledDate.isAfter(now)) {
        final remainingTime = scheduledDate.difference(now);
        if (onTimerUpdate != null) {
          onTimerUpdate!(id, remainingTime);
        }
        lg.log(
          'ReminderNotification: Notification ID=$id: ${remainingTime.inHours}h ${remainingTime.inMinutes % 60}m ${remainingTime.inSeconds % 60}s remaining',
          time: DateTime.now(),
        );
      } else {
        _scheduledNotifications.remove(id);
        lg.log(
          'ReminderNotification: Notification ID=$id has triggered or passed and is removed from tracking',
          time: DateTime.now(),
        );
      }
    });

    if (_scheduledNotifications.isEmpty) {
      _timer?.cancel();
      lg.log(
        'ReminderNotification: No scheduled notifications left; timer stopped',
        time: DateTime.now(),
      );
    }
  }

  // Get remaining time for a specific notification
  Duration? getRemainingTime(int id) {
    if (_scheduledNotifications.containsKey(id)) {
      final now = tz.TZDateTime.now(tz.local);
      final scheduledDate = _scheduledNotifications[id]!;
      if (scheduledDate.isAfter(now)) {
        return scheduledDate.difference(now);
      } else {
        _scheduledNotifications.remove(id);
        lg.log(
          'ReminderNotification: Notification ID=$id has passed and is removed from tracking',
          time: DateTime.now(),
        );
        return null;
      }
    }
    return null;
  }

  // Cancel a specific notification
  Future<void> cancelNotification(int id) async {
    try {
      await flutterLocalNotificationsPlugin.cancel(id);
      _scheduledNotifications.remove(id);
      lg.log(
        'ReminderNotification: Notification ID=$id canceled',
        time: DateTime.now(),
      );
    } catch (e) {
      lg.log(
        'ReminderNotification: Error canceling notification for ID: $id: $e',
        time: DateTime.now(),
      );
    }
  }

  // Cancel all notifications
  Future<void> cancelAllNotifications() async {
    try {
      await flutterLocalNotificationsPlugin.cancelAll();
      _scheduledNotifications.clear();
      _timer?.cancel();
      lg.log(
        'ReminderNotification: All notifications canceled',
        time: DateTime.now(),
      );
    } catch (e) {
      lg.log(
        'ReminderNotification: Error canceling all notifications: $e',
        time: DateTime.now(),
      );
    }
  }

  // Schedule reminders for all leads with a specific reminder option
  Future<void> scheduleRemindersForAllLeads(String? reminderOption) async {
    try {
      lg.log(
        'ReminderNotification: Scheduling reminders for all leads with option: $reminderOption',
        time: DateTime.now(),
      );
      final reminders = await DatabaseHelper.instance.getReminders();
      if (reminders.isEmpty) {
        lg.log(
          'ReminderNotification: No reminders found in database',
          time: DateTime.now(),
        );
        return;
      }

      if (reminderOption == "Don't remind") {
        for (var reminder in reminders) {
          final String leadId = reminder['lead_id']?.toString() ?? '';
          if (leadId.isEmpty) {
            lg.log(
              'ReminderNotification: Skipping reminder with empty lead_id: $reminder',
              time: DateTime.now(),
            );
            continue;
          }
          await cancelNotification(int.parse(leadId));
          lg.log(
            'ReminderNotification: Cancelled notification for lead ID: $leadId due to "Don\'t remind"',
            time: DateTime.now(),
          );
        }
        lg.log(
          'ReminderNotification: All notifications cancelled due to "Don\'t remind"',
          time: DateTime.now(),
        );
        return;
      }

      final now = DateTime.now();
      lg.log('ReminderNotification: Current time: $now', time: DateTime.now());
      for (var reminder in reminders) {
        try {
          final String leadId = reminder['lead_id']?.toString() ?? '';
          final String leadName = reminder['lead_name']?.toString() ?? 'Lead';
          final String reminderDateString =
              reminder['reminder_date']?.toString() ?? '';
          final String reminderTimeString =
              reminder['reminder_time']?.toString() ?? '';

          lg.log(
            'ReminderNotification: Processing reminder, ID: $leadId, Name: $leadName, Date: $reminderDateString, Time: $reminderTimeString',
            time: DateTime.now(),
          );

          if (leadId.isEmpty ||
              reminderDateString.isEmpty ||
              reminderTimeString.isEmpty) {
            lg.log(
              'ReminderNotification: Skipping reminder with invalid data (ID: $leadId, date: "$reminderDateString", time: "$reminderTimeString")',
              time: DateTime.now(),
            );
            continue;
          }

          // Parse date and time
          DateTime reminderDateTime;
          try {
            final dateParts = reminderDateString.split('-');
            if (dateParts.length != 3) {
              lg.log(
                'ReminderNotification: Invalid date format for lead ID: $leadId, date: $reminderDateString',
                time: DateTime.now(),
              );
              continue;
            }
            final date = DateTime(
              int.parse(dateParts[0]),
              int.parse(dateParts[1]),
              int.parse(dateParts[2]),
            );
            // Parse time (supports both 24-hour and 12-hour for backward compatibility)
            reminderDateTime = _parseTimeString(reminderTimeString, date);
            lg.log(
              'ReminderNotification: Parsed reminderDateTime: $reminderDateTime for lead ID: $leadId',
              time: DateTime.now(),
            );
          } catch (e) {
            lg.log(
              'ReminderNotification: Error parsing date/time for lead ID: $leadId, date: $reminderDateString, time: $reminderTimeString, error: $e',
              time: DateTime.now(),
            );
            continue;
          }

          if (reminderDateTime.isBefore(now.add(const Duration(seconds: 10)))) {
            lg.log(
              'ReminderNotification: Reminder time $reminderDateTime is in the past or too close to now for lead ID: $leadId, skipping',
              time: DateTime.now(),
            );
            continue;
          }

          await cancelNotification(int.parse(leadId));
          lg.log(
            'ReminderNotification: Cancelled existing notification for lead ID: $leadId',
            time: DateTime.now(),
          );

          await scheduleNotification(
            id: int.parse(leadId),
            title: 'Reminder: Follow-up with $leadName',
            body: 'Scheduled for $reminderDateString at $reminderTimeString.',
            scheduledDate: reminderDateTime,
          );
          lg.log(
            'ReminderNotification: Successfully scheduled notification for lead ID: $leadId at $reminderDateTime',
            time: DateTime.now(),
          );
        } catch (e, stackTrace) {
          lg.log(
            'ReminderNotification: Error processing lead ID: : $e',
            time: DateTime.now(),
          );
          lg.log(
            'ReminderNotification: Stack trace: $stackTrace',
            time: DateTime.now(),
          );
        }
      }

      // Log all pending notifications after scheduling
      final pendingNotifications =
          await flutterLocalNotificationsPlugin.pendingNotificationRequests();
      lg.log(
        'ReminderNotification: All pending notifications after scheduling: ${pendingNotifications.map((n) => "ID: ${n.id}, Payload: ${n.payload}").toList()}',
        time: DateTime.now(),
      );
    } catch (e, stackTrace) {
      lg.log(
        'ReminderNotification: Error in scheduleRemindersForAllLeads: $e',
        time: DateTime.now(),
      );
      lg.log(
        'ReminderNotification: Stack trace: $stackTrace',
        time: DateTime.now(),
      );
    }
  }
}
