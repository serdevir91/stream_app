/// Models for the internal backend
class LocalStreamResult {
  final String url;
  final String title;
  final String quality;
  final String provider;
  final bool isDirectLink;

  LocalStreamResult({
    required this.url,
    required this.title,
    required this.quality,
    required this.provider,
    required this.isDirectLink,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'quality': quality,
        'provider': provider,
        'is_direct_link': isDirectLink,
      };
}

/// A Dart implementation of the backend logic to allow standalone Android usage.
///
/// Ports the following Python embed addons to Dart:
/// - VidSrc (vidsrc.py) — vidsrc-embed.ru
/// - TwoEmbed (twoembed.py) — 2embed.cc
/// - SuperEmbed (superembed.py) — multiembed.mov
/// - VidLink (vidlink.py) — vidlink.pro
/// - EmbedSU (embedsu.py) — embed.su
class InternalBackendService {
  static final InternalBackendService _instance =
      InternalBackendService._internal();
  factory InternalBackendService() => _instance;
  InternalBackendService._internal();

  /// All supported embed addon IDs.
  static const List<String> _supportedAddonIds = [
    'builtin.vidsrc',
    'builtin.twoembed',
    'builtin.superembed',
    'builtin.vidlink',
    'builtin.embedsu',
  ];

  /// Mimics GET /api/addons — returns all internal embed addons.
  Future<Map<String, dynamic>> getAddons() async {
    return {
      'addons': [
        {
          'id': 'builtin.vidsrc',
          'name': 'VidSrc',
          'description': 'VidSrc embed player provider.',
          'version': '1.0.0',
          'types': ['movie', 'series'],
          'is_builtin': true,
          'enabled': true,
        },
        {
          'id': 'builtin.twoembed',
          'name': '2Embed',
          'description': '2Embed multi-server embed provider.',
          'version': '1.0.0',
          'types': ['movie', 'series'],
          'is_builtin': true,
          'enabled': true,
        },
        {
          'id': 'builtin.superembed',
          'name': 'SuperEmbed',
          'description': 'SuperEmbed multi-server embed provider.',
          'version': '1.0.0',
          'types': ['movie', 'series'],
          'is_builtin': true,
          'enabled': true,
        },
        {
          'id': 'builtin.vidlink',
          'name': 'VidLink',
          'description': 'VidLink embed player provider.',
          'version': '1.0.0',
          'types': ['movie', 'series'],
          'is_builtin': true,
          'enabled': true,
        },
        {
          'id': 'builtin.embedsu',
          'name': 'EmbedSU',
          'description': 'EmbedSU embed player provider.',
          'version': '1.0.0',
          'types': ['movie', 'series'],
          'is_builtin': true,
          'enabled': true,
        },
      ],
    };
  }

  /// Mimics GET /api/resolve — resolves streams for a given addon.
  ///
  /// [addonId] specifies which addon to use. Defaults to VidSrc for backward
  /// compatibility. If [addonId] is 'auto' or empty, all addons are queried.
  Future<Map<String, dynamic>> resolve({
    required String query,
    required String tmdbId,
    required String type,
    int season = 1,
    int episode = 1,
    String addonId = '',
  }) async {
    final streams = <LocalStreamResult>[];

    // Determine which addons to query
    final List<String> targets;
    if (addonId.isEmpty ||
        addonId == 'auto' ||
        !_supportedAddonIds.contains(addonId)) {
      targets = _supportedAddonIds;
    } else {
      targets = [addonId];
    }

    for (final id in targets) {
      final result = _resolveAddon(
        addonId: id,
        tmdbId: tmdbId,
        type: type,
        season: season,
        episode: episode,
      );
      if (result != null) {
        streams.add(result);
      }
    }

    return {
      'success': streams.isNotEmpty,
      'streams': streams.map((s) => s.toJson()).toList(),
    };
  }

