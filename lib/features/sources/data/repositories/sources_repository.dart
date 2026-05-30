import 'package:hive/hive.dart';
import '../../domain/entities/source.dart';
import '../models/source_model.dart';

class SourcesRepository {
  static const String boxName = 'sources_box';
  static const String metaBoxName = 'sources_meta_box';

  Future<void> init() async {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(SourceModelAdapter());
    }
    await Hive.openBox<SourceModel>(boxName);
    await Hive.openBox<dynamic>(metaBoxName);
  }

  Box<SourceModel> get _box => Hive.box<SourceModel>(boxName);
  Box<dynamic> get _metaBox => Hive.box<dynamic>(metaBoxName);

  List<Source> getSources() {
    return _box.values.toList();
  }

  Future<void> addSource(Source source, {int? updatedAtMs}) async {
    final model = SourceModel.fromEntity(source);
    await _box.put(model.id, model);
    final timestamp = updatedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    await _metaBox.put('updated_at_ms_${model.id}', timestamp);
  }

  Future<void> removeSource(String id) async {
    await _box.delete(id);
    await _metaBox.delete('updated_at_ms_$id');
  }

  Future<void> toggleSource(String id, bool isEnabled, {int? updatedAtMs}) async {
    final model = _box.get(id);
    if (model != null) {
      final updatedModel = SourceModel.fromEntity(
        model.copyWith(isEnabled: isEnabled),
      );
      await _box.put(id, updatedModel);
      final timestamp = updatedAtMs ?? DateTime.now().millisecondsSinceEpoch;
      await _metaBox.put('updated_at_ms_$id', timestamp);
    }
  }

  int getSourceUpdatedAtMs(String id) {
    if (!Hive.isBoxOpen(metaBoxName)) return 0;
    return (_metaBox.get('updated_at_ms_$id') as int?) ?? 0;
  }
}
