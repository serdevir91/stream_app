import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../background/keep_alive_service.dart';
import '../subtitles/subtitle_engine.dart';
import 'local_media_server.dart';

class ExternalPlayerApp {
  final String packageName;
  final String label;

  const ExternalPlayerApp(this.packageName, this.label);
}

class ExternalPlaybackResult {
  /// False when no player could be opened.
  final bool launched;
  final int positionMs;
  final int durationMs;

  /// The player reported that the video played to the end.
  final bool completed;

  const ExternalPlaybackResult({
    required this.launched,
    this.positionMs = 0,
    this.durationMs = 0,
    this.completed = false,
  });
}

/// Hands a stream to an installed Android player (VLC, MX, Just Player,
/// mpv). Header-protected streams go through the local proxy, and the
/// subtitle is re-timed here and served as UTF-8 SRT, so the external
/// player shows it in sync without its own delay settings.
class ExternalPlayerService {
  ExternalPlayerService._();

  static const MethodChannel _channel = MethodChannel(
    'stream_app/external_player',
  );

  /// Settings value for "ask every time".
  static const String askValue = 'ask';

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  static Future<List<ExternalPlayerApp>> installedPlayers() async {
    if (!isSupported) return const [];
    try {
      final raw = await _channel.invokeListMethod<dynamic>('listPlayers');
      final apps = <ExternalPlayerApp>[];
      for (final item in raw ?? const []) {
        if (item is! Map) continue;
        final pkg = item['package']?.toString() ?? '';
        if (pkg.isEmpty || pkg.startsWith('com.example.stream_app')) continue;
        apps.add(ExternalPlayerApp(pkg, item['label']?.toString() ?? pkg));
      }
      apps.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
      return apps;
    } catch (e) {
      debugPrint('listPlayers failed: $e');
      return const [];
    }
  }

  /// Opens [source] (URL or local file path) and waits until the player
  /// returns. [packageName] null or [askValue] shows the system chooser.
  static Future<ExternalPlaybackResult> play({
    required String source,
    required String title,
    String? packageName,
    Map<String, String>? headers,
    int positionMs = 0,
    SubtitleDocument? subtitle,
    SubtitleTiming timing = const SubtitleTiming(),
    String subtitleName = 'Subtitle',
  }) async {
    if (!isSupported) return const ExternalPlaybackResult(launched: false);
    final server = LocalMediaServer.instance;
    await KeepAliveService.acquire(
      KeepAliveReason.externalPlayer,
      title: title,
      text: 'Playing in external player',
    );
    try {
      final url = await _playableUrl(source, headers, server);
      final subs = <Map<String, String>>[];
      if (subtitle != null && subtitle.cues.isNotEmpty) {
        final name = '${_safeName(title)}.srt';
        final subUrl = await server.serveText(name, subtitle.toSrt(timing));
        subs.add({'url': subUrl, 'name': subtitleName});
      }
      final pkg = (packageName == null || packageName == askValue)
          ? null
          : packageName;
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'launch',
        {
          'url': url,
          'package': pkg,
          'title': title,
          'positionMs': positionMs,
          'subtitles': subs,
          'headers': headers ?? const <String, String>{},
        },
      );
      return ExternalPlaybackResult(
        launched: result != null,
        positionMs: (result?['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (result?['durationMs'] as num?)?.toInt() ?? 0,
        completed: result?['endBy'] == 'playback_completion',
      );
    } catch (e) {
      debugPrint('External player launch failed: $e');
      return const ExternalPlaybackResult(launched: false);
    } finally {
      await KeepAliveService.release(KeepAliveReason.externalPlayer);
    }
  }

  static Future<String> _playableUrl(
    String source,
    Map<String, String>? headers,
    LocalMediaServer server,
  ) async {
    final uri = Uri.tryParse(source);
    final isRemote = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    if (!isRemote) {
      final path = uri != null && uri.scheme == 'file' ? uri.toFilePath() : source;
      return server.getServedUrl(path);
    }
    if (headers != null && headers.isNotEmpty) {
      return server.proxyUrl(source, headers);
    }
    return source;
  }

  static String _safeName(String title) {
    final cleaned = title.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    final trimmed = cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned;
    return trimmed.isEmpty ? 'subtitle' : trimmed;
  }
}
