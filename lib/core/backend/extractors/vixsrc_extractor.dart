import 'dart:convert';
import 'package:dio/dio.dart';

class VixSrcVariant {
  final String quality;
  final String url;
  final int bandwidth;
  final String? resolution;

  const VixSrcVariant({
    required this.quality,
    required this.url,
    required this.bandwidth,
    this.resolution,
  });
}

class VixSrcAudioTrack {
  final String language;
  final String name;
  final String url;
  final bool isDefault;

  const VixSrcAudioTrack({
    required this.language,
    required this.name,
    required this.url,
    required this.isDefault,
  });
}

class VixSrcSubtitleTrack {
  final String language;
  final String name;
  final String url;

  const VixSrcSubtitleTrack({
    required this.language,
    required this.name,
    required this.url,
  });
}

class VixSrcPlaylistDetails {
  final String? ivHex;
  final String? keyUrl;
  final List<String> segmentUrls;
  final List<double> segmentDurations;

  const VixSrcPlaylistDetails({
    this.ivHex,
    this.keyUrl,
    required this.segmentUrls,
    required this.segmentDurations,
  });
}

class VixSrcResult {
  final String masterUrl;
  final List<VixSrcVariant> videoVariants;
  final List<VixSrcAudioTrack> audioTracks;
  final List<VixSrcSubtitleTrack> subtitles;
  final Map<String, String> headers;

  const VixSrcResult({
    required this.masterUrl,
    required this.videoVariants,
    required this.audioTracks,
    required this.subtitles,
    required this.headers,
  });

  VixSrcVariant? getBestVideoVariant([String? preferredQuality]) {
    if (videoVariants.isEmpty) return null;
    if (preferredQuality != null) {
      final match = videoVariants.firstWhere(
        (v) => v.quality.toLowerCase().contains(preferredQuality.toLowerCase()),
        orElse: () => videoVariants.first,
      );
      return match;
    }
    // Prefer 720p or 1080p
    final p720 = videoVariants.where((v) => v.quality == '720p').firstOrNull;
    if (p720 != null) return p720;
    final p1080 = videoVariants.where((v) => v.quality == '1080p').firstOrNull;
    if (p1080 != null) return p1080;
    return videoVariants.first;
  }

  VixSrcAudioTrack? getAudioTrack([String preferredLang = 'eng']) {
    if (audioTracks.isEmpty) return null;
    final match = audioTracks.firstWhere(
      (a) => a.language.toLowerCase() == preferredLang.toLowerCase(),
      orElse: () => audioTracks.firstWhere(
        (a) => a.isDefault,
        orElse: () => audioTracks.first,
      ),
    );
    return match;
  }
}

class VixSrcExtractor {
  final Dio _dio;

