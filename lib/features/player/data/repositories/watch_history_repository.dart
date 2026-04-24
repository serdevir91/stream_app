import 'package:hive/hive.dart';
import '../../domain/entities/watch_history.dart';
import '../models/watch_history_model.dart';

class WatchHistoryRepository {
  static const String boxName = 'watch_history_box';

  Future<void> init() async {
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(WatchHistoryModelAdapter());
    }
    await Hive.openBox<WatchHistoryModel>(boxName);
  }

  Box<WatchHistoryModel> get _box => Hive.box<WatchHistoryModel>(boxName);

  List<WatchHistory> getHistory() {
    return _box.values.toList();
  }

  Future<void> saveProgress(WatchHistory history) async {
    final model = WatchHistoryModel.fromEntity(history);
    await _box.put(model.mediaId, model);
  }

  WatchHistory? getProgress(String mediaId) {
    return _box.get(mediaId);
  }
}
