/// Android [NotificationService] backed by `flutter_local_notifications`.
///
/// Creates a dedicated notification channel on Android O+ and supports
/// exact and inexact alarms depending on OS version and permission.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:kabuk/services/notification.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Default Android notification channel.
const _kChannelId = 'kabuk_default';
const _kChannelName = 'Kabuk';
const _kChannelDescription = 'Kabuk agent notifications';

/// Direct-messages notification channel.
const _kDmChannelId = 'kabuk_dm';
const _kDmChannelName = 'Direct Messages';
const _kDmChannelDescription = 'Incoming Nostr direct messages';

/// Android [NotificationService] using `flutter_local_notifications`.
class AndroidNotificationService implements NotificationService {
  /// Creates an [AndroidNotificationService].
  AndroidNotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<Map<String, dynamic>> _tapController =
      StreamController<Map<String, dynamic>>.broadcast();
  bool _initialized = false;
  int _nextId = 0;

  /// Initializes the notification plugin and creates Android channels.
  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        _tapController.add({'payload': response.payload, 'id': response.id});
      },
    );

    // Create the default notification channel.
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kChannelId,
        _kChannelName,
        description: _kChannelDescription,
        importance: Importance.high,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kDmChannelId,
        _kDmChannelName,
        description: _kDmChannelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
    await androidPlugin?.requestNotificationsPermission();

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
          channelId ?? _kChannelId,
          _kChannelName,
          channelDescription: _kChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
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
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId ?? _kChannelId,
          _kChannelName,
          channelDescription: _kChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: payload != null ? jsonEncode(payload) : null,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
    dev.log(
      'Scheduled Android notification "$title" for $dateTime (id: $id)',
      name: 'AndroidNotificationService',
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
