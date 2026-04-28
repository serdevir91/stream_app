import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_text.dart';
import '../../../../core/settings/app_settings_provider.dart';
import '../../../library/presentation/providers/library_provider.dart';
import '../../../player/data/repositories/watch_history_repository.dart';
import '../../../player/domain/entities/watch_history.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../player/presentation/screens/player_screen.dart';
import '../../../search/domain/entities/media_item.dart';
import '../../../search/presentation/screens/media_details_screen.dart';
import '../providers/home_provider.dart';

class HomeContent extends ConsumerStatefulWidget {
  const HomeContent({super.key});

  @override
  ConsumerState<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends ConsumerState<HomeContent> {
  late final PageController _featuredController;
  Timer? _featuredTimer;
  int _featuredCount = 0;

  @override
  void initState() {
    super.initState();
    _featuredController = PageController(
      viewportFraction: _featuredViewportFraction(),
    );
  }

  double _featuredViewportFraction() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
        return 1.0;
      default:
        return 0.92;
    }
  }

  @override
  void dispose() {
    _featuredTimer?.cancel();
    _featuredController.dispose();
    super.dispose();
  }

  void _syncFeaturedTimer(int count) {
    if (count <= 1) {
      _featuredCount = count;
      _featuredTimer?.cancel();
      _featuredTimer = null;
      return;
    }

    if (_featuredTimer != null && _featuredCount == count) {
      return;
    }

    _featuredCount = count;
    _featuredTimer?.cancel();
    _featuredTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !_featuredController.hasClients || _featuredCount <= 1) {
        return;
      }

      final currentPage = _featuredController.page?.round() ?? 0;
      final nextPage = (currentPage + 1) % _featuredCount;
      _featuredController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        top: 24.0,
        bottom: 8.0,
      ),
      child: Text(
        title,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildFeaturedImage(MediaItem item) {
    final backdrop = item.backdropUrl;
    final poster = item.posterUrl;

    if (backdrop != null && backdrop.isNotEmpty) {
      return Image.network(
        backdrop,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) =>
            const ColoredBox(color: Colors.black45),
      );
    }

    if (poster != null && poster.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            poster,
            fit: BoxFit.cover,
            color: Colors.black54,
            colorBlendMode: BlendMode.darken,
            errorBuilder: (context, error, stackTrace) =>
                const ColoredBox(color: Colors.black45),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Image.network(
              poster,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
        ],
      );
    }

    return const ColoredBox(color: Colors.black45);
  }

  MediaItem _historyToMediaItem(WatchHistory history) {
    return MediaItem(
      id: history.mediaId,
      title: history.title,
      type: history.mediaType,
      posterUrl: history.posterUrl,
      backdropUrl: history.backdropUrl,
      description: null,
      rating: null,
    );
  }

  void _openPlayer(
    BuildContext context,
    MediaItem item, {
    required String subtitleLanguage,
    int season = 1,
    int episode = 1,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          mediaId: item.id,
          title: item.title,
          type: item.type,
          season: season,
          episode: episode,
          posterUrl: item.posterUrl,
          backdropUrl: item.backdropUrl,
          subtitleLanguage: subtitleLanguage,
        ),
      ),
    );
  }

  Future<void> _removeFromContinueWatching(WatchHistory history) async {
    final text = ref.read(appTextProvider);
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(text.t('remove_from_continue')),
          content: Text(text.t('remove_from_continue_confirm')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(text.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(text.t('remove_button')),
            ),
          ],
        );
      },
    );

    if (shouldRemove != true) {
      return;
    }

    await ref.read(watchHistoryRepositoryProvider).deleteProgress(history.mediaId);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text.t('removed_from_continue'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = ref.watch(appTextProvider);
    final settings = ref.watch(appSettingsProvider);

    final featuredWeekly = ref.watch(featuredWeeklyProvider);
    final trendingMovies = ref.watch(trendingMoviesProvider);
    final trendingSeries = ref.watch(trendingSeriesProvider);
    final animationMovies = ref.watch(animationMoviesProvider);
    final horrorMovies = ref.watch(horrorMoviesProvider);
    final dramaMovies = ref.watch(dramaMoviesProvider);
    final thrillerMovies = ref.watch(thrillerMoviesProvider);
    final animeSeries = ref.watch(animeSeriesProvider);
    final recommended = ref.watch(recommendedForYouProvider);
    final classics = ref.watch(classicsProvider);
    final western = ref.watch(westernProvider);
    final movies1950s = ref.watch(movies1950sProvider);
    final movies1960s = ref.watch(movies1960sProvider);
    final movies1970s = ref.watch(movies1970sProvider);
    final movies1980s = ref.watch(movies1980sProvider);

    final continueItems = ref.watch(continueWatchingProvider);
    final libraryItems = ref.watch(libraryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          text.t('app_name'),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.redAccent,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(text.t('featured')),
            _buildFeaturedSlider(
              context,
              featuredWeekly,
              subtitleLanguage: settings.subtitleLanguage,
            ),
            if (continueItems.isNotEmpty) ...[
              _buildSectionTitle(text.t('continue_watching')),
              _buildContinueWatchingList(
                context,
                continueItems,
                subtitleLanguage: settings.subtitleLanguage,
              ),
            ],
            if (libraryItems.isNotEmpty) ...[
              _buildSectionTitle(text.t('my_list')),
              _buildLibraryQuickList(context, libraryItems),
            ],
            _buildSectionTitle(text.t('recommended_for_you')),
            _buildHorizontalList(
              context,
              recommended,
              noDataText: text.t('no_data'),
            ),
            _buildSectionTitle(text.t('trending_movies')),
            _buildHorizontalList(
              context,
              trendingMovies,
              noDataText: text.t('no_data'),
            ),
            _buildSectionTitle(text.t('trending_series')),
            _buildHorizontalList(
              context,
              trendingSeries,
              noDataText: text.t('no_data'),
            ),
            _buildSectionTitle(text.t('animation_movies')),
            _buildHorizontalList(
              context,
              animationMovies,
              noDataText: text.t('no_data'),
            ),
            _buildSectionTitle(text.t('anime_series')),
            _buildHorizontalList(
              context,
              animeSeries,
              noDataText: text.t('no_data'),
            ),
            _buildSectionTitle(text.t('horror_movies')),
            _buildHorizontalList(
              context,
              horrorMovies,
              noDataText: text.t('no_data'),
            ),
            _buildSectionTitle(text.t('drama_movies')),
            _buildHorizontalList(
              context,
              dramaMovies,
              noDataText: text.t('no_data'),
            ),
            _buildSectionTitle(text.t('thriller_movies')),
            _buildHorizontalList(
              context,
              thrillerMovies,
              noDataText: text.t('no_data'),
            ),
            _buildSectionTitle(text.t('classic_movies')),
            _buildHorizontalList(
              context,
              classics,
              noDataText: text.t('no_data'),
            ),
            _buildSectionTitle(text.t('western_movies')),
            _buildHorizontalList(
              context,
              western,
              noDataText: text.t('no_data'),
            ),
            _buildSectionTitle(text.t('movies_1950s')),
            _buildHorizontalList(
              context,
              movies1950s,
              noDataText: text.t('no_data'),
            ),
            _buildSectionTitle(text.t('movies_1960s')),
            _buildHorizontalList(
              context,
              movies1960s,
              noDataText: text.t('no_data'),
            ),
            _buildSectionTitle(text.t('movies_1970s')),
            _buildHorizontalList(
              context,
              movies1970s,
              noDataText: text.t('no_data'),
            ),
            _buildSectionTitle(text.t('movies_1980s')),
            _buildHorizontalList(
              context,
              movies1980s,
              noDataText: text.t('no_data'),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturedSlider(
    BuildContext context,
    AsyncValue<List<MediaItem>> asyncData, {
    required String subtitleLanguage,
  }) {
    final text = ref.watch(appTextProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideLayout = screenWidth >= 1000;
    final sliderHeight =
        (screenWidth * (isWideLayout ? 0.36 : 0.56)).clamp(210.0, 460.0);
    final cardMargin = isWideLayout ? 0.0 : 6.0;
    final cardRadius = isWideLayout ? 0.0 : 16.0;

    return asyncData.when(
      data: (items) {
        final backdropItems = items
            .where(
              (item) => item.backdropUrl != null && item.backdropUrl!.isNotEmpty,
            )
            .toList();
        final usable = backdropItems.isNotEmpty
            ? backdropItems
            : items
                  .where(
                    (item) =>
                        item.posterUrl != null && item.posterUrl!.isNotEmpty,
                  )
                  .toList();
        _syncFeaturedTimer(usable.length);

        if (usable.isEmpty) {
          return SizedBox(
            height: sliderHeight,
            child: Center(child: Text(text.t('no_data'))),
          );
        }

        return SizedBox(
          height: sliderHeight,
          child: PageView.builder(
            controller: _featuredController,
            itemCount: usable.length,
            itemBuilder: (context, index) {
              final item = usable[index];
              return GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MediaDetailsScreen(mediaItem: item),
                    ),
                  );
                },
                child: Container(
                  margin: EdgeInsets.symmetric(horizontal: cardMargin),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(cardRadius),
                    color: Colors.grey.shade900,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildFeaturedImage(item),
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black87],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.star, color: Colors.amber, size: 14),
                                const SizedBox(width: 4),
                                Text(item.rating?.toStringAsFixed(1) ?? 'N/A'),
                                const SizedBox(width: 10),
                                FilledButton.tonalIcon(
                                  onPressed: () {
                                    _openPlayer(
                                      context,
                                      item,
                                      subtitleLanguage: subtitleLanguage,
                                    );
                                  },
                                  icon: const Icon(Icons.play_arrow),
                                  label: Text(text.t('play_now')),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
      loading: () => SizedBox(
        height: sliderHeight,
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => SizedBox(
        height: sliderHeight,
        child: Center(child: Text('Error: $error')),
      ),
    );
  }

  Widget _buildContinueWatchingList(
    BuildContext context,
    List<ContinueWatchItem> items, {
    required String subtitleLanguage,
  }) {
    final text = ref.watch(appTextProvider);

    return SizedBox(
      height: 220,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final history = item.baseHistory;
          final image = history.posterUrl ?? history.backdropUrl;
          final progress = item.startFromBeginning ? 0.0 : history.progressRatio;

          String subtitle;
          if (history.mediaType == 'tv') {
            final episodeTag = 'S${item.targetSeason}:E${item.targetEpisode}';
            subtitle = item.startFromBeginning
                ? '${text.t('next_episode')} - $episodeTag'
                : '${text.t('resume')} - $episodeTag';
          } else {
            subtitle = text.t('resume');
          }

          return GestureDetector(
            onTap: () {
              _openPlayer(
                context,
                _historyToMediaItem(history),
                subtitleLanguage: subtitleLanguage,
                season: item.targetSeason,
                episode: item.targetEpisode,
              );
            },
            onLongPress: () => _removeFromContinueWatching(history),
            child: SizedBox(
              width: 150,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (image != null)
                              Image.network(
                                image,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const ColoredBox(color: Colors.grey),
                              )
                            else
                              const ColoredBox(color: Colors.grey),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 4,
                                backgroundColor: Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      history.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLibraryQuickList(BuildContext context, List<MediaItem> items) {
    return SizedBox(
      height: 210,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length.clamp(0, 12),
        itemBuilder: (context, index) {
          final item = items[index];
          return GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MediaDetailsScreen(mediaItem: item),
                ),
              );
            },
            child: SizedBox(
              width: 135,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: item.posterUrl != null
                            ? Image.network(
                                item.posterUrl!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorBuilder: (context, error, stackTrace) =>
                                    const ColoredBox(color: Colors.grey),
                              )
                            : const ColoredBox(
                                color: Colors.grey,
                                child: Center(child: Icon(Icons.bookmark)),
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHorizontalList(
    BuildContext context,
    AsyncValue<List<MediaItem>> asyncData, {
    required String noDataText,
  }) {
    return asyncData.when(
      data: (items) {
        if (items.isEmpty) {
          return SizedBox(height: 200, child: Center(child: Text(noDataText)));
        }
        return SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MediaDetailsScreen(mediaItem: item),
                    ),
                  );
                },
                child: SizedBox(
                  width: 140,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: item.posterUrl != null
                                ? Image.network(
                                    item.posterUrl!,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    errorBuilder: (context, error, stackTrace) =>
                                        const ColoredBox(color: Colors.grey),
                                  )
                                : const ColoredBox(
                                    color: Colors.grey,
                                    child: Center(child: Icon(Icons.movie)),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              item.rating?.toStringAsFixed(1) ?? 'N/A',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
      loading: () => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => SizedBox(
        height: 200,
        child: Center(child: Text('Error: $err')),
      ),
    );
  }
}
