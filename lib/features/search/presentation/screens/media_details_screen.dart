import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/addon_service_provider.dart';
import '../../../../core/i18n/app_text.dart';
import '../../../../core/settings/app_settings_provider.dart';
import '../../../library/presentation/providers/library_provider.dart';
import '../../../library/presentation/providers/watched_provider.dart';
import '../../domain/entities/media_item.dart';
import '../providers/search_provider.dart';
import '../../../player/data/repositories/watch_history_repository.dart';
import '../../../player/domain/entities/watch_history.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../player/presentation/screens/player_screen.dart';
import '../../../home/presentation/screens/category_media_screen.dart';

typedef EpisodeTarget = ({int season, int episode});

class MediaDetailsScreen extends ConsumerStatefulWidget {
  final MediaItem mediaItem;

  const MediaDetailsScreen({super.key, required this.mediaItem});

  @override
  ConsumerState<MediaDetailsScreen> createState() => _MediaDetailsScreenState();
}

class _MediaDetailsScreenState extends ConsumerState<MediaDetailsScreen> {
  int? _selectedSeason;
  bool _isResolving = false;
  int? _highlightedEpisodeNumber;
  int _selectedTabIndex = 0;
  final Map<int, GlobalKey> _episodeKeys = {};
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

  Future<void> _toggleEpisodeWatched({
    required int season,
    required int episodeNumber,
    required bool isCurrentlyWatched,
    required Map<String, WatchHistory> tvEpisodeHistory,
  }) async {
    final repo = ref.read(watchHistoryRepositoryProvider);
    final key = _episodeHistoryKey(season, episodeNumber);
    if (isCurrentlyWatched) {
      final historyEntry = tvEpisodeHistory[key];
      if (historyEntry != null) {
        await repo.deleteByHistoryId(historyEntry.historyId);
      } else {
        await repo.deleteByHistoryId('tv_${widget.mediaItem.id}_s${season}_e$episodeNumber');
      }
    } else {
      final newHistory = WatchHistory(
        mediaId: widget.mediaItem.id,
        title: widget.mediaItem.title,
        mediaType: 'tv',
        season: season,
        episode: episodeNumber,
        posterUrl: widget.mediaItem.posterUrl,
        backdropUrl: widget.mediaItem.backdropUrl,
        lastPosition: 1,
        duration: 1,
        isWatched: true,
      );
      await repo.saveProgress(newHistory);
    }
  }

