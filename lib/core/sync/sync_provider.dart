import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_service.dart';
import 'device_identity.dart';
import '../../features/library/presentation/providers/library_provider.dart';
import '../../features/player/presentation/providers/player_provider.dart';

final syncServiceProvider = Provider<SyncService?>((ref) {
  final watchHistoryRepo = ref.watch(watchHistoryRepositoryProvider);
  final libraryRepo = ref.watch(libraryRepositoryProvider);
  final service = SyncService(watchHistoryRepo, libraryRepo);
  unawaited(service.init());
  ref.onDispose(service.dispose);
  ref.listen<int>(
    watchHistoryChangesProvider.select((value) => value.value ?? 0),
    (previous, next) => service.syncDebounced(),
  );
  ref.listen<int>(
    libraryChangesProvider.select((value) => value.value ?? 0),
    (previous, next) => service.syncDebounced(),
  );
  return service;
});

final syncRegisteredProvider = FutureProvider<bool>((ref) async {
  return await DeviceIdentity.isRegistered();
});

final syncStatusProvider = FutureProvider<SyncStatus>((ref) async {
  final isRegistered = await ref.watch(syncRegisteredProvider.future);
  if (!isRegistered) return SyncStatus.disabled;

  final syncService = ref.watch(syncServiceProvider);
  if (syncService == null) return SyncStatus.disabled;

  final lastSync = await syncService.getLastSyncTimestamp();
  return SyncStatus(
    lastSyncMs: lastSync,
    isEnabled: true,
  );
});

class SyncStatus {
  final int lastSyncMs;
  final bool isEnabled;

  const SyncStatus({this.lastSyncMs = 0, this.isEnabled = false});

  static const SyncStatus disabled = SyncStatus();

  String get lastSyncFormatted {
    if (lastSyncMs == 0) return 'Hic senkronlanmadi';
    final date = DateTime.fromMillisecondsSinceEpoch(lastSyncMs);
    return '${date.day}.${date.month}.${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
