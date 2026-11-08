import 'package:hive/hive.dart';

/// Per-addon reliability: how often it returns streams, how fast, and how
/// often the stream it returned actually played. Kept in Hive so the ranking
/// learns across sessions.
class SourceStats {
  SourceStats._();

  static const String boxName = 'source_stats_box';

  static Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<dynamic>(boxName);
    }
  }

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen(boxName) ? Hive.box<dynamic>(boxName) : null;

  static Map<String, num> _read(String addonId) {
    final raw = _box?.get(addonId);
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v is num ? v : 0));
    }
    return <String, num>{};
  }

  static void _write(String addonId, Map<String, num> value) {
    _box?.put(addonId, value);
  }

  /// Records one resolve attempt for [addonId].
  static void recordResolve(String addonId, {required bool found, required int elapsedMs}) {
    if (addonId.isEmpty) return;
    final s = _read(addonId);
    final attempts = (s['a'] ?? 0) + 1;
    final hits = (s['s'] ?? 0) + (found ? 1 : 0);
    final prevMs = (s['ms'] ?? elapsedMs).toDouble();
    // Exponential moving average so a few slow days do not stick forever.
    final ms = found ? prevMs * 0.7 + elapsedMs * 0.3 : prevMs;
    _write(addonId, {...s, 'a': attempts, 's': hits, 'ms': ms});
  }

  /// Records whether a stream from [addonId] started playing.
  static void recordPlayback(String addonId, {required bool ok}) {
    if (addonId.isEmpty) return;
    final s = _read(addonId);
    final key = ok ? 'p' : 'f';
    _write(addonId, {...s, key: (s[key] ?? 0) + 1});
  }

  static AddonReliability of(String addonId) {
    final s = _read(addonId);
    return AddonReliability(
      attempts: (s['a'] ?? 0).toInt(),
      hits: (s['s'] ?? 0).toInt(),
      avgMs: (s['ms'] ?? 0).toDouble(),
      playOk: (s['p'] ?? 0).toInt(),
      playFail: (s['f'] ?? 0).toInt(),
    );
  }
}

class AddonReliability {
  final int attempts;
  final int hits;
  final double avgMs;
  final int playOk;
  final int playFail;

  const AddonReliability({
    this.attempts = 0,
    this.hits = 0,
    this.avgMs = 0,
    this.playOk = 0,
    this.playFail = 0,
  });

  /// Laplace-smoothed hit rate; 0.5 for an addon never tried.
  double get hitRate => (hits + 1) / (attempts + 2);

  /// Laplace-smoothed playback success rate; 0.5 when unknown.
  double get playRate => (playOk + 1) / (playOk + playFail + 2);

  /// Good enough to start playback without waiting for slower addons.
  bool get isTrusted => attempts >= 3 && hitRate >= 0.6 && playRate >= 0.6;
}

class SourceRanking {
  SourceRanking._();

  static final RegExp _resolution = RegExp(
    r'(2160|1440|1080|720|576|480|360)\s*p|\b(4k|uhd)\b',
    caseSensitive: false,
  );

  /// Vertical resolution read from the quality field or title, or null.
  static int? resolutionOf(Map<String, dynamic> stream) {
    final text = '${stream['quality'] ?? ''} ${stream['title'] ?? ''} ${stream['filename'] ?? ''}';
    final m = _resolution.firstMatch(text);
    if (m == null) return null;
    if (m.group(2) != null) return 2160;
    return int.tryParse(m.group(1)!);
  }

  static bool _isHls(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    return path.endsWith('.m3u8');
  }

  static bool hasLanguageTag(Map<String, dynamic> stream, String language) {
    final text = '${stream['title'] ?? ''} ${stream['provider'] ?? ''}'.toLowerCase();
    switch (language) {
      case 'tr':
        return text.contains('türkçe') ||
            text.contains('turkce') ||
            text.contains('dublaj') ||
            text.contains('tr dub') ||
            text.contains('altyaz') ||
            RegExp(r'\btr\b').hasMatch(text);
      case 'ar':
        return text.contains('arabic') || RegExp(r'\bar\b').hasMatch(text);
      case 'fa':
        return text.contains('persian') || text.contains('farsi');
      default:
        return false;
    }
  }

  /// Score for one stream; higher plays first.
  static double score(
    Map<String, dynamic> stream, {
    required AddonReliability reliability,
    required int addonOrder,
    String language = 'en',
  }) {
    var score = 0.0;

    final height = resolutionOf(stream);
    score += switch (height) {
      null => 14,
      >= 2160 => 26, // 4K often stutters on phones; 1080p is the sweet spot.
      >= 1080 => 30,
      >= 720 => 22,
      >= 480 => 10,
      _ => 4,
    };

    final direct = stream['is_direct_link'] != false;
    final url = (stream['url'] ?? '').toString();
    if (direct) {
      score += 25;
      if (_isHls(url)) score += 3;
    }

    score += reliability.hitRate * 20;
    score += reliability.playRate * 30;
    if (reliability.avgMs > 0) {
      score -= (reliability.avgMs / 1000).clamp(0, 8);
    }

    // Built-in order is the tie breaker for addons with no history yet.
    score += (12 - addonOrder.clamp(0, 12)) * 0.5;

    if (language != 'en' && hasLanguageTag(stream, language)) score += 8;

    return score;
  }

  /// Sorted copy of [streams], best first. Stable for equal scores.
  static List<Map<String, dynamic>> rank(
    List<Map<String, dynamic>> streams, {
    required AddonReliability Function(String addonId) reliabilityOf,
    required int Function(String addonId) orderOf,
    String language = 'en',
  }) {
    final scored = <(int, double, Map<String, dynamic>)>[];
    for (var i = 0; i < streams.length; i++) {
      final s = streams[i];
      final id = (s['addon_id'] ?? '').toString();
      scored.add((
        i,
        score(s, reliability: reliabilityOf(id), addonOrder: orderOf(id), language: language),
        s,
      ));
    }
    scored.sort((a, b) {
      final c = b.$2.compareTo(a.$2);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    return [for (final e in scored) e.$3];
  }
}