  static const defaultHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://vixsrc.to/',
    'Origin': 'https://vixsrc.to',
  };

  VixSrcExtractor({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
                headers: defaultHeaders,
              ),
            );

  Future<VixSrcResult?> extract({
    required String tmdbId,
    required String mediaType,
    int? season,
    int? episode,
  }) async {
    try {
      final isTv = mediaType == 'tv' || mediaType == 'series';
      final apiUrl = isTv
          ? 'https://vixsrc.to/api/tv/$tmdbId/${season ?? 1}/${episode ?? 1}'
          : 'https://vixsrc.to/api/movie/$tmdbId';

      final apiRes = await _dio.get(apiUrl);
      if (apiRes.statusCode != 200 || apiRes.data == null) return null;

      final dynamic rawData = apiRes.data;
      final Map<String, dynamic> data = rawData is Map
          ? Map<String, dynamic>.from(rawData)
          : Map<String, dynamic>.from(jsonDecode(rawData.toString()) as Map);

      final src = data['src']?.toString();
      if (src == null || src.isEmpty) return null;

      final embedUrl = src.startsWith('http') ? src : 'https://vixsrc.to$src';
      final embedRes = await _dio.get(
        embedUrl,
        options: Options(headers: {'Referer': 'https://vixsrc.to/'}),
      );
      if (embedRes.statusCode != 200 || embedRes.data == null) return null;

      final html = embedRes.data.toString();
      final token = RegExp(r'''token['"]?\s*:\s*['"]([^'"]+)''').firstMatch(html)?.group(1);
      final expires = RegExp(r'''expires['"]?\s*:\s*['"]([^'"]+)''').firstMatch(html)?.group(1);
      final playlistUrl = RegExp(r'''url\s*:\s*['"]([^'"]+)''').firstMatch(html)?.group(1);

      if (token == null || expires == null || playlistUrl == null) {
        // ignore: avoid_print
        print('VixSrcExtractor: Missing token/expires/url in embed page');
        return null;
      }

      final masterUrl = '$playlistUrl?token=$token&expires=$expires&h=1&lang=en';
      final masterRes = await _dio.get(
        masterUrl,
        options: Options(headers: {
          'Referer': embedUrl,
          'Origin': 'https://vixsrc.to',
        }),
      );
      if (masterRes.statusCode != 200 || masterRes.data == null) return null;

      final masterText = masterRes.data.toString();
      return _parseMasterPlaylist(masterUrl, masterText);
    } catch (e) {
      // ignore: avoid_print
      print('VixSrcExtractor.extract failed: $e');
      return null;
    }
  }

  VixSrcResult _parseMasterPlaylist(String masterUrl, String masterText) {
    final videoVariants = <VixSrcVariant>[];
    final audioTracks = <VixSrcAudioTrack>[];
    final subtitles = <VixSrcSubtitleTrack>[];

    final lines = masterText.split('\n').map((l) => l.trim()).toList();

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Audio tracks: #EXT-X-MEDIA:TYPE=AUDIO,...
      if (line.startsWith('#EXT-X-MEDIA:TYPE=AUDIO')) {
        final lang = RegExp(r'LANGUAGE="([^"]+)"').firstMatch(line)?.group(1) ?? 'und';
        final name = RegExp(r'NAME="([^"]+)"').firstMatch(line)?.group(1) ?? lang;
        final uri = RegExp(r'URI="([^"]+)"').firstMatch(line)?.group(1);
        final isDefault = line.contains('DEFAULT=YES');
        if (uri != null) {
          final absUri = uri.startsWith('http') ? uri : _resolveUrl(masterUrl, uri);
          audioTracks.add(VixSrcAudioTrack(
            language: lang,
            name: name,
            url: absUri,
            isDefault: isDefault,
          ));
        }
      }

      // Subtitles: #EXT-X-MEDIA:TYPE=SUBTITLES,...
      if (line.startsWith('#EXT-X-MEDIA:TYPE=SUBTITLES')) {
        final lang = RegExp(r'LANGUAGE="([^"]+)"').firstMatch(line)?.group(1) ?? 'und';
        final name = RegExp(r'NAME="([^"]+)"').firstMatch(line)?.group(1) ?? lang;
        final uri = RegExp(r'URI="([^"]+)"').firstMatch(line)?.group(1);
        if (uri != null) {
          final absUri = uri.startsWith('http') ? uri : _resolveUrl(masterUrl, uri);
          subtitles.add(VixSrcSubtitleTrack(
            language: lang,
            name: name,
            url: absUri,
          ));
        }
      }

      // Video streams: #EXT-X-STREAM-INF:...
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
        final resMatch = RegExp(r'RESOLUTION=(\d+x\d+)').firstMatch(line);
        final bandwidth = bwMatch != null ? int.tryParse(bwMatch.group(1)!) ?? 0 : 0;
        final res = resMatch?.group(1);

        String quality = 'Auto';
        if (res != null) {
          final height = res.split('x').last;
          quality = '${height}p';
        } else if (bandwidth > 3000000) {
          quality = '1080p';
        } else if (bandwidth > 1500000) {
          quality = '720p';
        } else {
          quality = '480p';
        }

        // Next non-empty line is URI
        for (int j = i + 1; j < lines.length; j++) {
          final next = lines[j];
          if (next.isNotEmpty && !next.startsWith('#')) {
            final absUri = next.startsWith('http') ? next : _resolveUrl(masterUrl, next);
            videoVariants.add(VixSrcVariant(
              quality: quality,
              url: absUri,
              bandwidth: bandwidth,
              resolution: res,
            ));
            break;
          }
        }
      }
    }

    // Sort video variants by bandwidth descending
    videoVariants.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));

    return VixSrcResult(
      masterUrl: masterUrl,
      videoVariants: videoVariants,
      audioTracks: audioTracks,
      subtitles: subtitles,
      headers: defaultHeaders,
    );
  }

  Future<VixSrcPlaylistDetails?> parsePlaylistDetails(String playlistUrl) async {
    try {
      final res = await _dio.get(playlistUrl);
      if (res.statusCode != 200 || res.data == null) return null;

      final text = res.data.toString();
      final lines = text.split('\n').map((l) => l.trim()).toList();

      String? ivHex;
      String? keyUrl;
      final segmentUrls = <String>[];
      final segmentDurations = <double>[];

      double currentDuration = 8.0;

      for (final line in lines) {
        if (line.startsWith('#EXT-X-KEY:')) {
          final ivM = RegExp(r'IV=0x([0-9a-fA-F]+)').firstMatch(line);
          if (ivM != null) ivHex = ivM.group(1);

          final uriM = RegExp(r'URI="([^"]+)"').firstMatch(line);
          if (uriM != null) {
            final uri = uriM.group(1)!;
            keyUrl = uri.startsWith('http') ? uri : _resolveUrl(playlistUrl, uri);
          }
        } else if (line.startsWith('#EXTINF:')) {
          final durM = RegExp(r'#EXTINF:([0-9.]+),?').firstMatch(line);
          if (durM != null) {
            currentDuration = double.tryParse(durM.group(1)!) ?? 8.0;
          }
        } else if (line.isNotEmpty && !line.startsWith('#')) {
          final absSeg = line.startsWith('http') ? line : _resolveUrl(playlistUrl, line);
          segmentUrls.add(absSeg);
          segmentDurations.add(currentDuration);
        }
      }

      return VixSrcPlaylistDetails(
        ivHex: ivHex,
        keyUrl: keyUrl,
        segmentUrls: segmentUrls,
        segmentDurations: segmentDurations,
      );
    } catch (e) {
      // ignore: avoid_print
      print('VixSrcExtractor.parsePlaylistDetails error: $e');
      return null;
    }
  }

  String _resolveUrl(String baseUrl, String relativePath) {
    try {
      final base = Uri.parse(baseUrl);
      return base.resolve(relativePath).toString();
    } catch (_) {
      return relativePath;
    }
  }
}