  void _scrollToEpisode(int seasonNumber, int episodeNumber) {
    setState(() {
      _selectedSeason = seasonNumber;
      _selectedTabIndex = 0; // Switch to Episodes tab
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 150), () {
        final key = _episodeKeys[episodeNumber];
        if (key != null && key.currentContext != null) {
          Scrollable.ensureVisible(
            key.currentContext!,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOut,
            alignment: 0.5,
          );
          
          setState(() {
            _highlightedEpisodeNumber = episodeNumber;
          });
          
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              setState(() {
                _highlightedEpisodeNumber = null;
              });
            }
          });
        }
      });
    });
  }

  String _episodeHistoryKey(int season, int episode) => '${season}_$episode';

  String _normalizeType(String value) {
    final t = value.trim().toLowerCase();
    if (t == 'tv' || t == 'series' || t == 'show') return 'tv';
    return 'movie';
  }

  ({int season, int episode})? _latestEpisodeProgress(
    List<WatchHistory> items,
  ) {
    WatchHistory? latest;
    for (final item in items) {
      if (_normalizeType(item.mediaType) != 'tv' ||
          item.mediaId != widget.mediaItem.id) {
        continue;
      }
      if (latest == null || item.updatedAtMs > latest.updatedAtMs) {
        latest = item;
      }
    }
    if (latest == null) {
      return null;
    }
    return (season: latest.season, episode: latest.episode);
  }

  WatchHistory? _latestMediaProgress(
    List<WatchHistory> items,
    String mediaType,
  ) {
    WatchHistory? latest;
    for (final item in items) {
      if (_normalizeType(item.mediaType) != _normalizeType(mediaType) ||
          item.mediaId != widget.mediaItem.id) {
        continue;
      }
      if (latest == null || item.updatedAtMs > latest.updatedAtMs) {
        latest = item;
      }
    }
    return latest;
  }

  Map<String, WatchHistory> _tvEpisodeProgressByKey(List<WatchHistory> items) {
    final byKey = <String, WatchHistory>{};
    for (final item in items) {
      if (_normalizeType(item.mediaType) != 'tv' ||
          item.mediaId != widget.mediaItem.id) {
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

  ContinueWatchItem? _continueItemForMedia(List<ContinueWatchItem> items) {
    for (final item in items) {
      if (_normalizeType(item.baseHistory.mediaType) == 'tv' &&
          item.baseHistory.mediaId == widget.mediaItem.id) {
        return item;
      }
    }
    return null;
  }

  int _episodeCountForSeason(List<Season> seasons, int seasonNumber) {
    for (final season in seasons) {
      if (season.seasonNumber == seasonNumber) {
        return season.episodeCount;
      }
    }
    return 0;
  }

  EpisodeTarget _resolveContinueTarget(
    List<Season> seasons, {
    ContinueWatchItem? continueItem,
    ({int season, int episode})? latestEpisodeProgress,
  }) {
    if (seasons.isEmpty) {
      return (season: 1, episode: 1);
    }

    final orderedSeasons = [...seasons]
      ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    final fallbackSeason = orderedSeasons.first.seasonNumber;
    const fallbackEpisode = 1;

    var season =
        continueItem?.targetSeason ??
        latestEpisodeProgress?.season ??
        fallbackSeason;
    var episode =
        continueItem?.targetEpisode ??
        latestEpisodeProgress?.episode ??
        fallbackEpisode;

    var seasonIndex = orderedSeasons.indexWhere((item) => item.seasonNumber == season);
    if (seasonIndex == -1) {
      season = fallbackSeason;
      episode = fallbackEpisode;
      seasonIndex = 0;
    }

    final count = _episodeCountForSeason(orderedSeasons, season);
    if (count > 0 && episode > count) {
      if (seasonIndex + 1 < orderedSeasons.length) {
        season = orderedSeasons[seasonIndex + 1].seasonNumber;
        episode = 1;
      } else {
        episode = count;
      }
    } else if (count > 0) {
      episode = episode.clamp(1, count);
    } else if (episode < 1) {
      episode = 1;
    }

    return (season: season, episode: episode);
  }

  EpisodeTarget? _previousEpisodeTarget(
    List<Season> seasons,
    EpisodeTarget current,
  ) {
    final orderedSeasons = [...seasons]
      ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    final currentIndex = orderedSeasons.indexWhere(
      (season) => season.seasonNumber == current.season,
    );
    if (currentIndex == -1) {
      return current.episode > 1
          ? (season: current.season, episode: current.episode - 1)
          : null;
    }

    if (current.episode > 1) {
      return (season: current.season, episode: current.episode - 1);
    }

    if (currentIndex == 0) {
      return null;
    }

    final previousSeason = orderedSeasons[currentIndex - 1];
    final previousEpisode = previousSeason.episodeCount > 0
        ? previousSeason.episodeCount
        : 1;
    return (season: previousSeason.seasonNumber, episode: previousEpisode);
  }

  EpisodeTarget? _nextEpisodeTarget(
    List<Season> seasons,
    EpisodeTarget current,
  ) {
    final orderedSeasons = [...seasons]
      ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    final currentIndex = orderedSeasons.indexWhere(
      (season) => season.seasonNumber == current.season,
    );
    if (currentIndex == -1) {
      return (season: current.season, episode: current.episode + 1);
    }

    final currentCount = _episodeCountForSeason(orderedSeasons, current.season);
    if (currentCount == 0 || current.episode < currentCount) {
      return (season: current.season, episode: current.episode + 1);
    }

    if (currentIndex + 1 >= orderedSeasons.length) {
      return null;
    }

    final nextSeason = orderedSeasons[currentIndex + 1];
    return (season: nextSeason.seasonNumber, episode: 1);
  }

  List<Map<String, dynamic>> _prioritizeDirectStreams(
    List<Map<String, dynamic>> streams,
    bool preferAnimeSources,
  ) {
    final sorted = List<Map<String, dynamic>>.from(streams);
    sorted.sort((a, b) {
      final aDirect = a['is_direct_link'] == true ? 1 : 0;
      final bDirect = b['is_direct_link'] == true ? 1 : 0;
      final directCompare = bDirect.compareTo(aDirect);
      if (directCompare != 0) return directCompare;
      return _streamProviderScore(
        a,
        preferAnimeSources,
      ).compareTo(_streamProviderScore(b, preferAnimeSources));
    });
    return sorted;
  }

  int _streamProviderScore(
    Map<String, dynamic> stream,
    bool preferAnimeSources,
  ) {
    if (!preferAnimeSources) {
      return 0;
    }
    final addonId = stream['addon_id']?.toString().toLowerCase() ?? '';
    final provider = stream['provider']?.toString().toLowerCase() ?? '';
    if (addonId.contains('streamimdb') || provider.contains('streamimdb')) {
      return 0;
    }
    if (addonId.contains('vidsrccc') || provider.contains('vidsrc.cc')) {
      return 1;
    }
    if (addonId.contains('vidsrc') || provider.contains('vidsrc')) return 2;
    if (addonId.contains('videasy') || provider.contains('videasy')) return 3;
    if (addonId.contains('embedsu') || provider.contains('embedsu')) return 4;
    return 10;
  }

  bool _preferAnimeSources() {
    if (widget.mediaItem.type != 'tv') {
      return false;
    }
    final details = ref
        .read(
          mediaDetailsProvider(
            '${widget.mediaItem.type}:${widget.mediaItem.id}',
          ),
        )
        .maybeWhen(data: (value) => value, orElse: () => null);
    return details?.genres.any(
          (genre) => genre.toLowerCase().contains('animation'),
        ) ??
        false;
  }

  Future<void> _resolveAndPickSource({
    int season = 1,
    int episode = 1,
    String? preferredSourceId,
    int? runtimeMinutes,
  }) async {
    final text = ref.read(appTextProvider);
    final settings = ref.read(appSettingsProvider);
    final addonService = ref.read(addonServiceProvider);
    final preferAnimeSources = _preferAnimeSources();

    var addons = addonService.enabledAddons;
    if (addons.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(text.t('no_active_addon'))));
      return;
    }

    setState(() {
      _isResolving = true;
    });

    try {
      final data = await addonService.resolve(
        query: widget.mediaItem.title,
        tmdbId: widget.mediaItem.id,
        contentType: widget.mediaItem.type == 'tv' ? 'series' : 'movie',
        season: season,
        episode: episode,
      );

      final streams = (data['streams'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
      final prioritizedStreams = _prioritizeDirectStreams(
        streams,
        preferAnimeSources,
      );

      if (!mounted) return;

      if (prioritizedStreams.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(text.t('no_stream_found'))));
        return;
      }

      if (settings.autoSelectSource) {
        final preferredSourceIdToUse =
            preferredSourceId?.trim().isNotEmpty == true
            ? preferredSourceId!.trim()
            : settings.preferredSourceId.trim();
        final preferredMirror = settings.preferredMirror.trim().toLowerCase();
        Map<String, dynamic>? selected;

        if (preferredMirror.isNotEmpty && preferredMirror != 'auto') {
          for (final stream in prioritizedStreams) {
            final title = (stream['title'] ?? '').toString().toLowerCase();
            final provider = (stream['provider'] ?? '').toString().toLowerCase();
            final url = (stream['url'] ?? '').toString().toLowerCase();
            if (title.contains(preferredMirror) ||
                provider.contains(preferredMirror) ||
                url.contains(preferredMirror)) {
              selected = stream;
              break;
            }
          }
        }

        if (selected == null && preferredSourceIdToUse.isNotEmpty) {
          for (final stream in prioritizedStreams) {
            if (stream['addon_id']?.toString() == preferredSourceIdToUse) {
              selected = stream;
              break;
            }
          }
        }
        selected ??= prioritizedStreams.first;
        _playSelectedStream(
          selected,
          season: season,
          episode: episode,
          runtimeMinutes: runtimeMinutes,
        );
      } else {
        final seasonsAsync = ref.read(
          seriesSeasonsProvider(widget.mediaItem.id),
        );
        final seasons = seasonsAsync.value ?? [];
        final currentTarget = (season: season, episode: episode);
        final nextTarget = seasons.isNotEmpty
            ? _nextEpisodeTarget(seasons, currentTarget)
            : null;
        final episodeCount = seasons.isNotEmpty
            ? _episodeCountForSeason(seasons, season)
            : null;

        _showResolvedStreamsSheet(
          context,
          prioritizedStreams,
          season: season,
          episode: episode,
          runtimeMinutes: runtimeMinutes,
          nextSeasonNumber: nextTarget?.season,
          nextEpisodeNumber: nextTarget?.episode,
          totalEpisodesInSeason: episodeCount,
        );
      }
    } catch (e) {
      debugPrint('Resolve error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(text.t('no_stream_found'))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResolving = false;
        });
      }
    }
  }

  void _playSelectedStream(
    Map<String, dynamic> stream, {
    required int season,
    required int episode,
    int? runtimeMinutes,
  }) {
    final settings = ref.read(appSettingsProvider);
    final streamUrl = (stream['url'] ?? '').toString();
    final provider = (stream['provider'] ?? '').toString();
    final addonId = stream['addon_id']?.toString();
    final isDirectLink = stream['is_direct_link'] == true;

    if (streamUrl.isEmpty || !mounted) {
      return;
    }

    final seasonsAsync = ref.read(seriesSeasonsProvider(widget.mediaItem.id));
    final seasons = seasonsAsync.value ?? [];
    final currentTarget = (season: season, episode: episode);
    final nextTarget = seasons.isNotEmpty
        ? _nextEpisodeTarget(seasons, currentTarget)
        : null;
    final episodeCount = seasons.isNotEmpty
        ? _episodeCountForSeason(seasons, season)
        : null;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          mediaId: widget.mediaItem.id,
          title: widget.mediaItem.title,
          type: widget.mediaItem.type,
          season: season,
          episode: episode,
          posterUrl: widget.mediaItem.posterUrl,
          backdropUrl: widget.mediaItem.backdropUrl,
          sourceId: addonId,
          initialStreamUrl: streamUrl,
          initialProvider: provider,
          initialIsDirectLink: isDirectLink,
          subtitleLanguage: settings.subtitleLanguage,
          runtimeMinutes: runtimeMinutes,
          nextSeasonNumber: nextTarget?.season,
          nextEpisodeNumber: nextTarget?.episode,
          totalEpisodesInSeason: episodeCount,
          preferAnimeSources: _preferAnimeSources(),
        ),
      ),
    );
  }

  void _showResolvedStreamsSheet(
    BuildContext context,
    List<Map<String, dynamic>> streams, {
    required int season,
    required int episode,
    int? runtimeMinutes,
    int? nextSeasonNumber,
    int? nextEpisodeNumber,
    int? totalEpisodesInSeason,
  }) {
    final text = ref.read(appTextProvider);
    final settings = ref.read(appSettingsProvider);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161822),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.75,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.hub_rounded, color: Colors.redAccent, size: 24),
                      const SizedBox(width: 10),
                      Text(
                        text.t('resolved_sources'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white12),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: streams.length,
                    separatorBuilder: (buildContext, separatorIndex) =>
                        const Divider(height: 1, color: Colors.white10),
                    itemBuilder: (itemContext, index) {
                      final stream = streams[index];
                      final provider = (stream['provider'] ?? 'Unknown').toString();
                      final quality = (stream['quality'] ?? 'Auto').toString();
                      final title = (stream['title'] ?? widget.mediaItem.title).toString();
                      final addonId = stream['addon_id']?.toString();
                      final streamUrl = (stream['url'] ?? '').toString();
                      final isDirectLink = stream['is_direct_link'] ?? true;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '$provider • $quality',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                        ),
                        trailing: const Icon(
                          Icons.play_circle_fill,
                          color: Colors.redAccent,
                          size: 32,
                        ),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PlayerScreen(
                                mediaId: widget.mediaItem.id,
                                title: widget.mediaItem.title,
                                type: widget.mediaItem.type,
                                season: season,
                                episode: episode,
                                posterUrl: widget.mediaItem.posterUrl,
                                backdropUrl: widget.mediaItem.backdropUrl,
                                sourceId: addonId,
                                initialStreamUrl: streamUrl,
                                initialProvider: provider,
                                initialIsDirectLink: isDirectLink as bool,
                                subtitleLanguage: settings.subtitleLanguage,
                                runtimeMinutes: runtimeMinutes,
                                nextSeasonNumber: nextSeasonNumber,
                                nextEpisodeNumber: nextEpisodeNumber,
                                totalEpisodesInSeason: totalEpisodesInSeason,
                                preferAnimeSources: _preferAnimeSources(),
                              ),
                            ),
                          );
                        },
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

  @override
  Widget build(BuildContext context) {
    final text = ref.watch(appTextProvider);
    final item = widget.mediaItem;
    final mediaDetailsAsync = ref.watch(
      mediaDetailsProvider('${item.type}:${item.id}'),
    );
    final mediaDetails = mediaDetailsAsync.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );
    final directorsList = mediaDetails?.directorName?.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() ?? const <String>[];
    final creatorsList = mediaDetails?.creatorName?.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() ?? const <String>[];
    final mediaHistoryEntries = ref
        .watch(watchHistoryEntriesProvider)
        .where((history) => history.mediaId == item.id)
        .toList();
    final latestMediaProgress = _latestMediaProgress(
      mediaHistoryEntries,
      item.type,
    );
    final latestEpisodeProgress = item.type == 'tv'
        ? _latestEpisodeProgress(mediaHistoryEntries)
        : null;
    final tvEpisodeHistory = item.type == 'tv'
        ? _tvEpisodeProgressByKey(mediaHistoryEntries)
        : const <String, WatchHistory>{};
    final continueWatchingAsync = ref.watch(continueWatchingProvider);
    final continueItem = item.type == 'tv'
        ? _continueItemForMedia(continueWatchingAsync.value ?? const [])
        : null;
    final inLibrary = ref.watch(
      libraryProvider.select(
        (items) => items.any((libraryItem) => libraryItem.id == item.id),
      ),
    );
    final isWatched = ref.watch(
      watchedProvider.select(
        (items) => items.any((watchedItem) => watchedItem.id == item.id),
      ),
    );

    final isTv = item.type == 'tv';

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Hero AppBar with double gradient
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor: const Color(0xFF0F0F13),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.backdropUrl != null || item.posterUrl != null)
                    Image.network(
                      item.backdropUrl ?? item.posterUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const ColoredBox(color: Colors.black),
                    )
                  else
                    const ColoredBox(color: Colors.black),
                  // Top & bottom gradient overlays
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.6),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.4),
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

          // Main Header Info
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Metadata Badges Row
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // IMDb Rating Badge
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
                              (item.rating ?? mediaDetails?.rating)?.toStringAsFixed(1) ?? 'N/A',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Content Type Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          text.t(item.type).toUpperCase(),
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      // Release Date
                      if (mediaDetails?.releaseDate != null && mediaDetails!.releaseDate!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Text(
                            mediaDetails.releaseDate!,
                            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                      // Runtime
                      if (mediaDetails?.runtimeMinutes != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Text(
                            '${mediaDetails!.runtimeMinutes} ${text.t('minutes_suffix')}',
                            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),

                  // Genres
                  if (mediaDetails != null && mediaDetails.genres.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: mediaDetails.genres.map((genre) {
                        return InkWell(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CategoryMediaScreen(
                                  categoryKey: 'genre_$genre',
                                  title: genre,
                                  crossAxisCount: 3,
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
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
                            final added = await ref.read(libraryProvider.notifier).toggle(item);
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
                              color: inLibrary ? Colors.redAccent : Colors.white24,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: Icon(
                            inLibrary ? Icons.bookmark_remove : Icons.bookmark_add_outlined,
                            color: inLibrary ? Colors.redAccent : Colors.white,
                          ),
                          label: Text(
                            inLibrary ? text.t('remove_from_library') : text.t('add_to_library'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: inLibrary ? Colors.redAccent : Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final added = await ref.read(watchedProvider.notifier).toggle(item);
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

                  // Movie Play Button (if Movie)
                  if (!isTv) ...[
                    const SizedBox(height: 12),
                    if (latestMediaProgress != null) ...[
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _isResolving
                            ? null
                            : () => _resolveAndPickSource(
                                runtimeMinutes: mediaDetails?.runtimeMinutes,
                              ),
                        child: Container(
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
                              Text(
                                text.t('watch_history'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(
                                value: latestMediaProgress.progressRatio,
                                minHeight: 5,
                                backgroundColor: Colors.white10,
                                color: Colors.redAccent,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                latestMediaProgress.isWatched
                                    ? text.t('completed')
                                    : '${text.t('in_progress')} • ${(latestMediaProgress.progressRatio * 100).round()}%',
                                style: const TextStyle(fontSize: 11, color: Colors.white60),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _isResolving
                            ? null
                            : () => _resolveAndPickSource(
                                runtimeMinutes: mediaDetails?.runtimeMinutes,
                              ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        icon: _isResolving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.play_arrow_rounded, size: 24),
                        label: Text(
                          _isResolving ? text.t('resolving') : text.t('play_now'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Segmented Tabs Header
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        if (isTv) ...[
                          Expanded(
                            child: _buildSegmentTab(
                              title: text.t('episodes'),
                              isSelected: _selectedTabIndex == 0,
                              onTap: () => setState(() => _selectedTabIndex = 0),
                            ),
                          ),
                        ],
                        Expanded(
                          child: _buildSegmentTab(
                            title: text.t('overview') != 'overview' ? text.t('overview') : (text.languageCode == 'tr' ? 'Genel Bakış' : 'Overview'),
                            isSelected: isTv ? _selectedTabIndex == 1 : _selectedTabIndex == 0,
                            onTap: () => setState(() => _selectedTabIndex = isTv ? 1 : 0),
                          ),
                        ),
                        Expanded(
                          child: _buildSegmentTab(
                            title: text.languageCode == 'tr' ? 'Benzer Yapımlar' : 'Related',
                            isSelected: isTv ? _selectedTabIndex == 2 : _selectedTabIndex == 1,
                            onTap: () => setState(() => _selectedTabIndex = isTv ? 2 : 1),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Tab Contents
                  if (isTv && _selectedTabIndex == 0)
                    _buildSeasonsSection(
                      context,
                      latestEpisodeProgress: latestEpisodeProgress,
                      continueItem: continueItem,
                      tvEpisodeHistory: tvEpisodeHistory,
                      runtimeMinutes: mediaDetails?.runtimeMinutes,
                    )
                  else if ((isTv && _selectedTabIndex == 1) || (!isTv && _selectedTabIndex == 0))
                    _buildOverviewSection(
                      context,
                      item: item,
                      mediaDetails: mediaDetails,
                      directorsList: directorsList,
                      creatorsList: creatorsList,
                    )
                  else
                    _buildRelatedSection(
                      context,
                      mediaDetails: mediaDetails,
                    ),
                ],
              ),
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
          color: isSelected ? Colors.redAccent : Colors.transparent,
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

  Widget _buildOverviewSection(
    BuildContext context, {
    required MediaItem item,
    required MediaDetailsInfo? mediaDetails,
    required List<String> directorsList,
    required List<String> creatorsList,
  }) {
    final text = ref.watch(appTextProvider);
    final descriptionText = item.description?.trim().isNotEmpty == true
        ? item.description!.trim()
        : (mediaDetails?.description ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Overview Text
        if (descriptionText.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Text(
              descriptionText,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade300,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Cast & Crew Info Card
        if (mediaDetails != null)
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
                // Directors
                if (item.type == 'movie' && directorsList.isNotEmpty) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.movie_creation_outlined, size: 16, color: Colors.redAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            text: '${text.t('director')}: ',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13),
                            children: List.generate(directorsList.length, (idx) {
                              final name = directorsList[idx];
                              return TextSpan(
                                children: [
                                  TextSpan(
                                    text: name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.underline,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => CategoryMediaScreen(
                                              categoryKey: 'actor_$name',
                                              title: name,
                                              crossAxisCount: 3,
                                            ),
                                          ),
                                        );
                                      },
                                  ),
                                  if (idx < directorsList.length - 1)
                                    const TextSpan(text: ', ', style: TextStyle(color: Colors.white70, decoration: TextDecoration.none)),
                                ],
                              );
                            }),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],

                // Creators
                if (item.type == 'tv' && creatorsList.isNotEmpty) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.create_outlined, size: 16, color: Colors.redAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            text: '${text.t('creator')}: ',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13),
                            children: List.generate(creatorsList.length, (idx) {
                              final name = creatorsList[idx];
                              return TextSpan(
                                children: [
                                  TextSpan(
                                    text: name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.underline,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => CategoryMediaScreen(
                                              categoryKey: 'actor_$name',
                                              title: name,
                                              crossAxisCount: 3,
                                            ),
                                          ),
                                        );
                                      },
                                  ),
                                  if (idx < creatorsList.length - 1)
                                    const TextSpan(text: ', ', style: TextStyle(color: Colors.white70, decoration: TextDecoration.none)),
                                ],
                              );
                            }),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],

                // Cast Names
                if (mediaDetails.castNames.isNotEmpty) ...[
                  const Divider(color: Colors.white10, height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.people_outline, size: 16, color: Colors.redAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            text: '${text.t('cast')}: ',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13),
                            children: List.generate(mediaDetails.castNames.length, (idx) {
                              final name = mediaDetails.castNames[idx];
                              return TextSpan(
                                children: [
                                  TextSpan(
                                    text: name,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.normal,
                                      decoration: TextDecoration.underline,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => CategoryMediaScreen(
                                              categoryKey: 'actor_$name',
                                              title: name,
                                              crossAxisCount: 3,
                                            ),
                                          ),
                                        );
                                      },
                                  ),
                                  if (idx < mediaDetails.castNames.length - 1)
                                    const TextSpan(text: ', ', style: TextStyle(color: Colors.white70, decoration: TextDecoration.none)),
                                ],
                              );
                            }),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                // Production Companies
                if (mediaDetails.productionCompanies.isNotEmpty) ...[
                  const Divider(color: Colors.white10, height: 16),
                  Text(
                    text.t('production_companies'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: mediaDetails.productionCompanies.map((company) {
                      return InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CategoryMediaScreen(
                                categoryKey: 'company_$company',
                                title: company,
                                crossAxisCount: 3,
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.business_center_outlined, size: 11, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(company, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                            ],
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
    );
  }

  Widget _buildSeasonsSection(
    BuildContext context, {
    ({int season, int episode})? latestEpisodeProgress,
    ContinueWatchItem? continueItem,
    required Map<String, WatchHistory> tvEpisodeHistory,
    int? runtimeMinutes,
  }) {
    final text = ref.watch(appTextProvider);
    final seasonsAsync = ref.watch(seriesSeasonsProvider(widget.mediaItem.id));

    return seasonsAsync.when(
      data: (seasons) {
        if (seasons.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(text.t('no_seasons'), style: const TextStyle(color: Colors.white60)),
            ),
          );
        }

        final continueTarget = _resolveContinueTarget(
          seasons,
          continueItem: continueItem,
          latestEpisodeProgress: latestEpisodeProgress,
        );
        final previousTarget = _previousEpisodeTarget(seasons, continueTarget);
        final nextTarget = _nextEpisodeTarget(seasons, continueTarget);
        final continueHistory = tvEpisodeHistory[_episodeHistoryKey(
          continueTarget.season,
          continueTarget.episode,
        )];
        final shouldAdvanceToNextEpisode = continueHistory?.isWatched == true && nextTarget != null;
        final primaryTarget = shouldAdvanceToNextEpisode ? nextTarget : continueTarget;
        final primaryHistory = tvEpisodeHistory[_episodeHistoryKey(
          primaryTarget.season,
          primaryTarget.episode,
        )];
        final primaryWatched = primaryHistory?.isWatched ?? false;
        final primaryLabel = shouldAdvanceToNextEpisode
            ? text.t('next_episode')
            : text.t('last_watched_episode');

        _selectedSeason ??= continueTarget.season;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Continue Watching Box
            Container(
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
                      Text(
                        '$primaryLabel: S${primaryTarget.season}:E${primaryTarget.episode}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (primaryWatched)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            text.t('completed'),
                            style: const TextStyle(fontSize: 10, color: Colors.greenAccent, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: primaryHistory?.progressRatio ?? 0.0,
                    minHeight: 5,
                    backgroundColor: Colors.white10,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (previousTarget != null) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isResolving
                                ? null
                                : () => _resolveAndPickSource(
                                    season: previousTarget.season,
                                    episode: previousTarget.episode,
                                    preferredSourceId: continueItem?.baseHistory.sourceId,
                                    runtimeMinutes: runtimeMinutes,
                                  ),
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
                          onPressed: _isResolving
                              ? null
                              : () => _resolveAndPickSource(
                                  season: primaryTarget.season,
                                  episode: primaryTarget.episode,
                                  preferredSourceId: continueItem?.baseHistory.sourceId,
                                  runtimeMinutes: runtimeMinutes,
                                ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                          icon: _isResolving
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.play_arrow_rounded, size: 18),
                          label: Text(
                            _isResolving ? text.t('resolving') : text.t('play_now'),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ),
                      if (nextTarget != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isResolving
                                ? null
                                : () => _resolveAndPickSource(
                                    season: nextTarget.season,
                                    episode: nextTarget.episode,
                                    preferredSourceId: continueItem?.baseHistory.sourceId,
                                    runtimeMinutes: runtimeMinutes,
                                  ),
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
            ),

            const SizedBox(height: 16),

            // Highest Rated IMDb Episode Banner
            ref.watch(highestRatedEpisodeProvider(widget.mediaItem.id)).maybeWhen(
              data: (info) {
                if (info == null) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: InkWell(
                    onTap: () => _scrollToEpisode(info.seasonNumber, info.episode.episodeNumber),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.amber.withValues(alpha: 0.15),
                            Colors.amber.withValues(alpha: 0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star_rounded, color: Colors.amber, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  text.languageCode == 'tr' ? 'En Yüksek IMDb\'li Bölüm' : 'Highest Rated Episode',
                                  style: const TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'S${info.seasonNumber}:E${info.episode.episodeNumber} - ${info.episode.name}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              info.episode.voteAverage?.toStringAsFixed(1) ?? 'N/A',
                              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),

            // Horizontal Season Selector Pills
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: seasons.length,
                itemBuilder: (context, index) {
                  final season = seasons[index];
                  final isSelected = season.seasonNumber == _selectedSeason;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${season.name} (${season.episodeCount})'),
                      selected: isSelected,
                      selectedColor: Colors.redAccent,
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      side: BorderSide(
                        color: isSelected ? Colors.redAccent : Colors.white12,
                      ),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey.shade400,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedSeason = season.seasonNumber;
                          });
                        }
                      },
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // Episode List
            if (_selectedSeason != null)
              _buildEpisodesSection(
                context,
                _selectedSeason!,
                latestEpisodeProgress: latestEpisodeProgress,
                tvEpisodeHistory: tvEpisodeHistory,
                runtimeMinutes: runtimeMinutes,
              ),
          ],
        );
      },
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
      error: (error, _) => Text('${text.t('resolve_failed')}: $error'),
    );
  }

  Widget _buildEpisodesSection(
    BuildContext context,
    int seasonNumber, {
    ({int season, int episode})? latestEpisodeProgress,
    required Map<String, WatchHistory> tvEpisodeHistory,
    int? runtimeMinutes,
  }) {
    final text = ref.watch(appTextProvider);
    final episodesAsync = ref.watch(
      seasonEpisodesProvider('${widget.mediaItem.id}_$seasonNumber'),
    );

    return episodesAsync.when(
      data: (episodes) {
        if (episodes.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Text(text.t('no_episodes'), style: const TextStyle(color: Colors.white60)),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: episodes.length,
          itemBuilder: (itemContext, index) {
            final episode = episodes[index];
            final episodeRuntimeMinutes = episode.runtimeMinutes ?? runtimeMinutes;
            final episodeHistory = tvEpisodeHistory[_episodeHistoryKey(
              seasonNumber,
              episode.episodeNumber,
            )];
            final hasProgress = episodeHistory != null;
            final bool isAired = episode.isAired;
            final isHighlighted = episode.episodeNumber == _highlightedEpisodeNumber;

            return Container(
              key: _episodeKeys.putIfAbsent(episode.episodeNumber, () => GlobalKey()),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isHighlighted
                    ? Colors.amber.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isHighlighted ? Colors.amber : Colors.white10,
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      episode.stillPath != null
                          ? Image.network(
                              episode.stillPath!,
                              width: 100,
                              height: 60,
                              fit: BoxFit.cover,
                              errorBuilder: (buildContext, error, stackTrace) =>
                                  const ColoredBox(
                                    color: Colors.white10,
                                    child: SizedBox(width: 100, height: 60, child: Icon(Icons.movie, color: Colors.grey)),
                                  ),
                            )
                          : const ColoredBox(
                              color: Colors.white10,
                              child: SizedBox(width: 100, height: 60, child: Icon(Icons.movie, color: Colors.grey)),
                            ),
                      if (isAired)
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                        ),
                    ],
                  ),
                ),
                title: Text(
                  '${episode.episodeNumber}. ${episode.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isAired ? Colors.white : Colors.white38,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (episode.voteAverage != null && episode.voteAverage! > 0) ...[
                          const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                          const SizedBox(width: 2),
                          Text(
                            episode.voteAverage!.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (episodeRuntimeMinutes != null && episodeRuntimeMinutes > 0)
                          Text(
                            '$episodeRuntimeMinutes dk',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                          ),
                      ],
                    ),
                    if (!isAired && episode.airDate != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${text.t('airs_on')}: ${episode.formattedAirDate}',
                          style: const TextStyle(fontSize: 11, color: Colors.orangeAccent, fontWeight: FontWeight.w500),
                        ),
                      ),
                    if (hasProgress) ...[
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: episodeHistory.progressRatio,
                        minHeight: 3,
                        backgroundColor: Colors.white10,
                        color: Colors.redAccent,
                      ),
                    ],
                  ],
                ),
                trailing: Tooltip(
                  message: episodeHistory?.isWatched == true
                      ? (text.languageCode == 'tr' ? 'İzlemedim olarak işaretle' : 'Mark as unwatched')
                      : (text.languageCode == 'tr' ? 'İzledim olarak işaretle' : 'Mark as watched'),
                  child: InkWell(
                    onTap: () {
                      _toggleEpisodeWatched(
                        season: seasonNumber,
                        episodeNumber: episode.episodeNumber,
                        isCurrentlyWatched: episodeHistory?.isWatched == true,
                        tvEpisodeHistory: tvEpisodeHistory,
                      );
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(6.0),
                      child: Icon(
                        episodeHistory?.isWatched == true
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: episodeHistory?.isWatched == true
                            ? const Color(0xFF00E054)
                            : Colors.white30,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                onTap: (!isAired || _isResolving)
                    ? null
                    : () => _resolveAndPickSource(
                        season: seasonNumber,
                        episode: episode.episodeNumber,
                        runtimeMinutes: episodeRuntimeMinutes,
                      ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
      error: (error, _) => Text('${text.t('resolve_failed')}: $error'),
    );
  }

  Widget _buildRelatedSection(
    BuildContext context, {
    required MediaDetailsInfo? mediaDetails,
  }) {
    final text = ref.watch(appTextProvider);

    if (mediaDetails == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final hasSequels = mediaDetails.relatedItems.isNotEmpty;
    final hasRecs = mediaDetails.recommendations.isNotEmpty;

    if (!hasSequels && !hasRecs) {
      return Container(
        padding: const EdgeInsets.all(20),
        alignment: Alignment.center,
        child: Text(
          text.languageCode == 'tr' ? 'Benzer içerik bulunamadı' : 'No related media found',
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasSequels) ...[
          Text(
            text.languageCode == 'tr' ? 'Devam Filmleri & Spin-off\'lar' : 'Sequels & Spin-offs',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: mediaDetails.relatedItems.length,
              itemBuilder: (context, index) {
                final rel = mediaDetails.relatedItems[index];
                return _buildRelatedCard(context, rel);
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (hasRecs) ...[
          Text(
            text.languageCode == 'tr' ? 'Benzer Yapımlar' : 'Similar Recommendations',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: mediaDetails.recommendations.length,
              itemBuilder: (context, index) {
                final rec = mediaDetails.recommendations[index];
                return _buildRelatedCard(context, rec);
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRelatedCard(BuildContext context, MediaItem item) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MediaDetailsScreen(mediaItem: item),
          ),
        );
      },
      child: Container(
        width: 130,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    item.posterUrl != null
                        ? Image.network(
                            item.posterUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const ColoredBox(color: Colors.white10),
                          )
                        : const ColoredBox(
                            color: Colors.white10,
                            child: Center(child: Icon(Icons.movie, color: Colors.grey)),
                          ),
                    if (item.rating != null && item.rating! > 0)
                      Positioned(
                        bottom: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, color: Colors.amber, size: 12),
                              const SizedBox(width: 2),
                              Text(
                                item.rating!.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
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
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
