import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_text.dart';
import '../../../search/domain/entities/media_item.dart';
import '../../../search/presentation/screens/media_details_screen.dart';
import '../providers/discover_provider.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen>
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

  void _triggerSwipe(bool toRight, MediaItem item) {
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
        ref.read(discoverProvider.notifier).swipeWatched(item);
      } else {
        ref.read(discoverProvider.notifier).swipeMyList(item);
      }
    });
  }

  void _triggerSkip(MediaItem item) {
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
      ref.read(discoverProvider.notifier).skip(item);
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
    final notifier = ref.read(discoverProvider.notifier);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filter = ref.watch(discoverProvider).filter;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          text.languageCode == 'tr' ? 'Keşfet Filtreleri' : 'Discover Filters',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      text.languageCode == 'tr' ? 'İçerik Türü' : 'Content Type',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildFilterPill(
                          label: text.languageCode == 'tr' ? 'Hepsi' : 'All',
                          isSelected: filter.mediaType == 'all',
                          onTap: () => notifier.setMediaType('all'),
                        ),
                        const SizedBox(width: 8),
                        _buildFilterPill(
                          label: text.languageCode == 'tr' ? 'Filmler' : 'Movies',
                          isSelected: filter.mediaType == 'movie',
                          onTap: () => notifier.setMediaType('movie'),
                        ),
                        const SizedBox(width: 8),
                        _buildFilterPill(
                          label: text.languageCode == 'tr' ? 'Diziler' : 'TV Shows',
                          isSelected: filter.mediaType == 'tv',
                          onTap: () => notifier.setMediaType('tv'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      text.languageCode == 'tr' ? 'Minimum IMDb / TMDB Puanı' : 'Minimum Rating',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildFilterPill(
                          label: text.languageCode == 'tr' ? 'Tümü' : 'Any',
                          isSelected: filter.minRating == 0.0,
                          onTap: () => notifier.setMinRating(0.0),
                        ),
                        const SizedBox(width: 8),
                        _buildFilterPill(
                          label: '★ 7.0+',
                          isSelected: filter.minRating == 7.0,
                          onTap: () => notifier.setMinRating(7.0),
                        ),
                        const SizedBox(width: 8),
                        _buildFilterPill(
                          label: '★ 7.5+',
                          isSelected: filter.minRating == 7.5,
                          onTap: () => notifier.setMinRating(7.5),
                        ),
                        const SizedBox(width: 8),
                        _buildFilterPill(
                          label: '★ 8.0+',
                          isSelected: filter.minRating == 8.0,
                          onTap: () => notifier.setMinRating(8.0),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      text.languageCode == 'tr' ? 'Sıralama Ölçütü' : 'Sort By',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildFilterPill(
                          label: text.languageCode == 'tr' ? 'IMDb Puanına Göre' : 'Top Rated',
                          isSelected: filter.sortBy == 'rating',
                          onTap: () => notifier.setSortBy('rating'),
                        ),
                        const SizedBox(width: 8),
                        _buildFilterPill(
                          label: text.languageCode == 'tr' ? 'Popülerliğe Göre' : 'Popularity',
                          isSelected: filter.sortBy == 'popularity',
                          onTap: () => notifier.setSortBy('popularity'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.deepPurpleAccent : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.deepPurpleAccent : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = ref.watch(appTextProvider);
    final state = ref.watch(discoverProvider);
    final notifier = ref.read(discoverProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
            const SizedBox(width: 8),
            Text(
              text.languageCode == 'tr' ? 'Keşfet & Oyla' : 'Discover & Rate',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: Colors.white),
            tooltip: text.languageCode == 'tr' ? 'Filtreler' : 'Filters',
            onPressed: () => _openFilterSheet(context, text),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Genre Bar
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: discoverGenres.length,
                itemBuilder: (context, index) {
                  final genre = discoverGenres[index];
                  final isSelected = state.filter.genreKey == genre.key;
                  final label = text.languageCode == 'tr' ? genre.labelTr : genre.labelEn;

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: isSelected,
                      selectedColor: Colors.deepPurpleAccent,
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      side: BorderSide(
                        color: isSelected ? Colors.deepPurpleAccent : Colors.white10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (_) => notifier.setGenre(genre),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // Card Stack Area
            Expanded(
              child: state.isInitialLoading
                  ? const Center(child: CircularProgressIndicator())
                  : state.cards.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.movie_filter_rounded, size: 64, color: Colors.white24),
                              const SizedBox(height: 16),
                              Text(
                                text.languageCode == 'tr'
                                    ? 'Bu filtrelere uygun kart kalmadı!'
                                    : 'No cards left with these filters!',
                                style: const TextStyle(color: Colors.white70, fontSize: 16),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: () => notifier.setGenre(discoverGenres[0]),
                                icon: const Icon(Icons.refresh),
                                label: Text(text.languageCode == 'tr' ? 'Filtreleri Sıfırla' : 'Reset Filters'),
                              ),
                            ],
                          ),
                        )
                      : Stack(
                          alignment: Alignment.center,
                          children: [
                            // Show back cards
                            for (int i = math.min(state.cards.length - 1, 2); i > 0; i--)
                              _buildBackgroundCard(state.cards[i], i),

                            // Top interactive card
                            _buildTopCard(state.cards.first, text),
                          ],
                        ),
            ),

            const SizedBox(height: 14),

            // Bottom Action Buttons (Undo, Skip, Info, Library, Watched)
            if (state.cards.isNotEmpty)
              _buildBottomActionButtons(context, state.cards.first, state.undoStack.isNotEmpty),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundCard(MediaItem item, int depth) {
    final scale = 1.0 - (depth * 0.05);
    final offsetY = depth * 12.0;

    return Transform.translate(
      offset: Offset(0, offsetY),
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: 1.0 - (depth * 0.25),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.88,
            height: MediaQuery.of(context).size.height * 0.62,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: Colors.grey.shade900,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: item.posterUrl != null
                  ? Image.network(
                      item.posterUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const ColoredBox(color: Colors.black45),
                    )
                  : const ColoredBox(color: Colors.black45),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopCard(MediaItem item, AppText text) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final currentOffset = _animController.isAnimating ? _cardOffsetAnimation.value : _dragOffset;
    final rotationAngle = (currentOffset.dx / screenWidth) * 0.25;

    // Stamp Opacities
    final double rightOpacity = (currentOffset.dx / 100).clamp(0.0, 1.0);
    final double leftOpacity = (-currentOffset.dx / 100).clamp(0.0, 1.0);

    return GestureDetector(
      onPanStart: (_) {},
      onPanUpdate: (details) {
        setState(() {
          _dragOffset += details.delta;
        });
      },
      onPanEnd: (details) {
        if (_dragOffset.dx > 100) {
          _triggerSwipe(true, item);
        } else if (_dragOffset.dx < -100) {
          _triggerSwipe(false, item);
        } else {
          _resetPosition();
        }
      },
      child: Transform.translate(
        offset: currentOffset,
        child: Transform.rotate(
          angle: rotationAngle,
          child: Container(
            width: screenWidth * 0.88,
            height: screenHeight * 0.62,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Poster
                  if (item.posterUrl != null)
                    Image.network(
                      item.posterUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const ColoredBox(color: Colors.grey),
                    )
                  else
                    const ColoredBox(color: Colors.black54),

                  // Bottom Gradient
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.2),
                          Colors.black.withValues(alpha: 0.85),
                          Colors.black.withValues(alpha: 0.98),
                        ],
                        stops: const [0.3, 0.55, 0.8, 1.0],
                      ),
                    ),
                  ),

                  // Top Header Badges (IMDb + Type)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (item.rating != null && item.rating! > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  item.rating!.toStringAsFixed(1),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          const SizedBox.shrink(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Text(
                            item.type == 'tv' ? 'DİZİ' : 'FİLM',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Watched Stamp Overlay (Appears on Right Drag)
                  if (rightOpacity > 0.05)
                    Positioned(
                      top: 40,
                      left: 20,
                      child: Transform.rotate(
                        angle: -0.25,
                        child: Opacity(
                          opacity: rightOpacity,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF00E054), width: 3),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_rounded, color: Color(0xFF00E054), size: 24),
                                const SizedBox(width: 8),
                                Text(
                                  text.languageCode == 'tr' ? 'İZLEDİM' : 'WATCHED',
                                  style: const TextStyle(
                                    color: Color(0xFF00E054),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 20,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  // My List Stamp Overlay (Appears on Left Drag)
                  if (leftOpacity > 0.05)
                    Positioned(
                      top: 40,
                      right: 20,
                      child: Transform.rotate(
                        angle: 0.25,
                        child: Opacity(
                          opacity: leftOpacity,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.amberAccent, width: 3),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.bookmark_add_rounded, color: Colors.amberAccent, size: 24),
                                const SizedBox(width: 8),
                                Text(
                                  text.languageCode == 'tr' ? 'LİSTEMDE' : 'MY LIST',
                                  style: const TextStyle(
                                    color: Colors.amberAccent,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 20,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Bottom Text Info
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 20,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MediaDetailsScreen(mediaItem: item),
                          ),
                        );
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (item.description != null && item.description!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              item.description!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                height: 1.3,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                text.languageCode == 'tr' ? 'Detayları Gör' : 'View Details',
                                style: const TextStyle(
                                  color: Colors.deepPurpleAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: Colors.deepPurpleAccent, size: 16),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActionButtons(BuildContext context, MediaItem item, bool canUndo) {
    final notifier = ref.read(discoverProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Undo Button
          _buildCircleButton(
            icon: Icons.undo_rounded,
            color: Colors.amber,
            size: 46,
            iconSize: 22,
            enabled: canUndo,
            onPressed: canUndo ? notifier.undo : null,
          ),

          // Skip / Pass Button
          _buildCircleButton(
            icon: Icons.close_rounded,
            color: Colors.grey.shade400,
            size: 52,
            iconSize: 28,
            onPressed: () => _triggerSkip(item),
          ),

          // Info Button
          _buildCircleButton(
            icon: Icons.info_outline_rounded,
            color: Colors.blueAccent,
            size: 46,
            iconSize: 22,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MediaDetailsScreen(mediaItem: item),
                ),
              );
            },
          ),

          // Add to Library Button (Swipe Left equivalent)
          _buildCircleButton(
            icon: Icons.bookmark_add_rounded,
            color: Colors.amberAccent,
            size: 56,
            iconSize: 30,
            onPressed: () => _triggerSwipe(false, item),
          ),

          // Watched Button (Swipe Right equivalent)
          _buildCircleButton(
            icon: Icons.check_circle_rounded,
            color: const Color(0xFF00E054),
            size: 60,
            iconSize: 34,
            onPressed: () => _triggerSwipe(true, item),
          ),
        ],
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required Color color,
    required double size,
    required double iconSize,
    required VoidCallback? onPressed,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled && onPressed != null ? 1.0 : 0.35,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          customBorder: const CircleBorder(),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
            ),
            child: Icon(icon, color: color, size: iconSize),
          ),
        ),
      ),
    );
  }
}
