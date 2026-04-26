import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/source.dart';
import '../../data/repositories/sources_repository.dart';

final sourcesRepositoryProvider = Provider<SourcesRepository>((ref) {
  return SourcesRepository();
});

class SourcesNotifier extends Notifier<List<Source>> {
  late SourcesRepository _repository;

  @override
  List<Source> build() {
    _repository = ref.watch(sourcesRepositoryProvider);
    return _repository.getSources();
  }

  void _loadSources() {
    state = _repository.getSources();
  }

  Future<void> addSource(Source source) async {
    await _repository.addSource(source);
    _loadSources();
  }

  Future<void> removeSource(String id) async {
    await _repository.removeSource(id);
    _loadSources();
  }

  Future<void> toggleSource(String id, bool isEnabled) async {
    await _repository.toggleSource(id, isEnabled);
    _loadSources();
  }
}

final sourcesProvider = NotifierProvider<SourcesNotifier, List<Source>>(
  SourcesNotifier.new,
);
