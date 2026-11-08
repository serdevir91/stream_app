import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

/// Theme colors by role, so screens follow light, dark and AMOLED modes.
extension ThemeX on BuildContext {
  ColorScheme get cs => Theme.of(this).colorScheme;

  /// Main text and icons.
  Color get fg => cs.onSurface;

  /// Secondary text and icons.
  Color get fgMuted => cs.onSurfaceVariant;

  /// Hints, captions and disabled text.
  Color get fgFaint => cs.onSurfaceVariant.withValues(alpha: 0.72);

  /// Dividers, borders and subtle fills.
  Color get line => cs.outlineVariant.withValues(alpha: 0.55);

  /// Card and tile background.
  Color get card => cs.surfaceContainer;

  /// Raised card, menu and sheet background.
  Color get cardHigh => cs.surfaceContainerHigh;

  /// Page background.
  Color get bg => Theme.of(this).scaffoldBackgroundColor;

  bool get isLight => Theme.of(this).brightness == Brightness.light;
}

/// Keeps a screen built for a dark look (poster backdrops, the player) dark
/// when the app runs in light mode. In dark and AMOLED modes it does nothing.
class DarkScope extends StatelessWidget {
  const DarkScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.dark) return child;
    return Theme(
      data: AppTheme.forMode('dark'),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: child,
      ),
    );
  }
}
