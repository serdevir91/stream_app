import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'base_addon.dart';

class WebSourceAddon extends BaseAddon {
  final String sourceUrl;

  WebSourceAddon({
    required this.sourceUrl,
    required AddonManifest manifest,
  }) : _manifest = manifest;

  final AddonManifest _manifest;
  final Map<String, _CandidateItem> _parsedItems = {};
  bool _isParsed = false;

  @override
  AddonManifest get manifest => _manifest;

  @override
  Future<List<SearchResult>> search(String query, String contentType) async {
    _ensureParsed(defaultType: contentType);
    final q = query.trim().toLowerCase();

    final results = <SearchResult>[];
    for (final candidate in _parsedItems.values) {
      if (contentType == 'series' && candidate.contentType == 'movie') continue;
      if (contentType == 'movie' && candidate.contentType == 'series') continue;

      final haystack =
          '${candidate.title} ${candidate.description ?? ''}'.toLowerCase();
      if (q.isNotEmpty && !haystack.contains(q)) continue;

      results.add(SearchResult(
        id: candidate.id,
        title: candidate.title,
        type: candidate.contentType,
        poster: candidate.poster,
        description: candidate.description,
      ));
    }

    return results.take(50).toList();
  }

  @override
  Future<List<StreamResult>> getStreams(
    String contentId,
    String contentType,
    int season,
    int episode,
  ) async {
    _ensureParsed(defaultType: contentType);

    var candidate = _parsedItems[contentId];
    if (candidate == null && _parsedItems.length == 1) {
      candidate = _parsedItems.values.first;
    }

    if (candidate == null) return [];

    return candidate.streams
        .map((streamUrl) => StreamResult(
              url: streamUrl,
              title: candidate!.title,
              quality: _guessQuality(streamUrl),
              provider: _manifest.name,
              isDirectLink: true,
            ))
        .toList();
  }

  void _ensureParsed({required String defaultType}) {
    if (_isParsed) return;
    _isParsed = true;

    if (_isDirectMediaUrl(sourceUrl)) {
      final cid = _candidateId(sourceUrl);
      _parsedItems[cid] = _CandidateItem(
        id: cid,
        title: _titleFromUrl(sourceUrl),
        contentType:
            defaultType == 'movie' || defaultType == 'series' ? defaultType : 'movie',
        description: 'Doğrudan medya bağlantısı',
        streams: [sourceUrl],
      );
      return;
    }

    _parseHtmlSource(defaultType);
  }

