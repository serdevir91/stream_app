const List<String> defaultHomeCategories = [
  'recommended_for_you',
  'trending_movies',
  'trending_series',
  'studio_marvel',
  'studio_disney',
  'studio_dc',
  'studio_dreamworks',
  'studio_paramount',
  'studio_netflix',
  'studio_hbo',
  'studio_prime',
  'studio_pixar',
  'studio_warnerbros',
  'studio_universal',
  'animation_movies',
  'anime_series',
  'horror_movies',
  'drama_movies',
  'thriller_movies',
  'classic_movies',
  'western_movies',
  'movies_1950s',
  'movies_1960s',
  'movies_1970s',
  'movies_1980s',
];

class AppSettings {
  static const int schemaVersion = 11;

  final String appLanguage;
  final String subtitleLanguage;
  final String tmdbAccessToken;
  final String wyzieApiKey;
  final String backendUrl;
  final bool autoSelectSource;
  final String preferredSourceId;
  final String preferredMirror; // 'auto', 'vidx', 'cargo', 'cabin', 'glow', 'boxr', 'gale', 'tile', 'pixel', 'hatch', 'veil', 'crate', 'cube', 'aero', etc.
  final String videoPlayer; // 'native', 'media_kit', 'webview'
  final bool autoSelectSubtitle;
  final double defaultSubtitleOffset; // Subtitle delay in seconds (e.g. 0.0, 0.5, -1.0)
  final String themeMode; // 'dark', 'light', 'amoled'
  final String librarySort;
  final bool watchHistoryEnabled;
  final bool newEpisodeNotificationsEnabled;
  final int completionPercentage;
  final List<String> homeCategories;

  const AppSettings({
    required this.appLanguage,
    required this.subtitleLanguage,
    required this.tmdbAccessToken,
    required this.wyzieApiKey,
    required this.backendUrl,
    required this.autoSelectSource,
    required this.preferredSourceId,
    this.preferredMirror = 'auto',
    required this.videoPlayer,
    required this.autoSelectSubtitle,
    this.defaultSubtitleOffset = 0.0,
    this.themeMode = 'dark',
    required this.librarySort,
    required this.watchHistoryEnabled,
    required this.newEpisodeNotificationsEnabled,
    required this.completionPercentage,
    required this.homeCategories,
  });

  static const AppSettings defaults = AppSettings(
    appLanguage: 'en',
    subtitleLanguage: 'en',
    tmdbAccessToken: '',
    wyzieApiKey: '',
    backendUrl: 'http://127.0.0.1:8000',
    autoSelectSource: true,
    preferredSourceId: '',
    preferredMirror: 'auto',
    videoPlayer: 'native',
    autoSelectSubtitle: false,
    defaultSubtitleOffset: 0.0,
    themeMode: 'dark',
    librarySort: 'recent',
    watchHistoryEnabled: true,
    newEpisodeNotificationsEnabled: true,
    completionPercentage: 90,
    homeCategories: defaultHomeCategories,
  );

  AppSettings copyWith({
    String? appLanguage,
    String? subtitleLanguage,
    String? tmdbAccessToken,
    String? wyzieApiKey,
    String? backendUrl,
    bool? autoSelectSource,
    String? preferredSourceId,
    String? preferredMirror,
    String? videoPlayer,
    bool? autoSelectSubtitle,
    double? defaultSubtitleOffset,
    String? themeMode,
    String? librarySort,
    bool? watchHistoryEnabled,
    bool? newEpisodeNotificationsEnabled,
    int? completionPercentage,
    List<String>? homeCategories,
  }) {
    return AppSettings(
      appLanguage: appLanguage ?? this.appLanguage,
      subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
      tmdbAccessToken: tmdbAccessToken ?? this.tmdbAccessToken,
      wyzieApiKey: wyzieApiKey ?? this.wyzieApiKey,
      backendUrl: backendUrl ?? this.backendUrl,
      autoSelectSource: autoSelectSource ?? this.autoSelectSource,
      preferredSourceId: preferredSourceId ?? this.preferredSourceId,
      preferredMirror: preferredMirror ?? this.preferredMirror,
      videoPlayer: videoPlayer ?? this.videoPlayer,
      autoSelectSubtitle: autoSelectSubtitle ?? this.autoSelectSubtitle,
      defaultSubtitleOffset:
          defaultSubtitleOffset ?? this.defaultSubtitleOffset,
      themeMode: themeMode ?? this.themeMode,
      librarySort: librarySort ?? this.librarySort,
      watchHistoryEnabled: watchHistoryEnabled ?? this.watchHistoryEnabled,
      newEpisodeNotificationsEnabled:
          newEpisodeNotificationsEnabled ?? this.newEpisodeNotificationsEnabled,
      completionPercentage: completionPercentage ?? this.completionPercentage,
      homeCategories: homeCategories ?? this.homeCategories,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'schemaVersion': schemaVersion,
      'appLanguage': appLanguage,
      'subtitleLanguage': subtitleLanguage,
      'tmdbAccessToken': tmdbAccessToken,
      'wyzieApiKey': wyzieApiKey,
      'backendUrl': backendUrl,
      'autoSelectSource': autoSelectSource,
      'preferredSourceId': preferredSourceId,
      'preferredMirror': preferredMirror,
      'videoPlayer': videoPlayer,
      'autoSelectSubtitle': autoSelectSubtitle,
      'defaultSubtitleOffset': defaultSubtitleOffset,
      'themeMode': themeMode,
      'librarySort': librarySort,
      'watchHistoryEnabled': watchHistoryEnabled,
      'newEpisodeNotificationsEnabled': newEpisodeNotificationsEnabled,
      'completionPercentage': completionPercentage,
      'homeCategories': homeCategories,
    };
  }

