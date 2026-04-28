import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_text.dart';
import '../../../search/presentation/screens/media_details_screen.dart';
import '../providers/library_provider.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(appTextProvider);
    final libraryItems = ref.watch(libraryProvider);

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
        ],
      ),
    );
  }
}
