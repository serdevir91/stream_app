import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/search_provider.dart';

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchResults = ref.watch(searchResultsProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search for movies or series...',
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
            return const Center(child: Text('No results found.'));
          }
          return ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final item = results[index];
              return ListTile(
                leading: item.posterUrl != null 
                    ? Image.network(item.posterUrl!, width: 50, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.movie)) 
                    : const Icon(Icons.movie),
                title: Text(item.title),
                subtitle: Text(item.type.toUpperCase()),
                onTap: () {
                  // Navigate to player or details
                },
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
