import 'package:dio/dio.dart';

class OnlineSubtitleResult {
  final String url;
  final String label;
  final String languageCode;
  final String format;
  /// Frame rate the subtitle was timed for, when the source reports it.
  final double? fps;
  final String? releaseName;

  const OnlineSubtitleResult({
    required this.url,
    required this.label,
    required this.languageCode,
    this.format = 'srt',
    this.fps,
    this.releaseName,
  });
}

/// Scores how well a subtitle release name matches the video release name.
/// Higher is better; 0 means nothing in common or no hint.
double releaseSimilarity(String? videoRelease, String? subtitleRelease) {
  if (videoRelease == null || subtitleRelease == null) return 0;
  final a = _releaseTokens(videoRelease);
  final b = _releaseTokens(subtitleRelease);
  if (a.isEmpty || b.isEmpty) return 0;
  double score = 0;
  final sa = _sourceClass(a);
  final sb = _sourceClass(b);
  if (sa != null && sa == sb) score += 6;
  if (sa != null && sb != null && sa != sb) score -= 4;
  const distinctive = {
    'amzn', 'nf', 'dsnp', 'hmax', 'atvp', 'hulu', 'pcok', 'max', 'repack',
    'proper', 'extended', 'unrated', 'directors', 'imax', 'remastered',
  };
  for (final t in a.intersection(b)) {
    if (distinctive.contains(t)) score += 3;
  }
  final ga = _releaseGroup(videoRelease);
  final gb = _releaseGroup(subtitleRelease);
  if (ga != null && ga == gb) score += 8;
  return score;
}

Set<String> _releaseTokens(String value) => value
    .toLowerCase()
    .replaceAll('web-dl', 'webdl')
    .replaceAll('blu-ray', 'bluray')
    .split(RegExp(r'[^a-z0-9]+'))
    .where((t) => t.isNotEmpty)
    .toSet();

String? _sourceClass(Set<String> tokens) {
  if (tokens.any((t) => t == 'bluray' || t == 'brrip' || t == 'bdrip' || t == 'remux')) {
    return 'bluray';
  }
  if (tokens.any((t) => t == 'web' || t == 'webdl' || t == 'webrip')) return 'web';
  if (tokens.any((t) => t == 'hdtv' || t == 'pdtv')) return 'hdtv';
  if (tokens.any((t) => t == 'dvdrip' || t == 'dvd')) return 'dvd';
  return null;
}

String? _releaseGroup(String value) {
  final cleaned = value.replaceAll(RegExp(r'\.(srt|vtt|mkv|mp4|ass)$', caseSensitive: false), '');
  final m = RegExp(r'-([A-Za-z0-9]{2,})(?:\[[^\]]*\])?$').firstMatch(cleaned.trim());
  return m?.group(1)?.toLowerCase();
}

class OnlineSubtitleRepository {
  final Dio _dio;
  final String _tmdbAccessToken;
  final String _wyzieApiKey;

  OnlineSubtitleRepository(
    this._dio, {
    required String tmdbAccessToken,
    required String wyzieApiKey,
  }) : _tmdbAccessToken = tmdbAccessToken,
       _wyzieApiKey = wyzieApiKey;

  static const Map<String, String> _openSubtitlesLanguageCodes = {
    'tr': 'tur',
    'en': 'eng',
    'es': 'spa',
    'de': 'ger',
    'fr': 'fre',
    'it': 'ita',
    'pt': 'por',
    'ru': 'rus',
    'ar': 'ara',
  };

  final Map<String, String?> _imdbCache = {};
  final Map<String, OnlineSubtitleResult?> _subtitleCache = {};

