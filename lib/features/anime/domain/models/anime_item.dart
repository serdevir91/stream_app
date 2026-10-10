import '../../../search/domain/entities/media_item.dart';

class AnimeItem {
  final int malId;
  final int? anilistId;
  final String title;
  final String? englishTitle;
  final String? romajiTitle;
  final String? japaneseTitle;
  final List<String> synonyms;
  final String? posterUrl;
  final String? backdropUrl;
  final String? synopsis;
  final String type; // TV, Movie, OVA, Special, ONA, Music
  final int? episodes;
  final String status; // Currently Airing, Finished Airing, Not yet aired
  final bool isAiring;
  final double? score;
  final int? scoredBy;
  final int? rank;
  final int? popularity;
  final List<String> genres;
  final List<String> studios;
  final int? year;
  final String? season;
  final String? airedString;
  final String? duration;
  final String? rating;
  final String? trailerUrl;

  const AnimeItem({
    required this.malId,
    this.anilistId,
    required this.title,
    this.englishTitle,
    this.romajiTitle,
    this.japaneseTitle,
    this.synonyms = const [],
    this.posterUrl,
    this.backdropUrl,
    this.synopsis,
    this.type = 'TV',
    this.episodes,
    this.status = 'Finished Airing',
    this.isAiring = false,
    this.score,
    this.scoredBy,
    this.rank,
    this.popularity,
    this.genres = const [],
    this.studios = const [],
    this.year,
    this.season,
    this.airedString,
    this.duration,
    this.rating,
    this.trailerUrl,
  });

  String get displayTitle {
    if (englishTitle != null && englishTitle!.trim().isNotEmpty) {
      return englishTitle!;
    }
    if (title.trim().isNotEmpty) {
      return title;
    }
    if (romajiTitle != null && romajiTitle!.trim().isNotEmpty) {
      return romajiTitle!;
    }
    return 'Anime';
  }

  String get subtitleInfo {
    final parts = <String>[];
    if (type.isNotEmpty) parts.add(type);
    if (year != null && year! > 0) parts.add(year.toString());
    if (episodes != null && episodes! > 0) {
      parts.add('$episodes Ep');
    } else if (isAiring) {
      parts.add('Airing');
    }
    return parts.join(' • ');
  }

  factory AnimeItem.fromJikan(Map<String, dynamic> json) {
    final images = json['images'] as Map<String, dynamic>?;
    final jpg = images?['jpg'] as Map<String, dynamic>?;
    final webp = images?['webp'] as Map<String, dynamic>?;
    final poster = webp?['large_image_url'] ??
        jpg?['large_image_url'] ??
        webp?['image_url'] ??
        jpg?['image_url'];

    final trailer = json['trailer'] as Map<String, dynamic>?;
    final trailerImages = trailer?['images'] as Map<String, dynamic>?;
    final backdrop = trailerImages?['maximum_image_url'] ??
        trailerImages?['large_image_url'] ??
        trailerImages?['medium_image_url'] ??
        poster;

    final genreList = <String>[];
    if (json['genres'] is List) {
      for (final g in json['genres']) {
        if (g is Map && g['name'] != null) {
          genreList.add(g['name'].toString());
        }
      }
    }

    final studioList = <String>[];
    if (json['studios'] is List) {
      for (final s in json['studios']) {
        if (s is Map && s['name'] != null) {
          studioList.add(s['name'].toString());
        }
      }
    }

    final synonymList = <String>[];
    if (json['title_synonyms'] is List) {
      for (final s in json['title_synonyms']) {
        if (s != null) synonymList.add(s.toString());
      }
    }

    final rawScore = json['score'];
    final scoreVal = rawScore is num ? rawScore.toDouble() : null;

    final aired = json['aired'] as Map<String, dynamic>?;

    return AnimeItem(
      malId: json['mal_id'] is int ? json['mal_id'] : int.tryParse(json['mal_id']?.toString() ?? '0') ?? 0,
      title: json['title']?.toString() ?? '',
      englishTitle: json['title_english']?.toString(),
      romajiTitle: json['title']?.toString(),
      japaneseTitle: json['title_japanese']?.toString(),
      synonyms: synonymList,
      posterUrl: poster?.toString(),
      backdropUrl: backdrop?.toString(),
      synopsis: json['synopsis']?.toString(),
      type: json['type']?.toString() ?? 'TV',
      episodes: json['episodes'] is int ? json['episodes'] : int.tryParse(json['episodes']?.toString() ?? ''),
      status: json['status']?.toString() ?? '',
      isAiring: json['airing'] == true,
      score: scoreVal,
      scoredBy: json['scored_by'] is int ? json['scored_by'] : null,
      rank: json['rank'] is int ? json['rank'] : null,
      popularity: json['popularity'] is int ? json['popularity'] : null,
      genres: genreList,
      studios: studioList,
      year: json['year'] is int ? json['year'] : null,
      season: json['season']?.toString(),
      airedString: aired?['string']?.toString(),
      duration: json['duration']?.toString(),
      rating: json['rating']?.toString(),
      trailerUrl: trailer?['url']?.toString(),
    );
  }

