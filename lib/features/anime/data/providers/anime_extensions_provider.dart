import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../../domain/models/anime_extension.dart';

const String _kAnimeExtensionsBox = 'anime_extensions_box';

final List<AnimeExtension> defaultAnimeExtensions = [
  const AnimeExtension(
    id: 'openani',
    name: 'OpenAnime (Direct MP4)',
    description: 'High-speed direct 1080p/720p MP4 streaming from openani.me CDN (Range & seek supported).',
    version: '1.0.0',
    icon: '🌸',
    isDirectStream: true,
    isEnabled: true,
    priority: 1,
  ),
  const AnimeExtension(
    id: 'altyazi_arsivi',
    name: 'Altyazı Arşivi',
    description: 'Turkish & English WebVTT subtitles archive from gitlab.com/agnogad/altyazi_arsivi.',
    version: '1.0.0',
    icon: '🇹🇷',
    isDirectStream: false,
    isEnabled: true,
    priority: 2,
  ),
  const AnimeExtension(
    id: 'tmdb_bridge',
    name: 'TMDB TV Bridge',
    description: 'Cross-resolves anime titles listed on TMDB across 13+ movie/series streaming servers.',
    version: '2.0.0',
    icon: '🌉',
    isEnabled: true,
    priority: 3,
  ),
  const AnimeExtension(
    id: 'vidsrc_anime',
    name: 'VidSrc Anime',
    description: 'Multi-server anime embed player supporting both Sub and Dub video sources.',
    version: '2.1.0',
    icon: '🎬',
    isEnabled: true,
    priority: 4,
  ),
  const AnimeExtension(
    id: 'twoembed_anime',
    name: '2Embed Anime',
    description: 'Fast and responsive HTML5 anime embed player with adblock compatibility.',
    version: '1.4.0',
    icon: '⚡',
    isEnabled: true,
    priority: 5,
  ),
  const AnimeExtension(
    id: 'multiembed_anime',
    name: 'MultiEmbed Anime',
    description: 'Secondary anime mirror server with high uptime.',
    version: '1.1.0',
    icon: '🌐',
    isEnabled: true,
    priority: 6,
  ),
];

class AnimeExtensionsNotifier extends Notifier<List<AnimeExtension>> {
  Box? _box;

  @override
  List<AnimeExtension> build() {
    _initBox();
    return defaultAnimeExtensions;
  }

  Future<void> _initBox() async {
    try {
      _box = await Hive.openBox(_kAnimeExtensionsBox);
      _loadState();
    } catch (_) {
      // Keep default
    }
  }

  void _loadState() {
    if (_box == null) return;
    final saved = <AnimeExtension>[];
    for (final def in defaultAnimeExtensions) {
      final isEnabled = _box!.get('enabled_${def.id}', defaultValue: def.isEnabled) as bool;
      final priority = _box!.get('priority_${def.id}', defaultValue: def.priority) as int;
      saved.add(def.copyWith(isEnabled: isEnabled, priority: priority));
    }
    saved.sort((a, b) => a.priority.compareTo(b.priority));
    state = saved;
  }

  Future<void> toggleExtension(String id, bool enabled) async {
    state = state.map((ext) {
      if (ext.id == id) {
        return ext.copyWith(isEnabled: enabled);
      }
      return ext;
    }).toList();

    if (_box != null) {
      await _box!.put('enabled_$id', enabled);
    }
  }

  Future<void> reorderExtensions(int oldIndex, int newIndex) async {
    final list = List<AnimeExtension>.from(state);
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);

    final updated = <AnimeExtension>[];
    for (int i = 0; i < list.length; i++) {
      final updatedExt = list[i].copyWith(priority: i + 1);
      updated.add(updatedExt);
      if (_box != null) {
        await _box!.put('priority_${updatedExt.id}', i + 1);
      }
    }
    state = updated;
  }

  Future<void> reorderExtensionsDirect(int oldIndex, int newIndex) async {
    final list = List<AnimeExtension>.from(state);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);

    final updated = <AnimeExtension>[];
    for (int i = 0; i < list.length; i++) {
      final updatedExt = list[i].copyWith(priority: i + 1);
      updated.add(updatedExt);
      if (_box != null) {
        await _box!.put('priority_${updatedExt.id}', i + 1);
      }
    }
    state = updated;
  }

  Future<void> resetToDefaults() async {
    state = defaultAnimeExtensions;
    if (_box != null) {
      await _box!.clear();
    }
  }
}

final animeExtensionsProvider =
    NotifierProvider<AnimeExtensionsNotifier, List<AnimeExtension>>(
  AnimeExtensionsNotifier.new,
);
