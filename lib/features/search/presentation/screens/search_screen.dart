import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/i18n/app_text.dart';
import '../../../../core/settings/app_settings_provider.dart';
import '../providers/search_provider.dart';
import 'media_details_screen.dart';

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(appTextProvider);
    final settings = ref.watch(appSettingsProvider);
    final searchResults = ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(text.t('search')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: text.t('search_hint'),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.black26,
              ),
              onSubmitted: (value) {
                ref.read(searchQueryProvider.notifier).setQuery(value);
              },
            ),
          ),
        ),
      ),
      body: searchResults.when(
        data: (results) {
          if (results.isEmpty) {
            if (settings.tmdbAccessToken.trim().isEmpty) {
              return Center(child: Text(text.t('api_required')));
            }
            return Center(child: Text(text.t('no_results')));
          }
          return ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final item = results[index];
              return Card(
                margin: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 4.0,
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(8.0),
                  leading: item.posterUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(4.0),
                          child: Image.network(
                            item.posterUrl!,
                            width: 60,
                            height: 90,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.movie, size: 60),
                          ),
                        )
                      : const Icon(Icons.movie, size: 60),
                  title: Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.star, size: 16, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(item.rating?.toStringAsFixed(1) ?? 'N/A'),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.type.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.description ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
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
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}