  Future<void> _parseHtmlSource(String defaultType) async {
    String body;
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/json,*/*',
        },
        followRedirects: true,
      ));

      final response = await dio.get(sourceUrl);
      if (response.statusCode != null && response.statusCode! >= 400) return;
      body = response.data?.toString() ?? '';
    } catch (_) {
      return;
    }

    final lowerBody = body.toLowerCase();

    final titleMatch =
        RegExp(r'<title[^>]*>([\s\S]*?)</title>').firstMatch(body);
    final pageTitle =
        titleMatch != null ? _cleanupText(titleMatch.group(1)) : _titleFromUrl(sourceUrl);

    final descMatch = RegExp(
            "<meta[^>]+(?:name=[\"']description[\"']|property=[\"']og:description[\"'])[^>]+content=[\"'](.*?)[\"']")
        .firstMatch(lowerBody);
    final pageDescription =
        descMatch != null ? _cleanupText(descMatch.group(1)) : null;

    final posterMatch = RegExp(
            "<meta[^>]+property=[\"']og:image[\"'][^>]+content=[\"'](.*?)[\"']")
        .firstMatch(lowerBody);
    final pagePoster = posterMatch != null
        ? _normalizeUrl(posterMatch.group(1)!, sourceUrl)
        : null;

    final urls = <String>{};
    for (final match in RegExp(r'https?://[^\s"<>]+').allMatches(lowerBody)) {
      final normalized = _normalizeUrl(match.group(0)!, sourceUrl);
      if (_isDirectMediaUrl(normalized)) urls.add(normalized);
    }

    for (final match in RegExp("(?:href|src)=[\"']([^\"']+)[\"']")
        .allMatches(lowerBody)) {
      final normalized = _normalizeUrl(match.group(1)!, sourceUrl);
      if (_isDirectMediaUrl(normalized)) urls.add(normalized);
    }

    if (urls.isEmpty) return;

    for (final mediaUrl in urls.toList()..sort()) {
      final itemTitle = _titleFromUrl(mediaUrl);
      final inferredType = _inferType(itemTitle, pageTitle, defaultType);
      final cid = _candidateId(mediaUrl);
      _parsedItems[cid] = _CandidateItem(
        id: cid,
        title: itemTitle,
        contentType: inferredType,
        description: pageDescription,
        poster: pagePoster,
        streams: [mediaUrl],
      );
    }

    if (_parsedItems.isNotEmpty) {
      final mergedId = _candidateId(sourceUrl);
      final mergedStreams =
          _parsedItems.values.map((item) => item.streams.first).toList();
      _parsedItems[mergedId] = _CandidateItem(
        id: mergedId,
        title: pageTitle,
        contentType:
            defaultType == 'movie' || defaultType == 'series' ? defaultType : 'movie',
        description: pageDescription,
        poster: pagePoster,
        streams: mergedStreams,
      );
    }
  }

  static const _mediaExtensions = [
    '.m3u8', '.mp4', '.webm', '.mkv', '.avi', '.mov', '.m4v', '.mpd',
  ];

  static bool _isDirectMediaUrl(String url) {
    final value = url.trim().toLowerCase();
    if (value.startsWith('magnet:?')) return true;
    final path = value.split('?').first.split('#').first;
    return _mediaExtensions.any((ext) => path.endsWith(ext));
  }

  static String _normalizeUrl(String url, String baseUrl) {
    final clean = url.trim();
    if (clean.startsWith('//')) {
      final parsed = Uri.tryParse(baseUrl);
      return '${parsed?.scheme ?? 'https'}:$clean';
    }
    if (clean.startsWith('/')) {
      final base = Uri.tryParse(baseUrl);
      if (base != null) {
        return '${base.scheme}://${base.host}${base.port != 80 && base.port != 443 ? ':${base.port}' : ''}$clean';
      }
    }
    return clean;
  }

  static String _titleFromUrl(String url) {
    final parsed = Uri.tryParse(url);
    var filename = parsed?.path.split('/').last ?? url;
    filename = filename.replaceFirst(RegExp(r'\.[A-Za-z0-9]{2,5}$'), '');
    final title = filename.replaceAll(RegExp(r'[-_]'), ' ').trim();
    return title.isNotEmpty ? title : 'Web Kaynağı';
  }

  static String _candidateId(String value) {
    final digest = sha1.convert(utf8.encode(value)).toString().substring(0, 14);
    return 'web-$digest';
  }

  static String _inferType(String title, String contextTitle, String defaultType) {
    final text = '$title $contextTitle'.toLowerCase();
    if (['s01', 's1', 'season', 'episode', 'bölüm', 'sezon']
        .any((token) => text.contains(token))) {
      return 'series';
    }
    if (defaultType == 'movie' || defaultType == 'series') return defaultType;
    return 'movie';
  }

  static String _guessQuality(String url) {
    final lower = url.toLowerCase();
    for (final token in ['2160', '1440', '1080', '720', '480', '360']) {
      if (lower.contains(token)) return '${token}p';
    }
    if (lower.startsWith('magnet:?')) return 'Torrent';
    if (lower.contains('.m3u8')) return 'HLS';
    if (lower.contains('.mpd')) return 'DASH';
    return 'Auto';
  }

  static String _cleanupText(String? value) {
    var text = value ?? '';
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    return text.trim();
  }
}

class _CandidateItem {
  final String id;
  final String title;
  final String contentType;
  final String? description;
  final String? poster;
  final List<String> streams;

  _CandidateItem({
    required this.id,
    required this.title,
    required this.contentType,
    this.description,
    this.poster,
    required this.streams,
  });
}
