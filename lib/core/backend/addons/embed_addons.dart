import 'base_addon.dart';

class VidSrcAddon extends BaseAddon {
  @override
  final AddonManifest manifest = AddonManifest(
    id: 'builtin.vidsrc',
    name: 'VidSrc',
    description: 'VidSrc embed player provider.',
    version: '1.0.0',
    types: ['movie', 'series'],
    isBuiltin: true,
  );

  @override
  Future<List<SearchResult>> search(String query, String contentType) async =>
      [];

  @override
  Future<List<StreamResult>> getStreams(
    String contentId,
    String contentType,
    int season,
    int episode,
  ) async {
    final isImdb = contentId.startsWith('tt');
    final isMovie = contentType == 'movie';
    final idParam = isImdb ? 'imdb=$contentId' : 'tmdb=$contentId';

    String url;
    if (isMovie) {
      url = 'https://vidsrc-embed.ru/embed/movie?$idParam&ds_lang=tr';
    } else {
      url =
          'https://vidsrc-embed.ru/embed/tv?$idParam&season=$season&episode=$episode&ds_lang=tr&autonext=1';
    }

    return [
      StreamResult(
        url: url,
        title: 'VidSrc',
        quality: 'HD',
        provider: 'VidSrc',
        isDirectLink: false,
      ),
    ];
  }
}

class TwoEmbedAddon extends BaseAddon {
  @override
  final AddonManifest manifest = AddonManifest(
    id: 'builtin.twoembed',
    name: '2Embed',
    description: '2Embed multi-server embed provider.',
    version: '1.0.0',
    types: ['movie', 'series'],
    isBuiltin: true,
  );

  @override
  Future<List<SearchResult>> search(String query, String contentType) async =>
      [];

  @override
  Future<List<StreamResult>> getStreams(
    String contentId,
    String contentType,
    int season,
    int episode,
  ) async {
    final isMovie = contentType == 'movie';

    String url;
    if (isMovie) {
      url = 'https://www.2embed.cc/embed/$contentId';
    } else {
      url =
          'https://www.2embed.cc/embed/tv?id=$contentId&s=$season&e=$episode';
    }

    return [
      StreamResult(
        url: url,
        title: '2Embed',
        quality: 'HD',
        provider: '2Embed',
        isDirectLink: false,
      ),
    ];
  }
}

class SuperEmbedAddon extends BaseAddon {
  @override
  final AddonManifest manifest = AddonManifest(
    id: 'builtin.superembed',
    name: 'SuperEmbed',
    description: 'SuperEmbed multi-server embed provider.',
    version: '1.0.0',
    types: ['movie', 'series'],
    isBuiltin: true,
  );

  @override
  Future<List<SearchResult>> search(String query, String contentType) async =>
      [];

  @override
  Future<List<StreamResult>> getStreams(
    String contentId,
    String contentType,
    int season,
    int episode,
  ) async {
    final isImdb = contentId.startsWith('tt');
    final isMovie = contentType == 'movie';
    final idParam = isImdb ? 'imdb=1' : 'tmdb=1';

    String url;
    if (isMovie) {
      url = 'https://multiembed.mov/?video_id=$contentId&$idParam';
    } else {
      url =
          'https://multiembed.mov/?video_id=$contentId&$idParam&s=$season&e=$episode';
    }

    return [
      StreamResult(
        url: url,
        title: 'SuperEmbed',
        quality: 'HD',
        provider: 'SuperEmbed',
        isDirectLink: false,
      ),
    ];
  }
}

class VidLinkAddon extends BaseAddon {
  @override
  final AddonManifest manifest = AddonManifest(
    id: 'builtin.vidlink',
    name: 'VidLink',
    description: 'VidLink embed player provider.',
    version: '1.0.0',
    types: ['movie', 'series'],
    isBuiltin: true,
  );

  @override
  Future<List<SearchResult>> search(String query, String contentType) async =>
      [];

  @override
  Future<List<StreamResult>> getStreams(
    String contentId,
    String contentType,
    int season,
    int episode,
  ) async {
    final isMovie = contentType == 'movie';

    String url;
    if (isMovie) {
      url = 'https://vidlink.pro/movie/$contentId';
    } else {
      url = 'https://vidlink.pro/tv/$contentId/$season/$episode';
    }

    return [
      StreamResult(
        url: url,
        title: 'VidLink',
        quality: 'HD',
        provider: 'VidLink',
        isDirectLink: false,
      ),
    ];
  }
}

class EmbedSUAddon extends BaseAddon {
  @override
  final AddonManifest manifest = AddonManifest(
    id: 'builtin.embedsu',
    name: 'EmbedSU',
    description: 'EmbedSU embed player provider.',
    version: '1.0.0',
    types: ['movie', 'series'],
    isBuiltin: true,
  );

  @override
  Future<List<SearchResult>> search(String query, String contentType) async =>
      [];

  @override
  Future<List<StreamResult>> getStreams(
    String contentId,
    String contentType,
    int season,
    int episode,
  ) async {
    final isMovie = contentType == 'movie';

    String url;
    if (isMovie) {
      url = 'https://embed.su/embed/movie/$contentId';
    } else {
      url = 'https://embed.su/embed/tv/$contentId/$season/$episode';
    }

    return [
      StreamResult(
        url: url,
        title: 'EmbedSU',
        quality: 'HD',
        provider: 'EmbedSU',
        isDirectLink: false,
      ),
    ];
  }
}
