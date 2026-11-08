import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';

import 'core/app_baseline.dart';
import 'core/backend/addon_service.dart';
import 'core/backend/addon_service_provider.dart';
import 'core/backend/addons/addon_config_repository.dart';
import 'core/backend/source_ranking.dart';
import 'core/network/tmdb_cache_interceptor.dart';
import 'core/theme/app_theme.dart';
import 'core/backend_bootstrap_service.dart';
import 'core/settings/app_settings_repository.dart';
import 'core/subtitles/subtitle_prefs.dart';
import 'core/settings/app_settings_provider.dart';
import 'features/sources/data/repositories/sources_repository.dart';

import 'features/home/presentation/screens/home_screen.dart';
import 'features/library/data/repositories/library_repository.dart';
import 'features/library/data/repositories/watched_repository.dart';

import 'features/player/data/repositories/watch_history_repository.dart';
import 'features/downloads/data/services/download_service.dart';
import 'core/subtitles/online_subtitle_repository.dart';
import 'package:dio/dio.dart';
import 'features/downloads/presentation/providers/download_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await Hive.initFlutter();

  final appSettingsRepository = AppSettingsRepository();
  final addonConfigRepository = AddonConfigRepository();
  // Local boxes open side by side; none of them touches the network.
  await Future.wait([
    appSettingsRepository.init(),
    SubtitlePrefs.init(),
    SourceStats.init(),
    TmdbCacheInterceptor.init(),
    SourcesRepository().init(),
    WatchHistoryRepository().init(),
    LibraryRepository().init(),
    WatchedRepository().init(),
    addonConfigRepository.init(),
  ]);
  final appSettings = appSettingsRepository.getSettings();
  initAddonConfigRepository(addonConfigRepository);

  final addonService = AddonService(
    configRepo: addonConfigRepository,
    tmdbAccessToken: appSettings.tmdbAccessToken,
  )..preferredLanguage = appSettings.appLanguage == 'en'
        ? appSettings.subtitleLanguage
        : appSettings.appLanguage;
  await addonService.init();
  initAddonService(addonService);

  // Built per use so a TMDB token or Wyzie key saved later is picked up.
  final downloadService = DownloadService(
    subtitleRepoBuilder: () {
      final settings = appSettingsRepository.getSettings();
      return OnlineSubtitleRepository(
        Dio(),
        tmdbAccessToken: settings.tmdbAccessToken,
        wyzieApiKey: settings.wyzieApiKey,
      );
    },
  );
  initDownloadService(downloadService);

  runApp(const ProviderScope(child: MyApp()));

  // Work the first frame does not need runs after it.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await downloadService.init();
    await BackendBootstrapService.ensureBackendRunning(
      tmdbAccessToken: appSettings.tmdbAccessToken,
    );
    await BackendBootstrapService.syncTmdbToken(appSettings.tmdbAccessToken);
  });
}

final _baselineObserver = BaselineNavigatorObserver();

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final theme = AppTheme.forMode(settings.themeMode);

    return MaterialApp(
      title: 'Stream App',
      navigatorObservers: [_baselineObserver],
      debugShowCheckedModeBanner: false,
      theme: theme,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.overlayStyle(theme.brightness),
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomeScreen(),
    );
  }
}

