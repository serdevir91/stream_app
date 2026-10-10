class AnimeEpisode {
  final int malId;
  final int episodeNumber;
  final String title;
  final String? japaneseTitle;
  final String? romajiTitle;
  final String? aired;
  final double? score;
  final bool isFiller;
  final bool isRecap;
  final String? synopsis;

  const AnimeEpisode({
    required this.malId,
    required this.episodeNumber,
    required this.title,
    this.japaneseTitle,
    this.romajiTitle,
    this.aired,
    this.score,
    this.isFiller = false,
    this.isRecap = false,
    this.synopsis,
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

  factory AnimeEpisode.synthetic(int animeMalId, int episodeNumber) {
    return AnimeEpisode(
      malId: animeMalId,
      episodeNumber: episodeNumber,
      title: 'Episode $episodeNumber',
    );
  }
}
