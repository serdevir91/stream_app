import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../search/domain/entities/media_item.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../data/repositories/library_repository.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository();
});

final libraryChangesProvider = StreamProvider<int>((ref) {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.watchChanges();
});

class LibraryNotifier extends Notifier<List<MediaItem>> {
  late LibraryRepository _repository;

  @override
  List<MediaItem> build() {
    _repository = ref.watch(libraryRepositoryProvider);
    ref.watch(libraryChangesProvider);
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

/// Library items sorted by most recently watched first.
/// Items without watch history are placed at the end in their original order.
final sortedLibraryProvider = Provider<List<MediaItem>>((ref) {
  final items = ref.watch(libraryProvider);
  ref.watch(watchHistoryChangesProvider);
  final historyRepo = ref.watch(watchHistoryRepositoryProvider);
  final allHistory = historyRepo.getAllHistory();

  // Build a map of mediaId -> latest updatedAtMs across all episodes.
  final lastWatchedMap = <String, int>{};
  for (final entry in allHistory) {
    final existing = lastWatchedMap[entry.mediaId];
    if (existing == null || entry.updatedAtMs > existing) {
      lastWatchedMap[entry.mediaId] = entry.updatedAtMs;
    }
  }

  final sorted = List<MediaItem>.from(items);
  sorted.sort((a, b) {
    final aTime = lastWatchedMap[a.id];
    final bTime = lastWatchedMap[b.id];
    // Both have watch history: sort by most recent first.
    if (aTime != null && bTime != null) {
      return bTime.compareTo(aTime);
    }
    // Only one has watch history: that one comes first.
    if (aTime != null) return -1;
    if (bTime != null) return 1;
    // Neither has watch history: keep original order.
    return 0;
  });

  return sorted;
});

