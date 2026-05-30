import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_service.dart';
import 'device_identity.dart';
import '../../features/library/presentation/providers/library_provider.dart';
import '../../features/library/presentation/providers/watched_provider.dart';
import '../../features/player/presentation/providers/player_provider.dart';
import '../../features/sources/presentation/providers/sources_provider.dart';
import '../settings/app_settings_provider.dart';
import '../backend/addon_service_provider.dart';
import '../../features/addons/presentation/screens/addon_manager_screen.dart';

final syncServiceProvider = Provider<SyncService?>((ref) {
  final watchHistoryRepo = ref.watch(watchHistoryRepositoryProvider);
  final libraryRepo = ref.watch(libraryRepositoryProvider);
  final watchedRepo = ref.watch(watchedRepositoryProvider);
  final settingsRepo = ref.watch(appSettingsRepositoryProvider);
  final sourcesRepo = ref.watch(sourcesRepositoryProvider);
  final addonConfigRepo = ref.watch(addonConfigRepositoryProvider);

  final service = SyncService(
    watchHistoryRepo: watchHistoryRepo,
    libraryRepo: libraryRepo,
    watchedRepo: watchedRepo,
    settingsRepo: settingsRepo,
    sourcesRepo: sourcesRepo,
    addonConfigRepo: addonConfigRepo,
  );
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
  ref.listen<int>(
    watchedChangesProvider.select((value) => value.value ?? 0),
    (previous, next) => service.syncDebounced(),
  );
  ref.listen(
    appSettingsProvider,
    (previous, next) => service.syncDebounced(),
  );
  ref.listen(
    sourcesProvider,
    (previous, next) => service.syncDebounced(),
  );
  ref.listen<int>(
    addonConfigChangesProvider.select((value) => value.value ?? 0),
    (previous, next) {
      service.syncDebounced();
      ref.read(addonServiceProvider).reloadConfig();
      ref.invalidate(addonsProvider);
    },
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
    if (lastSyncMs == 0) return 'Never';
    final date = DateTime.fromMillisecondsSinceEpoch(lastSyncMs);
    final dayStr = date.day.toString().padLeft(2, '0');
    final monthStr = date.month.toString().padLeft(2, '0');
    final hourStr = date.hour.toString().padLeft(2, '0');
    final minuteStr = date.minute.toString().padLeft(2, '0');
    return '$dayStr.$monthStr.${date.year} $hourStr:$minuteStr';
  }
}
