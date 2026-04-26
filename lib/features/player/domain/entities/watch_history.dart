class WatchHistory {
  final String historyId;
  final String mediaId;
  final String title;
  final String mediaType; // movie or tv
  final int season;
  final int episode;
  final String? posterUrl;
  final String? backdropUrl;
  final int lastPosition; // in milliseconds
  final int duration; // in milliseconds
  final bool isWatched;
  final int updatedAtMs;

  WatchHistory({
    this.historyId = '',
    required this.mediaId,
    required this.title,
    this.mediaType = 'movie',
    this.season = 1,
    this.episode = 1,
    this.posterUrl,
    this.backdropUrl,
    required this.lastPosition,
    required this.duration,
    this.isWatched = false,
    int? updatedAtMs,
  }) : updatedAtMs = updatedAtMs ?? DateTime.now().millisecondsSinceEpoch;

  double get progressRatio {
    if (duration <= 0) {
      return 0;
    }
    final ratio = lastPosition / duration;
    if (ratio < 0) {
      return 0;
    }
    if (ratio > 1) {
      return 1;
    }
    return ratio;
  }

  WatchHistory copyWith({
    String? historyId,
    String? mediaId,
    String? title,
    String? mediaType,
    int? season,
    int? episode,
    String? posterUrl,
    String? backdropUrl,
    int? lastPosition,
    int? duration,
    bool? isWatched,
    int? updatedAtMs,
  }) {
    return WatchHistory(
      historyId: historyId ?? this.historyId,
      mediaId: mediaId ?? this.mediaId,
      title: title ?? this.title,
      mediaType: mediaType ?? this.mediaType,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      posterUrl: posterUrl ?? this.posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      lastPosition: lastPosition ?? this.lastPosition,
      duration: duration ?? this.duration,
      isWatched: isWatched ?? this.isWatched,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }
}
