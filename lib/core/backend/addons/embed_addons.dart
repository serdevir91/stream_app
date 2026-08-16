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

class VidBoxAddon extends BaseAddon {
  @override
  final AddonManifest manifest = AddonManifest(
    id: 'builtin.vidbox',
    name: 'VidBox',
    description:
        'VidBox multi-mirror streaming provider with 19+ mirror servers (Vidx, Cargo, Cabin, Gale, Boxr, Tile, Pixel, Hatch, Veil, Crate, Cube, Aero, etc.).',
    version: '1.0.0',
    types: ['movie', 'series'],
    icon: '📦',
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
    final cid = contentId.trim();

    if (isMovie) {
      return [
        StreamResult(
          url:
              'https://cinesrc.st/embed/movie/$cid?color=%23e50914&autoskip=true&quality=1080',
          title: 'VidBox (Vidx 1080p)',
          quality: '1080p',
          provider: 'VidBox - Vidx',
          isDirectLink: false,
        ),
        StreamResult(
          url:
              'https://vidup.to/movie/$cid?autoPlay=true&theme=e50914&sub=en&chromecast=false',
          title: 'VidBox (Cargo 1080p)',
          quality: '1080p',
          provider: 'VidBox - Cargo',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://vidnest.fun/movie/$cid',
          title: 'VidBox (Cabin HD)',
          quality: 'HD',
          provider: 'VidBox - Cabin',
          isDirectLink: false,
        ),
        StreamResult(
          url:
              'https://peachify.top/embed/movie/$cid?autoPlay=true&sub=English&cast=hide&pip=hide&accent=e50914',
          title: 'VidBox (Boxr 1080p)',
          quality: '1080p',
          provider: 'VidBox - Boxr',
          isDirectLink: false,
        ),
        StreamResult(
          url:
              'https://primesrc.me/embed/movie?tmdb=$cid&fallback=true&serverOrder=PrimeVid',
          title: 'VidBox (Tile 1080p)',
          quality: '1080p',
          provider: 'VidBox - Tile',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://player.videasy.net/movie/$cid?color=e50914&overlay=true',
          title: 'VidBox (Cube HD)',
          quality: 'HD',
          provider: 'VidBox - Cube',
          isDirectLink: false,
        ),
        StreamResult(
          url:
              'https://www.vidking.net/embed/movie/$cid?autoPlay=true&color=e50914',
          title: 'VidBox (Hatch 1080p)',
          quality: '1080p',
          provider: 'VidBox - Hatch',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://www.zxcstream.xyz/player/movie/$cid',
          title: 'VidBox (Gale HD)',
          quality: 'HD',
          provider: 'VidBox - Gale',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://cinemaos.tech/player/$cid',
          title: 'VidBox (Glow HD)',
          quality: 'HD',
          provider: 'VidBox - Glow',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://play.xpass.top/e/movie/$cid',
          title: 'VidBox (Veil HD)',
          quality: 'HD',
          provider: 'VidBox - Veil',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://airflix1.com/embed/movie/$cid',
          title: 'VidBox (Pixel HD)',
          quality: 'HD',
          provider: 'VidBox - Pixel',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://vidfast.pro/movie/$cid',
          title: 'VidBox (Halo HD)',
          quality: 'HD',
          provider: 'VidBox - Halo',
          isDirectLink: false,
        ),
        StreamResult(
          url:
              'https://vidcore.net/movie/$cid?autoPlay=true&theme=e50914&sub=en&chromecast=false',
          title: 'VidBox (Crate 1080p)',
          quality: '1080p',
          provider: 'VidBox - Crate',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://vidrock.ru/movie/$cid',
          title: 'VidBox (Aero HD)',
          quality: 'HD',
          provider: 'VidBox - Aero',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://moviesapi.to/movie/$cid',
          title: 'VidBox (Comet HD)',
          quality: 'HD',
          provider: 'VidBox - Comet',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://vsembed.ru/embed/movie/$cid',
          title: 'VidBox (Pulse HD)',
          quality: 'HD',
          provider: 'VidBox - Pulse',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://vaplayer.ru/embed/movie/$cid',
          title: 'VidBox (Tide HD)',
          quality: 'HD',
          provider: 'VidBox - Tide',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://vidzen.fun/movie/$cid',
          title: 'VidBox (Umbra HD)',
          quality: 'HD',
          provider: 'VidBox - Umbra',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://vidsync.xyz/embed/movie/$cid?autoPlay=true&theme=e50914',
          title: 'VidBox (Stash HD)',
          quality: 'HD',
          provider: 'VidBox - Stash',
          isDirectLink: false,
        ),
      ];
    } else {
      return [
        StreamResult(
          url:
              'https://cinesrc.st/embed/tv/$cid?s=$season&e=$episode&color=%23e50914&autonext=true&autoskip=true&quality=1080',
          title: 'VidBox (Vidx 1080p)',
          quality: '1080p',
          provider: 'VidBox - Vidx',
          isDirectLink: false,
        ),
        StreamResult(
          url:
              'https://vidup.to/tv/$cid/$season/$episode?autoPlay=true&autoNext=true&nextButton=true&theme=e50914&sub=en&chromecast=false',
          title: 'VidBox (Cargo 1080p)',
          quality: '1080p',
          provider: 'VidBox - Cargo',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://vidnest.fun/tv/$cid/$season/$episode',
          title: 'VidBox (Cabin HD)',
          quality: 'HD',
          provider: 'VidBox - Cabin',
          isDirectLink: false,
        ),
        StreamResult(
          url:
              'https://peachify.top/embed/tv/$cid/$season/$episode?autoPlay=true&autoNext=30&showNextBtn=true&sub=English&cast=hide&pip=hide&accent=e50914',
          title: 'VidBox (Boxr 1080p)',
          quality: '1080p',
          provider: 'VidBox - Boxr',
          isDirectLink: false,
        ),
        StreamResult(
          url:
              'https://primesrc.me/embed/tv?tmdb=$cid&season=$season&episode=$episode&fallback=true&serverOrder=PrimeVid',
          title: 'VidBox (Tile 1080p)',
          quality: '1080p',
          provider: 'VidBox - Tile',
          isDirectLink: false,
        ),
        StreamResult(
          url:
              'https://player.videasy.net/tv/$cid/$season/$episode?color=e50914&overlay=true&nextEpisode=true&autoplayNextEpisode=true&episodeSelector=true',
          title: 'VidBox (Cube HD)',
          quality: 'HD',
          provider: 'VidBox - Cube',
          isDirectLink: false,
        ),
        StreamResult(
          url:
              'https://www.vidking.net/embed/tv/$cid/$season/$episode?autoPlay=true&color=e50914&nextEpisode=true&episodeSelector=true',
          title: 'VidBox (Hatch 1080p)',
          quality: '1080p',
          provider: 'VidBox - Hatch',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://www.zxcstream.xyz/player/tv/$cid/$season/$episode',
          title: 'VidBox (Gale / Maze HD)',
          quality: 'HD',
          provider: 'VidBox - Gale',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://cinemaos.tech/player/$cid/$season/$episode',
          title: 'VidBox (Glow / Theta HD)',
          quality: 'HD',
          provider: 'VidBox - Glow',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://play.xpass.top/e/tv/$cid/$season/$episode',
          title: 'VidBox (Veil / Ember HD)',
          quality: 'HD',
          provider: 'VidBox - Veil',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://airflix1.com/embed/tv/$cid/$season/$episode',
          title: 'VidBox (Pixel HD)',
          quality: 'HD',
          provider: 'VidBox - Pixel',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://vidfast.pro/tv/$cid/$season/$episode',
          title: 'VidBox (Halo / Cobra HD)',
          quality: 'HD',
          provider: 'VidBox - Halo',
          isDirectLink: false,
        ),
        StreamResult(
          url:
              'https://vidcore.net/tv/$cid/$season/$episode?autoPlay=true&theme=e50914&sub=en&chromecast=false',
          title: 'VidBox (Crate 1080p)',
          quality: '1080p',
          provider: 'VidBox - Crate',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://vidrock.ru/tv/$cid/$season/$episode',
          title: 'VidBox (Aero HD)',
          quality: 'HD',
          provider: 'VidBox - Aero',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://moviesapi.to/tv/$cid/$season/$episode',
          title: 'VidBox (Comet / Raze HD)',
          quality: 'HD',
          provider: 'VidBox - Comet',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://vsembed.ru/embed/tv/$cid/$season/$episode',
          title: 'VidBox (Pulse / Drift HD)',
          quality: 'HD',
          provider: 'VidBox - Pulse',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://vaplayer.ru/embed/tv/$cid/$season/$episode',
          title: 'VidBox (Tide / Flux HD)',
          quality: 'HD',
          provider: 'VidBox - Tide',
          isDirectLink: false,
        ),
        StreamResult(
          url: 'https://vidzen.fun/tv/$cid/$season/$episode',
          title: 'VidBox (Umbra / Opal HD)',
          quality: 'HD',
          provider: 'VidBox - Umbra',
          isDirectLink: false,
        ),
        StreamResult(
          url:
              'https://vidsync.xyz/embed/tv/$cid/$season/$episode?autoPlay=true&autoNext=true&nextButton=true&theme=e50914',
          title: 'VidBox (Stash HD)',
          quality: 'HD',
          provider: 'VidBox - Stash',
          isDirectLink: false,
        ),
      ];
    }
  }
}

