/// iOS [NotificationService] backed by `flutter_local_notifications`.
///
/// Uses APNs (Apple Push Notification Service) on-device channels.
/// Handles permission requests, notification channels, and tap callbacks.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:kabuk/services/notification.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// iOS [NotificationService] using `flutter_local_notifications`.
class IosNotificationService implements NotificationService {
  /// Creates an [IosNotificationService].
  IosNotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<Map<String, dynamic>> _tapController =
      StreamController<Map<String, dynamic>>.broadcast();
  bool _initialized = false;
  int _nextId = 0;

  /// Initializes the notification plugin and requests permissions.
  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();

    const initSettings = InitializationSettings(
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        _tapController.add({'payload': payload, 'id': response.id});
      },
    );

    // Request permissions.
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _initialized = true;
  }

  @override
  Future<void> show({
    required String title,
    required String body,
    String? channelId,
    Map<String, dynamic>? payload,
  }) async {
    await _ensureInit();
    final id = _nextId++;
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload != null ? jsonEncode(payload) : null,
    );
  }

  @override
  Future<void> schedule({
    required String title,
    required String body,
    required DateTime dateTime,
    String? channelId,
    Map<String, dynamic>? payload,
  }) async {
    await _ensureInit();
    final id = _nextId++;
    final scheduled = tz.TZDateTime.from(dateTime, tz.local);
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      const NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload != null ? jsonEncode(payload) : null,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
    dev.log(
      'Scheduled iOS notification "$title" for $dateTime (id: $id)',
      name: 'IosNotificationService',
    );
  }

  @override
  Future<void> cancel(String id) async {
    await _ensureInit();
    final numId = int.tryParse(id);
    if (numId != null) await _plugin.cancel(numId);
  }

  @override
  Future<void> cancelAll() async {
    await _ensureInit();
    await _plugin.cancelAll();
  }

  @override
  Stream<Map<String, dynamic>> get onTap => _tapController.stream;

  @override
  void dispose() {
    _tapController.close();
  }

  Future<void> _ensureInit() async {
    if (!_initialized) await initialize();
  }
}
