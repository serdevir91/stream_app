class AnimeEpisode {
  final int malId;
  final int episodeNumber;
  final int seasonNumber;
  final String title;
  final String? japaneseTitle;
  final String? romajiTitle;
  final String? aired;
  final double? score;
  final bool isFiller;
  final bool isRecap;
  final String? synopsis;
  final String? thumbnailUrl;
  final int? runtimeMinutes;

  const AnimeEpisode({
    required this.malId,
    required this.episodeNumber,
    this.seasonNumber = 1,
    required this.title,
    this.japaneseTitle,
    this.romajiTitle,
    this.aired,
    this.score,
    this.isFiller = false,
    this.isRecap = false,
    this.synopsis,
    this.thumbnailUrl,
    this.runtimeMinutes,
  });

  String get displayTitle {
    if (title.trim().isNotEmpty && !title.toLowerCase().startsWith('episode')) {
      return title;
    }
    if (romajiTitle != null && romajiTitle!.trim().isNotEmpty) {
      return romajiTitle!;
    }
    return 'Episode $episodeNumber';
  }

  AnimeEpisode copyWith({
    int? malId,
    int? episodeNumber,
    int? seasonNumber,
    String? title,
    String? japaneseTitle,
    String? romajiTitle,
    String? aired,
    double? score,
    bool? isFiller,
    bool? isRecap,
    String? synopsis,
    String? thumbnailUrl,
    int? runtimeMinutes,
  }) {
    return AnimeEpisode(
      malId: malId ?? this.malId,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      title: title ?? this.title,
      japaneseTitle: japaneseTitle ?? this.japaneseTitle,
      romajiTitle: romajiTitle ?? this.romajiTitle,
      aired: aired ?? this.aired,
      score: score ?? this.score,
      isFiller: isFiller ?? this.isFiller,
      isRecap: isRecap ?? this.isRecap,
      synopsis: synopsis ?? this.synopsis,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      runtimeMinutes: runtimeMinutes ?? this.runtimeMinutes,
    );
  }

  factory AnimeEpisode.fromJikan(int animeMalId, Map<String, dynamic> json) {
    final epNum = json['mal_id'] is int
        ? json['mal_id']
        : int.tryParse(json['mal_id']?.toString() ?? '') ?? 1;

    final rawScore = json['score'];
    final scoreVal = rawScore is num ? rawScore.toDouble() : null;

    return AnimeEpisode(
      malId: animeMalId,
      episodeNumber: epNum,
      title: json['title']?.toString() ?? 'Episode $epNum',
      japaneseTitle: json['title_japanese']?.toString(),
      romajiTitle: json['title_romanji']?.toString(),
      aired: json['aired']?.toString(),
      score: scoreVal,
      isFiller: json['filler'] == true,
      isRecap: json['recap'] == true,
      synopsis: json['synopsis']?.toString(),
    );
  }

  factory AnimeEpisode.fromKitsu(int animeMalId, Map<String, dynamic> json) {
    final attrs = json['attributes'] as Map<String, dynamic>? ?? {};
    final epNum = attrs['number'] is int
        ? attrs['number'] as int
        : int.tryParse(attrs['number']?.toString() ?? '1') ?? 1;
    final seasonNum = attrs['seasonNumber'] is int
        ? attrs['seasonNumber'] as int
        : int.tryParse(attrs['seasonNumber']?.toString() ?? '1') ?? 1;

    final titles = attrs['titles'] as Map<String, dynamic>?;
    final title = attrs['canonicalTitle']?.toString() ??
        titles?['en_us']?.toString() ??
        titles?['en_jp']?.toString() ??
        'Episode $epNum';

    final thumbObj = attrs['thumbnail'] as Map<String, dynamic>?;
    final thumb = thumbObj?['original']?.toString() ??
        thumbObj?['large']?.toString() ??
        thumbObj?['medium']?.toString();

    final lengthVal = attrs['length'] is int
        ? attrs['length'] as int
        : int.tryParse(attrs['length']?.toString() ?? '');

    return AnimeEpisode(
      malId: animeMalId,
      episodeNumber: epNum,
      seasonNumber: seasonNum,
      title: title,
      synopsis: attrs['synopsis']?.toString() ?? attrs['description']?.toString(),
      aired: attrs['airdate']?.toString(),
      thumbnailUrl: thumb,
      runtimeMinutes: lengthVal,
    );
  }

  factory AnimeEpisode.synthetic(int animeMalId, int episodeNumber, {String? defaultThumbnail}) {
    return AnimeEpisode(
      malId: animeMalId,
      episodeNumber: episodeNumber,
      title: 'Episode $episodeNumber',
      thumbnailUrl: defaultThumbnail,
    );
  }
}
