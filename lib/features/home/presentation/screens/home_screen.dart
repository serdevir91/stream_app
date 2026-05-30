import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_text.dart';
import '../../../../core/sync/sync_provider.dart';
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
    });
  }

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
      body: _screens[_currentIndex],
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (miniPlayerState.isActive)
            MiniPlayer(
              onTap: () {
                final state = ref.read(miniPlayerProvider);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(
                      mediaId: state.mediaId ?? '',
                      title: state.title ?? '',
                      type: state.type ?? 'movie',
                      season: state.season,
                      episode: state.episode,
                      posterUrl: state.posterUrl,
                    ),
                  ),
                );
              },
              onClose: () {},
            ),
          BottomNavigationBar(
            currentIndex: _currentIndex,
            type: BottomNavigationBarType.fixed,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            items: [
              BottomNavigationBarItem(
                icon: const Icon(Icons.home),
                label: text.t('home'),
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.search),
                label: text.t('search'),
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.library_books),
                label: text.t('library'),
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.settings),
                label: text.t('settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
