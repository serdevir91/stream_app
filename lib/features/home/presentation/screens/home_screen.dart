import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_text.dart';
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

  final List<Widget> _screens = [
    const HomeContent(),
    const SearchScreen(),
    const LibraryScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final text = ref.watch(appTextProvider);

    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
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
    );
  }
}
