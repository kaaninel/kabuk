/// Desktop [NotificationService] backed by `flutter_local_notifications`.
///
/// On macOS this uses native notification centre. On Linux this uses
/// libnotify (if available). Windows uses toast notifications.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:kabuk/services/notification.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Desktop [NotificationService] using `flutter_local_notifications`.
class DesktopNotificationService implements NotificationService {
  /// Creates a [DesktopNotificationService].
  DesktopNotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<Map<String, dynamic>> _tapController =
      StreamController<Map<String, dynamic>>.broadcast();
  bool _initialized = false;
  int _nextId = 0;

  /// Initializes the notification plugin.
  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();

    const initSettings = InitializationSettings(
      macOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
      linux: LinuxInitializationSettings(defaultActionName: 'Open'),
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        _tapController.add({'payload': response.payload, 'id': response.id});
      },
    );

    // Request permissions on macOS.
    await _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
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
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
        linux: LinuxNotificationDetails(),
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
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
        linux: LinuxNotificationDetails(),
      ),
      payload: payload != null ? jsonEncode(payload) : null,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
    dev.log(
      'Scheduled desktop notification "$title" for $dateTime (id: $id)',
      name: 'DesktopNotificationService',
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
