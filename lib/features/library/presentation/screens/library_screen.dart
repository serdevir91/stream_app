import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_text.dart';
import '../../../search/domain/entities/media_item.dart';
import '../../../search/presentation/screens/media_details_screen.dart';
import '../providers/library_provider.dart';
import '../providers/watched_provider.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(appTextProvider);
    final libraryItems = ref.watch(sortedLibraryProvider);
    final newEpisodes = ref.watch(newEpisodesProvider);
    final watchedItems = ref.watch(sortedWatchedProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(text.t('library_title')),
          bottom: TabBar(
            tabs: [
              Tab(text: text.t('my_list')),
              Tab(text: text.t('watched_movies')),
            ],
            indicatorColor: Colors.redAccent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.grey,
          ),
        ),
        body: TabBarView(
          children: [
            _buildWatchlistTab(context, ref, text, libraryItems, newEpisodes),
            _buildWatchedTab(context, ref, text, watchedItems),
          ],
        ),
      ),
    );
  }

  Widget _buildWatchlistTab(
    BuildContext context,
    WidgetRef ref,
    AppText text,
    List<MediaItem> libraryItems,
    AsyncValue<List<NewEpisodeItem>> newEpisodes,
  ) {
    return _buildMediaGrid(
      context: context,
      ref: ref,
      text: text,
      items: libraryItems,
      emptyTextKey: 'no_saved_items',
      onRemove: (item) => ref.read(libraryProvider.notifier).remove(item.id),
      header: newEpisodes.when(
        data: (items) {
          if (items.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text.t('new_episodes'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...items.map(
                (item) => Card(
                  child: ListTile(
                    leading: item.series.posterUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              item.series.posterUrl!,
                              width: 46,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.tv),
                            ),
                          )
                        : const Icon(Icons.tv),
                    title: Text(item.series.title),
                    subtitle: Text(
                      'S${item.episode.seasonNumber}:E${item.episode.episodeNumber} - ${item.episode.name}'
                      '${item.episode.formattedAirDate.isEmpty ? '' : ' • ${item.episode.formattedAirDate}'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              MediaDetailsScreen(mediaItem: item.series),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                text.t('saved_items'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          );
        },
        loading: () => const SizedBox.shrink(),
        error: (error, stackTrace) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildWatchedTab(
    BuildContext context,
    WidgetRef ref,
    AppText text,
    List<MediaItem> watchedItems,
  ) {
    return _buildMediaGrid(
      context: context,
      ref: ref,
      text: text,
      items: watchedItems,
      emptyTextKey: 'no_watched_items',
      onRemove: (item) => ref.read(watchedProvider.notifier).remove(item.id),
    );
  }

  Widget _buildMediaGrid({
    required BuildContext context,
    required WidgetRef ref,
    required AppText text,
    required List<MediaItem> items,
    required String emptyTextKey,
    required void Function(MediaItem item) onRemove,
    Widget? header,
  }) {
    if (items.isEmpty && header == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.video_library_outlined,
                size: 64,
                color: Colors.grey.shade600,
              ),
              const SizedBox(height: 16),
              Text(
                text.t(emptyTextKey),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade400,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final int crossAxisCount =
        (MediaQuery.of(context).size.width / 120).floor().clamp(3, 8);

    return CustomScrollView(
      slivers: [
        if (header != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(
                left: 12,
                right: 12,
                top: 12,
                bottom: 4,
              ),
              child: header,
            ),
          ),
        if (items.isEmpty && header != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
              child: Center(
                child: Text(
                  text.t(emptyTextKey),
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: 2 / 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = items[index];
                  return _buildGridCard(context, ref, text, item, onRemove);
                },
                childCount: items.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGridCard(
    BuildContext context,
    WidgetRef ref,
    AppText text,
    MediaItem item,
    void Function(MediaItem item) onRemove,
  ) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => MediaDetailsScreen(mediaItem: item),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Poster Image or Fallback
            item.posterUrl != null
                ? Image.network(
                    item.posterUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _buildFallbackPoster(item),
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        color: Colors.grey.shade900,
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                      );
                    },
                  )
                : _buildFallbackPoster(item),

            // Rating Badge (top-left)
            if (item.rating != null && item.rating! > 0)
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 10),
                      const SizedBox(width: 3),
                      Text(
                        item.rating!.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Delete overlay (top-right)
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                onTap: () => onRemove(item),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.75),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                      width: 0.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 14,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),

            // Bottom subtle overlay with type badge
            Positioned(
              bottom: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
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
    );
  }

  Widget _buildFallbackPoster(MediaItem item) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.grey.shade900, Colors.grey.shade800],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            item.type == 'tv' ? Icons.tv : Icons.movie,
            color: Colors.grey.shade500,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
