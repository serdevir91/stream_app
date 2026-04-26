import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/watch_history.dart';
import '../../data/repositories/watch_history_repository.dart';

final watchHistoryRepositoryProvider = Provider<WatchHistoryRepository>((ref) {
  return WatchHistoryRepository();
});

final watchHistoryChangesProvider = StreamProvider<int>((ref) {
  final repo = ref.watch(watchHistoryRepositoryProvider);
  return repo.watchChanges();
});

final continueWatchingProvider = Provider<List<ContinueWatchItem>>((ref) {
  ref.watch(watchHistoryChangesProvider);
  final repo = ref.watch(watchHistoryRepositoryProvider);
  return repo.getContinueWatchingItems();
});

final watchHistoryEntriesProvider = Provider<List<WatchHistory>>((ref) {
  ref.watch(watchHistoryChangesProvider);
  final repo = ref.watch(watchHistoryRepositoryProvider);
  return repo.getAllHistory();
});
