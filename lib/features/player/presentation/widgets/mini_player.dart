import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/mini_player_provider.dart';

class MiniPlayer extends ConsumerWidget {
  final VoidCallback onTap;
  final VoidCallback onClose;

  const MiniPlayer({
    super.key,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(miniPlayerProvider);
    if (!state.isActive) return const SizedBox.shrink();

    final isTv = state.type == 'tv' || state.type == 'series' || state.type == 'show';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            if (state.posterUrl != null)
              Image.network(
                state.posterUrl!,
                width: 48,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stackTrace) => Container(
                  width: 48,
                  height: 64,
                  color: Colors.grey.shade800,
                  child: const Icon(Icons.movie, color: Colors.white54, size: 20),
                ),
              )
            else
              Container(
                width: 48,
                height: 64,
                color: Colors.grey.shade800,
                child: const Icon(Icons.movie, color: Colors.white54, size: 20),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.title ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isTv)
                    Text(
                      'S${state.season}:E${state.episode}',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: () {
                ref.read(miniPlayerProvider.notifier).setPlaying(!state.isPlaying);
              },
              icon: Icon(
                state.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
            ),
            IconButton(
              onPressed: () {
                ref.read(miniPlayerProvider.notifier).deactivate();
                onClose();
              },
              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
