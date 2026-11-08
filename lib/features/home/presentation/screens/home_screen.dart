import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/theme_x.dart';

import '../../../../core/app_baseline.dart';
import '../../../../core/i18n/app_text.dart';
import '../../../../core/settings/app_settings_provider.dart';
import '../../../../core/sync/sync_provider.dart';
import '../../../../core/tutorial/onboarding_tutorial_dialog.dart';
import '../../../player/presentation/providers/mini_player_provider.dart';
import '../../../player/presentation/widgets/mini_player.dart';
import '../../../player/presentation/screens/player_screen.dart';
import '../../../search/presentation/screens/search_screen.dart';
import '../../../library/presentation/screens/library_screen.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import 'home_content.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Trigger cloud synchronization on app launch
      ref.read(syncServiceProvider);
      final settings = ref.read(appSettingsProvider);
      if (!settings.hasSeenTutorial && mounted) {
        OnboardingTutorialDialog.show(context);
      } else if (mounted) {
        AppBaseline.checkForUpdatesSilently(context);
      }
    });
  }

  final Set<int> _visitedTabs = {0};

  final List<Widget> _screens = [
    const HomeContent(),
    const SearchScreen(),
    const LibraryScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final text = ref.watch(appTextProvider);
    final miniPlayerState = ref.watch(miniPlayerProvider);

    return Scaffold(
      // Tabs keep their state once opened; unopened tabs are not built yet.
      body: IndexedStack(
        index: _currentIndex,
        children: [
          for (var i = 0; i < _screens.length; i++)
            _visitedTabs.contains(i) ? _screens[i] : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (miniPlayerState.isActive)
            MiniPlayer(
              onTap: () {
                final state = ref.read(miniPlayerProvider);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DarkScope(child: PlayerScreen(
                      mediaId: state.mediaId ?? '',
                      title: state.title ?? '',
                      type: state.type ?? 'movie',
                      season: state.season,
                      episode: state.episode,
                      posterUrl: state.posterUrl,
                    )),
                  ),
                );
              },
              onClose: () {},
            ),
          NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
                _visitedTabs.add(index);
              });
            },
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home_rounded),
                label: text.t('home'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.search_rounded),
                label: text.t('search'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.video_library_outlined),
                selectedIcon: const Icon(Icons.video_library_rounded),
                label: text.t('library'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: const Icon(Icons.settings_rounded),
                label: text.t('settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
