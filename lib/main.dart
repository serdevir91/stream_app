import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/backend_bootstrap_service.dart';
import 'core/settings/app_settings_repository.dart';
import 'features/sources/data/repositories/sources_repository.dart';

import 'features/home/presentation/screens/home_screen.dart';
import 'features/library/data/repositories/library_repository.dart';
import 'features/player/data/repositories/watch_history_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  final appSettingsRepository = AppSettingsRepository();
  await appSettingsRepository.init();
  final appSettings = appSettingsRepository.getSettings();

  await BackendBootstrapService.ensureBackendRunning(
    tmdbAccessToken: appSettings.tmdbAccessToken,
  );
  await BackendBootstrapService.syncTmdbToken(appSettings.tmdbAccessToken);

  final sourcesRepository = SourcesRepository();
  await sourcesRepository.init();

  final watchHistoryRepository = WatchHistoryRepository();
  await watchHistoryRepository.init();

  final libraryRepository = LibraryRepository();
  await libraryRepository.init();

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stream App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
