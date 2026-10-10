import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_text.dart';
import '../../domain/models/anime_item.dart';
import '../providers/anime_providers.dart';
import 'anime_details_screen.dart';
import 'anime_browse_screen.dart';
import 'anime_search_screen.dart';
import 'anime_discover_screen.dart';
import 'anime_extensions_screen.dart';

class AnimeScreen extends ConsumerStatefulWidget {
  const AnimeScreen({super.key});

  @override
  ConsumerState<AnimeScreen> createState() => _AnimeScreenState();
}

class _AnimeScreenState extends ConsumerState<AnimeScreen> {
  final PageController _spotlightController = PageController();
  int _currentSpotlightIndex = 0;
  Timer? _spotlightTimer;

  @override
  void initState() {
    super.initState();
    _startSpotlightTimer();
  }

  @override
  void dispose() {
    _spotlightTimer?.cancel();
    _spotlightController.dispose();
    super.dispose();
  }

  void _startSpotlightTimer() {
    _spotlightTimer?.cancel();
    _spotlightTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final state = ref.read(animeHomeScreenProvider);
      if (state.spotlight.isEmpty) return;
      final int nextIndex = (_currentSpotlightIndex + 1) % state.spotlight.length;
      _spotlightController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = ref.watch(appTextProvider);
    final state = ref.watch(animeHomeScreenProvider);
    final notifier = ref.read(animeHomeScreenProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.deepPurple, Colors.indigoAccent],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'ANIME',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              text.t('anime'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded, color: Colors.amberAccent),
            tooltip: text.languageCode == 'tr' ? 'Anime Keşfet' : 'Anime Discover',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AnimeDiscoverScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.extension_rounded, color: Colors.deepPurpleAccent),
            tooltip: text.languageCode == 'tr' ? 'Anime Eklentileri' : 'Anime Extensions',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AnimeExtensionsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.search_rounded, color: Colors.white),
            tooltip: text.t('search'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AnimeSearchScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: text.t('refresh'),
            onPressed: () => notifier.loadHomeData(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => notifier.loadHomeData(),
        color: Colors.deepPurpleAccent,
        backgroundColor: const Color(0xFF1A1A24),
        child: state.isLoading && state.spotlight.isEmpty
            ? const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent))
            : state.error != null && state.trending.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_off_rounded, size: 56, color: Colors.white38),
                          const SizedBox(height: 16),
                          Text(
                            text.t('no_data'),
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            state.error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => notifier.loadHomeData(),
                            icon: const Icon(Icons.refresh),
                            label: Text(text.t('try_again')),
                          ),
                        ],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Spotlight Hero Carousel
                        if (state.spotlight.isNotEmpty) ...[
                          _buildSpotlightCarousel(state.spotlight, text),
                          const SizedBox(height: 16),
                        ],

                        // Discover Banner Card
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const AnimeDiscoverScreen()),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFF6C5CE7).withValues(alpha: 0.35),
                                    const Color(0xFF3F51B5).withValues(alpha: 0.2),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.deepPurpleAccent.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.deepPurpleAccent.withValues(alpha: 0.25),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.style_rounded, color: Colors.amberAccent, size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          text.languageCode == 'tr' ? 'Anime Keşfet (Kart Modu)' : 'Anime Discover (Card Mode)',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          text.languageCode == 'tr'
                                              ? 'Kaydırarak yeni animeler keşfedin ve listenize ekleyin.'
                                              : 'Swipe cards to discover trending & top anime for your watchlist.',
                                          style: const TextStyle(color: Colors.white60, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 14),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Genre Chips Bar
                        if (state.genres.isNotEmpty) ...[
                          _buildGenreFilterBar(state, notifier, text),
                          const SizedBox(height: 16),
                        ],

                        // Selected Genre Section (if filtered)
                        if (state.selectedGenre != null) ...[
                          if (state.isGenreLoading)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: CircularProgressIndicator(color: Colors.deepPurpleAccent),
                              ),
                            )
                          else if (state.genreItems.isNotEmpty)
                            _buildAnimeSection(
                              title: state.selectedGenre!,
                              subtitle: '${state.genreItems.length} Titles',
                              items: state.genreItems,
                              onViewAll: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => AnimeBrowseScreen(
                                      title: state.selectedGenre!,
                                      genre: state.selectedGenre,
                                    ),
                                  ),
                                );
                              },
                              text: text,
                            ),
                          const SizedBox(height: 16),
                        ],

                        // Trending (Top Airing)
                        if (state.trending.isNotEmpty) ...[
                          _buildAnimeSection(
                            title: text.languageCode == 'tr' ? 'Trend Animeler' : 'Trending Anime',
                            subtitle: text.languageCode == 'tr' ? 'Şu Anda Yayınlananlar' : 'Top Airing Now',
                            items: state.trending,
                            onViewAll: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AnimeBrowseScreen(
                                    title: text.languageCode == 'tr' ? 'Trend Animeler' : 'Trending Anime',
                                    filter: 'airing',
                                  ),
                                ),
                              );
                            },
                            text: text,
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Current Season (This Season)
                        if (state.seasonNow.isNotEmpty) ...[
                          _buildAnimeSection(
                            title: text.languageCode == 'tr' ? 'Bu Sezonun Animeleri' : 'This Season',
                            subtitle: text.languageCode == 'tr' ? 'Sezonun Popüler Yapımları' : 'Current Season Hits',
                            items: state.seasonNow,
                            onViewAll: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AnimeBrowseScreen(
                                    title: text.languageCode == 'tr' ? 'Bu Sezonun Animeleri' : 'This Season',
                                    isSeasonNow: true,
                                  ),
                                ),
                              );
                            },
                            text: text,
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Popular Anime (All time by popularity)
                        if (state.popular.isNotEmpty) ...[
                          _buildAnimeSection(
                            title: text.languageCode == 'tr' ? 'En Popüler Animeler' : 'Popular Anime',
                            subtitle: text.languageCode == 'tr' ? 'Hayranların Favorileri' : 'All-Time Fan Favorites',
                            items: state.popular,
                            onViewAll: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AnimeBrowseScreen(
                                    title: text.languageCode == 'tr' ? 'En Popüler Animeler' : 'Popular Anime',
                                    filter: 'bypopularity',
                                  ),
                                ),
                              );
                            },
                            text: text,
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Top Rated
                        if (state.topRated.isNotEmpty) ...[
                          _buildAnimeSection(
                            title: text.languageCode == 'tr' ? 'En Çok Beğenilenler' : 'Top Rated Anime',
                            subtitle: text.languageCode == 'tr' ? 'Tüm Zamanların En İyileri' : 'Top Ranked of All Time',
                            items: state.topRated,
                            onViewAll: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AnimeBrowseScreen(
                                    title: text.languageCode == 'tr' ? 'En Çok Beğenilenler' : 'Top Rated Anime',
                                  ),
                                ),
                              );
                            },
                            text: text,
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Upcoming Anime
                        if (state.upcoming.isNotEmpty) ...[
                          _buildAnimeSection(
                            title: text.languageCode == 'tr' ? 'Yakında Yayınlanacaklar' : 'Upcoming Anime',
                            subtitle: text.languageCode == 'tr' ? 'Gelecek Sezonlar' : 'Coming Soon',
                            items: state.upcoming,
                            onViewAll: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AnimeBrowseScreen(
                                    title: text.languageCode == 'tr' ? 'Yakında Yayınlanacaklar' : 'Upcoming Anime',
                                    filter: 'upcoming',
                                  ),
                                ),
                              );
                            },
                            text: text,
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Recently Updated Anime
                        if (state.recentlyUpdated.isNotEmpty) ...[
                          _buildAnimeSection(
                            title: text.languageCode == 'tr' ? 'Son Güncellenenler' : 'Recently Updated',
                            subtitle: text.languageCode == 'tr' ? 'Yeni Eklenen Bölümler' : 'Fresh Releases',
                            items: state.recentlyUpdated,
                            onViewAll: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AnimeBrowseScreen(
                                    title: text.languageCode == 'tr' ? 'Son Güncellenenler' : 'Recently Updated',
                                    isRecentlyUpdated: true,
                                  ),
                                ),
                              );
                            },
                            text: text,
                          ),
                          const SizedBox(height: 32),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Spotlight Carousel Widget
  // -------------------------------------------------------------

  Widget _buildSpotlightCarousel(List<AnimeItem> items, AppText text) {
    final size = MediaQuery.of(context).size;
    final cardHeight = size.height * 0.36;

    return Column(
      children: [
        SizedBox(
          height: cardHeight,
          child: PageView.builder(
            controller: _spotlightController,
            itemCount: items.length,
            onPageChanged: (index) {
              setState(() {
                _currentSpotlightIndex = index;
              });
            },
            itemBuilder: (context, index) {
              final anime = items[index];
              return GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AnimeDetailsScreen(anime: anime),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Image
                        if (anime.backdropUrl != null || anime.posterUrl != null)
                          Image.network(
                            anime.backdropUrl ?? anime.posterUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const ColoredBox(color: Color(0xFF1E1E28)),
                          )
                        else
                          const ColoredBox(color: Color(0xFF1E1E28)),

                        // Gradient
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.3),
                                Colors.black.withValues(alpha: 0.85),
                                Colors.black.withValues(alpha: 0.98),
                              ],
                              stops: const [0.3, 0.55, 0.8, 1.0],
                            ),
                          ),
                        ),

                        // Score & Status Badges at Top
                        Positioned(
                          top: 14,
                          left: 14,
                          right: 14,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (anime.score != null && anime.score! > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.amber.withValues(alpha: 0.6)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                                      const SizedBox(width: 4),
                                      Text(
                                        anime.score!.toStringAsFixed(1),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                const SizedBox.shrink(),
                              if (anime.isAiring)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.deepPurpleAccent.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'AIRING',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 10,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Content Details at Bottom
                        Positioned(
                          bottom: 16,
                          left: 16,
                          right: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                anime.displayTitle,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                anime.subtitleInfo,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (anime.genres.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: anime.genres.take(3).map((g) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.white12),
                                      ),
                                      child: Text(
                                        g,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // Indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(items.length, (i) {
            final isSelected = i == _currentSpotlightIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isSelected ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: isSelected ? Colors.deepPurpleAccent : Colors.white24,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // Genre Filter Bar
  // -------------------------------------------------------------

  Widget _buildGenreFilterBar(
    AnimeHomeState state,
    AnimeHomeNotifier notifier,
    AppText text,
  ) {
    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: state.genres.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            final isAll = state.selectedGenre == null;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(text.languageCode == 'tr' ? 'Tümü' : 'All'),
                selected: isAll,
                selectedColor: Colors.deepPurpleAccent,
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                side: BorderSide(
                  color: isAll ? Colors.deepPurpleAccent : Colors.white12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                labelStyle: TextStyle(
                  color: isAll ? Colors.white : Colors.white70,
                  fontSize: 12,
                  fontWeight: isAll ? FontWeight.bold : FontWeight.normal,
                ),
                onSelected: (_) => notifier.selectGenre(null),
              ),
            );
          }

          final genre = state.genres[index - 1];
          final isSelected = state.selectedGenre == genre;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(genre),
              selected: isSelected,
              selectedColor: Colors.deepPurpleAccent,
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              side: BorderSide(
                color: isSelected ? Colors.deepPurpleAccent : Colors.white12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              onSelected: (_) => notifier.selectGenre(genre),
            ),
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------
  // Anime Section Row
  // -------------------------------------------------------------

  Widget _buildAnimeSection({
    required String title,
    required String subtitle,
    required List<AnimeItem> items,
    required VoidCallback onViewAll,
    required AppText text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: onViewAll,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Row(
                  children: [
                    Text(
                      text.languageCode == 'tr' ? 'Tümü' : 'View All',
                      style: const TextStyle(
                        color: Colors.deepPurpleAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: Colors.deepPurpleAccent, size: 16),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Horizontal List of Cards
        SizedBox(
          height: 216,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _buildAnimeCard(item);
            },
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // Anime Card
  // -------------------------------------------------------------

  Widget _buildAnimeCard(AnimeItem item) {
    return Container(
      width: 126,
      margin: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AnimeDetailsScreen(anime: item),
            ),
          );
        },
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Poster
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 2 / 3,
                    child: item.posterUrl != null
                        ? Image.network(
                            item.posterUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const ColoredBox(color: Color(0xFF1E1E28)),
                          )
                        : const ColoredBox(color: Color(0xFF1E1E28)),
                  ),

                  // Rating badge
                  if (item.score != null && item.score! > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, color: Colors.amber, size: 12),
                            const SizedBox(width: 2),
                            Text(
                              item.score!.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Episode count / Status badge
                  if (item.episodes != null && item.episodes! > 0)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${item.episodes} Ep',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  else if (item.isAiring)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.deepPurpleAccent.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Airing',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 6),

            // Title
            Text(
              item.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