  factory AppSettings.fromMap(Map<dynamic, dynamic> map) {
    return AppSettings(
      appLanguage: (map['appLanguage'] ?? 'en').toString(),
      subtitleLanguage: (map['subtitleLanguage'] ?? 'en').toString(),
      tmdbAccessToken: (map['tmdbAccessToken'] ?? '').toString(),
      wyzieApiKey: (map['wyzieApiKey'] ?? '').toString(),
      backendUrl: (map['backendUrl'] ?? 'http://127.0.0.1:8000').toString(),
      autoSelectSource: (map['autoSelectSource'] ?? true) == true,
      preferredSourceId: (map['preferredSourceId'] ?? '').toString(),
      preferredMirror: (map['preferredMirror'] ?? 'auto').toString(),
      videoPlayer: (map['videoPlayer'] ?? 'native').toString(),
      autoSelectSubtitle: (map['autoSelectSubtitle'] ?? false) == true,
      defaultSubtitleOffset: (map['defaultSubtitleOffset'] is num)
          ? (map['defaultSubtitleOffset'] as num).toDouble()
          : 0.0,
      themeMode: (map['themeMode'] ?? 'dark').toString(),
      librarySort: (map['librarySort'] ?? 'recent').toString(),
      watchHistoryEnabled: (map['watchHistoryEnabled'] ?? true) == true,
      newEpisodeNotificationsEnabled:
          (map['newEpisodeNotificationsEnabled'] ?? true) == true,
      completionPercentage: map['completionPercentage'] is int
          ? map['completionPercentage'] as int
          : 90,
      homeCategories: (map['homeCategories'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          defaultHomeCategories,
    );
  }
}

const Map<String, String> supportedVidBoxMirrors = {
  'auto': 'Otomatik (En Hızlı)',
  'vidx': 'Vidx (1080p CineSrc)',
  'cargo': 'Cargo (1080p VidUp)',
  'cabin': 'Cabin (HD VidNest)',
  'boxr': 'Boxr (1080p Peachify)',
  'tile': 'Tile (1080p PrimeSrc)',
  'cube': 'Cube (HD Videasy)',
  'gale': 'Gale / Maze (ZxcStream)',
  'glow': 'Glow / Theta (CinemaOS)',
  'hatch': 'Hatch (1080p VidKing)',
  'veil': 'Veil / Ember (Xpass)',
  'pixel': 'Pixel (AirFlix)',
  'halo': 'Halo / Photon (VidFast)',
  'crate': 'Crate (1080p VidCore)',
  'aero': 'Aero / Atlas (VidRock)',
  'comet': 'Comet / Kite (MoviesApi)',
  'pulse': 'Pulse / Drift (VSEmbed)',
  'tide': 'Tide / Flux (VAPlayer)',
  'umbra': 'Umbra / Opal (VidZen)',
};

const Map<String, String> supportedThemeModes = {
  'dark': 'Koyu Tema',
  'amoled': 'AMOLED Saf Siyah',
  'light': 'Açık Tema',
};

const Map<String, String> supportedVideoPlayers = {
  'native': 'Native Player (ExoPlayer)',
  'media_kit': 'Media Kit (MPV)',
  'webview': 'WebView (Embed)',
};

const Map<String, String> supportedAppLanguages = {
  'tr': 'Turkce',
  'en': 'English',
};

const Map<String, String> supportedSubtitleLanguages = {
  'tr': 'Turkce',
  'en': 'English',
  'es': 'Espanol',
  'de': 'Deutsch',
  'fr': 'Francais',
  'it': 'Italiano',
  'pt': 'Portugues',
  'ru': 'Russian',
  'ar': 'Arabic',
};

const Map<String, String> supportedLibrarySortOptions = {
  'recent': 'Recently Watched',
  'added': 'Recently Added',
  'title': 'Title',
  'rating': 'Rating',
  'type': 'Type',
};
