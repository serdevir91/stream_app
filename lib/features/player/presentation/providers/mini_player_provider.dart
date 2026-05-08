import 'package:flutter_riverpod/flutter_riverpod.dart';

class MiniPlayerState {
  final bool isActive;
  final String? mediaId;
  final String? title;
  final String? type;
  final int season;
  final int episode;
  final String? posterUrl;
  final bool isPlaying;

  const MiniPlayerState({
    this.isActive = false,
    this.mediaId,
    this.title,
    this.type,
    this.season = 1,
    this.episode = 1,
    this.posterUrl,
    this.isPlaying = false,
  });

  MiniPlayerState copyWith({
    bool? isActive,
    String? mediaId,
    String? title,
    String? type,
    int? season,
    int? episode,
    String? posterUrl,
    bool? isPlaying,
  }) {
    return MiniPlayerState(
      isActive: isActive ?? this.isActive,
      mediaId: mediaId ?? this.mediaId,
      title: title ?? this.title,
      type: type ?? this.type,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      posterUrl: posterUrl ?? this.posterUrl,
      isPlaying: isPlaying ?? this.isPlaying,
    );
  }
}

class MiniPlayerNotifier extends Notifier<MiniPlayerState> {
  @override
  MiniPlayerState build() => const MiniPlayerState();

  void activate({
    required String mediaId,
    required String title,
    required String type,
    required int season,
    required int episode,
    String? posterUrl,
  }) {
    state = MiniPlayerState(
      isActive: true,
      mediaId: mediaId,
      title: title,
      type: type,
      season: season,
      episode: episode,
      posterUrl: posterUrl,
      isPlaying: true,
    );
  }

  void deactivate() {
    state = const MiniPlayerState();
  }

  void setPlaying(bool playing) {
    state = state.copyWith(isPlaying: playing);
  }
}

final miniPlayerProvider =
    NotifierProvider<MiniPlayerNotifier, MiniPlayerState>(
  MiniPlayerNotifier.new,
);
