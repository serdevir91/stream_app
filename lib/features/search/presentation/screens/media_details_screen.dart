import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/addon_service_provider.dart';
import '../../../../core/i18n/app_text.dart';
import '../../../../core/settings/app_settings_provider.dart';
import '../../../library/presentation/providers/library_provider.dart';
import '../../domain/entities/media_item.dart';
import '../providers/search_provider.dart';
import '../../../player/data/repositories/watch_history_repository.dart';
import '../../../player/domain/entities/watch_history.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../player/presentation/screens/player_screen.dart';

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
    final orderedSeasons = [...seasons]
      ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    final fallbackSeason = orderedSeasons.first.seasonNumber;
    final fallbackEpisode = 1;

    var season =
        continueItem?.targetSeason ??
        latestEpisodeProgress?.season ??
        fallbackSeason;
    var episode =
        continueItem?.targetEpisode ??
        latestEpisodeProgress?.episode ??
        fallbackEpisode;

    if (!orderedSeasons.any((item) => item.seasonNumber == season)) {
      season = fallbackSeason;
      episode = fallbackEpisode;
    }

    final count = _episodeCountForSeason(orderedSeasons, season);
    if (count > 0) {
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
  ) {
    final sorted = List<Map<String, dynamic>>.from(streams);
    sorted.sort((a, b) {
      final aDirect = a['is_direct_link'] == true ? 1 : 0;
      final bDirect = b['is_direct_link'] == true ? 1 : 0;
      return bDirect.compareTo(aDirect);
    });
    return sorted;
  }

  Future<void> _resolveAndPickSource({
    int season = 1,
    int episode = 1,
    int? runtimeMinutes,
  }) async {
    final text = ref.read(appTextProvider);
    final settings = ref.read(appSettingsProvider);
    final addonService = ref.read(addonServiceProvider);

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
      final prioritizedStreams = _prioritizeDirectStreams(streams);

      if (!mounted) return;

      if (prioritizedStreams.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(text.t('no_stream_found'))));
        return;
      }

      if (settings.autoSelectSource) {
        final preferredSourceId = settings.preferredSourceId.trim();
        Map<String, dynamic>? selected;

        if (preferredSourceId.isNotEmpty) {
          for (final stream in prioritizedStreams) {
            if (stream['addon_id']?.toString() == preferredSourceId) {
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
        // Compute next episode info for manual stream picker too.
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

    // Compute next episode info from cached seasons data.
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
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.75,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.hub_outlined, color: Colors.lightBlueAccent),
                      SizedBox(width: 8),
                      Text(
                        text.t('resolved_sources'),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: streams.length,
                    separatorBuilder: (buildContext, separatorIndex) =>
                        const Divider(height: 1),
                    itemBuilder: (itemContext, index) {
                      final stream = streams[index];
                      final provider = (stream['provider'] ?? 'Unknown')
                          .toString();
                      final quality = (stream['quality'] ?? 'Auto').toString();
                      final title = (stream['title'] ?? widget.mediaItem.title)
                          .toString();
                      final addonId = stream['addon_id']?.toString();
                      final streamUrl = (stream['url'] ?? '').toString();
                      final isDirectLink = stream['is_direct_link'] ?? true;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.deepPurple.shade700,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '$provider • $quality',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey.shade400),
                        ),
                        trailing: const Icon(
                          Icons.play_circle_fill,
                          color: Colors.greenAccent,
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
    final continueItem = item.type == 'tv'
        ? _continueItemForMedia(ref.watch(continueWatchingProvider))
        : null;
    final inLibrary = ref.watch(
      libraryProvider.select(
        (items) => items.any((libraryItem) => libraryItem.id == item.id),
      ),
    );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: item.backdropUrl != null
                  ? Image.network(
                      item.backdropUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (buildContext, error, stackTrace) =>
                          const ColoredBox(color: Colors.black),
                    )
                  : item.posterUrl != null
                  ? Image.network(
                      item.posterUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (buildContext, error, stackTrace) =>
                          const ColoredBox(color: Colors.black),
                    )
                  : const ColoredBox(color: Colors.black),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        (item.rating ?? mediaDetails?.rating)?.toStringAsFixed(
                              1,
                            ) ??
                            'N/A',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.type.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    (() {
                      final local = item.description?.trim() ?? '';
                      if (local.isNotEmpty) {
                        return local;
                      }
                      return mediaDetails?.description ?? '';
                    })(),
                    style: const TextStyle(fontSize: 16),
                  ),
                  if (mediaDetails != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade900,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (mediaDetails.runtimeMinutes != null)
                            Text(
                              '${text.t(item.type == 'movie' ? 'movie_runtime' : 'episode_runtime')}: ${mediaDetails.runtimeMinutes} dk',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (mediaDetails.castNames.isNotEmpty) ...[
                            if (mediaDetails.runtimeMinutes != null)
                              const SizedBox(height: 8),
                            Text(
                              '${text.t('cast')}: ${mediaDetails.castNames.join(', ')}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                          if (mediaDetails.leadName != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              '${text.t(item.type == 'movie' ? 'director' : 'creator')}: ${mediaDetails.leadName}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (item.type == 'movie' && latestMediaProgress != null) ...[
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _isResolving
                          ? null
                          : () => _resolveAndPickSource(
                              runtimeMinutes: mediaDetails?.runtimeMinutes,
                            ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.shade900,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              text.t('watch_history'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: latestMediaProgress.progressRatio,
                              minHeight: 6,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              latestMediaProgress.isWatched
                                  ? text.t('completed')
                                  : '${text.t('in_progress')} • ${(latestMediaProgress.progressRatio * 100).round()}%',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final added = await ref
                            .read(libraryProvider.notifier)
                            .toggle(item);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              added
                                  ? text.t('added_to_library')
                                  : text.t('removed_from_library'),
                            ),
                          ),
                        );
                      },
                      icon: Icon(
                        inLibrary
                            ? Icons.bookmark_remove
                            : Icons.bookmark_add_outlined,
                      ),
                      label: Text(
                        inLibrary
                            ? text.t('remove_from_library')
                            : text.t('add_to_library'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (item.type == 'movie')
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _isResolving
                            ? null
                            : () => _resolveAndPickSource(
                                runtimeMinutes: mediaDetails?.runtimeMinutes,
                              ),
                        icon: _isResolving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.play_arrow),
                        label: Text(
                          _isResolving
                              ? text.t('resolving')
                              : text.t('play_now'),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    )
                  else
                    _buildSeasonsSection(
                      context,
                      latestEpisodeProgress: latestEpisodeProgress,
                      continueItem: continueItem,
                      tvEpisodeHistory: tvEpisodeHistory,
                      runtimeMinutes: mediaDetails?.runtimeMinutes,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
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
          return Text(text.t('no_seasons'));
        }

        final continueTarget = _resolveContinueTarget(
          seasons,
          continueItem: continueItem,
          latestEpisodeProgress: latestEpisodeProgress,
        );
        final previousTarget = _previousEpisodeTarget(seasons, continueTarget);
        final nextTarget = _nextEpisodeTarget(seasons, continueTarget);
        final continueHistory =
            tvEpisodeHistory[_episodeHistoryKey(
              continueTarget.season,
              continueTarget.episode,
            )];
        final shouldAdvanceToNextEpisode =
            continueHistory?.isWatched == true && nextTarget != null;
        final primaryTarget = shouldAdvanceToNextEpisode
            ? nextTarget
            : continueTarget;
        final primaryHistory =
            tvEpisodeHistory[_episodeHistoryKey(
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
            LayoutBuilder(
              builder: (context, constraints) {
                final stackButtons = constraints.maxWidth < 620;
                final continueProgressValue =
                    primaryHistory?.progressRatio ?? 0.0;
                final continueSubtitle = primaryWatched
                    ? text.t('completed')
                    : '${text.t('in_progress')} • ${(continueProgressValue * 100).round()}%';

                final previousButton = OutlinedButton.icon(
                  onPressed: previousTarget == null || _isResolving
                      ? null
                      : () => _resolveAndPickSource(
                          season: previousTarget.season,
                          episode: previousTarget.episode,
                          runtimeMinutes: runtimeMinutes,
                        ),
                  icon: const Icon(Icons.skip_previous),
                  label: Text(text.t('watch_previous_episode')),
                );

                final continueButton = InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _isResolving
                      ? null
                      : () => _resolveAndPickSource(
                          season: primaryTarget.season,
                          episode: primaryTarget.episode,
                          runtimeMinutes: runtimeMinutes,
                        ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade900,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$primaryLabel: '
                          'S${primaryTarget.season}:E${primaryTarget.episode}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: continueProgressValue,
                          minHeight: 6,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          continueSubtitle,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );

                final nextButton = OutlinedButton.icon(
                  onPressed: nextTarget == null || _isResolving
                      ? null
                      : () => _resolveAndPickSource(
                          season: nextTarget.season,
                          episode: nextTarget.episode,
                          runtimeMinutes: runtimeMinutes,
                        ),
                  icon: const Icon(Icons.skip_next),
                  label: Text(text.t('watch_next_episode')),
                );

                if (stackButtons) {
                  return Column(
                    children: [
                      SizedBox(width: double.infinity, child: previousButton),
                      const SizedBox(height: 8),
                      SizedBox(width: double.infinity, child: continueButton),
                      const SizedBox(height: 8),
                      SizedBox(width: double.infinity, child: nextButton),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: previousButton),
                    const SizedBox(width: 8),
                    Expanded(child: continueButton),
                    const SizedBox(width: 8),
                    Expanded(child: nextButton),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              text.t('seasons'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButton<int>(
              value: _selectedSeason,
              isExpanded: true,
              items: seasons.map((season) {
                return DropdownMenuItem(
                  value: season.seasonNumber,
                  child: Text(
                    '${season.name} (${season.episodeCount} ${text.t('episodes')})',
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedSeason = value;
                });
              },
            ),
            const SizedBox(height: 16),
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
      loading: () => const Center(child: CircularProgressIndicator()),
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
          return Text(text.t('no_episodes'));
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: episodes.length,
          itemBuilder: (itemContext, index) {
            final episode = episodes[index];
            final episodeRuntimeMinutes =
                episode.runtimeMinutes ?? runtimeMinutes;
            final episodeHistory =
                tvEpisodeHistory[_episodeHistoryKey(
                  seasonNumber,
                  episode.episodeNumber,
                )];
            final hasProgress = episodeHistory != null;
            final bool isAired = episode.isAired;
            return ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: episode.stillPath != null
                    ? Image.network(
                        episode.stillPath!,
                        width: 100,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (buildContext, error, stackTrace) =>
                            const ColoredBox(
                              color: Colors.grey,
                              child: SizedBox(width: 100, height: 60),
                            ),
                      )
                    : const ColoredBox(
                        color: Colors.grey,
                        child: SizedBox(width: 100, height: 60),
                      ),
              ),
              title: Text(
                '${episode.episodeNumber}. ${episode.name}',
                style: TextStyle(color: isAired ? null : Colors.white54),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (episode.voteAverage != null &&
                      episode.voteAverage! > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star,
                              color: Colors.amber, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            'IMDb ${episode.voteAverage!.toStringAsFixed(1)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.amber.shade200,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (episodeRuntimeMinutes != null &&
                      episodeRuntimeMinutes > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${text.t('episode_runtime')}: $episodeRuntimeMinutes dk',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ),
                  if (!isAired && episode.airDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${text.t('airs_on')}: ${episode.formattedAirDate}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.orangeAccent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  else if (isAired && episode.airDate != null && !hasProgress)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${text.t('aired_on')}: ${episode.formattedAirDate}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                  if (hasProgress) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: episodeHistory.progressRatio,
                      minHeight: 4,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      episodeHistory.isWatched
                          ? text.t('completed')
                          : '${text.t('in_progress')} • ${(episodeHistory.progressRatio * 100).round()}%',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ],
              ),
              trailing: !isAired
                  ? const Icon(Icons.schedule, color: Colors.orangeAccent)
                  : Icon(
                      hasProgress
                          ? (episodeHistory.isWatched
                                ? Icons.check_circle
                                : Icons.history)
                          : Icons.play_arrow,
                      color: hasProgress
                          ? (episodeHistory.isWatched
                                ? Colors.greenAccent
                                : Colors.amber)
                          : Colors.lightBlueAccent,
                    ),
              onTap: (!isAired || _isResolving)
                  ? null
                  : () => _resolveAndPickSource(
                      season: seasonNumber,
                      episode: episode.episodeNumber,
                      runtimeMinutes: episodeRuntimeMinutes,
                    ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Text('${text.t('resolve_failed')}: $error'),
    );
  }
}
