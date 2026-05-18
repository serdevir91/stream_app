class AppSettings {
  static const int schemaVersion = 4;

  final String appLanguage;
  final String subtitleLanguage;
  final String tmdbAccessToken;
  final String backendUrl;
  final bool autoSelectSource;
  final String preferredSourceId;
  final String videoPlayer; // 'native' or 'media_kit'

  const AppSettings({
    required this.appLanguage,
    required this.subtitleLanguage,
    required this.tmdbAccessToken,
    required this.backendUrl,
    required this.autoSelectSource,
    required this.preferredSourceId,
    required this.videoPlayer,
  });

  static const AppSettings defaults = AppSettings(
    appLanguage: 'en',
    subtitleLanguage: 'en',
    tmdbAccessToken: '',
    backendUrl: 'http://127.0.0.1:8000',
    autoSelectSource: true,
    preferredSourceId: '',
    videoPlayer: 'native',
  );

  AppSettings copyWith({
    String? appLanguage,
    String? subtitleLanguage,
    String? tmdbAccessToken,
    String? backendUrl,
    bool? autoSelectSource,
    String? preferredSourceId,
    String? videoPlayer,
  }) {
    return AppSettings(
      appLanguage: appLanguage ?? this.appLanguage,
      subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
      tmdbAccessToken: tmdbAccessToken ?? this.tmdbAccessToken,
      backendUrl: backendUrl ?? this.backendUrl,
      autoSelectSource: autoSelectSource ?? this.autoSelectSource,
      preferredSourceId: preferredSourceId ?? this.preferredSourceId,
      videoPlayer: videoPlayer ?? this.videoPlayer,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'schemaVersion': schemaVersion,
      'appLanguage': appLanguage,
      'subtitleLanguage': subtitleLanguage,
      'tmdbAccessToken': tmdbAccessToken,
      'backendUrl': backendUrl,
      'autoSelectSource': autoSelectSource,
      'preferredSourceId': preferredSourceId,
      'videoPlayer': videoPlayer,
    };
  }

  factory AppSettings.fromMap(Map<dynamic, dynamic> map) {
    return AppSettings(
      appLanguage: (map['appLanguage'] ?? 'en').toString(),
      subtitleLanguage: (map['subtitleLanguage'] ?? 'en').toString(),
      tmdbAccessToken: (map['tmdbAccessToken'] ?? '').toString(),
      backendUrl: (map['backendUrl'] ?? 'http://127.0.0.1:8000').toString(),
      autoSelectSource: (map['autoSelectSource'] ?? true) == true,
      preferredSourceId: (map['preferredSourceId'] ?? '').toString(),
      videoPlayer: (map['videoPlayer'] ?? 'native').toString(),
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
