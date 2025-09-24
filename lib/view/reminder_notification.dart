import 'dart:async';
import 'dart:convert';
import 'dart:developer' as lg;
import 'dart:io';
import 'dart:typed_data';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// Top-level function for background notification handling
@pragma('vm:entry-point')
void backgroundNotificationHandler(NotificationResponse response) {
  lg.log(
    'ReminderNotification: Background notification received, payload: ${response.payload}',
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
    lg.log('ReminderNotification: Initializing notifications');
    try {
      // Initialize timezone
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
      lg.log('ReminderNotification: Timezone initialized: Asia/Kolkata');
    } catch (e) {
      lg.log('ReminderNotification: Error initializing timezone: $e');
      tz.setLocalLocation(tz.getLocation('UTC')); // Fallback to UTC
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

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
    lg.log(
      'ReminderNotification: Android notification channel created: lead_reminder_channel',
    );

    // Initialize plugin with background handler
    bool? initialized = await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        lg.log(
          'ReminderNotification: Notification tapped, payload: ${response.payload}',
        );
      },
      onDidReceiveBackgroundNotificationResponse: backgroundNotificationHandler,
    );
    lg.log(
      'ReminderNotification: Notification plugin initialized: $initialized',
    );

    // Request permissions
    if (Platform.isAndroid) {
      await requestNotificationPermission();
      await requestExactAlarmsPermission();
      final status = await Permission.ignoreBatteryOptimizations.request();
      lg.log(
        'ReminderNotification: Battery optimization exemption: ${status.isGranted}',
      );
    } else if (Platform.isIOS) {
      await requestIOSNotificationPermission();
    }

    _startTimer();
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
      );
      return granted;
    } catch (e) {
      lg.log(
        'ReminderNotification: Error requesting notification permission (Android): $e',
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
      );
      return granted;
    } catch (e) {
      lg.log(
        'ReminderNotification: Error requesting notification permission (iOS): $e',
      );
      return false;
    }
  }

  Future<bool> requestExactAlarmsPermission() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      lg.log('ReminderNotification: Android SDK version: $sdkInt');

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
        );
        if (!canScheduleExact) {
          await androidPlugin?.requestExactAlarmsPermission();
          final updatedStatus =
              await androidPlugin?.canScheduleExactNotifications() ?? false;
          lg.log(
            'ReminderNotification: Exact alarm permission request result: $updatedStatus',
          );
          return updatedStatus;
        }
        return canScheduleExact;
      }
      return true;
    } catch (e) {
      lg.log(
        'ReminderNotification: Error checking/requesting exact alarm permission: $e',
      );
      return false;
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
        'ReminderNotification: Scheduling notification with ID: $id, Title: $title, Body: $body, ScheduledDate: $scheduledDate',
      );

      // Check permissions
      if (Platform.isAndroid) {
        final status = await Permission.scheduleExactAlarm.request();
        if (!status.isGranted) {
          lg.log(
            'ReminderNotification: SCHEDULE_EXACT_ALARM permission not granted',
          );
          return;
        }
      }
      if (Platform.isIOS) {
        final granted = await requestIOSNotificationPermission();
        if (!granted) {
          lg.log(
            'ReminderNotification: iOS notification permissions not granted',
          );
          return;
        }
      }

      // Validate scheduled date
      final now = DateTime.now();
      if (scheduledDate.isBefore(now.add(const Duration(seconds: 10)))) {
        lg.log(
          'ReminderNotification: Error: Scheduled date ($scheduledDate) is too close to current time ($now).',
        );
        throw Exception(
          'Scheduled date must be at least 10 seconds in the future.',
        );
      }

      final tzScheduledDate = tz.TZDateTime.from(scheduledDate, tz.local);
      lg.log('ReminderNotification: TZ Scheduled Date: $tzScheduledDate');

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
      lg.log('ReminderNotification: Using schedule mode: $androidScheduleMode');

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
      );

      // Log pending notifications for debugging
      final pendingNotifications =
          await flutterLocalNotificationsPlugin.pendingNotificationRequests();
      if (pendingNotifications.any((notification) => notification.id == id)) {
        lg.log('ReminderNotification: Notification with ID=$id is pending');
      } else {
        lg.log(
          'ReminderNotification: No pending notification found with ID=$id',
        );
      }
    } catch (e, stackTrace) {
      lg.log('ReminderNotification: Error scheduling notification: $e');
      lg.log('ReminderNotification: Stack trace: $stackTrace');
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
      lg.log('ReminderNotification: Immediate notification shown: ID=$id');
    } catch (e) {
      lg.log('ReminderNotification: Error showing immediate notification: $e');
    }
  }

  // Start a timer to periodically update remaining time
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateRemainingTime();
    });
    lg.log('ReminderNotification: Timer started for remaining time updates');
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
        );
      } else {
        _scheduledNotifications.remove(id);
        lg.log(
          'ReminderNotification: Notification ID=$id has triggered and is removed from tracking',
        );
      }
    });

    if (_scheduledNotifications.isEmpty) {
      _timer?.cancel();
      lg.log(
        'ReminderNotification: No scheduled notifications left; timer stopped',
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
      lg.log('ReminderNotification: Notification ID=$id canceled');
    } catch (e) {
      lg.log('ReminderNotification: Error canceling notification: $e');
    }
  }

  // Cancel all notifications
  Future<void> cancelAllNotifications() async {
    try {
      await flutterLocalNotificationsPlugin.cancelAll();
      _scheduledNotifications.clear();
      _timer?.cancel();
      lg.log('ReminderNotification: All notifications canceled');
    } catch (e) {
      lg.log('ReminderNotification: Error canceling all notifications: $e');
    }
  }

  // Schedule reminders for all leads with a specific reminder option
  Future<void> scheduleRemindersForAllLeads(String? reminderOption) async {
    try {
      lg.log(
        'ReminderNotification: Scheduling reminders for all leads with option: $reminderOption',
      );
      final prefs = await SharedPreferences.getInstance();
      final List<String>? allLeadsJson = prefs.getStringList('all_leads');
      if (allLeadsJson == null || allLeadsJson.isEmpty) {
        lg.log('ReminderNotification: No leads found in shared preferences');
        return;
      }

      if (reminderOption == "Don't remind") {
        for (String leadJson in allLeadsJson) {
          final Map<String, dynamic> lead = json.decode(leadJson);
          final String leadId = lead['lead_id']?.toString() ?? '';
          if (leadId.isNotEmpty) {
            await cancelNotification(int.parse(leadId));
            lg.log(
              'ReminderNotification: Cancelled notification for lead ID: $leadId due to "Don\'t remind"',
            );
          }
        }
        await prefs.setString('global_reminder_option', "Don't remind");
        lg.log('ReminderNotification: Global reminder set to "Don\'t remind"');
        return;
      }

      Duration reminderDuration;
      bool useDefault = reminderOption == null || reminderOption.isEmpty;
      if (useDefault) {
        reminderDuration = const Duration(minutes: 30);
        lg.log(
          'ReminderNotification: Using default reminder duration: 30 minutes',
        );
      } else {
        switch (reminderOption) {
          case '15 mins':
            reminderDuration = const Duration(minutes: 15);
            break;
          case '30 mins':
            reminderDuration = const Duration(minutes: 30);
            break;
          case '45 mins':
            reminderDuration = const Duration(minutes: 45);
            break;
          case '60 mins':
            reminderDuration = const Duration(minutes: 60);
            break;
          default:
            reminderDuration = const Duration(minutes: 30);
            useDefault = true;
            lg.log(
              'ReminderNotification: Invalid reminder option "$reminderOption", falling back to default 30 minutes',
            );
        }
        await prefs.setString('global_reminder_option', reminderOption);
        lg.log(
          'ReminderNotification: Global reminder option saved: $reminderOption',
        );
      }

      final now = DateTime.now();
      for (String leadJson in allLeadsJson) {
        try {
          final Map<String, dynamic> lead = json.decode(leadJson);
          final String leadId = lead['lead_id']?.toString() ?? '';
          final String leadName = lead['name']?.toString() ?? 'Lead';
          final String reminderDateString =
              lead['reminder_date']?.toString() ?? '';
          final String reminderTimeString =
              lead['reminder_time']?.toString() ?? '';

          if (leadId.isEmpty ||
              reminderDateString.isEmpty ||
              reminderTimeString.isEmpty) {
            lg.log(
              'ReminderNotification: Skipping lead with invalid data (ID: $leadId, date: "$reminderDateString", time: "$reminderTimeString")',
            );
            continue;
          }

          // Parse date and time (assuming format 'yyyy-MM-dd' and 'HH:mm')
          DateTime reminderDateTime;
          try {
            final dateParts = reminderDateString.split('-');
            final timeParts = reminderTimeString.split(':');
            reminderDateTime = DateTime(
              int.parse(dateParts[0]),
              int.parse(dateParts[1]),
              int.parse(dateParts[2]),
              int.parse(timeParts[0]),
              int.parse(timeParts[1]),
            );
          } catch (e) {
            lg.log(
              'ReminderNotification: Error parsing date/time for lead ID: $leadId, date: $reminderDateString, time: $reminderTimeString, error: $e',
            );
            continue;
          }

          if (reminderDateTime.isBefore(now)) {
            lg.log(
              'ReminderNotification: Reminder time $reminderDateTime is in the past for lead ID: $leadId, skipping',
            );
            continue;
          }

          final reminderTime = reminderDateTime.subtract(reminderDuration);
          if (reminderTime.isBefore(now)) {
            lg.log(
              'ReminderNotification: Reminder time $reminderTime is in the past for lead ID: $leadId, skipping',
            );
            continue;
          }

          await cancelNotification(int.parse(leadId));
          lg.log(
            'ReminderNotification: Cancelled existing notification for lead ID: $leadId',
          );

          final String reminderType = useDefault ? 'default' : 'custom';
          await scheduleNotification(
            id: int.parse(leadId),
            title: 'Reminder: Follow-up with $leadName',
            body:
                'Scheduled for $reminderDateString at $reminderTimeString ($reminderType).',
            scheduledDate: reminderTime,
          );
          lg.log(
            'ReminderNotification: Successfully scheduled $reminderType notification for lead ID: $leadId at $reminderTime',
          );
        } catch (e, stackTrace) {
          lg.log('ReminderNotification: Error processing lead: $e');
          lg.log('ReminderNotification: Stack trace: $stackTrace');
        }
      }
    } catch (e, stackTrace) {
      lg.log('ReminderNotification: Error in scheduleRemindersForAllLeads: $e');
      lg.log('ReminderNotification: Stack trace: $stackTrace');
    }
  }
}
