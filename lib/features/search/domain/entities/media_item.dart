class MediaItem {
  final String id;
  final String sourceId;
  final String title;
  final String type; // 'movie' or 'series'
  final String? posterUrl;
  final String? description;
  final String? streamUrl; // Could be fetched later, or present in search result
  
  MediaItem({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.type,
    this.posterUrl,
    this.description,
    this.streamUrl,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json, String sourceId) {
    return MediaItem(
      id: json['id'] as String,
      sourceId: sourceId,
      title: json['title'] as String,
      type: json['type'] as String,
      posterUrl: json['posterUrl'] as String?,
      description: json['description'] as String?,
      streamUrl: json['streamUrl'] as String?,
    );
  }
}
