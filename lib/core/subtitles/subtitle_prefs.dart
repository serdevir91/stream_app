import 'package:hive/hive.dart';

/// Per-title subtitle offset, so a fix made in episode 1 carries over to the
/// rest of the series and survives restarts.
class SubtitlePrefs {
  SubtitlePrefs._();

  static const String boxName = 'subtitle_prefs_box';

  static Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<dynamic>(boxName);
    }
  }

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen(boxName) ? Hive.box<dynamic>(boxName) : null;

  static double? offsetFor(String mediaId) {
    final value = _box?.get('offset:$mediaId');
    return value is num ? value.toDouble() : null;
  }

  static Future<void> setOffset(String mediaId, double seconds) async {
    final box = _box;
    if (box == null || mediaId.isEmpty) return;
    if (seconds == 0) {
      await box.delete('offset:$mediaId');
    } else {
      await box.put('offset:$mediaId', seconds);
    }
  }
}
