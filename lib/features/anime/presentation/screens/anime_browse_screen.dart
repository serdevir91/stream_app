import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_text.dart';
import '../../domain/models/anime_item.dart';
import '../providers/anime_providers.dart';
import 'anime_details_screen.dart';

class AnimeBrowseScreen extends ConsumerStatefulWidget {
  final String title;
  final String? filter;
  final String? genre;
  final bool isSeasonNow;
  final bool isRecentlyUpdated;
  final bool isMovies;

  const AnimeBrowseScreen({
    super.key,
    required this.title,
    this.filter,
    this.genre,
    this.isSeasonNow = false,
    this.isRecentlyUpdated = false,
    this.isMovies = false,
  });

  @override
  ConsumerState<AnimeBrowseScreen> createState() => _AnimeBrowseScreenState();
}

class _AnimeBrowseScreenState extends ConsumerState<AnimeBrowseScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<AnimeItem> _items = [];
  int _currentPage = 1;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 400 &&
        !_isLoading &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _currentPage = 1;
      _items.clear();
      _hasMore = true;
    });

    final api = ref.read(jikanApiServiceProvider);
    try {
      List<AnimeItem> result;
      if (widget.isMovies) {
        result = await api.getTopMovies(page: 1, limit: 24);
      } else if (widget.isSeasonNow) {
        result = await api.getSeasonNow(page: 1, limit: 24);
      } else if (widget.isRecentlyUpdated) {
        result = await api.getRecentlyUpdated(page: 1, limit: 24);
      } else if (widget.genre != null) {
        result = await api.searchAnime(query: '', genres: widget.genre, page: 1, limit: 24);
      } else {
        result = await api.getTopAnime(filter: widget.filter, page: 1, limit: 24);
      }

      if (mounted) {
        setState(() {
          _items.addAll(result);
          _isLoading = false;
          _hasMore = result.length >= 20;
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

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() {
      _isLoadingMore = true;
    });

    final nextPage = _currentPage + 1;
    final api = ref.read(jikanApiServiceProvider);

    try {
      List<AnimeItem> result;
      if (widget.isMovies) {
        result = await api.getTopMovies(page: nextPage, limit: 24);
      } else if (widget.isSeasonNow) {
        result = await api.getSeasonNow(page: nextPage, limit: 24);
      } else if (widget.isRecentlyUpdated) {
        result = await api.getRecentlyUpdated(page: nextPage, limit: 24);
      } else if (widget.genre != null) {
        result = await api.searchAnime(query: '', genres: widget.genre, page: nextPage, limit: 24);
      } else {
        result = await api.getTopAnime(filter: widget.filter, page: nextPage, limit: 24);
      }

      if (mounted) {
        setState(() {
          _currentPage = nextPage;
          _items.addAll(result);
          _isLoadingMore = false;
          _hasMore = result.length >= 20;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
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
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent))
          : _error != null && _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 48, color: Colors.white38),
                      const SizedBox(height: 12),
                      Text(text.t('no_data'), style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadInitial,
                        child: Text(text.t('try_again')),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadInitial,
                  color: Colors.deepPurpleAccent,
                  backgroundColor: const Color(0xFF1E1E28),
                  child: GridView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.58,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _items.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _items.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(color: Colors.deepPurpleAccent, strokeWidth: 2),
                          ),
                        );
                      }

                      final item = _items[index];
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
                            // Poster
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

                                    // Score badge
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

                            // Title
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
                  ),
                ),
    );
  }
}
