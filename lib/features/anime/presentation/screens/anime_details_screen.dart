import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_text.dart';
import '../../../../core/settings/app_settings_provider.dart';
import '../../../library/presentation/providers/library_provider.dart';
import '../../../library/presentation/providers/watched_provider.dart';
import '../../../player/domain/entities/watch_history.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../player/presentation/screens/player_screen.dart';
import '../../../downloads/domain/entities/download_item.dart';
import '../../../downloads/presentation/providers/download_provider.dart';
import '../../domain/models/anime_item.dart';
import '../../domain/models/anime_episode.dart';
import '../../data/providers/anime_extensions_provider.dart';
import '../providers/anime_providers.dart';
import 'anime_extensions_screen.dart';

class AnimeDetailsScreen extends ConsumerStatefulWidget {
  final AnimeItem anime;

  const AnimeDetailsScreen({super.key, required this.anime});

  @override
  ConsumerState<AnimeDetailsScreen> createState() => _AnimeDetailsScreenState();
}

class _AnimeDetailsScreenState extends ConsumerState<AnimeDetailsScreen> {
  int _selectedTabIndex = 0;
  bool _isResolvingStream = false;
  int _selectedEpisodeBatch = 0;
  static const int _batchSize = 50;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _formatDuration(int ms) {
    if (ms <= 0) return '00:00';
    final duration = Duration(milliseconds: ms);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _episodeHistoryKey(int season, int episode) => '${season}_$episode';

  Map<String, WatchHistory> _tvEpisodeProgressByKey(List<WatchHistory> items) {
    final byKey = <String, WatchHistory>{};
    final mediaIdStr = 'anime_${widget.anime.malId}';
    for (final item in items) {
      if (item.mediaId.trim() != mediaIdStr &&
          item.mediaId.trim() != widget.anime.malId.toString()) {
        continue;
      }
      final key = _episodeHistoryKey(item.season, item.episode);
      final existing = byKey[key];
      if (existing == null || item.updatedAtMs > existing.updatedAtMs) {
        byKey[key] = item;
      }
    }
    return byKey;
  }

  WatchHistory? _latestMediaProgress(List<WatchHistory> items) {
    WatchHistory? latest;
    final mediaIdStr = 'anime_${widget.anime.malId}';
    for (final item in items) {
      if (item.mediaId.trim() != mediaIdStr &&
          item.mediaId.trim() != widget.anime.malId.toString()) {
        continue;
      }
      if (latest == null || item.updatedAtMs > latest.updatedAtMs) {
        latest = item;
      }
    }
    return latest;
  }

  Future<void> _toggleEpisodeWatched({
    required int episodeNumber,
    required bool isCurrentlyWatched,
    required Map<String, WatchHistory> tvEpisodeHistory,
  }) async {
    final repo = ref.read(watchHistoryRepositoryProvider);
    final key = _episodeHistoryKey(1, episodeNumber);
    if (isCurrentlyWatched) {
      final historyEntry = tvEpisodeHistory[key];
      if (historyEntry != null) {
        await repo.deleteByHistoryId(historyEntry.historyId);
      } else {
        await repo.deleteByHistoryId('tv_anime_${widget.anime.malId}_s1_e$episodeNumber');
      }
    } else {
      final newHistory = WatchHistory(
        mediaId: 'anime_${widget.anime.malId}',
        title: '${widget.anime.displayTitle} - Ep $episodeNumber',
        mediaType: widget.anime.isMovie ? 'movie' : 'tv',
        season: 1,
        episode: episodeNumber,
        posterUrl: widget.anime.posterUrl,
        backdropUrl: widget.anime.backdropUrl,
        lastPosition: 1,
        duration: 1,
        isWatched: true,
      );
      await repo.saveProgress(newHistory);
    }
  }

  Future<void> _toggleMovieWatched(bool isCurrentlyWatched) async {
    final repo = ref.read(watchHistoryRepositoryProvider);
    final history = ref.read(watchHistoryRepositoryProvider).getAllHistory();
    final latest = _latestMediaProgress(history);
    if (isCurrentlyWatched) {
      if (latest != null) {
        await repo.deleteByHistoryId(latest.historyId);
      } else {
        await repo.deleteByHistoryId('movie_anime_${widget.anime.malId}');
      }
    } else {
      final newHistory = WatchHistory(
        mediaId: 'anime_${widget.anime.malId}',
        title: widget.anime.displayTitle,
        mediaType: 'movie',
        season: 1,
        episode: 1,
        posterUrl: widget.anime.posterUrl,
        backdropUrl: widget.anime.backdropUrl,
        lastPosition: 1,
        duration: 1,
        isWatched: true,
      );
      await repo.saveProgress(newHistory);
    }
  }

  Future<void> _playEpisode({
    required AnimeItem anime,
    required AnimeEpisode episode,
    int? totalEpisodes,
    bool forceSelectStream = false,
  }) async {
    final text = ref.read(appTextProvider);
    final resolver = ref.read(animeStreamResolverProvider);
    final settings = ref.read(appSettingsProvider);
    final extensions = ref.read(animeExtensionsProvider);

    // If local downloaded file exists, play it directly
    final downloadService = ref.read(downloadServiceProvider);
    final itemId = anime.isMovie
        ? 'movie_anime_${anime.malId}'
        : 'tv_anime_${anime.malId}_s1_e${episode.episodeNumber}';
    final downloaded = downloadService.getItem(itemId);
    if (downloaded != null &&
        downloaded.status == 'completed' &&
        downloaded.localVideoPath.isNotEmpty &&
        File(downloaded.localVideoPath).existsSync()) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            mediaId: 'anime_${anime.malId}',
            title: anime.isMovie
                ? anime.displayTitle
                : '${anime.displayTitle} - ${episode.displayTitle}',
            type: anime.isMovie ? 'movie' : 'tv',
            season: 1,
            episode: episode.episodeNumber,
            posterUrl: anime.posterUrl,
            backdropUrl: anime.backdropUrl,
            localVideoPath: downloaded.localVideoPath,
            localSubtitlePath: downloaded.localSubtitlePath,
            preferAnimeSources: true,
          ),
        ),
      );
      return;
    }

    setState(() {
      _isResolvingStream = true;
    });

    try {
      final streams = await resolver.resolveEpisodeStreams(
        anime: anime,
        episodeNumber: episode.episodeNumber,
        extensions: extensions,
      );

      if (!mounted) return;

      if (streams.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(text.t('no_stream_found')),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final epCount = totalEpisodes ?? (anime.episodes ?? 1);

      // If user holds/requests server picker or if autoSelectSource is false
      if (forceSelectStream || !settings.autoSelectSource) {
        _showResolvedStreamsSheet(
          context,
          streams,
          episode: episode,
          totalEpisodes: epCount,
        );
        return;
      }

      // Auto-select first stream
      _launchPlayer(
        stream: streams.first,
        allStreams: streams,
        episode: episode,
        totalEpisodes: epCount,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${text.t('error_prefix')}: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResolvingStream = false;
        });
      }
    }
  }

  void _showResolvedStreamsSheet(
    BuildContext context,
    List<Map<String, dynamic>> streams, {
    required AnimeEpisode episode,
    required int totalEpisodes,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B1B26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.anime.isMovie
                          ? 'Select Movie Server'
                          : 'Ep ${episode.episodeNumber} - Select Server',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.extension_rounded, color: Colors.deepPurpleAccent, size: 20),
                      tooltip: 'Manage Anime Extensions',
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const AnimeExtensionsScreen()),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: streams.length,
                    itemBuilder: (context, index) {
                      final s = streams[index];
                      final provider = s['provider']?.toString() ?? 'Server ${index + 1}';
                      final quality = s['quality']?.toString() ?? 'HD';
                      final isDirect = s['is_direct_link'] == true;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF14141E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.deepPurpleAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isDirect ? Icons.flash_on_rounded : Icons.play_arrow_rounded,
                              color: Colors.deepPurpleAccent,
                            ),
                          ),
                          title: Text(
                            provider,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            isDirect ? 'Direct Stream (Fast & High Quality)' : 'External Mirror',
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              quality,
                              style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _launchPlayer(
                              stream: s,
                              allStreams: streams,
                              episode: episode,
                              totalEpisodes: totalEpisodes,
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _launchPlayer({
    required Map<String, dynamic> stream,
    required List<Map<String, dynamic>> allStreams,
    required AnimeEpisode episode,
    required int totalEpisodes,
  }) {
    final settings = ref.read(appSettingsProvider);
    final streamUrl = stream['url']?.toString() ?? '';
    final provider = stream['provider']?.toString() ?? 'Anime Stream';
    final isDirectLink = stream['is_direct_link'] == true;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          mediaId: 'anime_${widget.anime.malId}',
          title: widget.anime.isMovie
              ? widget.anime.displayTitle
              : '${widget.anime.displayTitle} - ${episode.displayTitle}',
          type: widget.anime.isMovie ? 'movie' : 'tv',
          season: 1,
          episode: episode.episodeNumber,
          posterUrl: widget.anime.posterUrl,
          backdropUrl: widget.anime.backdropUrl,
          initialStreamUrl: streamUrl,
          initialProvider: provider,
          initialIsDirectLink: isDirectLink,
          initialStreams: allStreams,
          subtitleLanguage: settings.subtitleLanguage,
          nextEpisodeNumber: (episode.episodeNumber < totalEpisodes)
              ? episode.episodeNumber + 1
              : null,
          totalEpisodesInSeason: totalEpisodes,
          preferAnimeSources: true,
        ),
      ),
    );
  }

  Future<void> _downloadEpisode(AnimeEpisode episode) async {
    final text = ref.read(appTextProvider);
    final resolver = ref.read(animeStreamResolverProvider);
    final downloadService = ref.read(downloadServiceProvider);
    final extensions = ref.read(animeExtensionsProvider);

    try {
      final streams = await resolver.resolveEpisodeStreams(
        anime: widget.anime,
        episodeNumber: episode.episodeNumber,
        extensions: extensions,
      );
      if (streams.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(text.t('no_stream_found')),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
      final directStream = streams.firstWhere(
        (s) => s['is_direct_link'] == true,
        orElse: () => streams.first,
      );

      final itemId = widget.anime.isMovie
          ? 'movie_anime_${widget.anime.malId}'
          : 'tv_anime_${widget.anime.malId}_s1_e${episode.episodeNumber}';

      final downloadItem = DownloadItem(
        id: itemId,
        mediaId: 'anime_${widget.anime.malId}',
        title: widget.anime.isMovie
            ? widget.anime.displayTitle
            : '${widget.anime.displayTitle} Ep ${episode.episodeNumber}',
        mediaType: widget.anime.isMovie ? 'movie' : 'tv',
        season: 1,
        episode: episode.episodeNumber,
        episodeTitle: episode.displayTitle,
        posterUrl: episode.thumbnailUrl ?? widget.anime.posterUrl,
        backdropUrl: widget.anime.backdropUrl,
        quality: directStream['quality']?.toString() ?? '1080p',
        streamUrl: directStream['url']?.toString() ?? '',
        localVideoPath: '',
        status: 'queued',
        createdAt: DateTime.now(),
      );
      await downloadService.startDownload(downloadItem);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              text.languageCode == 'tr'
                  ? '${episode.displayTitle} indirme sırasına alındı.'
                  : '${episode.displayTitle} added to downloads.',
            ),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${text.t('error_prefix')}: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = ref.watch(appTextProvider);
    final anime = widget.anime;
    final isMovie = anime.isMovie;
    final mediaItem = anime.toMediaItem();

    final detailsAsync = ref.watch(animeDetailsProvider(anime.malId));
    final detailsState = detailsAsync.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );
    final currentAnime = detailsState?.anime ?? anime;
    final episodes = detailsState?.episodes ?? const <AnimeEpisode>[];
    final characters = detailsState?.characters ?? const <Map<String, dynamic>>[];
    final recommendations = detailsState?.recommendations ?? const <AnimeItem>[];

    // Watch history tracking
    final allHistory = ref.watch(watchHistoryEntriesProvider);
    final tvEpisodeHistory = !isMovie ? _tvEpisodeProgressByKey(allHistory) : const <String, WatchHistory>{};
    final movieProgress = isMovie ? _latestMediaProgress(allHistory) : null;

    final inLibrary = ref.watch(
      libraryProvider.select((items) => items.any((i) => i.id == mediaItem.id)),
    );
    final isWatched = ref.watch(
      watchedProvider.select((items) => items.any((i) => i.id == mediaItem.id)),
    );

    final backdrop = currentAnime.backdropUrl ?? currentAnime.posterUrl;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Hero SliverAppBar with cinematic gradient overlays
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor: const Color(0xFF0F0F13),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.extension_rounded, color: Colors.deepPurpleAccent),
                tooltip: 'Anime Extensions',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AnimeExtensionsScreen()),
                  );
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (backdrop != null && backdrop.isNotEmpty)
                    Image.network(
                      backdrop,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF1E1E28)),
                    )
                  else
                    const ColoredBox(color: Color(0xFF1E1E28)),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.6),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.5),
                          const Color(0xFF0F0F13),
                        ],
                        stops: const [0.0, 0.3, 0.7, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Main Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    currentAnime.displayTitle,
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Metadata Badges Row
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Score Badge
                      if (currentAnime.score != null && currentAnime.score! > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                currentAnime.score!.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Content Type Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.deepPurpleAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          isMovie ? 'ANIME MOVIE' : (currentAnime.type.isNotEmpty ? 'ANIME ${currentAnime.type}' : 'ANIME TV'),
                          style: const TextStyle(
                            color: Colors.deepPurpleAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      // Year / Season
                      if (currentAnime.year != null && currentAnime.year! > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Text(
                            currentAnime.year.toString(),
                            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),

                      // Duration / Episodes
                      if (isMovie && currentAnime.duration != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Text(
                            currentAnime.duration!,
                            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        )
                      else if (!isMovie && (currentAnime.episodes != null || episodes.isNotEmpty))
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Text(
                            '${currentAnime.episodes ?? episodes.length} Ep',
                            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),

                      // Airing Status
                      if (currentAnime.isAiring)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.teal.withValues(alpha: 0.4)),
                          ),
                          child: const Text(
                            'AIRING',
                            style: TextStyle(color: Colors.tealAccent, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),

                  // Genres
                  if (currentAnime.genres.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: currentAnime.genres.map((genre) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Text(
                            genre,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade300,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Main Action Row (Library & Watched Toggles)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final added = await ref.read(libraryProvider.notifier).toggle(mediaItem);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  added ? text.t('added_to_library') : text.t('removed_from_library'),
                                ),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: inLibrary ? Colors.deepPurpleAccent : Colors.white24,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: Icon(
                            inLibrary ? Icons.bookmark_remove : Icons.bookmark_add_outlined,
                            color: inLibrary ? Colors.deepPurpleAccent : Colors.white,
                          ),
                          label: Text(
                            inLibrary ? text.t('remove_from_library') : text.t('add_to_library'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: inLibrary ? Colors.deepPurpleAccent : Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            if (isMovie) {
                              await _toggleMovieWatched(isWatched);
                            }
                            final added = await ref.read(watchedProvider.notifier).toggle(mediaItem);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  added ? text.t('added_to_watched') : text.t('removed_from_watched'),
                                ),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isWatched ? const Color(0xFF00E054) : Colors.white,
                            side: BorderSide(
                              color: isWatched ? const Color(0xFF00E054) : Colors.white24,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: Icon(
                            isWatched ? Icons.check_circle : Icons.visibility_outlined,
                            color: isWatched ? const Color(0xFF00E054) : Colors.white,
                          ),
                          label: Text(
                            isWatched ? text.t('watched') : text.t('mark_as_watched'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: isWatched ? const Color(0xFF00E054) : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Movie Play & Progress Box
                  if (isMovie) ...[
                    const SizedBox(height: 12),
                    _buildMoviePlayCard(
                      context,
                      anime: currentAnime,
                      progress: movieProgress,
                      text: text,
                    ),
                  ],

                  // TV Continue Watching Banner
                  if (!isMovie && episodes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildContinueWatchingBanner(
                      context,
                      anime: currentAnime,
                      episodes: episodes,
                      tvHistory: tvEpisodeHistory,
                      text: text,
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Segmented Tabs Header
                  _buildSegmentedTabsHeader(isMovie: isMovie, text: text),

                  const SizedBox(height: 16),

                  // Tab Contents
                  if (!isMovie && _selectedTabIndex == 0)
                    _buildEpisodesSection(
                      context,
                      episodes: episodes,
                      tvHistory: tvEpisodeHistory,
                      isLoading: detailsAsync.isLoading && episodes.isEmpty,
                      text: text,
                    )
                  else if ((!isMovie && _selectedTabIndex == 1) || (isMovie && _selectedTabIndex == 0))
                    _buildOverviewAndCastSection(
                      context,
                      anime: currentAnime,
                      characters: characters,
                      isLoading: detailsAsync.isLoading && characters.isEmpty,
                      text: text,
                    )
                  else
                    _buildRecommendedSection(
                      context,
                      recommendations: recommendations,
                      isLoading: detailsAsync.isLoading && recommendations.isEmpty,
                      text: text,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Movie Play Card
  // -------------------------------------------------------------

  Widget _buildMoviePlayCard(
    BuildContext context, {
    required AnimeItem anime,
    required WatchHistory? progress,
    required AppText text,
  }) {
    final effectiveDuration = (progress != null && progress.duration > 1)
        ? progress.duration
        : 100 * 60 * 1000;
    final progressRatio = (progress != null)
        ? (progress.isWatched ? 1.0 : (progress.lastPosition / effectiveDuration).clamp(0.0, 1.0))
        : 0.0;
    final isWatched = progress?.isWatched == true;

    final dummyMovieEpisode = AnimeEpisode(
      malId: anime.malId,
      episodeNumber: 1,
      title: anime.displayTitle,
      thumbnailUrl: anime.backdropUrl ?? anime.posterUrl,
    );

    return Column(
      children: [
        if (progress != null && (progress.lastPosition > 0 || isWatched)) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isWatched ? Icons.check_circle_rounded : Icons.play_circle_fill_rounded,
                          size: 16,
                          color: isWatched ? const Color(0xFF00E054) : Colors.deepPurpleAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          text.t('watch_history'),
                          style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                    Text(
                      isWatched ? text.t('completed') : '%${(progressRatio * 100).round()}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isWatched ? const Color(0xFF00E054) : Colors.deepPurpleAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progressRatio,
                    minHeight: 6,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isWatched ? const Color(0xFF00E054) : Colors.deepPurpleAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isWatched ? text.t('completed') : text.t('in_progress'),
                      style: const TextStyle(fontSize: 11, color: Colors.white60),
                    ),
                    if (progress.lastPosition > 0)
                      Text(
                        '${_formatDuration(progress.lastPosition)} / ${_formatDuration(effectiveDuration)}',
                        style: const TextStyle(fontSize: 11, color: Colors.white60, fontWeight: FontWeight.w500),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              flex: 3,
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isResolvingStream
                      ? null
                      : () => _playEpisode(
                            anime: anime,
                            episode: dummyMovieEpisode,
                            totalEpisodes: 1,
                          ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurpleAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  icon: _isResolvingStream
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.play_arrow_rounded, size: 24),
                  label: Text(
                    _isResolvingStream
                        ? text.t('resolving')
                        : (progressRatio > 0 ? text.t('resume') : (text.languageCode == 'tr' ? 'Filmi Oynat' : 'Play Movie')),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => _downloadEpisode(dummyMovieEpisode),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.cyanAccent,
                    side: const BorderSide(color: Colors.cyanAccent, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.download_for_offline_rounded, size: 20, color: Colors.cyanAccent),
                  label: Text(
                    text.languageCode == 'tr' ? 'İndir' : 'Download',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // TV Continue Watching Banner
  // -------------------------------------------------------------

  Widget _buildContinueWatchingBanner(
    BuildContext context, {
    required AnimeItem anime,
    required List<AnimeEpisode> episodes,
    required Map<String, WatchHistory> tvHistory,
    required AppText text,
  }) {
    // Find latest watched episode
    int targetEpNum = 1;
    WatchHistory? latestHistory;
    for (final ep in episodes) {
      final h = tvHistory[_episodeHistoryKey(1, ep.episodeNumber)];
      if (h != null) {
        if (latestHistory == null || h.updatedAtMs > latestHistory.updatedAtMs) {
          latestHistory = h;
          targetEpNum = ep.episodeNumber;
        }
      }
    }

    // If latest was completed, offer next episode
    if (latestHistory?.isWatched == true && targetEpNum < episodes.length) {
      targetEpNum++;
      latestHistory = tvHistory[_episodeHistoryKey(1, targetEpNum)];
    }

    final targetEpisode = episodes.firstWhere(
      (e) => e.episodeNumber == targetEpNum,
      orElse: () => episodes.first,
    );

    final isCompleted = latestHistory?.isWatched == true;
    final epDuration = (latestHistory != null && latestHistory.duration > 1)
        ? latestHistory.duration
        : 24 * 60 * 1000;
    final progressRatio = isCompleted
        ? 1.0
        : ((latestHistory != null && latestHistory.lastPosition > 0)
            ? (latestHistory.lastPosition / epDuration).clamp(0.0, 1.0)
            : 0.0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isCompleted
                        ? Icons.check_circle_rounded
                        : (progressRatio > 0 ? Icons.play_circle_fill_rounded : Icons.play_arrow_rounded),
                    size: 16,
                    color: isCompleted ? const Color(0xFF00E054) : Colors.deepPurpleAccent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Ep $targetEpNum: ${targetEpisode.displayTitle}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              if (isCompleted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E054).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    text.t('completed'),
                    style: const TextStyle(fontSize: 10, color: Color(0xFF00E054), fontWeight: FontWeight.bold),
                  ),
                )
              else if (progressRatio > 0)
                Text(
                  '%${(progressRatio * 100).round()}',
                  style: const TextStyle(fontSize: 12, color: Colors.deepPurpleAccent, fontWeight: FontWeight.bold),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressRatio,
              minHeight: 6,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(
                isCompleted ? const Color(0xFF00E054) : Colors.deepPurpleAccent,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (targetEpNum > 1) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isResolvingStream
                        ? null
                        : () {
                            final prev = episodes.firstWhere(
                              (e) => e.episodeNumber == targetEpNum - 1,
                              orElse: () => episodes.first,
                            );
                            _playEpisode(
                              anime: anime,
                              episode: prev,
                              totalEpisodes: episodes.length,
                            );
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.skip_previous, size: 16),
                    label: Text(
                      text.t('watch_previous_episode'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _isResolvingStream
                      ? null
                      : () => _playEpisode(
                            anime: anime,
                            episode: targetEpisode,
                            totalEpisodes: episodes.length,
                          ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurpleAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  icon: _isResolvingStream
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(
                    _isResolvingStream
                        ? text.t('resolving')
                        : (progressRatio > 0 ? text.t('resume') : text.t('play_now')),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
              if (targetEpNum < episodes.length) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isResolvingStream
                        ? null
                        : () {
                            final next = episodes.firstWhere(
                              (e) => e.episodeNumber == targetEpNum + 1,
                              orElse: () => episodes.last,
                            );
                            _playEpisode(
                              anime: anime,
                              episode: next,
                              totalEpisodes: episodes.length,
                            );
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.skip_next, size: 16),
                    label: Text(
                      text.t('watch_next_episode'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Segmented Tabs Header
  // -------------------------------------------------------------

  Widget _buildSegmentedTabsHeader({required bool isMovie, required AppText text}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          if (!isMovie)
            Expanded(
              child: _buildSegmentTab(
                title: text.t('episodes'),
                isSelected: _selectedTabIndex == 0,
                onTap: () => setState(() => _selectedTabIndex = 0),
              ),
            ),
          Expanded(
            child: _buildSegmentTab(
              title: text.languageCode == 'tr' ? 'Genel Bakış & Oyuncular' : 'Overview & Cast',
              isSelected: isMovie ? _selectedTabIndex == 0 : _selectedTabIndex == 1,
              onTap: () => setState(() => _selectedTabIndex = isMovie ? 0 : 1),
            ),
          ),
          Expanded(
            child: _buildSegmentTab(
              title: text.languageCode == 'tr' ? 'Öneriler' : 'Recommended',
              isSelected: isMovie ? _selectedTabIndex == 1 : _selectedTabIndex == 2,
              onTap: () => setState(() => _selectedTabIndex = isMovie ? 1 : 2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentTab({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.deepPurpleAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey.shade400,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Episodes Section (for Series)
  // -------------------------------------------------------------

  Widget _buildEpisodesSection(
    BuildContext context, {
    required List<AnimeEpisode> episodes,
    required Map<String, WatchHistory> tvHistory,
    required bool isLoading,
    required AppText text,
  }) {
    if (isLoading && episodes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: Colors.deepPurpleAccent),
        ),
      );
    }

    if (episodes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            text.t('no_episodes'),
            style: const TextStyle(color: Colors.white60),
          ),
        ),
      );
    }

    final totalBatches = (episodes.length / _batchSize).ceil();
    final startIdx = _selectedEpisodeBatch * _batchSize;
    final endIdx = (startIdx + _batchSize).clamp(0, episodes.length);
    final displayedEpisodes = episodes.sublist(startIdx, endIdx);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Batch selector pills (for long series with > 50 episodes)
        if (totalBatches > 1) ...[
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: totalBatches,
              itemBuilder: (context, bIdx) {
                final bStart = bIdx * _batchSize + 1;
                final bEnd = ((bIdx + 1) * _batchSize).clamp(1, episodes.length);
                final isSelected = bIdx == _selectedEpisodeBatch;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('$bStart - $bEnd'),
                    selected: isSelected,
                    selectedColor: Colors.deepPurpleAccent,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    side: BorderSide(
                      color: isSelected ? Colors.deepPurpleAccent : Colors.white12,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey.shade400,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedEpisodeBatch = bIdx;
                        });
                      }
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Header
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${text.t('episodes')} (${episodes.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
              Text(
                '${displayedEpisodes.length} Shown',
                style: const TextStyle(fontSize: 12, color: Colors.white38),
              ),
            ],
          ),
        ),

        // Episode List
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: displayedEpisodes.length,
          itemBuilder: (context, index) {
            final episode = displayedEpisodes[index];
            final history = tvHistory[_episodeHistoryKey(1, episode.episodeNumber)];
            final isEpWatched = history?.isWatched == true;
            final epDuration = (history != null && history.duration > 1)
                ? history.duration
                : ((episode.runtimeMinutes != null && episode.runtimeMinutes! > 0)
                    ? episode.runtimeMinutes! * 60 * 1000
                    : 24 * 60 * 1000);
            final progressRatio = isEpWatched
                ? 1.0
                : ((history != null && history.lastPosition > 0)
                    ? (history.lastPosition / epDuration).clamp(0.0, 1.0)
                    : 0.0);

            final epThumbnail = episode.thumbnailUrl ??
                widget.anime.backdropUrl ??
                widget.anime.posterUrl;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: ListTile(
                onTap: () => _playEpisode(
                  anime: widget.anime,
                  episode: episode,
                  totalEpisodes: episodes.length,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 100,
                    height: 60,
                    child: Stack(
                      fit: StackFit.expand,
                      alignment: Alignment.center,
                      children: [
                        if (epThumbnail != null && epThumbnail.isNotEmpty)
                          Image.network(
                            epThumbnail,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const ColoredBox(
                              color: Colors.white10,
                              child: Icon(Icons.movie, color: Colors.grey),
                            ),
                          )
                        else
                          const ColoredBox(
                            color: Colors.white10,
                            child: Icon(Icons.movie, color: Colors.grey),
                          ),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                title: Text(
                  '${episode.episodeNumber}. ${episode.displayTitle}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (episode.score != null && episode.score! > 0) ...[
                          const Icon(Icons.star_rounded, color: Colors.amber, size: 13),
                          const SizedBox(width: 2),
                          Text(
                            episode.score!.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          '${episode.runtimeMinutes ?? 24} dk',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                    if (progressRatio > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: progressRatio,
                                minHeight: 3,
                                backgroundColor: Colors.white10,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isEpWatched ? const Color(0xFF00E054) : Colors.deepPurpleAccent,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isEpWatched ? text.t('completed') : '%${(progressRatio * 100).round()}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isEpWatched ? const Color(0xFF00E054) : Colors.deepPurpleAccent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.download_for_offline_outlined, size: 20, color: Colors.cyanAccent),
                      tooltip: text.languageCode == 'tr' ? 'Bölümü İndir' : 'Download Episode',
                      onPressed: () => _downloadEpisode(episode),
                    ),
                    IconButton(
                      icon: Icon(
                        isEpWatched ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                        size: 20,
                        color: isEpWatched ? const Color(0xFF00E054) : Colors.white38,
                      ),
                      tooltip: text.languageCode == 'tr' ? 'İzlendi Olarak İşaretle' : 'Mark Watched',
                      onPressed: () => _toggleEpisodeWatched(
                        episodeNumber: episode.episodeNumber,
                        isCurrentlyWatched: isEpWatched,
                        tvEpisodeHistory: tvHistory,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // Overview & Cast Section
  // -------------------------------------------------------------

  Widget _buildOverviewAndCastSection(
    BuildContext context, {
    required AnimeItem anime,
    required List<Map<String, dynamic>> characters,
    required bool isLoading,
    required AppText text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Synopsis
        if (anime.synopsis != null && anime.synopsis!.trim().isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Text(
              anime.synopsis!.trim(),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade300,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Production Info Box
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (anime.studios.isNotEmpty) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.business_center_outlined, size: 16, color: Colors.deepPurpleAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${text.languageCode == "tr" ? "Stüdyolar" : "Studios"}: ${anime.studios.join(", ")}',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              if (anime.status.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 16, color: Colors.deepPurpleAccent),
                    const SizedBox(width: 8),
                    Text(
                      '${text.languageCode == "tr" ? "Durum" : "Status"}: ${anime.status}',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              if (anime.rating != null && anime.rating!.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 16, color: Colors.deepPurpleAccent),
                    const SizedBox(width: 8),
                    Text(
                      '${text.languageCode == "tr" ? "Yaş Derecelendirmesi" : "Rating"}: ${anime.rating!}',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Cast & Characters
        Text(
          text.languageCode == 'tr' ? 'Karakterler ve Seslendirmenler' : 'Characters & Voice Actors',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 12),

        if (isLoading && characters.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: Colors.deepPurpleAccent),
            ),
          )
        else if (characters.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                text.languageCode == 'tr' ? 'Karakter bilgisi bulunamadı.' : 'No character information available.',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          )
        else
          SizedBox(
            height: 190,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: characters.length,
              itemBuilder: (context, idx) {
                final c = characters[idx];
                final name = c['name']?.toString() ?? 'Character';
                final role = c['role']?.toString() ?? '';
                final image = c['image']?.toString();
                final actorName = c['actor_name']?.toString();

                return Container(
                  width: 130,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161622),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: image != null && image.isNotEmpty
                            ? Image.network(
                                image,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const ColoredBox(
                                  color: Colors.white10,
                                  child: Icon(Icons.person, color: Colors.white38),
                                ),
                              )
                            : const ColoredBox(
                                color: Colors.white10,
                                child: Center(child: Icon(Icons.person, color: Colors.white38)),
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            if (role.isNotEmpty)
                              Text(
                                role,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white54, fontSize: 10),
                              ),
                            if (actorName != null && actorName.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                actorName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.deepPurpleAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  // -------------------------------------------------------------
  // Recommended Section
  // -------------------------------------------------------------

  Widget _buildRecommendedSection(
    BuildContext context, {
    required List<AnimeItem> recommendations,
    required bool isLoading,
    required AppText text,
  }) {
    if (isLoading && recommendations.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: Colors.deepPurpleAccent),
        ),
      );
    }

    if (recommendations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            text.languageCode == 'tr' ? 'Öneri bulunamadı.' : 'No recommendations available.',
            style: const TextStyle(color: Colors.white60),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 115).floor().clamp(3, 7);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.62,
            crossAxisSpacing: 10,
            mainAxisSpacing: 12,
          ),
          itemCount: recommendations.length,
          itemBuilder: (context, index) {
            final rec = recommendations[index];
            return GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AnimeDetailsScreen(anime: rec),
                  ),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (rec.posterUrl != null)
                            Image.network(
                              rec.posterUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF1E1E28)),
                            )
                          else
                            const ColoredBox(color: Color(0xFF1E1E28)),
                          if (rec.score != null && rec.score! > 0)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star_rounded, color: Colors.amber, size: 10),
                                    const SizedBox(width: 2),
                                    Text(
                                      rec.score!.toStringAsFixed(1),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 9,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    rec.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
