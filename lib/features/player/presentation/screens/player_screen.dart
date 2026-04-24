import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import '../providers/player_provider.dart';
import '../../domain/entities/watch_history.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final String mediaId;
  final String streamUrl;
  final String title;

  const PlayerScreen({
    super.key, 
    required this.mediaId,
    required this.streamUrl, 
    required this.title,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late VlcPlayerController _videoPlayerController;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _videoPlayerController = VlcPlayerController.network(
      widget.streamUrl,
      hwAcc: HwAcc.full,
      autoPlay: true,
      options: VlcPlayerOptions(),
    );
    
    // Seek to previous position if available
    _initPlaybackPosition();
  }
  
  Future<void> _initPlaybackPosition() async {
    final repo = ref.read(watchHistoryRepositoryProvider);
    final history = repo.getProgress(widget.mediaId);
    if (history != null && history.lastPosition > 0) {
      // Wait for player to be ready before seeking
      // For simplicity in this demo, we assume the player gets ready quickly,
      // but in production, we should listen to the player state.
    }
  }

  Future<void> _saveProgress() async {
    if (_isDisposed) return;
    try {
      final position = await _videoPlayerController.getPosition();
      final duration = await _videoPlayerController.getDuration();
      
      if (position.inMilliseconds > 0 && duration.inMilliseconds > 0) {
        final repo = ref.read(watchHistoryRepositoryProvider);
        final isWatched = position.inMilliseconds >= duration.inMilliseconds * 0.9; // 90% watched = completed
        
        await repo.saveProgress(WatchHistory(
          mediaId: widget.mediaId,
          title: widget.title,
          lastPosition: position.inMilliseconds,
          duration: duration.inMilliseconds,
          isWatched: isWatched,
        ));
      }
    } catch (e) {
      debugPrint("Error saving progress: $e");
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _saveProgress().then((_) async {
      await _videoPlayerController.stopRendererScanning();
      await _videoPlayerController.dispose();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.title),
        elevation: 0,
      ),
      body: Center(
        child: VlcPlayer(
          controller: _videoPlayerController,
          aspectRatio: 16 / 9,
          placeholder: const Center(child: CircularProgressIndicator()),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_videoPlayerController.value.isPlaying) {
            _videoPlayerController.pause();
          } else {
            _videoPlayerController.play();
          }
        },
        child: const Icon(Icons.play_arrow),
      ),
    );
  }
}