  Future<String?> resolveImdbId({
    required String mediaId,
    required String mediaType,
    String? streamUrl,
  }) async {
    final embedded = _extractImdbId(streamUrl) ?? _extractImdbId(mediaId);
    if (embedded != null) {
      return embedded;
    }

    final tmdbId = mediaId.trim();
    if (tmdbId.isEmpty || _tmdbAccessToken.trim().isEmpty) {
      return null;
    }

    final cacheKey = '$mediaType:$tmdbId';
    if (_imdbCache.containsKey(cacheKey)) {
      return _imdbCache[cacheKey];
    }

    try {
      final tmdbType = mediaType == 'tv' ? 'tv' : 'movie';
      final response = await _dio.get(
        'https://api.themoviedb.org/3/$tmdbType/$tmdbId/external_ids',
        options: Options(
          headers: {
            'Authorization': 'Bearer ${_tmdbAccessToken.trim()}',
            'Accept': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
      final data = response.data;
      final imdbId = data is Map ? data['imdb_id']?.toString().trim() : null;
      final normalized = _extractImdbId(imdbId);
      _imdbCache[cacheKey] = normalized;
      return normalized;
    } catch (_) {
      _imdbCache[cacheKey] = null;
      return null;
    }
  }

  Future<OnlineSubtitleResult?> findBestSubtitle({
    required String imdbId,
    required String mediaType,
    required int season,
    required int episode,
    required String languageCode,
    String? releaseHint,
  }) async {
    final normalizedImdb = _extractImdbId(imdbId);
    final openSubtitlesImdbId = normalizedImdb?.replaceFirst(
      RegExp(r'^tt', caseSensitive: false),
      '',
    );
    if (normalizedImdb == null ||
        openSubtitlesImdbId == null ||
        openSubtitlesImdbId.isEmpty) {
      return null;
    }

    final normalizedLanguage = _normalizeLanguageCode(languageCode);
    final languageOrder = normalizedLanguage == 'en'
        ? <String>[normalizedLanguage]
        : <String>[normalizedLanguage, 'en'];

    for (final language in languageOrder) {
      if (_wyzieApiKey.trim().isNotEmpty) {
        final wyzieResult = await _findBestWyzieSubtitleForLanguage(
          imdbId: normalizedImdb,
          mediaType: mediaType,
          season: season,
          episode: episode,
          languageCode: language,
          releaseHint: releaseHint,
        );
        if (wyzieResult != null) {
          return wyzieResult;
        }
      }

      final result = await _findBestOpenSubtitlesSubtitleForLanguage(
        imdbId: openSubtitlesImdbId,
        mediaType: mediaType,
        season: season,
        episode: episode,
        languageCode: language,
        releaseHint: releaseHint,
      );
      if (result != null) {
        return result;
      }
    }

    return null;
  }

  Future<OnlineSubtitleResult?> _findBestWyzieSubtitleForLanguage({
    required String imdbId,
    required String mediaType,
    required int season,
    required int episode,
    required String languageCode,
    String? releaseHint,
  }) async {
    final cacheKey =
        'wyzie:$mediaType:$imdbId:$season:$episode:$languageCode:${_wyzieApiKey.trim().hashCode}:${releaseHint.hashCode}';
    if (_subtitleCache.containsKey(cacheKey)) {
      return _subtitleCache[cacheKey];
    }

    try {
      final params = <String, dynamic>{
        'id': imdbId,
        'language': languageCode,
        'format': 'srt,vtt',
        'source': 'all',
        'key': _wyzieApiKey.trim(),
      };
      if (mediaType == 'tv') {
        params['season'] = season;
        params['episode'] = episode;
      }

      final response = await _dio.get(
        'https://sub.wyzie.io/search',
        queryParameters: params,
        options: Options(
          headers: {'Accept': 'application/json'},
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 8),
        ),
      );

      final data = response.data;
      if (data is! List) {
        _subtitleCache[cacheKey] = null;
        return null;
      }

      final candidates =
          data
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .where(_isUsableWyzieSubtitle)
              .toList()
            ..sort(
              (a, b) => _scoreWyzieSubtitle(b, releaseHint)
                  .compareTo(_scoreWyzieSubtitle(a, releaseHint)),
            );

      if (candidates.isEmpty) {
        _subtitleCache[cacheKey] = null;
        return null;
      }

      final best = candidates.first;
      final rawUrl = best['url']?.toString().trim() ?? '';
      final subtitleUrl = _forceWyzieSubtitleFormat(rawUrl, 'srt');
      final display = best['display']?.toString().trim();
      final release = best['release']?.toString().trim();
      final source = best['source']?.toString().trim();
      final result = OnlineSubtitleResult(
        url: subtitleUrl,
        label: [
          if (display != null && display.isNotEmpty) display,
          if (source != null && source.isNotEmpty) source,
          if (release != null && release.isNotEmpty) release,
        ].join(' - '),
        languageCode: languageCode,
        format: 'srt',
        releaseName: release,
      );
      _subtitleCache[cacheKey] = result;
      return result;
    } catch (_) {
      _subtitleCache[cacheKey] = null;
      return null;
    }
  }

  Future<OnlineSubtitleResult?> _findBestOpenSubtitlesSubtitleForLanguage({
    required String imdbId,
    required String mediaType,
    required int season,
    required int episode,
    required String languageCode,
    String? releaseHint,
  }) async {
    final osLanguage =
        _openSubtitlesLanguageCodes[languageCode] ?? languageCode;
    final cacheKey =
        '$mediaType:$imdbId:$season:$episode:$osLanguage:${releaseHint.hashCode}';
    if (_subtitleCache.containsKey(cacheKey)) {
      return _subtitleCache[cacheKey];
    }

    try {
      final path = mediaType == 'tv'
          ? '/search/episode-$episode/imdbid-$imdbId/season-$season/sublanguageid-$osLanguage'
          : '/search/imdbid-$imdbId/sublanguageid-$osLanguage';

      final response = await _dio.get(
        'https://rest.opensubtitles.org$path',
        options: Options(
          headers: {
            'X-User-Agent': 'trailers.to-UA',
            'Accept': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 8),
        ),
      );

      final data = response.data;
      if (data is! List) {
        _subtitleCache[cacheKey] = null;
        return null;
      }

      final candidates =
          data
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .where(_isUsableSubtitle)
              .toList()
            ..sort(
              (a, b) => _scoreSubtitle(b, releaseHint)
                  .compareTo(_scoreSubtitle(a, releaseHint)),
            );

      if (candidates.isEmpty) {
        _subtitleCache[cacheKey] = null;
        return null;
      }

      final best = candidates.first;
      final downloadUrl = best['SubDownloadLink']?.toString().trim() ?? '';
      final subtitleUrl = _buildWyzieSubtitleUrl(downloadUrl) ?? downloadUrl;
      if (subtitleUrl.isEmpty) {
        _subtitleCache[cacheKey] = null;
        return null;
      }

      final fileName = best['SubFileName']?.toString().trim();
      final languageName = best['LanguageName']?.toString().trim();
      final result = OnlineSubtitleResult(
        url: subtitleUrl,
        label: [
          if (languageName != null && languageName.isNotEmpty) languageName,
          if (fileName != null && fileName.isNotEmpty) fileName,
        ].join(' - '),
        languageCode: languageCode,
        format: 'srt',
        fps: _parseFps(best['MovieFPS']),
        releaseName: best['MovieReleaseName']?.toString().trim().isNotEmpty == true
            ? best['MovieReleaseName'].toString().trim()
            : fileName,
      );
      _subtitleCache[cacheKey] = result;
      return result;
    } catch (_) {
      _subtitleCache[cacheKey] = null;
      return null;
    }
  }

  bool _isUsableSubtitle(Map<String, dynamic> item) {
    final downloadUrl = item['SubDownloadLink']?.toString().trim() ?? '';
    if (downloadUrl.isEmpty) return false;
    if (item['SubBad']?.toString() == '1') return false;
    final format = item['SubFormat']?.toString().toLowerCase().trim() ?? '';
    if (format.isNotEmpty && format != 'srt' && format != 'vtt') return false;
    return true;
  }

  bool _isUsableWyzieSubtitle(Map<String, dynamic> item) {
    final url = item['url']?.toString().trim() ?? '';
    if (url.isEmpty) return false;
    final format = item['format']?.toString().toLowerCase().trim() ?? '';
    if (format.isNotEmpty && format != 'srt' && format != 'vtt') return false;
    return true;
  }

  double? _parseFps(Object? value) {
    final fps = _toDouble(value);
    return fps > 1 ? fps : null;
  }

  double _scoreSubtitle(Map<String, dynamic> item, [String? releaseHint]) {
    double score = 0;
    score += releaseSimilarity(
          releaseHint,
          '${item['MovieReleaseName'] ?? ''} ${item['SubFileName'] ?? ''}',
        ) *
        3;
    score += _toDouble(item['Score']);
    score += _toDouble(item['SubDownloadsCnt']) / 1000;
    score += _toDouble(item['SubRating']) * 2;
    if (item['SubFromTrusted']?.toString() == '1') score += 8;
    if (item['SubHD']?.toString() == '1') score += 2;
    if (item['SubHearingImpaired']?.toString() == '1') score -= 3;
    if (item['SubForeignPartsOnly']?.toString() == '1') score -= 80;
    if (item['SubSumCD']?.toString() != '1') score -= 20;
    return score;
  }

  double _scoreWyzieSubtitle(Map<String, dynamic> item, [String? releaseHint]) {
    double score = 0;
    score += releaseSimilarity(releaseHint, item['release']?.toString()) * 3;
    score += _toDouble(item['downloadCount']) / 1000;
    if (item['isHearingImpaired'] == true) score -= 3;
    if (item['ai'] == true) score -= 1;
    final release = item['release']?.toString().toLowerCase() ?? '';
    if (release.contains('web')) score += 2;
    if (release.contains('bluray') || release.contains('blu-ray')) score += 2;
    if (release.contains('proper')) score += 1;
    return score;
  }

  double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _normalizeLanguageCode(String value) {
    final raw = value.trim().toLowerCase();
    if (raw.isEmpty) return 'tr';
    if (raw.length == 2) return raw;
    for (final entry in _openSubtitlesLanguageCodes.entries) {
      if (entry.value == raw) return entry.key;
    }
    return raw;
  }

  String? _extractImdbId(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final match = RegExp(r'tt\d{5,}', caseSensitive: false).firstMatch(value);
    return match?.group(0)?.toLowerCase();
  }

  String? _buildWyzieSubtitleUrl(String downloadUrl) {
    if (_wyzieApiKey.trim().isEmpty) return null;
    final match = RegExp(
      r'/vrf-([a-f0-9]+)/filead/(\d+)',
      caseSensitive: false,
    ).firstMatch(downloadUrl);
    if (match == null) return null;
    return Uri.https(
      'sub.wyzie.io',
      '/c/${match.group(1)}/id/${match.group(2)}',
      {
        'format': 'srt',
        'encoding': 'UTF-8',
        'key': _wyzieApiKey.trim(),
      },
    ).toString();
  }

  String _forceWyzieSubtitleFormat(String url, String format) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.host.toLowerCase().contains('wyzie.io')) {
      return url;
    }
    final params = Map<String, String>.from(uri.queryParameters);
    params['format'] = format;
    params['encoding'] = params['encoding'] ?? 'UTF-8';
    if (_wyzieApiKey.trim().isNotEmpty) {
      params['key'] = _wyzieApiKey.trim();
    }
    return uri.replace(queryParameters: params).toString();
  }
}
