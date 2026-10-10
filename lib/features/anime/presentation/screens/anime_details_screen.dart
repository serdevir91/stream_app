import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_text.dart';
import '../../../../core/settings/app_settings_provider.dart';
import '../../../library/presentation/providers/library_provider.dart';
import '../../../library/presentation/providers/watched_provider.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../player/domain/entities/watch_history.dart';
import '../../../player/presentation/screens/player_screen.dart';
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

class _AnimeDetailsScreenState extends ConsumerState<AnimeDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isSynopsisExpanded = false;
  bool _isResolvingStream = false;
  int _selectedEpisodeBatch = 0;
  static const int _batchSize = 50;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
                      'Ep ${episode.episodeNumber} - Select Server',
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
                              size: 20,
                            ),
                          ),
                          title: Text(
                            provider,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          subtitle: Text(
                            isDirect ? 'Direct HLS Stream' : 'Sandboxed Web Stream',
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
          title: '${widget.anime.displayTitle} - ${episode.displayTitle}',
          type: 'tv',
          season: 1,
          episode: episode.episodeNumber,
          posterUrl: widget.anime.posterUrl,
          backdropUrl: widget.anime.backdropUrl,
          initialStreamUrl: streamUrl,
          initialProvider: provider,
          initialIsDirectLink: isDirectLink,
          initialStreams: allStreams,
          subtitleLanguage: settings.subtitleLanguage,
          preferAnimeSources: true,
          totalEpisodesInSeason: totalEpisodes,
          nextEpisodeNumber: episode.episodeNumber < totalEpisodes ? episode.episodeNumber + 1 : null,
          nextSeasonNumber: null,
        ),
      ),
    );
  }

  Future<void> _toggleEpisodeWatched(int episodeNumber, bool isCurrentlyWatched) async {
    HapticFeedback.lightImpact();
    final repo = ref.read(watchHistoryRepositoryProvider);
    final mediaId = 'anime_${widget.anime.malId}';
    final nextWatched = !isCurrentlyWatched;
    await repo.saveProgress(
      WatchHistory(
        mediaId: mediaId,
        mediaType: 'tv',
        season: 1,
        episode: episodeNumber,
        lastPosition: nextWatched ? 1440 : 0,
        duration: 1440,
        isWatched: nextWatched,
        title: widget.anime.displayTitle,
        posterUrl: widget.anime.posterUrl,
        backdropUrl: widget.anime.backdropUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = ref.watch(appTextProvider);
    final animeAsync = ref.watch(animeDetailsProvider(widget.anime.malId));

    // MediaItem interoperability for library and watched toggles
    final mediaItem = widget.anime.toMediaItem();
    final isInLibrary = ref.watch(
      libraryProvider.select((items) => items.any((i) => i.id == mediaItem.id)),
    );
    final isWatched = ref.watch(
      watchedProvider.select((items) => items.any((i) => i.id == mediaItem.id)),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // Sliver App Bar with Backdrop
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                backgroundColor: const Color(0xFF0F0F13),
                leading: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.anime.backdropUrl != null || widget.anime.posterUrl != null)
                        Image.network(
                          widget.anime.backdropUrl ?? widget.anime.posterUrl!,
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
                              Colors.black.withValues(alpha: 0.4),
                              const Color(0xFF0F0F13).withValues(alpha: 0.9),
                              const Color(0xFF0F0F13),
                            ],
                            stops: const [0.2, 0.5, 0.85, 1.0],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Header Details
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Poster and Main Titles
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Poster
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: SizedBox(
                              width: 105,
                              height: 155,
                              child: widget.anime.posterUrl != null
                                  ? Image.network(
                                      widget.anime.posterUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) =>
                                          const ColoredBox(color: Color(0xFF1E1E28)),
                                    )
                                  : const ColoredBox(color: Color(0xFF1E1E28)),
                            ),
                          ),
                          const SizedBox(width: 16),

                          // Titles and Metadata
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.anime.displayTitle,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    height: 1.25,
                                  ),
                                ),
                                if (widget.anime.romajiTitle != null &&
                                    widget.anime.romajiTitle != widget.anime.displayTitle) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.anime.romajiTitle!,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const SizedBox(height: 8),

                                // Ratings and Meta Chips
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    if (widget.anime.score != null && widget.anime.score! > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                                            const SizedBox(width: 4),
                                            Text(
                                              widget.anime.score!.toStringAsFixed(1),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.white12),
                                      ),
                                      child: Text(
                                        widget.anime.type,
                                        style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    if (widget.anime.isAiring)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.deepPurpleAccent.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.deepPurpleAccent),
                                        ),
                                        child: const Text(
                                          'AIRING',
                                          style: TextStyle(color: Colors.deepPurpleAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      )
                                    else if (widget.anime.episodes != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '${widget.anime.episodes} Ep',
                                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                                        ),
                                      ),
                                  ],
                                ),

                                const SizedBox(height: 8),
                                Text(
                                  widget.anime.subtitleInfo,
                                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Action Buttons (Play Now, Library, Watched)
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                final episodes = animeAsync.value?.episodes ?? [];
                                final firstEp = episodes.isNotEmpty
                                    ? episodes.first
                                    : AnimeEpisode.synthetic(widget.anime.malId, 1);
                                _playEpisode(anime: widget.anime, episode: firstEp);
                              },
                              icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                              label: Text(
                                text.t('play_now'),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepPurpleAccent,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Library Toggle Button
                          IconButton.filledTonal(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              ref.read(libraryProvider.notifier).toggle(mediaItem);
                            },
                            icon: Icon(
                              isInLibrary ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
                              color: isInLibrary ? Colors.amberAccent : Colors.white70,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: isInLibrary
                                  ? Colors.amber.withValues(alpha: 0.2)
                                  : Colors.white.withValues(alpha: 0.08),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),

                          // Watched Toggle Button
                          IconButton.filledTonal(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              ref.read(watchedProvider.notifier).toggle(mediaItem);
                            },
                            icon: Icon(
                              isWatched ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                              color: isWatched ? const Color(0xFF00E054) : Colors.white70,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: isWatched
                                  ? const Color(0xFF00E054).withValues(alpha: 0.2)
                                  : Colors.white.withValues(alpha: 0.08),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),

                      // Synopsis
                      if (widget.anime.synopsis != null && widget.anime.synopsis!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isSynopsisExpanded = !_isSynopsisExpanded;
                            });
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.anime.synopsis!,
                                maxLines: _isSynopsisExpanded ? null : 3,
                                overflow: _isSynopsisExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isSynopsisExpanded
                                    ? (text.languageCode == 'tr' ? 'Daha az göster' : 'Show less')
                                    : (text.languageCode == 'tr' ? 'Daha fazla oku...' : 'Read more...'),
                                style: const TextStyle(
                                  color: Colors.deepPurpleAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Genres
                      if (widget.anime.genres.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: widget.anime.genres.map((g) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Text(
                                g,
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            );
                          }).toList(),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Tab Bar
                      TabBar(
                        controller: _tabController,
                        indicatorColor: Colors.deepPurpleAccent,
                        indicatorWeight: 3,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.white54,
                        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        tabs: [
                          Tab(text: text.t('episodes')),
                          Tab(text: text.t('cast')),
                          Tab(text: text.t('recommended_for_you')),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),

              // Tab View Content
              SliverFillRemaining(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Episodes Tab
                    _buildEpisodesTab(animeAsync, text),

                    // Characters & Cast Tab
                    _buildCharactersTab(animeAsync, text),

                    // Recommendations Tab
                    _buildRecommendationsTab(animeAsync, text),
                  ],
                ),
              ),
            ],
          ),

          // Stream Resolving Loading Overlay
          if (_isResolvingStream)
            Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E28),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.deepPurpleAccent),
                      const SizedBox(height: 16),
                      Text(
                        text.t('resolving'),
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Episodes Tab
  // -------------------------------------------------------------

  Widget _buildEpisodesTab(AsyncValue<AnimeDetailsState> animeAsync, AppText text) {
    ref.watch(watchHistoryChangesProvider);
    final historyRepo = ref.watch(watchHistoryRepositoryProvider);
    final animeMediaId = 'anime_${widget.anime.malId}';
    final animeHistoryList = historyRepo
        .getAllHistory()
        .where((h) => h.mediaId == animeMediaId)
        .toList();

    // Find the latest in-progress or last-watched episode
    final lastWatchedEntry = animeHistoryList.isNotEmpty
        ? (List.of(animeHistoryList)..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs))).first
        : null;

    final loadedEpisodes = animeAsync.asData?.value.episodes ?? const <AnimeEpisode>[];
    final episodes = loadedEpisodes.isNotEmpty
        ? loadedEpisodes
        : List.generate(
            widget.anime.episodes ?? 12,
            (i) => AnimeEpisode.synthetic(widget.anime.malId, i + 1),
          );

    if (episodes.isEmpty) {
      return Center(
        child: Text(
          text.t('no_episodes'),
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }

    // Batch splitting for long anime (e.g. One Piece, Naruto)
    final totalBatches = (episodes.length / _batchSize).ceil();
    final currentEpisodes = totalBatches > 1
        ? episodes.skip(_selectedEpisodeBatch * _batchSize).take(_batchSize).toList()
        : episodes;

    return Column(
      children: [
        if (animeAsync.isLoading)
          const LinearProgressIndicator(
            backgroundColor: Colors.transparent,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.deepPurpleAccent),
            minHeight: 2,
          ),
            // Continue Watching / Last Watched Banner
            if (lastWatchedEntry != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.deepPurple.withValues(alpha: 0.3),
                      Colors.indigo.withValues(alpha: 0.15),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.deepPurpleAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.history_rounded, color: Colors.amberAccent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            text.languageCode == 'tr'
                                ? 'Kaldığın Yer: Bölüm ${lastWatchedEntry.episode}'
                                : 'Resume: Episode ${lastWatchedEntry.episode}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            lastWatchedEntry.isWatched
                                ? (text.languageCode == 'tr' ? 'Tamamlandı' : 'Completed')
                                : (lastWatchedEntry.duration > 0
                                    ? '${((lastWatchedEntry.lastPosition / lastWatchedEntry.duration) * 100).toInt()}% izlendi'
                                    : text.t('in_progress')),
                            style: const TextStyle(color: Colors.white60, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.deepPurpleAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      onPressed: () {
                        final ep = episodes.firstWhere(
                          (e) => e.episodeNumber == lastWatchedEntry.episode,
                          orElse: () => episodes.first,
                        );
                        _playEpisode(anime: widget.anime, episode: ep, totalEpisodes: episodes.length);
                      },
                      child: Text(
                        text.languageCode == 'tr' ? 'Devam Et' : 'Resume',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            // Batch selector chips if anime has more than 50 episodes
            if (totalBatches > 1)
              SizedBox(
                height: 36,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: totalBatches,
                  itemBuilder: (context, index) {
                    final start = index * _batchSize + 1;
                    final end = ((index + 1) * _batchSize).clamp(1, episodes.length);
                    final isSelected = index == _selectedEpisodeBatch;

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('$start-$end'),
                        selected: isSelected,
                        selectedColor: Colors.deepPurpleAccent,
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        onSelected: (_) {
                          setState(() {
                            _selectedEpisodeBatch = index;
                          });
                        },
                      ),
                    );
                  },
                ),
              ),

            // Episodes List
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: currentEpisodes.length,
                itemBuilder: (context, index) {
                  final episode = currentEpisodes[index];
                  final progress = historyRepo.getProgress(
                    animeMediaId,
                    mediaType: 'tv',
                    season: 1,
                    episode: episode.episodeNumber,
                  );
                  final isEpWatched = progress?.isWatched == true;
                  final double progressRatio = (progress != null && progress.duration > 0)
                      ? (progress.lastPosition / progress.duration).clamp(0.0, 1.0)
                      : (isEpWatched ? 1.0 : 0.0);

                  return Card(
                    color: const Color(0xFF171720),
                    margin: const EdgeInsets.only(bottom: 8),
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isEpWatched
                            ? const Color(0xFF00E054).withValues(alpha: 0.4)
                            : Colors.white10,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: isEpWatched
                                  ? const Color(0xFF00E054).withValues(alpha: 0.15)
                                  : Colors.deepPurpleAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                '${episode.episodeNumber}',
                                style: TextStyle(
                                  color: isEpWatched
                                      ? const Color(0xFF00E054)
                                      : Colors.deepPurpleAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          title: Text(
                            episode.displayTitle,
                            style: TextStyle(
                              color: isEpWatched ? Colors.white70 : Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: episode.aired != null
                              ? Text(
                                  episode.aired!,
                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                )
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (episode.isFiller)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  margin: const EdgeInsets.only(right: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'FILLER',
                                    style: TextStyle(color: Colors.orange, fontSize: 9, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              // Server Picker Button
                              IconButton(
                                icon: const Icon(Icons.tune_rounded, color: Colors.white38, size: 18),
                                tooltip: 'Select Server',
                                onPressed: () => _playEpisode(
                                  anime: widget.anime,
                                  episode: episode,
                                  totalEpisodes: episodes.length,
                                  forceSelectStream: true,
                                ),
                              ),
                              // Watched Checkmark Toggle
                              IconButton(
                                icon: Icon(
                                  isEpWatched ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                                  color: isEpWatched ? const Color(0xFF00E054) : Colors.white38,
                                  size: 22,
                                ),
                                tooltip: isEpWatched ? 'Mark unwatched' : 'Mark watched',
                                onPressed: () => _toggleEpisodeWatched(episode.episodeNumber, isEpWatched),
                              ),
                              const SizedBox(width: 2),
                              IconButton(
                                icon: const Icon(Icons.play_circle_fill_rounded, color: Colors.deepPurpleAccent, size: 28),
                                onPressed: () => _playEpisode(
                                  anime: widget.anime,
                                  episode: episode,
                                  totalEpisodes: episodes.length,
                                ),
                              ),
                            ],
                          ),
                          onTap: () => _playEpisode(
                            anime: widget.anime,
                            episode: episode,
                            totalEpisodes: episodes.length,
                          ),
                        ),
                        // Episode watch progress bar
                        if (progressRatio > 0 && !isEpWatched)
                          LinearProgressIndicator(
                            value: progressRatio,
                            backgroundColor: Colors.transparent,
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.deepPurpleAccent),
                            minHeight: 2.5,
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
  // Characters Tab
  // -------------------------------------------------------------

  Widget _buildCharactersTab(AsyncValue<AnimeDetailsState> animeAsync, AppText text) {
    return animeAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent)),
      error: (_, _) => const SizedBox.shrink(),
      data: (data) {
        final characters = data.characters;
        if (characters.isEmpty) {
          return Center(
            child: Text(text.t('no_data'), style: const TextStyle(color: Colors.white54)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: characters.length,
          itemBuilder: (context, index) {
            final char = characters[index];
            final charImage = char['image'] as String?;
            final actorImage = char['actor_image'] as String?;

            return Card(
              color: const Color(0xFF171720),
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    // Character Photo
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 44,
                        height: 56,
                        child: charImage != null
                            ? Image.network(charImage, fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black26))
                            : const ColoredBox(color: Colors.black26),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Character Name & Role
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            char['name']?.toString() ?? '',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Text(
                            char['role']?.toString() ?? '',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      ),
                    ),

                    // Voice Actor Info
                    if (char['actor_name'] != null) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            char['actor_name'].toString(),
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          const Text(
                            'Japanese',
                            style: TextStyle(color: Colors.white38, fontSize: 10),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 40,
                          height: 52,
                          child: actorImage != null
                              ? Image.network(actorImage, fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black26))
                              : const ColoredBox(color: Colors.black26),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // -------------------------------------------------------------
  // Recommendations Tab
  // -------------------------------------------------------------

  Widget _buildRecommendationsTab(AsyncValue<AnimeDetailsState> animeAsync, AppText text) {
    return animeAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent)),
      error: (_, _) => const SizedBox.shrink(),
      data: (data) {
        final recs = data.recommendations;
        if (recs.isEmpty) {
          return Center(
            child: Text(text.t('no_data'), style: const TextStyle(color: Colors.white54)),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.64,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: recs.length,
          itemBuilder: (context, index) {
            final item = recs[index];
            return GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AnimeDetailsScreen(anime: item),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (item.posterUrl != null)
                      Image.network(
                        item.posterUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF1E1E28)),
                      )
                    else
                      const ColoredBox(color: Color(0xFF1E1E28)),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.9)],
                          ),
                        ),
                        child: Text(
                          item.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
