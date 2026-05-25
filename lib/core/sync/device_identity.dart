import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

class DeviceIdentity {
  static const String _boxName = 'sync_device_box';
  static const String _deviceIdKey = 'device_id';
  static const String _authTokenKey = 'auth_token';
  static const String _serverUrlKey = 'server_url';

  static String generateDeviceId() {
    final raw =
        '${DateTime.now().millisecondsSinceEpoch}_${Platform.environment['USERNAME'] ?? 'device'}';
    return sha256.convert(utf8.encode(raw)).toString().substring(0, 16);
  }

  static Future<Box> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box(_boxName);
    }
    return await Hive.openBox(_boxName);
  }

  static Future<String> getOrCreateDeviceId() async {
    final box = await _openBox();
    String? deviceId = box.get(_deviceIdKey) as String?;
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = generateDeviceId();
      await box.put(_deviceIdKey, deviceId);
    }
    return deviceId;
  }

  static Future<void> saveAuthToken(String token) async {
    final box = await _openBox();
    await box.put(_authTokenKey, token);
  }

  static Future<String?> getAuthToken() async {
    final box = await _openBox();
    return box.get(_authTokenKey) as String?;
  }

  static Future<void> saveServerUrl(String serverUrl) async {
    final box = await _openBox();
    await box.put(_serverUrlKey, serverUrl);
  }

  static Future<String?> getServerUrl() async {
    final box = await _openBox();
    final value = box.get(_serverUrlKey) as String?;
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  static Future<bool> isRegistered() async {
    final token = await getAuthToken();
    return token != null && token.isNotEmpty;
  }

  static Future<void> clearRegistration() async {
    final box = await _openBox();
    await box.delete(_authTokenKey);
    await box.delete(_serverUrlKey);
  }
}
