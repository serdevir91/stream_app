import 'dart:async';

import 'package:hive/hive.dart';

import '../../../search/domain/entities/media_item.dart';

class LibraryRepository {
  static const String boxName = 'library_box';
  final StreamController<int> _changesController =
      StreamController<int>.broadcast();
  int _changeVersion = 0;

  Future<void> init() async {
    await Hive.openBox<dynamic>(boxName);
  }

  Box<dynamic>? get _boxOrNull {
    if (!Hive.isBoxOpen(boxName)) {
      return null;
    }
    return Hive.box<dynamic>(boxName);
  }

  List<MediaItem> getItems() {
    final box = _boxOrNull;
    if (box == null) {
      return [];
    }

    return box.values
        .whereType<Map>()
        .map((item) => MediaItem.fromMap(item))
        .toList();
  }

  List<Map<String, dynamic>> getSyncEntries() {
    final box = _boxOrNull;
    if (box == null) {
      return [];
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final result = <Map<String, dynamic>>[];

    for (final item in box.values.whereType<Map>()) {
      final media = MediaItem.fromMap(item);
      final updatedAtMs = item['updated_at_ms'] is int
          ? item['updated_at_ms'] as int
          : now;
      result.add({
        'media_id': media.id,
        'title': media.title,
        'media_type': media.type,
        'poster_url': media.posterUrl,
        'backdrop_url': media.backdropUrl,
        'description': media.description,
        'rating': media.rating,
        'updated_at_ms': updatedAtMs,
      });
    }

    return result;
  }

  Set<String> getItemIds() {
    final box = _boxOrNull;
    if (box == null) {
      return {};
    }
    return box.keys.map((k) => k.toString()).toSet();
  }

  int? getUpdatedAtMs(String mediaId) {
    final box = _boxOrNull;
    if (box == null) {
      return null;
    }
    final raw = box.get(mediaId);
    if (raw is! Map) {
      return null;
    }
    final value = raw['updated_at_ms'];
    return value is int ? value : null;
  }

  bool contains(String mediaId) {
    return _boxOrNull?.containsKey(mediaId) ?? false;
  }

  Future<void> upsert(MediaItem item) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final box = _boxOrNull ?? await Hive.openBox<dynamic>(boxName);
    final map = <String, dynamic>{...item.toMap(), 'updated_at_ms': now};
    await box.put(item.id, map);
    _emitChange();
  }

  Future<void> upsertFromSync({
    required String mediaId,
    required String title,
    required String mediaType,
    String? posterUrl,
    String? backdropUrl,
    String? description,
    double? rating,
    required int updatedAtMs,
  }) async {
    final box = _boxOrNull ?? await Hive.openBox<dynamic>(boxName);
    final map = <String, dynamic>{
      'id': mediaId,
      'title': title,
      'type': mediaType,
      'posterUrl': posterUrl,
      'backdropUrl': backdropUrl,
      'description': description,
      'rating': rating,
      'updated_at_ms': updatedAtMs,
    };
    await box.put(mediaId, map);
    _emitChange();
  }

  Future<void> remove(String mediaId) async {
    final box = _boxOrNull;
    if (box == null) {
      return;
    }
    if (!box.containsKey(mediaId)) {
      return;
    }
    await box.delete(mediaId);
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
