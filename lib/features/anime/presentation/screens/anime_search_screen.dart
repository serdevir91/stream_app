import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_text.dart';
import '../../domain/models/anime_item.dart';
import '../providers/anime_providers.dart';
import 'anime_details_screen.dart';

class AnimeSearchScreen extends ConsumerStatefulWidget {
  const AnimeSearchScreen({super.key});

  @override
  ConsumerState<AnimeSearchScreen> createState() => _AnimeSearchScreenState();
}

class _AnimeSearchScreenState extends ConsumerState<AnimeSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  List<AnimeItem> _results = [];
  bool _isLoading = false;
  String? _selectedType; // 'tv', 'movie', 'ova'
  String? _error;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isLoading = false;
        _error = null;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _performSearch(query.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final api = ref.read(jikanApiServiceProvider);
    try {
      final items = await api.searchAnime(
        query: query,
        type: _selectedType,
        limit: 25,
      );
      if (mounted) {
        setState(() {
          _results = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = ref.watch(appTextProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F13),
        elevation: 0,
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: text.languageCode == 'tr' ? 'Anime ara (Naruto, Solo Leveling...)' : 'Search anime...',
            hintStyle: const TextStyle(color: Colors.white38),
            border: InputBorder.none,
          ),
          onChanged: _onQueryChanged,
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.white70),
              onPressed: () {
                _searchController.clear();
                _onQueryChanged('');
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips (All, TV, Movie, OVA)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildTypeChip('All', null),
                const SizedBox(width: 8),
                _buildTypeChip('TV', 'tv'),
                const SizedBox(width: 8),
                _buildTypeChip('Movie', 'movie'),
                const SizedBox(width: 8),
                _buildTypeChip('OVA', 'ova'),
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent))
                : _searchController.text.trim().isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.search_rounded, size: 64, color: Colors.white24),
                            const SizedBox(height: 12),
                            Text(
                              text.languageCode == 'tr' ? 'Anime aramak için bir şeyler yazın' : 'Type to search anime',
                              style: const TextStyle(color: Colors.white54, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white54, fontSize: 13),
                              ),
                            ),
                          )
                        : _results.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.search_off_rounded, size: 64, color: Colors.white24),
                                const SizedBox(height: 12),
                                Text(
                                  text.t('no_results'),
                                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                                ),
                              ],
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final crossAxisCount = (constraints.maxWidth / 115).floor().clamp(3, 8);
                              return GridView.builder(
                                padding: const EdgeInsets.all(12),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  childAspectRatio: 0.62,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 12,
                                ),
                                itemCount: _results.length,
                                itemBuilder: (context, index) {
                              final item = _results[index];
                              return GestureDetector(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AnimeDetailsScreen(anime: item),
                                    ),
                                  );
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            if (item.posterUrl != null)
                                              Image.network(
                                                item.posterUrl!,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, _, _) =>
                                                    const ColoredBox(color: Color(0xFF1E1E28)),
                                              )
                                            else
                                              const ColoredBox(color: Color(0xFF1E1E28)),
                                            if (item.score != null && item.score! > 0)
                                              Positioned(
                                                top: 4,
                                                right: 4,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black87,
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.star_rounded, color: Colors.amber, size: 10),
                                                      const SizedBox(width: 2),
                                                      Text(
                                                        item.score!.toStringAsFixed(1),
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 9,
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
                                      item.displayTitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        height: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(String label, String? type) {
    final isSelected = _selectedType == type;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: Colors.deepPurpleAccent,
      backgroundColor: Colors.white.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide(color: isSelected ? Colors.deepPurpleAccent : Colors.white12),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.white70,
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (_) {
        setState(() {
          _selectedType = type;
        });
        if (_searchController.text.trim().isNotEmpty) {
          _performSearch(_searchController.text.trim());
        }
      },
    );
  }
}
