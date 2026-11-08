import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Why the app must stay awake in the background.
enum KeepAliveReason { download, externalPlayer }

@pragma('vm:entry-point')
void keepAliveCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());
}

class _KeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Android freezes cached apps, which would stall downloads and the local
/// proxy an external player streams through. A dataSync foreground service
/// keeps the process running while any reason is active.
class KeepAliveService {
  KeepAliveService._();

  static const int _serviceId = 4107;
  static final Set<KeepAliveReason> _reasons = <KeepAliveReason>{};
  static bool _initialized = false;
  static String _title = 'Stream';
  static String _text = '';

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static void _ensureInit() {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'stream_keep_alive',
        channelName: 'Background activity',
        channelDescription: 'Downloads and external player streaming',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
  }

  static Future<void> requestPermission() async {
    if (!_supported) return;
    try {
      final status = await FlutterForegroundTask.checkNotificationPermission();
      if (status != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    } catch (e) {
      debugPrint('KeepAlive permission: $e');
    }
  }

  static Future<void> acquire(
    KeepAliveReason reason, {
    required String title,
    String text = '',
  }) async {
    if (!_supported) return;
    _reasons.add(reason);
    _title = title;
    _text = text;
    try {
      _ensureInit();
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: text,
        );
        return;
      }
      await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        serviceTypes: const [ForegroundServiceTypes.dataSync],
        notificationTitle: title,
        notificationText: text,
        callback: keepAliveCallback,
      );
    } catch (e) {
      debugPrint('KeepAlive start: $e');
    }
  }

  /// Updates the notification text; ignored when no reason is active.
  static Future<void> update({String? title, String? text}) async {
    if (!_supported || _reasons.isEmpty) return;
    if (title == _title && text == _text) return;
    _title = title ?? _title;
    _text = text ?? _text;
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: _title,
        notificationText: _text,
      );
    } catch (_) {}
  }

  static Future<void> release(KeepAliveReason reason) async {
    if (!_supported) return;
    _reasons.remove(reason);
    if (_reasons.isNotEmpty) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (e) {
      debugPrint('KeepAlive stop: $e');
    }
  }
}
