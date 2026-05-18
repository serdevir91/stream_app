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
      url = 'https://www.2embed.cc/embed/tv?id=$contentId&s=$season&e=$episode';
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

class DemoDirectAddon extends BaseAddon {
  @override
  final AddonManifest manifest = AddonManifest(
    id: 'builtin.demo_direct',
    name: 'Demo Direct (Test)',
    description: 'Native Player testleri icin dogrudan .mp4 dondurur.',
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
    // Her zaman calisan, acik kaynakli bir test videosu dondurur.
    return [
      StreamResult(
        url:
            'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
        title: 'Demo HD',
        quality: '1080p',
        provider: 'DemoDirect',
        isDirectLink: true,
      ),
    ];
  }
}

class VidEasyAddon extends BaseAddon {
  @override
  final AddonManifest manifest = AddonManifest(
    id: 'builtin.videasy',
    name: 'VidEasy',
    description: 'VidEasy embed player provider.',
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
    final url = isMovie
        ? 'https://player.videasy.net/movie/$contentId'
        : 'https://player.videasy.net/tv/$contentId/$season/$episode';
    return [
      StreamResult(
        url: url,
        title: 'VidEasy',
        quality: 'HD',
        provider: 'VidEasy',
        isDirectLink: false,
      ),
    ];
  }
}

class SmashyStreamAddon extends BaseAddon {
  @override
  final AddonManifest manifest = AddonManifest(
    id: 'builtin.smashystream',
    name: 'SmashyStream',
    description: 'SmashyStream embed player provider.',
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
    final url = isMovie
        ? 'https://embed.smashystream.com/playere.php?tmdb=$contentId'
        : 'https://embed.smashystream.com/playere.php?tmdb=$contentId&season=$season&episode=$episode';
    return [
      StreamResult(
        url: url,
        title: 'Smashy',
        quality: 'HD',
        provider: 'SmashyStream',
        isDirectLink: false,
      ),
    ];
  }
}

class PStreamAddon extends BaseAddon {
  @override
  final AddonManifest manifest = AddonManifest(
    id: 'builtin.pstream',
    name: 'P-Stream',
    description: 'P-Stream embed player provider.',
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
    final url = isMovie
        ? 'https://iframe.pstream.org/embed/tmdb-movie-$contentId'
        : 'https://iframe.pstream.org/embed/tmdb-tv-$contentId/$season/$episode';
    return [
      StreamResult(
        url: url,
        title: 'P-Stream',
        quality: 'HD',
        provider: 'P-Stream',
        isDirectLink: false,
      ),
    ];
  }
}

class VidSrcCcAddon extends BaseAddon {
  @override
  final AddonManifest manifest = AddonManifest(
    id: 'builtin.vidsrccc',
    name: 'VidSrc.cc',
    description: 'VidSrc.cc embed player provider.',
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
    final url = isMovie
        ? 'https://vidsrc.cc/v2/embed/movie/$contentId'
        : 'https://vidsrc.cc/v2/embed/tv/$contentId/$season/$episode';
    return [
      StreamResult(
        url: url,
        title: 'VidSrc.cc',
        quality: 'HD',
        provider: 'VidSrc.cc',
        isDirectLink: false,
      ),
    ];
  }
}

class StreamImdbAddon extends BaseAddon {
  @override
  final AddonManifest manifest = AddonManifest(
    id: 'builtin.streamimdb',
    name: 'StreamImdb',
    description: 'StreamImdb embed provider.',
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
    final url = isMovie
        ? 'https://vaplayer.ru/embed/movie/$contentId'
        : 'https://vaplayer.ru/embed/tv/$contentId/$season/$episode';
    return [
      StreamResult(
        url: url,
        title: 'StreamImdb',
        quality: 'HD',
        provider: 'StreamImdb',
        isDirectLink: false,
      ),
    ];
  }
}
