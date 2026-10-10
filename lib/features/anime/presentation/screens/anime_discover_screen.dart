import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_text.dart';
import '../../domain/models/anime_item.dart';
import '../providers/anime_discover_provider.dart';
import 'anime_details_screen.dart';

class AnimeDiscoverScreen extends ConsumerStatefulWidget {
  const AnimeDiscoverScreen({super.key});

  @override
  ConsumerState<AnimeDiscoverScreen> createState() => _AnimeDiscoverScreenState();
}

class _AnimeDiscoverScreenState extends ConsumerState<AnimeDiscoverScreen>
    with SingleTickerProviderStateMixin {
  Offset _dragOffset = Offset.zero;
  late AnimationController _animController;
  late Animation<Offset> _cardOffsetAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _triggerSwipe(bool toRight, AnimeItem item) {
    HapticFeedback.mediumImpact();
    final screenWidth = MediaQuery.of(context).size.width;
    final targetX = toRight ? screenWidth * 1.5 : -screenWidth * 1.5;

    _cardOffsetAnimation = Tween<Offset>(
      begin: _dragOffset,
      end: Offset(targetX, _dragOffset.dy),
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );

    _animController.forward(from: 0.0).then((_) {
      _animController.reset();
      setState(() {
        _dragOffset = Offset.zero;
      });
      if (toRight) {
        ref.read(animeDiscoverProvider.notifier).swipeWatched(item);
      } else {
        ref.read(animeDiscoverProvider.notifier).swipeMyList(item);
      }
    });
  }

  void _triggerSkip(AnimeItem item) {
    HapticFeedback.lightImpact();
    final screenHeight = MediaQuery.of(context).size.height;
    _cardOffsetAnimation = Tween<Offset>(
      begin: _dragOffset,
      end: Offset(0, screenHeight * 0.8),
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );

    _animController.forward(from: 0.0).then((_) {
      _animController.reset();
      setState(() {
        _dragOffset = Offset.zero;
      });
      ref.read(animeDiscoverProvider.notifier).skip(item);
    });
  }

  void _resetPosition() {
    _cardOffsetAnimation = Tween<Offset>(
      begin: _dragOffset,
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.elasticOut),
    );
    _animController.forward(from: 0.0).then((_) {
      _animController.reset();
      setState(() {
        _dragOffset = Offset.zero;
      });
    });
  }

  void _openFilterSheet(BuildContext context, AppText text) {
    final notifier = ref.read(animeDiscoverProvider.notifier);

    final animeGenres = [
      'Action', 'Adventure', 'Comedy', 'Drama', 'Fantasy', 'Romance',
      'Sci-Fi', 'Shounen', 'Supernatural', 'Mystery', 'Slice of Life',
      'Sports', 'Horror', 'Isekai'
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF171722),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final activeFilter = ref.watch(animeDiscoverProvider).filter;

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.72,
              maxChildSize: 0.9,
              minChildSize: 0.45,
              builder: (context, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Drag handle
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

                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            text.languageCode == 'tr' ? 'Anime Filtreleri' : 'Anime Filters',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              notifier.setGenre(null);
                              notifier.setFormat('all');
                              notifier.setStatus('all');
                              notifier.setMinScore(0.0);
                              notifier.setSortBy('popularity');
                              Navigator.pop(ctx);
                            },
                            child: Text(
                              text.languageCode == 'tr' ? 'Sıfırla' : 'Reset',
                              style: const TextStyle(color: Colors.deepPurpleAccent),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Sort By
                      Text(
                        text.languageCode == 'tr' ? 'Sıralama' : 'Sort By',
                        style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          _buildChoiceChip(
                            label: text.languageCode == 'tr' ? 'En Popüler' : 'Most Popular',
                            selected: activeFilter.sortBy == 'popularity',
                            onSelected: (_) => notifier.setSortBy('popularity'),
                          ),
                          _buildChoiceChip(
                            label: text.languageCode == 'tr' ? 'En Yüksek Puan (Güvenilir)' : 'Top Rated (Verified)',
                            selected: activeFilter.sortBy == 'score',
                            onSelected: (_) => notifier.setSortBy('score'),
                          ),
                          _buildChoiceChip(
                            label: text.languageCode == 'tr' ? 'Yayında / Trend' : 'Currently Airing',
                            selected: activeFilter.sortBy == 'airing',
                            onSelected: (_) => notifier.setSortBy('airing'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Format
                      Text(
                        text.languageCode == 'tr' ? 'Format' : 'Format',
                        style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          _buildChoiceChip(
                            label: text.languageCode == 'tr' ? 'Tümü' : 'All',
                            selected: activeFilter.format == 'all',
                            onSelected: (_) => notifier.setFormat('all'),
                          ),
                          _buildChoiceChip(
                            label: 'TV Series',
                            selected: activeFilter.format == 'tv',
                            onSelected: (_) => notifier.setFormat('tv'),
                          ),
                          _buildChoiceChip(
                            label: text.languageCode == 'tr' ? 'Film' : 'Movie',
                            selected: activeFilter.format == 'movie',
                            onSelected: (_) => notifier.setFormat('movie'),
                          ),
                          _buildChoiceChip(
                            label: 'OVA / Special',
                            selected: activeFilter.format == 'ova',
                            onSelected: (_) => notifier.setFormat('ova'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Min Score
                      Text(
                        text.languageCode == 'tr' ? 'Minimum Puan' : 'Minimum Score',
                        style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          _buildChoiceChip(
                            label: text.languageCode == 'tr' ? 'Fark etmez' : 'Any',
                            selected: activeFilter.minScore == 0.0,
                            onSelected: (_) => notifier.setMinScore(0.0),
                          ),
                          _buildChoiceChip(
                            label: '★ 7.0+',
                            selected: activeFilter.minScore == 7.0,
                            onSelected: (_) => notifier.setMinScore(7.0),
                          ),
                          _buildChoiceChip(
                            label: '★ 7.5+',
                            selected: activeFilter.minScore == 7.5,
                            onSelected: (_) => notifier.setMinScore(7.5),
                          ),
                          _buildChoiceChip(
                            label: '★ 8.0+',
                            selected: activeFilter.minScore == 8.0,
                            onSelected: (_) => notifier.setMinScore(8.0),
                          ),
                          _buildChoiceChip(
                            label: '★ 8.5+',
                            selected: activeFilter.minScore == 8.5,
                            onSelected: (_) => notifier.setMinScore(8.5),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Genres
                      Text(
                        text.languageCode == 'tr' ? 'Türler' : 'Genres',
                        style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildChoiceChip(
                            label: text.languageCode == 'tr' ? 'Tümü' : 'All',
                            selected: activeFilter.genre == null,
                            onSelected: (_) => notifier.setGenre(null),
                          ),
                          ...animeGenres.map((g) {
                            return _buildChoiceChip(
                              label: g,
                              selected: activeFilter.genre?.toLowerCase() == g.toLowerCase(),
                              onSelected: (_) => notifier.setGenre(g),
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Apply button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.deepPurpleAccent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(
                            text.languageCode == 'tr' ? 'Filtreleri Uygula' : 'Apply Filters',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildChoiceChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: Colors.deepPurpleAccent,
      backgroundColor: Colors.white.withValues(alpha: 0.05),
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.white70,
        fontSize: 12,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(
        color: selected ? Colors.deepPurpleAccent : Colors.white12,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onSelected: onSelected,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = ref.watch(appTextProvider);
    final state = ref.watch(animeDiscoverProvider);
    final notifier = ref.read(animeDiscoverProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F13),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.deepPurple, Colors.indigoAccent],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 14),
                  const SizedBox(width: 5),
                  Text(
                    text.languageCode == 'tr' ? 'Anime Keşfet' : 'Anime Discover',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          // Filter button
          IconButton(
            tooltip: text.languageCode == 'tr' ? 'Filtreler' : 'Filters',
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.tune_rounded, color: Colors.white),
                if (state.filter.genre != null ||
                    state.filter.format != 'all' ||
                    state.filter.minScore > 0.0 ||
                    state.filter.sortBy != 'popularity')
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.deepPurpleAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: () => _openFilterSheet(context, text),
          ),
        ],
      ),
      body: SafeArea(
        child: state.isInitialLoading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.deepPurpleAccent),
                    SizedBox(height: 16),
                    Text(
                      'Loading anime cards...',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              )
            : state.cards.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.explore_off_rounded, size: 72, color: Colors.white24),
                        const SizedBox(height: 16),
                        Text(
                          text.languageCode == 'tr'
                              ? 'Kart kalmadı! Filtreleri temizleyin.'
                              : 'No more anime cards! Try resetting filters.',
                          style: const TextStyle(color: Colors.white54, fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.tonal(
                          onPressed: () => _openFilterSheet(context, text),
                          child: Text(text.languageCode == 'tr' ? 'Filtreleri Değiştir' : 'Change Filters'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      // Instructions hint
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.swipe_rounded, color: Colors.white24, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              text.languageCode == 'tr'
                                  ? '← Listeme Ekle | İzledim →'
                                  : '← Add to Library | Mark Watched →',
                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                          ],
                        ),
                      ),

                      // Card Deck
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return Stack(
                                children: [
                                  // Next card under
                                  if (state.cards.length > 1)
                                    Positioned.fill(
                                      child: Transform.scale(
                                        scale: 0.94,
                                        child: Transform.translate(
                                          offset: const Offset(0, 12),
                                          child: Opacity(
                                            opacity: 0.7,
                                            child: _buildAnimeCard(
                                              state.cards[1],
                                              constraints,
                                              isTopCard: false,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                  // Active top card
                                  Positioned.fill(
                                    child: GestureDetector(
                                      onPanUpdate: (details) {
                                        setState(() {
                                          _dragOffset += details.delta;
                                        });
                                      },
                                      onPanEnd: (details) {
                                        final threshold = MediaQuery.of(context).size.width * 0.28;
                                        if (_dragOffset.dx > threshold) {
                                          _triggerSwipe(true, state.cards.first);
                                        } else if (_dragOffset.dx < -threshold) {
                                          _triggerSwipe(false, state.cards.first);
                                        } else if (_dragOffset.dy > 120) {
                                          _triggerSkip(state.cards.first);
                                        } else {
                                          _resetPosition();
                                        }
                                      },
                                      child: AnimatedBuilder(
                                        animation: _animController,
                                        builder: (context, child) {
                                          final offset = _animController.isAnimating
                                              ? _cardOffsetAnimation.value
                                              : _dragOffset;
                                          final rotation = (offset.dx / 400.0) * (math.pi / 16);

                                          return Transform.translate(
                                            offset: offset,
                                            child: Transform.rotate(
                                              angle: rotation,
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: _buildAnimeCard(
                                          state.cards.first,
                                          constraints,
                                          isTopCard: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),

                      // Bottom Floating Control Buttons
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0, left: 24, right: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Undo button
                            IconButton.filledTonal(
                              tooltip: text.languageCode == 'tr' ? 'Geri Al' : 'Undo',
                              icon: const Icon(Icons.replay_rounded, color: Colors.amber, size: 24),
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFF1E1E28),
                                padding: const EdgeInsets.all(12),
                              ),
                              onPressed: state.undoStack.isNotEmpty ? notifier.undo : null,
                            ),

                            // Skip button
                            IconButton.filledTonal(
                              tooltip: text.languageCode == 'tr' ? 'Geç' : 'Skip',
                              icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 28),
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFF1E1E28),
                                padding: const EdgeInsets.all(14),
                              ),
                              onPressed: () {
                                if (state.cards.isNotEmpty) {
                                  _triggerSkip(state.cards.first);
                                }
                              },
                            ),

                            // Info / Details button
                            IconButton.filled(
                              tooltip: text.languageCode == 'tr' ? 'Detaylar & İzle' : 'Details & Watch',
                              icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.deepPurpleAccent,
                                padding: const EdgeInsets.all(16),
                              ),
                              onPressed: () {
                                if (state.cards.isNotEmpty) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AnimeDetailsScreen(anime: state.cards.first),
                                    ),
                                  );
                                }
                              },
                            ),

                            // Add to Library (Left swipe action)
                            IconButton.filledTonal(
                              tooltip: text.t('add_to_library'),
                              icon: const Icon(Icons.bookmark_add_rounded, color: Colors.cyanAccent, size: 26),
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFF1E1E28),
                                padding: const EdgeInsets.all(12),
                              ),
                              onPressed: () {
                                if (state.cards.isNotEmpty) {
                                  _triggerSwipe(false, state.cards.first);
                                }
                              },
                            ),

                            // Mark Watched (Right swipe action)
                            IconButton.filledTonal(
                              tooltip: text.t('watched'),
                              icon: const Icon(Icons.check_rounded, color: Color(0xFF00E054), size: 28),
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFF1E1E28),
                                padding: const EdgeInsets.all(12),
                              ),
                              onPressed: () {
                                if (state.cards.isNotEmpty) {
                                  _triggerSwipe(true, state.cards.first);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildAnimeCard(AnimeItem item, BoxConstraints constraints, {required bool isTopCard}) {
    final poster = item.posterUrl;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AnimeDetailsScreen(anime: item),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1B1B26),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Poster Image
              if (poster != null)
                Image.network(
                  poster,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF1E1E28)),
                )
              else
                const ColoredBox(color: Color(0xFF1E1E28)),

              // Top & Bottom Gradients
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.25, 0.5, 1.0],
                      colors: [
                        Colors.black.withValues(alpha: 0.6),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.4),
                        Colors.black.withValues(alpha: 0.95),
                      ],
                    ),
                  ),
                ),
              ),

              // Top Badges
              Positioned(
                top: 14,
                left: 14,
                right: 14,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Type Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        item.type.isNotEmpty ? item.type : 'TV',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    // Rating Badge
                    if (item.score != null && item.score! > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.withValues(alpha: 0.6)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              item.score!.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // Bottom Info Box
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // English / Display Title
                    Text(
                      item.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Japanese / Romaji Title
                    if (item.romajiTitle != null && item.romajiTitle != item.displayTitle)
                      Text(
                        item.romajiTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    const SizedBox(height: 8),

                    // Metadata chips (Year, Status, Episodes)
                    Row(
                      children: [
                        if (item.year != null) ...[
                          Text(
                            item.year.toString(),
                            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 10),
                        ],
                        if (item.status.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: item.status.toLowerCase().contains('airing')
                                  ? const Color(0xFF00E054).withValues(alpha: 0.2)
                                  : Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.status,
                              style: TextStyle(
                                color: item.status.toLowerCase().contains('airing')
                                    ? const Color(0xFF00E054)
                                    : Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        if (item.episodes != null)
                          Text(
                            '${item.episodes} eps',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Genres
                    if (item.genres.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: item.genres.take(3).map((g) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.deepPurpleAccent.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              g,
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500),
                            ),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 6),

                    // Synopsis preview
                    if (item.synopsis != null && item.synopsis!.isNotEmpty)
                      Text(
                        item.synopsis!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
