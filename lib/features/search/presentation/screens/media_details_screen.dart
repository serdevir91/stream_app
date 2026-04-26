import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_text.dart';
import '../../../../core/settings/app_settings_provider.dart';
import '../../../library/presentation/providers/library_provider.dart';
import '../../domain/entities/media_item.dart';
import '../providers/search_provider.dart';
import '../../../addons/presentation/screens/addon_manager_screen.dart';
import '../../../player/presentation/screens/player_screen.dart';
import '../../../../core/backend/internal_backend.dart';

class MediaDetailsScreen extends ConsumerStatefulWidget {
  final MediaItem mediaItem;

  const MediaDetailsScreen({super.key, required this.mediaItem});

  @override
  ConsumerState<MediaDetailsScreen> createState() => _MediaDetailsScreenState();
}

class _MediaDetailsScreenState extends ConsumerState<MediaDetailsScreen> {
  int? _selectedSeason;
  bool _isResolving = false;

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

  Future<void> _resolveAndPickSource({int season = 1, int episode = 1}) async {
    final text = ref.read(appTextProvider);
    final settings = ref.read(appSettingsProvider);
    final addonNotifier = ref.read(addonsProvider.notifier);
    var addons = ref
        .read(addonsProvider)
        .where((addon) => addon.enabled)
        .toList();

    if (addons.isEmpty) {
      await addonNotifier.fetchAddons();
      if (!mounted) {
        return;
      }
      addons = ref
          .read(addonsProvider)
          .where((addon) => addon.enabled)
          .toList();
    }

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
      final dio = Dio(
        BaseOptions(
          baseUrl: settings.backendUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      Response<dynamic>? response;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          response = await dio.get(
            '/api/resolve',
            queryParameters: {
              'query': widget.mediaItem.title,
              'tmdb_id': widget.mediaItem.id,
              'type': widget.mediaItem.type == 'tv' ? 'series' : 'movie',
              'season': season,
              'episode': episode,
            },
          );
          break;
        } on DioException catch (error) {
          final retryable =
              error.response == null &&
              (error.type == DioExceptionType.connectionError ||
                  error.type == DioExceptionType.connectionTimeout ||
                  error.type == DioExceptionType.receiveTimeout);

          if (retryable && attempt == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 800));
            continue;
          }
          rethrow;
        }
      }

      if (response == null) {
        throw DioException(
          requestOptions: RequestOptions(path: '/api/resolve'),
          message: 'Resolve response is empty',
        );
      }

      final data = response.data;
      final streams = (data['streams'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
      final prioritizedStreams = _prioritizeDirectStreams(streams);

      if (!mounted) {
        return;
      }

      if (prioritizedStreams.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(text.t('no_stream_found'))));
        return;
      }

      _showResolvedStreamsSheet(
        context,
        prioritizedStreams,
        season: season,
        episode: episode,
      );
    } catch (e) {
      debugPrint('External resolve failed, trying internal: $e');
      final internalBackend = InternalBackendService();
      final data = await internalBackend.resolve(
        query: widget.mediaItem.title,
        tmdbId: widget.mediaItem.id,
        type: widget.mediaItem.type == 'tv' ? 'series' : 'movie',
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
      } else {
        _showResolvedStreamsSheet(
          context,
          prioritizedStreams,
          season: season,
          episode: episode,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResolving = false;
        });
      }
    }
  }

  void _showResolvedStreamsSheet(
    BuildContext context,
    List<Map<String, dynamic>> streams, {
    required int season,
    required int episode,
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
                        item.rating?.toStringAsFixed(1) ?? 'N/A',
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
                    item.description ?? '',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
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
                            : () => _resolveAndPickSource(),
                        icon: _isResolving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.hub),
                        label: Text(
                          _isResolving
                              ? text.t('resolving')
                              : text.t('resolve_and_play'),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    )
                  else
                    _buildSeasonsSection(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeasonsSection(BuildContext context) {
    final text = ref.watch(appTextProvider);
    final seasonsAsync = ref.watch(seriesSeasonsProvider(widget.mediaItem.id));

    return seasonsAsync.when(
      data: (seasons) {
        if (seasons.isEmpty) {
          return Text(text.t('no_seasons'));
        }

        _selectedSeason ??= seasons.first.seasonNumber;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
              _buildEpisodesSection(context, _selectedSeason!),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Text('${text.t('resolve_failed')}: $error'),
    );
  }

  Widget _buildEpisodesSection(BuildContext context, int seasonNumber) {
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
              title: Text('${episode.episodeNumber}. ${episode.name}'),
              trailing: const Icon(Icons.hub, color: Colors.lightBlueAccent),
              onTap: _isResolving
                  ? null
                  : () => _resolveAndPickSource(
                      season: seasonNumber,
                      episode: episode.episodeNumber,
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
