import 'package:hive/hive.dart';
import '../../domain/entities/source.dart';
import '../models/source_model.dart';

class SourcesRepository {
  static const String boxName = 'sources_box';

  Future<void> init() async {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(SourceModelAdapter());
    }
    await Hive.openBox<SourceModel>(boxName);
  }

  Box<SourceModel> get _box => Hive.box<SourceModel>(boxName);

  List<Source> getSources() {
    return _box.values.toList();
  }

  Future<void> addSource(Source source) async {
    final model = SourceModel.fromEntity(source);
    await _box.put(model.id, model);
  }

  Future<void> removeSource(String id) async {
    await _box.delete(id);
  }

  Future<void> toggleSource(String id, bool isEnabled) async {
    final model = _box.get(id);
    if (model != null) {
      final updatedModel = SourceModel.fromEntity(
        model.copyWith(isEnabled: isEnabled),
      );
      await _box.put(id, updatedModel);
    }
  }
}
