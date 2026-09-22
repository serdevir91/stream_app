import 'dart:async';
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
  }
}
