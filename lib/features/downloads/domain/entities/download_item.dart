class DownloadItem {
  final String id;
  final String mediaId;
  final String title;
  final String mediaType; // 'movie' or 'tv'
  final int? season;
  final int? episode;
  final String? episodeTitle;
  final String? posterUrl;
  final String? backdropUrl;
  final String quality;
  final String streamUrl;
  final String localVideoPath;
  final String? localSubtitlePath;
  final String subtitleLanguage;
  final String status; // 'queued', 'downloading', 'completed', 'failed', 'paused', 'canceled'
  final double progress; // 0.0 - 1.0
  final int downloadedBytes;
  final int totalBytes;
  final String speed;
  final DateTime createdAt;
  final String? errorMessage;

  const DownloadItem({
    required this.id,
    required this.mediaId,
    required this.title,
    required this.mediaType,
    this.season,
    this.episode,
    this.episodeTitle,
    this.posterUrl,
    this.backdropUrl,
    required this.quality,
    required this.streamUrl,
    required this.localVideoPath,
    this.localSubtitlePath,
    this.subtitleLanguage = 'tr',
    required this.status,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.speed = '',
    required this.createdAt,
    this.errorMessage,
  });

  bool get isCompleted => status == 'completed';
  bool get isDownloading => status == 'downloading';
  bool get isQueued => status == 'queued';
  bool get isFailed => status == 'failed';
  bool get isSeries => mediaType == 'tv' || mediaType == 'series';

  DownloadItem copyWith({
    String? id,
    String? mediaId,
    String? title,
    String? mediaType,
    int? season,
    int? episode,
    String? episodeTitle,
    String? posterUrl,
    String? backdropUrl,
    String? quality,
    String? streamUrl,
    String? localVideoPath,
    String? localSubtitlePath,
    String? subtitleLanguage,
    String? status,
    double? progress,
    int? downloadedBytes,
    int? totalBytes,
    String? speed,
    DateTime? createdAt,
    String? errorMessage,
  }) {
    return DownloadItem(
      id: id ?? this.id,
      mediaId: mediaId ?? this.mediaId,
      title: title ?? this.title,
      mediaType: mediaType ?? this.mediaType,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      posterUrl: posterUrl ?? this.posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      quality: quality ?? this.quality,
      streamUrl: streamUrl ?? this.streamUrl,
      localVideoPath: localVideoPath ?? this.localVideoPath,
      localSubtitlePath: localSubtitlePath ?? this.localSubtitlePath,
      subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      speed: speed ?? this.speed,
      createdAt: createdAt ?? this.createdAt,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'mediaId': mediaId,
      'title': title,
      'mediaType': mediaType,
      'season': season,
      'episode': episode,
      'episodeTitle': episodeTitle,
      'posterUrl': posterUrl,
      'backdropUrl': backdropUrl,
      'quality': quality,
      'streamUrl': streamUrl,
      'localVideoPath': localVideoPath,
      'localSubtitlePath': localSubtitlePath,
      'subtitleLanguage': subtitleLanguage,
      'status': status,
      'progress': progress,
      'downloadedBytes': downloadedBytes,
      'totalBytes': totalBytes,
      'speed': speed,
      'createdAt': createdAt.toIso8601String(),
      'errorMessage': errorMessage,
    };
  }

  factory DownloadItem.fromMap(Map<dynamic, dynamic> map) {
    return DownloadItem(
      id: (map['id'] ?? '').toString(),
      mediaId: (map['mediaId'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      mediaType: (map['mediaType'] ?? 'movie').toString(),
      season: map['season'] is int ? map['season'] as int : null,
      episode: map['episode'] is int ? map['episode'] as int : null,
      episodeTitle: map['episodeTitle']?.toString(),
      posterUrl: map['posterUrl']?.toString(),
      backdropUrl: map['backdropUrl']?.toString(),
      quality: (map['quality'] ?? 'Auto').toString(),
      streamUrl: (map['streamUrl'] ?? '').toString(),
      localVideoPath: (map['localVideoPath'] ?? '').toString(),
      localSubtitlePath: map['localSubtitlePath']?.toString(),
      subtitleLanguage: (map['subtitleLanguage'] ?? 'tr').toString(),
      status: (map['status'] ?? 'queued').toString(),
      progress: (map['progress'] is num) ? (map['progress'] as num).toDouble() : 0.0,
      downloadedBytes: (map['downloadedBytes'] is num) ? (map['downloadedBytes'] as num).toInt() : 0,
      totalBytes: (map['totalBytes'] is num) ? (map['totalBytes'] as num).toInt() : 0,
      speed: (map['speed'] ?? '').toString(),
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      errorMessage: map['errorMessage']?.toString(),
    );
  }
}
