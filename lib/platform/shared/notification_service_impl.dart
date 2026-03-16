/// Cross-platform [NotificationService] backed by `flutter_local_notifications`.
///
/// This serves as the shared fallback implementation that works across all
/// platforms supported by the plugin. Platform-specific implementations
/// (Android, iOS, Desktop) derive additional capabilities but this provides
/// baseline notification support.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:kabuk/services/notification.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Cross-platform [NotificationService] using `flutter_local_notifications`.
///
/// Lazily initializes the plugin on first use. Handles notification taps
/// via the [onTap] stream.
class SharedNotificationService implements NotificationService {
  /// Creates a [SharedNotificationService].
  SharedNotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<Map<String, dynamic>> _tapController =
      StreamController<Map<String, dynamic>>.broadcast();
  bool _initialized = false;
  int _nextId = 0;

  /// Initializes the notification plugin for the current platform.
  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
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
        final payload = <String, dynamic>{'id': response.id};
        if (response.payload != null) {
          try {
            final decoded =
                jsonDecode(response.payload!) as Map<String, dynamic>;
            payload.addAll(decoded);
          } on Object {
            payload['payload'] = response.payload;
          }
        }
        _tapController.add(payload);
      },
    );

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
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId ?? 'default',
          channelId ?? 'Default',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
        macOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
        linux: const LinuxNotificationDetails(),
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
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId ?? 'default',
          channelId ?? 'Default',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
        macOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
        linux: const LinuxNotificationDetails(),
      ),
      payload: payload != null ? jsonEncode(payload) : null,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
    dev.log(
      'Scheduled notification "$title" for $dateTime (id: $id)',
      name: 'SharedNotificationService',
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
