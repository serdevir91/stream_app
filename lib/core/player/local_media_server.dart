import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Lightweight local loopback HTTP server to serve locally stored
/// HLS playlists (.m3u8) and video segments (.ts / .mp4) to video players (ExoPlayer, VLC, MediaKit).
/// ExoPlayer does not reliably support local file:// .m3u8 playlists with relative segments.
/// Serving them via 127.0.0.1 resolves this cleanly across all platforms.
class LocalMediaServer {
  static LocalMediaServer? _instance;
  static LocalMediaServer get instance => _instance ??= LocalMediaServer._();

  LocalMediaServer._();

  HttpServer? _server;
  int get port => _server?.port ?? 0;
  final Map<String, String> _registeredDirectories = {};
  final Map<String, Map<String, String>> _proxySessions = {};
  final Map<String, String> _textFiles = {};
  HttpClient? _upstream;
  int _counter = 0;

  Future<void> ensureStarted() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server!.listen(_handleRequest, onError: (e) {
        debugPrint('LocalMediaServer error: $e');
      });
      debugPrint('LocalMediaServer running on http://127.0.0.1:$port');
    } catch (e) {
      debugPrint('LocalMediaServer bind failed: $e');
    }
  }

  /// Registers a local directory (e.g. an HLS folder) and returns a token.
  String registerDirectory(String dirPath) {
    final token = dirPath.hashCode.abs().toString();
    _registeredDirectories[token] = dirPath;
    return token;
  }

  /// Returns the localhost HTTP URL for a local file (especially .m3u8 playlists).
  Future<String> getServedUrl(String filePath) async {
    await ensureStarted();
    final file = File(filePath);
    final parentDir = file.parent.path;
    final token = registerDirectory(parentDir);
    final fileName = file.uri.pathSegments.last;
    return 'http://127.0.0.1:$port/hls/$token/$fileName';
  }

  /// Returns a loopback URL that fetches [url] with [headers] added. HLS
  /// playlists are rewritten so segments, keys and renditions also go through
  /// the proxy. Lets players without header support (VLC, external apps) play
  /// streams that need a Referer or Origin.
  Future<String> proxyUrl(String url, Map<String, String> headers) async {
    await ensureStarted();
    final session = 's${++_counter}${url.hashCode.abs()}';
    _proxySessions[session] = Map.of(headers);
    return _proxyPath(session, url);
  }

  String _proxyPath(String session, String upstream) {
    final encoded = base64Url.encode(utf8.encode(upstream)).replaceAll('=', '');
    final ext = _extensionHint(upstream);
    return 'http://127.0.0.1:$port/p/$session/$encoded$ext';
  }

  /// Keeps an extension at the end of proxied URLs, because some players
  /// pick the demuxer from it.
  String _extensionHint(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    for (final ext in const ['.m3u8', '.mp4', '.mkv', '.ts', '.webm', '.vtt', '.srt']) {
      if (path.endsWith(ext)) return '/x$ext';
    }
    return '';
  }

  /// Serves in-memory text (a prepared subtitle) and returns its URL.
  Future<String> serveText(String fileName, String content) async {
    await ensureStarted();
    final token = 't${++_counter}';
    _textFiles['$token/$fileName'] = content;
    return 'http://127.0.0.1:$port/txt/$token/$fileName';
  }

  Future<void> _handleProxy(
    HttpRequest request,
    String session,
    String encoded,
  ) async {
    final response = request.response;
    final headers = _proxySessions[session];
    String upstream;
    try {
      upstream = utf8.decode(base64Url.decode(base64Url.normalize(encoded)));
    } catch (_) {
      response.statusCode = HttpStatus.badRequest;
      await response.close();
      return;
    }
    if (headers == null) {
      response.statusCode = HttpStatus.gone;
      await response.close();
      return;
    }
    final client = _upstream ??= (HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..autoUncompress = true);
    try {
      final req = await client.getUrl(Uri.parse(upstream));
      headers.forEach(req.headers.set);
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
      final upRes = await req.close();
      final contentType = upRes.headers.contentType?.mimeType.toLowerCase() ?? '';
      final isPlaylist = contentType.contains('mpegurl') ||
          Uri.parse(upstream).path.toLowerCase().endsWith('.m3u8');
      response.statusCode = upRes.statusCode;
      if (isPlaylist) {
        final body = await upRes.transform(utf8.decoder).join();
        final base = upRes.redirects.isNotEmpty
            ? upRes.redirects.last.location.isAbsolute
                ? upRes.redirects.last.location
                : Uri.parse(upstream).resolveUri(upRes.redirects.last.location)
            : Uri.parse(upstream);
        final rewritten = rewritePlaylist(
          body,
          base,
          (abs) => _proxyPath(session, abs),
        );
        final bytes = utf8.encode(rewritten);
        response.headers.set('Content-Type', 'application/vnd.apple.mpegurl');
        response.headers.set('Content-Length', bytes.length.toString());
        response.add(bytes);
        await response.close();
        return;
      }
      for (final name in const [
        HttpHeaders.contentTypeHeader,
        HttpHeaders.contentLengthHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.acceptRangesHeader,
      ]) {
        final value = upRes.headers.value(name);
        if (value != null) response.headers.set(name, value);
      }
      if (request.method == 'HEAD') {
        await upRes.drain<void>();
        await response.close();
        return;
      }
      await upRes.pipe(response);
    } catch (e) {
      debugPrint('LocalMediaServer proxy error: $e');
      try {
        response.statusCode = HttpStatus.badGateway;
        await response.close();
      } catch (_) {}
    }
  }

  /// Rewrites every URI in an HLS playlist (segment lines and `URI="..."`
  /// attributes) to an absolute URL passed through [wrap].
  static String rewritePlaylist(
    String body,
    Uri base,
    String Function(String absoluteUrl) wrap,
  ) {
    final uriAttr = RegExp(r'URI="([^"]+)"');
    final out = StringBuffer();
    for (final rawLine in const LineSplitter().convert(body)) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        out.writeln();
      } else if (line.startsWith('#')) {
        out.writeln(line.replaceAllMapped(uriAttr, (m) {
          final abs = base.resolve(m.group(1)!).toString();
          return 'URI="${wrap(abs)}"';
        }));
      } else {
        out.writeln(wrap(base.resolve(line).toString()));
      }
    }
    return out.toString();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', '*');
    response.headers.set('Accept-Ranges', 'bytes');

    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.ok;
      await response.close();
      return;
    }

    final segments = request.uri.pathSegments;
    if (segments.length >= 3 && segments[0] == 'p') {
      await _handleProxy(request, segments[1], segments[2]);
      return;
    }
    if (segments.length == 3 && segments[0] == 'txt') {
      final content = _textFiles['${segments[1]}/${segments[2]}'];
      if (content != null) {
        final bytes = utf8.encode(content);
        final isVtt = segments[2].toLowerCase().endsWith('.vtt');
        response.headers.set(
          'Content-Type',
          isVtt ? 'text/vtt; charset=utf-8' : 'application/x-subrip; charset=utf-8',
        );
        response.headers.set('Content-Length', bytes.length.toString());
        response.add(bytes);
        await response.close();
        return;
      }
    }
    // Expected path format: /hls/<token>/<filename>
    if (segments.length >= 3 && segments[0] == 'hls') {
      final token = segments[1];
      final relativePath = segments.sublist(2).join('/');
      final baseDir = _registeredDirectories[token];

      if (baseDir != null) {
        final targetFile = File('$baseDir/$relativePath');
        if (await targetFile.exists()) {
          await _serveFile(request, response, targetFile);
          return;
        }
      }
    }

    response.statusCode = HttpStatus.notFound;
    response.write('Not Found');
    await response.close();
  }

  Future<void> _serveFile(
    HttpRequest request,
    HttpResponse response,
    File file,
  ) async {
    final ext = file.path.toLowerCase();
    String contentType = 'application/octet-stream';
    if (ext.endsWith('.m3u8')) {
      contentType = 'application/vnd.apple.mpegurl';
    } else if (ext.endsWith('.ts')) {
      contentType = 'video/mp2t';
    } else if (ext.endsWith('.mp4')) {
      contentType = 'video/mp4';
    } else if (ext.endsWith('.mkv')) {
      contentType = 'video/x-matroska';
    } else if (ext.endsWith('.srt')) {
      contentType = 'text/plain; charset=utf-8';
    } else if (ext.endsWith('.vtt')) {
      contentType = 'text/vtt; charset=utf-8';
    }

    response.headers.set('Content-Type', contentType);

    final totalLength = await file.length();
    final rangeHeader = request.headers.value('range');

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final parts = rangeHeader.substring(6).split('-');
      final start = int.tryParse(parts[0]) ?? 0;
      final end = parts.length > 1 && parts[1].isNotEmpty
          ? int.tryParse(parts[1]) ?? (totalLength - 1)
          : totalLength - 1;

      final chunkLength = (end - start) + 1;
      response.statusCode = HttpStatus.partialContent;
      response.headers.set('Content-Range', 'bytes $start-$end/$totalLength');
      response.headers.set('Content-Length', chunkLength.toString());

      try {
        await file.openRead(start, end + 1).pipe(response);
      } catch (_) {}
    } else {
      response.statusCode = HttpStatus.ok;
      response.headers.set('Content-Length', totalLength.toString());
      try {
        await file.openRead().pipe(response);
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _registeredDirectories.clear();
    _proxySessions.clear();
    _textFiles.clear();
    _upstream?.close(force: true);
    _upstream = null;
  }
}
