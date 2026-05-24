class AppSettings {
  static const int schemaVersion = 8;

  final String appLanguage;
  final String subtitleLanguage;
  final String tmdbAccessToken;
  final String wyzieApiKey;
  final String backendUrl;
  final bool autoSelectSource;
  final String preferredSourceId;
  final String videoPlayer; // 'native' or 'media_kit'
  final bool autoSelectSubtitle;
  final String librarySort;
  final bool watchHistoryEnabled;
  final bool newEpisodeNotificationsEnabled;
  final int completionPercentage;

  const AppSettings({
    required this.appLanguage,
    required this.subtitleLanguage,
    required this.tmdbAccessToken,
    required this.wyzieApiKey,
    required this.backendUrl,
    required this.autoSelectSource,
    required this.preferredSourceId,
    required this.videoPlayer,
    required this.autoSelectSubtitle,
    required this.librarySort,
    required this.watchHistoryEnabled,
    required this.newEpisodeNotificationsEnabled,
    required this.completionPercentage,
  });

  static const AppSettings defaults = AppSettings(
    appLanguage: 'en',
    subtitleLanguage: 'en',
    tmdbAccessToken: '',
    wyzieApiKey: '',
    backendUrl: 'http://127.0.0.1:8000',
    autoSelectSource: true,
    preferredSourceId: '',
    videoPlayer: 'native',
    autoSelectSubtitle: true,
    librarySort: 'recent',
    watchHistoryEnabled: true,
    newEpisodeNotificationsEnabled: true,
    completionPercentage: 90,
  );

  AppSettings copyWith({
    String? appLanguage,
    String? subtitleLanguage,
    String? tmdbAccessToken,
    String? wyzieApiKey,
    String? backendUrl,
    bool? autoSelectSource,
    String? preferredSourceId,
    String? videoPlayer,
    bool? autoSelectSubtitle,
    String? librarySort,
    bool? watchHistoryEnabled,
    bool? newEpisodeNotificationsEnabled,
    int? completionPercentage,
  }) {
    return AppSettings(
      appLanguage: appLanguage ?? this.appLanguage,
      subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
      tmdbAccessToken: tmdbAccessToken ?? this.tmdbAccessToken,
      wyzieApiKey: wyzieApiKey ?? this.wyzieApiKey,
      backendUrl: backendUrl ?? this.backendUrl,
      autoSelectSource: autoSelectSource ?? this.autoSelectSource,
      preferredSourceId: preferredSourceId ?? this.preferredSourceId,
      videoPlayer: videoPlayer ?? this.videoPlayer,
      autoSelectSubtitle: autoSelectSubtitle ?? this.autoSelectSubtitle,
      librarySort: librarySort ?? this.librarySort,
      watchHistoryEnabled: watchHistoryEnabled ?? this.watchHistoryEnabled,
      newEpisodeNotificationsEnabled:
          newEpisodeNotificationsEnabled ?? this.newEpisodeNotificationsEnabled,
      completionPercentage: completionPercentage ?? this.completionPercentage,
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
      'videoPlayer': videoPlayer,
      'autoSelectSubtitle': autoSelectSubtitle,
      'librarySort': librarySort,
      'watchHistoryEnabled': watchHistoryEnabled,
      'newEpisodeNotificationsEnabled': newEpisodeNotificationsEnabled,
      'completionPercentage': completionPercentage,
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
      videoPlayer: (map['videoPlayer'] ?? 'native').toString(),
      autoSelectSubtitle: (map['autoSelectSubtitle'] ?? true) == true,
      librarySort: (map['librarySort'] ?? 'recent').toString(),
      watchHistoryEnabled: (map['watchHistoryEnabled'] ?? true) == true,
      newEpisodeNotificationsEnabled:
          (map['newEpisodeNotificationsEnabled'] ?? true) == true,
      completionPercentage: map['completionPercentage'] is int
          ? map['completionPercentage'] as int
          : 90,
    );
  }
}

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
