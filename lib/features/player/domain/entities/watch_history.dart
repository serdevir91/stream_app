class WatchHistory {
  final String mediaId;
  final String title;
  final int lastPosition; // in milliseconds
  final int duration; // in milliseconds
  final bool isWatched;

  WatchHistory({
    required this.mediaId,
    required this.title,
    required this.lastPosition,
    required this.duration,
    this.isWatched = false,
  });

  WatchHistory copyWith({
    String? mediaId,
    String? title,
    int? lastPosition,
    int? duration,
    bool? isWatched,
  }) {
    return WatchHistory(
      mediaId: mediaId ?? this.mediaId,
      title: title ?? this.title,
      lastPosition: lastPosition ?? this.lastPosition,
      duration: duration ?? this.duration,
      isWatched: isWatched ?? this.isWatched,
    );
  }
}
