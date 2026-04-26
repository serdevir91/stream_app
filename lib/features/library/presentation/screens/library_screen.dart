import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_text.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../search/presentation/screens/media_details_screen.dart';
import '../providers/library_provider.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(appTextProvider);
    final libraryItems = ref.watch(libraryProvider);
    final history = ref.watch(watchHistoryEntriesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(text.t('library_title'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            text.t('saved_items'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (libraryItems.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(text.t('no_saved_items')),
              ),
            )
          else
            ...libraryItems.map(
              (item) => Card(
                child: ListTile(
                  leading: item.posterUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            item.posterUrl!,
                            width: 46,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.movie),
                          ),
                        )
                      : const Icon(Icons.movie),
                  title: Text(item.title),
                  subtitle: Text(item.type.toUpperCase()),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                    tooltip: text.t('remove'),
                    onPressed: () =>
                        ref.read(libraryProvider.notifier).remove(item.id),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            MediaDetailsScreen(mediaItem: item),
                      ),
                    );
                  },
                ),
              ),
            ),
          const SizedBox(height: 20),
          Text(
            text.t('watch_history'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (history.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(text.t('no_watch_history')),
              ),
            )
          else
            ...history.map((item) {
              final progressPercent = item.duration > 0
                  ? (item.lastPosition / item.duration)
                  : 0.0;
              final typeLabel = item.mediaType == 'tv'
                  ? 'TV • S${item.season}:E${item.episode}'
                  : 'MOVIE';
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(typeLabel, style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: progressPercent),
                      const SizedBox(height: 4),
                      Text(
                        item.isWatched
                            ? text.t('completed')
                            : text.t('in_progress'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
