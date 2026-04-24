import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/watch_history_repository.dart';

final watchHistoryRepositoryProvider = Provider<WatchHistoryRepository>((ref) {
  return WatchHistoryRepository();
});
