import '../../../core/player/stream_headers.dart';

/// Headers and attached subtitles of a resolved stream map, in the shape
/// [DownloadItem] stores them.
({Map<String, String> headers, List<Map<String, String>> subtitles})
    streamDownloadExtras(Map<dynamic, dynamic> stream) {
  final subs = <Map<String, String>>[];
  final raw = stream['subtitles'];
  if (raw is List) {
    for (final s in raw) {
      if (s is! Map) continue;
      final url = s['url']?.toString() ?? '';
      if (url.isEmpty) continue;
      subs.add({
        'url': url,
        'language': (s['language'] ?? s['lang'] ?? '').toString(),
        'label': (s['label'] ?? s['language'] ?? '').toString(),
        'format': (s['format'] ?? '').toString(),
      });
    }
  }
  return (headers: streamHeadersOf(stream) ?? const {}, subtitles: subs);
}