  factory AnimeItem.fromAniList(Map<String, dynamic> json) {
    final titleObj = json['title'] as Map<String, dynamic>?;
    final english = titleObj?['english']?.toString();
    final romaji = titleObj?['romaji']?.toString();
    final native = titleObj?['native']?.toString();
    final mainTitle = english ?? romaji ?? native ?? 'Anime';

    final coverImage = json['coverImage'] as Map<String, dynamic>?;
    final poster = coverImage?['extraLarge'] ?? coverImage?['large'] ?? coverImage?['medium'];
    final banner = json['bannerImage']?.toString() ?? poster?.toString();

    final rawScore = json['averageScore'];
    final scoreVal = rawScore is num ? rawScore.toDouble() / 10.0 : null;

    final genreList = <String>[];
    if (json['genres'] is List) {
      for (final g in json['genres']) {
        if (g != null) genreList.add(g.toString());
      }
    }

    final studioList = <String>[];
    final studiosObj = json['studios'] as Map<String, dynamic>?;
    if (studiosObj?['nodes'] is List) {
      for (final node in studiosObj!['nodes']) {
        if (node is Map && node['name'] != null) {
          studioList.add(node['name'].toString());
        }
      }
    }

    final synonymList = <String>[];
    if (json['synonyms'] is List) {
      for (final s in json['synonyms']) {
        if (s != null) synonymList.add(s.toString());
      }
    }

    final startDate = json['startDate'] as Map<String, dynamic>?;
    final startYear = startDate?['year'] is int ? startDate!['year'] as int : null;

    return AnimeItem(
      malId: json['idMal'] is int ? json['idMal'] : (json['id'] is int ? json['id'] : 0),
      anilistId: json['id'] is int ? json['id'] : null,
      title: mainTitle,
      englishTitle: english,
      romajiTitle: romaji,
      japaneseTitle: native,
      synonyms: synonymList,
      posterUrl: poster?.toString(),
      backdropUrl: banner,
      synopsis: json['description']?.toString().replaceAll(RegExp(r'<[^>]*>'), ''),
      type: json['format']?.toString() ?? 'TV',
      episodes: json['episodes'] is int ? json['episodes'] : null,
      status: json['status']?.toString() ?? '',
      isAiring: json['status'] == 'RELEASING',
      score: scoreVal,
      genres: genreList,
      studios: studioList,
      year: json['seasonYear'] is int ? (json['seasonYear'] as int) : startYear,
      season: json['season']?.toString().toLowerCase(),
      duration: json['duration'] != null ? '${json['duration']} min' : null,
    );
  }

  MediaItem toMediaItem() {
    return MediaItem(
      id: 'anime_$malId',
      title: displayTitle,
      type: 'tv',
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      description: synopsis,
      rating: score,
    );
  }
}
