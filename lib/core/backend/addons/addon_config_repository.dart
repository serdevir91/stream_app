import 'dart:async';
import 'package:hive_flutter/hive_flutter.dart';

class AddonConfigRepository {
  static const _boxName = 'addon_config_box';

  late Box _box;
  final StreamController<int> _changesController =
      StreamController<int>.broadcast();
  int _changeVersion = 0;

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  Map<String, bool> getEnabled() {
    final raw = _box.get('enabled');
    if (raw is Map) {
      return Map<String, bool>.from(raw.map(
        (k, v) => MapEntry(k.toString(), v == true),
      ));
    }
    return {};
  }

  Future<void> setEnabled(Map<String, bool> values) {
    return _box.put('enabled', values);
  }

  Map<String, String> getCustomUrls() {
    final raw = _box.get('custom_urls');
    if (raw is Map) {
      return Map<String, String>.from(raw.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ));
    }
    return {};
  }

  Future<void> setCustomUrls(Map<String, String> values) {
    return _box.put('custom_urls', values);
  }

  Map<String, Map<String, dynamic>> getCustomManifests() {
    final raw = _box.get('custom_manifests');
    if (raw is Map) {
      return raw.map((k, v) {
        if (v is Map) {
          return MapEntry(k.toString(), Map<String, dynamic>.from(v));
        }
        return MapEntry(k.toString(), <String, dynamic>{});
      });
    }
    return {};
  }

  Future<void> setCustomManifests(Map<String, Map<String, dynamic>> values) {
    return _box.put('custom_manifests', values);
  }

  List<String> getRemovedBuiltins() {
    final raw = _box.get('removed_builtins');
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return [];
  }

  Future<void> setRemovedBuiltins(List<String> values) {
    return _box.put('removed_builtins', values);
  }

  int getAddonConfigUpdatedAtMs() {
    return (_box.get('addon_config_updated_at_ms') as int?) ?? 0;
  }

  Future<void> saveAll({
    Map<String, bool>? enabled,
    Map<String, String>? customUrls,
    Map<String, Map<String, dynamic>>? customManifests,
    List<String>? removedBuiltins,
    int? updatedAtMs,
  }) async {
    if (enabled != null) await setEnabled(enabled);
    if (customUrls != null) await setCustomUrls(customUrls);
    if (customManifests != null) await setCustomManifests(customManifests);
    if (removedBuiltins != null) await setRemovedBuiltins(removedBuiltins);
    
    final timestamp = updatedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    await _box.put('addon_config_updated_at_ms', timestamp);
    _emitChange();
  }

  Stream<int> watchChanges() {
    return Stream<int>.multi((controller) {
      controller.add(_changeVersion);
      final sub = _changesController.stream.listen(
        controller.add,
        onError: controller.addError,
      );
      controller.onCancel = sub.cancel;
    });
  }

  void _emitChange() {
    if (_changesController.isClosed) {
      return;
    }
    _changeVersion += 1;
    _changesController.add(_changeVersion);
  }
}
