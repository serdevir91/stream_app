/// Extracts the HTTP headers a stream map needs. Sources store them under
/// `headers`, Stremio addons under `behaviorHints.proxyHeaders.request`.
Map<String, String>? streamHeadersOf(Map<dynamic, dynamic>? stream) {
  if (stream == null || stream.isEmpty) return null;
  final direct = stream['headers'];
  if (direct is Map && direct.isNotEmpty) {
    return direct.map((k, v) => MapEntry(k.toString(), v.toString()));
  }
  final hints = stream['behaviorHints'];
  if (hints is Map) {
    final proxy = hints['proxyHeaders'];
    final request = proxy is Map ? proxy['request'] : null;
    if (request is Map && request.isNotEmpty) {
      return request.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
  }
  return null;
}