  /// Resolves a single addon's stream URL.
  LocalStreamResult? _resolveAddon({
    required String addonId,
    required String tmdbId,
    required String type,
    required int season,
    required int episode,
  }) {
    final isImdb = tmdbId.startsWith('tt');
    final isMovie = type == 'movie';

    switch (addonId) {
      case 'builtin.vidsrc':
        return _resolveVidSrc(tmdbId, isImdb, isMovie, season, episode);
      case 'builtin.twoembed':
        return _resolveTwoEmbed(tmdbId, isImdb, isMovie, season, episode);
      case 'builtin.superembed':
        return _resolveSuperEmbed(tmdbId, isImdb, isMovie, season, episode);
      case 'builtin.vidlink':
        return _resolveVidLink(tmdbId, isImdb, isMovie, season, episode);
      case 'builtin.embedsu':
        return _resolveEmbedSU(tmdbId, isImdb, isMovie, season, episode);
      default:
        return null;
    }
  }

  /// VidSrc — vidsrc-embed.ru
  /// Ported from backend/addons/vidsrc.py
  LocalStreamResult _resolveVidSrc(
    String tmdbId,
    bool isImdb,
    bool isMovie,
    int season,
    int episode,
  ) {
    final idParam = isImdb ? 'imdb=$tmdbId' : 'tmdb=$tmdbId';
    String url;
    if (isMovie) {
      url = 'https://vidsrc-embed.ru/embed/movie?$idParam&ds_lang=tr';
    } else {
      url =
          'https://vidsrc-embed.ru/embed/tv?$idParam&season=$season&episode=$episode&ds_lang=tr&autonext=1';
    }
    return LocalStreamResult(
      url: url,
      title: 'VidSrc',
      quality: 'HD',
      provider: 'VidSrc',
      isDirectLink: false,
    );
  }

  /// 2Embed — 2embed.cc
  /// Ported from backend/addons/twoembed.py
  LocalStreamResult _resolveTwoEmbed(
    String tmdbId,
    bool isImdb,
    bool isMovie,
    int season,
    int episode,
  ) {
    String url;
    if (isMovie) {
      url = 'https://www.2embed.cc/embed/$tmdbId';
    } else {
      url =
          'https://www.2embed.cc/embed/tv?id=$tmdbId&s=$season&e=$episode';
    }
    return LocalStreamResult(
      url: url,
      title: '2Embed',
      quality: 'HD',
      provider: '2Embed',
      isDirectLink: false,
    );
  }

  /// SuperEmbed — multiembed.mov
  /// Ported from backend/addons/superembed.py
  LocalStreamResult _resolveSuperEmbed(
    String tmdbId,
    bool isImdb,
    bool isMovie,
    int season,
    int episode,
  ) {
    final idParam = isImdb ? 'imdb=1' : 'tmdb=1';
    String url;
    if (isMovie) {
      url = 'https://multiembed.mov/?video_id=$tmdbId&$idParam';
    } else {
      url =
          'https://multiembed.mov/?video_id=$tmdbId&$idParam&s=$season&e=$episode';
    }
    return LocalStreamResult(
      url: url,
      title: 'SuperEmbed',
      quality: 'HD',
      provider: 'SuperEmbed',
      isDirectLink: false,
    );
  }

  /// VidLink — vidlink.pro
  /// Ported from backend/addons/vidlink.py
  LocalStreamResult _resolveVidLink(
    String tmdbId,
    bool isImdb,
    bool isMovie,
    int season,
    int episode,
  ) {
    String url;
    if (isMovie) {
      url = 'https://vidlink.pro/movie/$tmdbId';
    } else {
      url = 'https://vidlink.pro/tv/$tmdbId/$season/$episode';
    }
    return LocalStreamResult(
      url: url,
      title: 'VidLink',
      quality: 'HD',
      provider: 'VidLink',
      isDirectLink: false,
    );
  }

  /// EmbedSU — embed.su
  /// Ported from backend/addons/embedsu.py
  LocalStreamResult _resolveEmbedSU(
    String tmdbId,
    bool isImdb,
    bool isMovie,
    int season,
    int episode,
  ) {
    String url;
    if (isMovie) {
      url = 'https://embed.su/embed/movie/$tmdbId';
    } else {
      url = 'https://embed.su/embed/tv/$tmdbId/$season/$episode';
    }
    return LocalStreamResult(
      url: url,
      title: 'EmbedSU',
      quality: 'HD',
      provider: 'EmbedSU',
      isDirectLink: false,
    );
  }

  /// Mimics GET /api/search — not supported by embed addons.
  Future<Map<String, dynamic>> search(String query, String type) async {
    return {'results': []};
  }
}
