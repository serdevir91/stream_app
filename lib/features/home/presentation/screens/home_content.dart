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
import 'category_media_screen.dart';
import '../providers/home_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeContent extends ConsumerStatefulWidget {
  const HomeContent({super.key});

  @override
  ConsumerState<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends ConsumerState<HomeContent> {
  late final PageController _featuredController;
  late final TextEditingController _tokenController;
  Timer? _featuredTimer;
  int _featuredCount = 0;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController();
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
    _tokenController.dispose();
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
    String? sourceId,
    int season = 1,
    int episode = 1,
  }) {
    final settings = ref.read(appSettingsProvider);
    final effectiveSourceId = (sourceId ?? '').trim().isNotEmpty
        ? sourceId!.trim()
        : settings.preferredSourceId.trim();
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
          sourceId: effectiveSourceId.isEmpty ? null : effectiveSourceId,
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

    await ref
        .read(watchHistoryRepositoryProvider)
        .deleteProgress(history.mediaId);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text.t('removed_from_continue'))));
  }

  Widget _buildTokenWarningBanner(BuildContext context, AppText text) {
    final settings = ref.read(appSettingsProvider);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orangeAccent,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text.t('tmdb_token_warning'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tokenController,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: text.t('paste_token_here'),
              hintStyle: const TextStyle(color: Colors.white38),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.orangeAccent),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.orangeAccent.withValues(alpha: 0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.orangeAccent),
              ),
              prefixIcon: const Icon(Icons.key, color: Colors.orangeAccent, size: 18),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () async {
                  final Uri url = Uri.parse('https://www.themoviedb.org/settings/api');
                  try {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } catch (_) {}
                },
                icon: const Icon(Icons.open_in_new, size: 14, color: Colors.orangeAccent),
                label: Text(
                  text.t('get_tmdb_token'),
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: () async {
                  final token = _tokenController.text.trim();
                  if (token.isEmpty) return;

                  final next = settings.copyWith(tmdbAccessToken: token);
                  final status = await ref.read(appSettingsProvider.notifier).saveSettings(next);
                  
                  if (!context.mounted) return;

                  final success = status == TmdbSyncStatus.synced || status == TmdbSyncStatus.skipped;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        success ? text.t('token_saved_success') : text.t('token_saved_fail'),
                        style: const TextStyle(fontSize: 13),
                      ),
                      backgroundColor: success ? Colors.green : Colors.red,
                    ),
                  );
                },
                icon: const Icon(Icons.save, size: 16),
                label: Text(text.t('save_token')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  AsyncValue<List<MediaItem>> _getCategoryData(WidgetRef ref, String key) {
    if (key.startsWith('studio_')) {
      final studioKey = key.replaceFirst('studio_', '');
      return ref.watch(studioMediaProvider(studioKey));
    }
    switch (key) {
      case 'recommended_for_you':
        return ref.watch(recommendedForYouProvider);
      case 'trending_movies':
        return ref.watch(trendingMoviesProvider);
      case 'trending_series':
        return ref.watch(trendingSeriesProvider);
      case 'animation_movies':
        return ref.watch(animationMoviesProvider);
      case 'anime_series':
        return ref.watch(animeSeriesProvider);
      case 'horror_movies':
        return ref.watch(horrorMoviesProvider);
      case 'drama_movies':
        return ref.watch(dramaMoviesProvider);
      case 'thriller_movies':
        return ref.watch(thrillerMoviesProvider);
      case 'classic_movies':
        return ref.watch(classicsProvider);
      case 'western_movies':
        return ref.watch(westernProvider);
      case 'movies_1950s':
        return ref.watch(movies1950sProvider);
      case 'movies_1960s':
        return ref.watch(movies1960sProvider);
      case 'movies_1970s':
        return ref.watch(movies1970sProvider);
      case 'movies_1980s':
        return ref.watch(movies1980sProvider);
      default:
        return const AsyncValue.data([]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = ref.watch(appTextProvider);
    final settings = ref.watch(appSettingsProvider);

    final featuredWeekly = ref.watch(featuredWeeklyProvider);
    final continueItems = ref.watch(continueWatchingProvider);
    final libraryItems = ref.watch(sortedLibraryProvider);

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
            if (settings.tmdbAccessToken.trim().isEmpty)
              _buildTokenWarningBanner(context, text),
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
            ...settings.homeCategories.map((key) {
              final asyncData = _getCategoryData(ref, key);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CategoryMediaScreen(
                            categoryKey: key,
                            title: text.t(key),
                          ),
                        ),
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: _buildSectionTitle(text.t(key))),
                        const Padding(
                          padding: EdgeInsets.only(right: 16.0, top: 24.0),
                          child: Icon(Icons.chevron_right, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  _buildHorizontalList(
                    context,
                    asyncData,
                    noDataText: text.t('no_data'),
                  ),
                ],
              );
            }),
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
    final sliderHeight = (screenWidth * (isWideLayout ? 0.36 : 0.56)).clamp(
      210.0,
      460.0,
    );
    final cardMargin = isWideLayout ? 0.0 : 6.0;
    final cardRadius = isWideLayout ? 0.0 : 16.0;

    return asyncData.when(
      data: (items) {
        final backdropItems = items
            .where(
              (item) =>
                  item.backdropUrl != null && item.backdropUrl!.isNotEmpty,
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
                                const Icon(
                                  Icons.star,
                                  color: Colors.amber,
                                  size: 14,
                                ),
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
          final progress = item.startFromBeginning
              ? 0.0
              : history.progressRatio;

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
                sourceId: history.sourceId,
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
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
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
    final text = ref.watch(appTextProvider);
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
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            item.posterUrl != null
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
                            Positioned(
                              bottom: 6,
                              left: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  text.t(item.type).toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
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
        final text = ref.watch(appTextProvider);
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
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                item.posterUrl != null
                                    ? Image.network(
                                        item.posterUrl!,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                const ColoredBox(
                                                  color: Colors.grey,
                                                ),
                                      )
                                    : const ColoredBox(
                                        color: Colors.grey,
                                        child: Center(child: Icon(Icons.movie)),
                                      ),
                                Positioned(
                                  bottom: 6,
                                  left: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 2.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.65),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      text.t(item.type).toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
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
                            const Icon(
                              Icons.star,
                              color: Colors.amber,
                              size: 14,
                            ),
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
      error: (err, _) =>
          SizedBox(height: 200, child: Center(child: Text('Error: $err'))),
    );
  }
}
