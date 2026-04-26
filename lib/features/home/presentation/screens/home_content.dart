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

class HomeContent extends ConsumerWidget {
  const HomeContent({super.key});

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

  MediaItem? _pickFirst(AsyncValue<List<MediaItem>> source) {
    final data = source.maybeWhen(data: (items) => items, orElse: () => null);
    if (data == null || data.isEmpty) {
      return null;
    }
    return data.first;
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(appTextProvider);
    final settings = ref.watch(appSettingsProvider);

    final trendingMovies = ref.watch(trendingMoviesProvider);
    final trendingSeries = ref.watch(trendingSeriesProvider);
    final animationMovies = ref.watch(animationMoviesProvider);
    final horrorMovies = ref.watch(horrorMoviesProvider);
    final dramaMovies = ref.watch(dramaMoviesProvider);
    final thrillerMovies = ref.watch(thrillerMoviesProvider);
    final animeSeries = ref.watch(animeSeriesProvider);

    final continueItems = ref.watch(continueWatchingProvider);
    final libraryItems = ref.watch(libraryProvider);

    final featured =
        (continueItems.isNotEmpty
            ? _historyToMediaItem(continueItems.first.baseHistory)
            : null) ??
        _pickFirst(trendingMovies) ??
        _pickFirst(trendingSeries) ??
        _pickFirst(animationMovies);

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
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (featured != null)
              _buildHeroBanner(
                context,
                ref,
                featured,
                subtitleLanguage: settings.subtitleLanguage,
              ),
            if (continueItems.isNotEmpty) ...[
              _buildSectionTitle(text.t('continue_watching')),
              _buildContinueWatchingList(
                context,
                ref,
                continueItems,
                subtitleLanguage: settings.subtitleLanguage,
              ),
            ],
            if (libraryItems.isNotEmpty) ...[
              _buildSectionTitle(text.t('my_list')),
              _buildLibraryQuickList(context, libraryItems),
            ],
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
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroBanner(
    BuildContext context,
    WidgetRef ref,
    MediaItem featured, {
    required String subtitleLanguage,
  }) {
    final text = ref.watch(appTextProvider);
    final heroImage = featured.backdropUrl ?? featured.posterUrl;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      height: 240,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.grey.shade900,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (heroImage != null)
            Image.network(
              heroImage,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const ColoredBox(color: Colors.black38),
            )
          else
            const ColoredBox(color: Colors.black38),
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
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  text.t('featured'),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  featured.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PlayerScreen(
                              mediaId: featured.id,
                              title: featured.title,
                              type: featured.type,
                              season: 1,
                              episode: 1,
                              posterUrl: featured.posterUrl,
                              backdropUrl: featured.backdropUrl,
                              subtitleLanguage: subtitleLanguage,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: Text(text.t('play_now')),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                MediaDetailsScreen(mediaItem: featured),
                          ),
                        );
                      },
                      icon: const Icon(Icons.info_outline),
                      label: Text(text.t('details')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueWatchingList(
    BuildContext context,
    WidgetRef ref,
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
          final progress = item.startFromBeginning
              ? 0.0
              : history.progressRatio;

          String subtitle;
          if (history.mediaType == 'tv') {
            final episodeTag = 'S${item.targetSeason}:E${item.targetEpisode}';
            subtitle = item.startFromBeginning
                ? '${text.t('next_episode')} • $episodeTag'
                : '${text.t('resume')} • $episodeTag';
          } else {
            subtitle = text.t('resume');
          }

          return GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PlayerScreen(
                    mediaId: history.mediaId,
                    title: history.title,
                    type: history.mediaType,
                    season: item.targetSeason,
                    episode: item.targetEpisode,
                    posterUrl: history.posterUrl,
                    backdropUrl: history.backdropUrl,
                    subtitleLanguage: subtitleLanguage,
                  ),
                ),
              );
            },
            child: Container(
              width: 150,
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
            child: Container(
              width: 135,
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
                      builder: (context) => MediaDetailsScreen(mediaItem: item),
                    ),
                  );
                },
                child: Container(
                  width: 140,
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
              );
            },
          ),
        );
      },
      loading: () => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, stack) =>
          SizedBox(height: 200, child: Center(child: Text('Error: $err'))),
    );
  }
}
