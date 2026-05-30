import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'addon_service.dart';
import 'addons/addon_config_repository.dart';

AddonService? _addonServiceInstance;
AddonConfigRepository? _addonConfigRepoInstance;

void initAddonService(AddonService service) {
  _addonServiceInstance = service;
}

void initAddonConfigRepository(AddonConfigRepository repo) {
  _addonConfigRepoInstance = repo;
}

final addonConfigRepositoryProvider = Provider<AddonConfigRepository>((ref) {
  return _addonConfigRepoInstance ?? AddonConfigRepository();
});

final addonServiceProvider = Provider<AddonService>((ref) {
  if (_addonServiceInstance != null) return _addonServiceInstance!;
  final configRepo = ref.read(addonConfigRepositoryProvider);
  return AddonService(configRepo: configRepo);
});

final addonConfigChangesProvider = StreamProvider<int>((ref) {
  final repo = ref.watch(addonConfigRepositoryProvider);
  return repo.watchChanges();
});
