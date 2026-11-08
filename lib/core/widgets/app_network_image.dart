import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Network image with a disk cache, a short fade-in and a decode size that
/// matches the box it is drawn in, so long poster rows do not hold
/// full-size bitmaps in memory.
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage(
    this.url, {
    super.key,
    this.fit,
    this.width,
    this.height,
    this.color,
    this.colorBlendMode,
    this.alignment = Alignment.center,
    this.errorBuilder,
  });

  final String url;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final Color? color;
  final BlendMode? colorBlendMode;
  final Alignment alignment;
  final Widget Function(BuildContext context, Object error, StackTrace? stackTrace)?
      errorBuilder;

  @override
  Widget build(BuildContext context) {
    if (url.trim().isEmpty) {
      return errorBuilder?.call(context, ArgumentError('empty url'), null) ??
          const ImagePlaceholder();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final w = _finite(width) ?? _finite(constraints.maxWidth);
        final h = _finite(height) ?? _finite(constraints.maxHeight);
        // With cover, the image may be scaled up to fill the taller side.
        final side = fit == BoxFit.cover && h != null && w != null
            ? math.max(w, h)
            : w;
        final cacheWidth = side == null ? null : (side * dpr).round().clamp(64, 1920);
        return CachedNetworkImage(
          imageUrl: url,
          fit: fit,
          width: width,
          height: height,
          color: color,
          colorBlendMode: colorBlendMode,
          alignment: alignment,
          memCacheWidth: cacheWidth,
          fadeInDuration: const Duration(milliseconds: 180),
          fadeOutDuration: Duration.zero,
          placeholder: (context, _) => const ImagePlaceholder(),
          errorWidget: (context, _, error) =>
              errorBuilder?.call(context, error, null) ?? const ImagePlaceholder(),
        );
      },
    );
  }

  static double? _finite(double? v) =>
      v == null || !v.isFinite || v <= 0 ? null : v;
}

/// Flat surface shown while an image loads or when it fails.
class ImagePlaceholder extends StatelessWidget {
  const ImagePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const SizedBox.expand(),
    );
  }
}

/// Pulsing grey block for skeleton loading states.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.width, this.height, this.radius = 12});

  final double? width;
  final double? height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 0.9).animate(_controller),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// A row of poster-shaped skeletons for a loading horizontal list.
class PosterRowSkeleton extends StatelessWidget {
  const PosterRowSkeleton({super.key, this.height = 200, this.itemWidth = 130});

  final double height;
  final double itemWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, _) => SkeletonBox(width: itemWidth, height: height),
      ),
    );
  }
}
