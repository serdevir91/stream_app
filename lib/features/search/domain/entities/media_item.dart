class MediaItem {
  final String id;
  final String title;
  final String type; // 'movie' or 'tv'
  final String? posterUrl;
  final String? backdropUrl;
  final String? description;
  final double? rating;

  MediaItem({
    required this.id,
    required this.title,
    required this.type,
    this.posterUrl,
    this.backdropUrl,
    this.description,
    this.rating,
  });

  factory MediaItem.fromTmdbJson(Map<String, dynamic> json) {
    // TMDB image base URL
    const String imageBaseUrl = 'https://image.tmdb.org/t/p/w500';

    // TMDB uses 'name' for TV shows and 'title' for movies
    final String title = json['title'] ?? json['name'] ?? 'Unknown';
    final String type = json['media_type'] ?? 'movie';

    String? posterUrl;
    if (json['poster_path'] != null) {
      posterUrl = '$imageBaseUrl${json['poster_path']}';
    }

    String? backdropUrl;
    if (json['backdrop_path'] != null) {
      backdropUrl = '$imageBaseUrl${json['backdrop_path']}';
    }

    return MediaItem(
      id: json['id'].toString(),
      title: title,
      type: type,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      description: json['overview'],
      rating: json['vote_average']?.toDouble(),
    );
  }

  factory MediaItem.fromVidSrcJson(Map<String, dynamic> json, String type) {
    return MediaItem(
      id: json['tmdb_id']?.toString() ?? '',
      title: json['title'] ?? 'Unknown',
      type: type,
      description: 'Kalite: ${json['quality'] ?? 'Bilinmiyor'}',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'type': type,
      'posterUrl': posterUrl,
      'backdropUrl': backdropUrl,
      'description': description,
      'rating': rating,
    };
  }

  factory MediaItem.fromMap(Map<dynamic, dynamic> map) {
    return MediaItem(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? 'Unknown').toString(),
      type: (map['type'] ?? 'movie').toString(),
      posterUrl: map['posterUrl']?.toString(),
      backdropUrl: map['backdropUrl']?.toString(),
      description: map['description']?.toString(),
      rating: map['rating'] is num ? (map['rating'] as num).toDouble() : null,
    );
  }
}

class Season {
  final int seasonNumber;
  final String name;
  final int episodeCount;

  Season({
    required this.seasonNumber,
    required this.name,
    required this.episodeCount,
  });

  factory Season.fromTmdbJson(Map<String, dynamic> json) {
    return Season(
      seasonNumber: json['season_number'] ?? 0,
      name: json['name'] ?? 'Unknown Season',
      episodeCount: json['episode_count'] ?? 0,
    );
  }
}

class Episode {
  final int episodeNumber;
  final String name;
  final String? stillPath;

  Episode({required this.episodeNumber, required this.name, this.stillPath});

  factory Episode.fromTmdbJson(Map<String, dynamic> json) {
    const String imageBaseUrl = 'https://image.tmdb.org/t/p/w500';
    return Episode(
      episodeNumber: json['episode_number'] ?? 0,
      name: json['name'] ?? 'Unknown',
      stillPath: json['still_path'] != null
          ? '$imageBaseUrl${json['still_path']}'
          : null,
    );
  }
}
