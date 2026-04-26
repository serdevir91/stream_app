import 'package:hive/hive.dart';

import '../../../search/domain/entities/media_item.dart';

class LibraryRepository {
  static const String boxName = 'library_box';

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

  bool contains(String mediaId) {
    return _boxOrNull?.containsKey(mediaId) ?? false;
  }

  Future<void> upsert(MediaItem item) async {
    final box = _boxOrNull ?? await Hive.openBox<dynamic>(boxName);
    await box.put(item.id, item.toMap());
  }

  Future<void> remove(String mediaId) async {
    final box = _boxOrNull;
    if (box == null) {
      return;
    }
    await box.delete(mediaId);
  }
}
