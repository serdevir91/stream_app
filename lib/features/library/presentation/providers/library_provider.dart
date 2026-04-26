import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../search/domain/entities/media_item.dart';
import '../../data/repositories/library_repository.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository();
});

class LibraryNotifier extends Notifier<List<MediaItem>> {
  late LibraryRepository _repository;

  @override
  List<MediaItem> build() {
    _repository = ref.watch(libraryRepositoryProvider);
    return _repository.getItems();
  }

  void _reload() {
    state = _repository.getItems();
  }

  bool isInLibrary(String mediaId) {
    return state.any((item) => item.id == mediaId);
  }

  Future<bool> toggle(MediaItem item) async {
    final alreadySaved = _repository.contains(item.id);
    if (alreadySaved) {
      await _repository.remove(item.id);
      _reload();
      return false;
    }

    await _repository.upsert(item);
    _reload();
    return true;
  }

  Future<void> remove(String mediaId) async {
    await _repository.remove(mediaId);
    _reload();
  }
}

final libraryProvider = NotifierProvider<LibraryNotifier, List<MediaItem>>(
  LibraryNotifier.new,
);
