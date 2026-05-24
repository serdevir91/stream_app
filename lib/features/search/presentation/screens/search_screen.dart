import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_text.dart';
import '../../../../core/settings/app_settings_provider.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../../domain/entities/media_item.dart';
import '../providers/search_provider.dart';
import 'media_details_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(searchQueryProvider),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _submitSearch() {
    final query = _searchController.text.trim();
    ref.read(searchQueryProvider.notifier).setQuery(query);
    if (query.isNotEmpty) {
      ref.read(recentSearchesProvider.notifier).addQuery(query);
    }
  }

  Widget _buildTokenWarningBanner(BuildContext context, AppText text) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orangeAccent,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text.t('tmdb_token_warning'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SettingsScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.settings, size: 16),
              label: Text(text.t('go_to_settings')),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = ref.watch(appTextProvider);
    final settings = ref.watch(appSettingsProvider);
    final isTokenMissing = settings.tmdbAccessToken.trim().isEmpty;
    final currentQuery = ref.watch(searchQueryProvider).trim();
    final searchResults = ref.watch(searchResultsProvider);
    final recentSearches = ref.watch(recentSearchesProvider);
    final mixedRecommendations = ref.watch(mixedRecommendationsProvider);
    final hasQuery = currentQuery.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(text.t('search')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(62),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submitSearch(),
              onChanged: (value) {
                if (value.trim().isEmpty && hasQuery) {
                  ref.read(searchQueryProvider.notifier).setQuery('');
                }
              },
              decoration: InputDecoration(
                hintText: text.t('search_hint'),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.black26,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: _submitSearch,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
            ),
          ),
        ),
      ),
      body: isTokenMissing
          ? Column(
              children: [
                _buildTokenWarningBanner(context, text),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        text.t('api_required'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : (hasQuery
              ? _buildSearchResults(searchResults, text)
              : _buildDiscoveryContent(
                  text,
                  recentSearches: recentSearches,
                  mixedRecommendations: mixedRecommendations,
                )),
    );
  }

  Widget _buildSearchResults(
    AsyncValue<List<MediaItem>> searchResults,
    AppText text,
  ) {
    return searchResults.when(
      data: (results) {
        if (results.isEmpty) {
          return Center(child: Text(text.t('no_results')));
        }
        return _buildMediaList(results);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error: $err')),
    );
  }

  Widget _buildDiscoveryContent(
    AppText text, {
    required List<String> recentSearches,
    required AsyncValue<List<MediaItem>> mixedRecommendations,
  }) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (recentSearches.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  text.t('recent_searches'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => ref.read(recentSearchesProvider.notifier).clear(),
                child: Text(text.t('clear_recent_searches')),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: recentSearches
                .map(
                  (query) => ActionChip(
                    label: Text(query),
                    onPressed: () {
                      _searchController.text = query;
                      _submitSearch();
                    },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 20),
        ] else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              text.t('search_to_start'),
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
        Text(
          text.t('mixed_recommendations'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        mixedRecommendations.when(
          data: (items) {
            if (items.isEmpty) {
              return Center(child: Text(text.t('no_data')));
            }
            return _buildMediaList(items, shrinkWrap: true, physics: const NeverScrollableScrollPhysics());
          },
          loading: () => const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(child: Text('Error: $err')),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaList(
    List<MediaItem> results, {
    bool shrinkWrap = false,
    ScrollPhysics? physics,
  }) {
    final text = ref.watch(appTextProvider);
    return ListView.builder(
      shrinkWrap: shrinkWrap,
      physics: physics,
      itemCount: results.length,
      itemBuilder: (context, index) {
        final item = results[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: ListTile(
            contentPadding: const EdgeInsets.all(8),
            leading: item.posterUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(4),
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
                    const Icon(Icons.star, size: 16, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(item.rating?.toStringAsFixed(1) ?? 'N/A'),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        text.t(item.type).toUpperCase(),
                        style: const TextStyle(fontSize: 10, color: Colors.white),
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
                  builder: (_) => MediaDetailsScreen(mediaItem: item),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
