class AppSettings {
  static const int schemaVersion = 2;

  final String appLanguage;
  final String subtitleLanguage;
  final String tmdbAccessToken;
  final String backendUrl;

  const AppSettings({
    required this.appLanguage,
    required this.subtitleLanguage,
    required this.tmdbAccessToken,
    required this.backendUrl,
  });

  static const AppSettings defaults = AppSettings(
    appLanguage: 'en',
    subtitleLanguage: 'en',
    tmdbAccessToken: '',
    backendUrl: 'http://127.0.0.1:8000',
  );

  AppSettings copyWith({
    String? appLanguage,
    String? subtitleLanguage,
    String? tmdbAccessToken,
    String? backendUrl,
  }) {
    return AppSettings(
      appLanguage: appLanguage ?? this.appLanguage,
      subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
      tmdbAccessToken: tmdbAccessToken ?? this.tmdbAccessToken,
      backendUrl: backendUrl ?? this.backendUrl,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'schemaVersion': schemaVersion,
      'appLanguage': appLanguage,
      'subtitleLanguage': subtitleLanguage,
      'tmdbAccessToken': tmdbAccessToken,
      'backendUrl': backendUrl,
    };
  }

  factory AppSettings.fromMap(Map<dynamic, dynamic> map) {
    return AppSettings(
      appLanguage: (map['appLanguage'] ?? 'en').toString(),
      subtitleLanguage: (map['subtitleLanguage'] ?? 'en').toString(),
      tmdbAccessToken: (map['tmdbAccessToken'] ?? '').toString(),
      backendUrl: (map['backendUrl'] ?? 'http://127.0.0.1:8000').toString(),
    );
  }
}

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
