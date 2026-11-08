import 'package:flutter_test/flutter_test.dart';
import 'package:stream_app/core/backend/addon_service.dart';
import 'package:stream_app/core/backend/addons/addon_config_repository.dart';
import 'package:stream_app/core/backend/addons/base_addon.dart';
import 'package:stream_app/core/backend/source_ranking.dart';

class _FakeAddon implements BaseAddon {
  _FakeAddon(this.id, this.delay, this.streams, {this.onlyId});

  final String id;
  final Duration delay;
  final List<StreamResult> streams;
  final String? onlyId;
  int calls = 0;

  @override
  AddonManifest get manifest => AddonManifest(id: id, name: id);

  @override
  Future<List<StreamResult>> getStreams(
    String contentId,
    String contentType,
    int season,
    int episode,
  ) async {
    calls++;
    await Future<void>.delayed(delay);
    if (onlyId != null && contentId != onlyId) return const [];
    return streams;
  }

  @override
  Future<List<SearchResult>> search(String query, String contentType) async => const [];
}

StreamResult _s(String url, {String title = '', bool direct = true}) =>
    StreamResult(url: url, title: title, isDirectLink: direct);

AddonService _service(List<BaseAddon> addons) =>
    AddonService(configRepo: AddonConfigRepository())..debugReplaceAddons(addons);

void main() {
  test('addons run in parallel and a slow one is cut off', () async {
    final service = _service([
      _FakeAddon('a', const Duration(milliseconds: 100), [_s('https://a/1.m3u8')]),
      _FakeAddon('b', const Duration(milliseconds: 150), [_s('https://b/1.mp4')]),
      _FakeAddon('slow', const Duration(seconds: 30), [_s('https://slow/1.mp4')]),
    ]);
    final watch = Stopwatch()..start();
    final data = await service.resolve(
      query: 'Movie',
      tmdbId: '123',
      contentType: 'movie',
      season: 1,
      episode: 1,
    );
    watch.stop();
    final urls = (data['streams'] as List).map((s) => s['url']).toSet();
    expect(urls, {'https://a/1.m3u8', 'https://b/1.mp4'});
    // 8 s per-addon cap, not 30 s, and not 100 + 150 ms one after another.
    expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('progress events grow and end with all addons done', () async {
    final service = _service([
      _FakeAddon('a', const Duration(milliseconds: 20), [_s('https://a/1.mp4')]),
      _FakeAddon('b', const Duration(milliseconds: 60), [_s('https://b/1.mp4')]),
    ]);
    final events = await service
        .resolveStream(query: 'X', tmdbId: '9', contentType: 'movie', season: 1, episode: 1)
        .toList();
    expect(events.first.finished, 0);
    expect(events.last.done, isTrue);
    expect(events.last.streams.length, 2);
  });

  test('second resolve is served from cache and a running job is shared', () async {
    final a = _FakeAddon('a', const Duration(milliseconds: 50), [_s('https://a/1.mp4')]);
    final service = _service([a]);
    final args = (query: 'X', tmdbId: '7');
    final first = service.resolve(query: args.query, tmdbId: args.tmdbId, contentType: 'movie', season: 1, episode: 1);
    final joined = service.resolve(query: args.query, tmdbId: args.tmdbId, contentType: 'movie', season: 1, episode: 1);
    await Future.wait([first, joined]);
    // One run: the id and the title lookup side by side.
    expect(a.calls, 2);
    await service.resolve(query: args.query, tmdbId: args.tmdbId, contentType: 'movie', season: 1, episode: 1);
    expect(a.calls, 2);
  });

  test('resolveFast returns after the grace period without the slow addon', () async {
    final service = _service([
      _FakeAddon('fast', const Duration(milliseconds: 50), [_s('https://fast/1.mp4')]),
      _FakeAddon('slow', const Duration(seconds: 6), [_s('https://slow/1.mp4')]),
    ]);
    final watch = Stopwatch()..start();
    final data = await service.resolveFast(
      query: 'X',
      tmdbId: '5',
      contentType: 'movie',
      season: 1,
      episode: 1,
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    expect((data['streams'] as List).single['url'], 'https://fast/1.mp4');
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('title lookup is used when the id finds nothing', () async {
    final service = _service([
      _FakeAddon('a', Duration.zero, [_s('https://a/1.mp4')], onlyId: 'Movie Title'),
    ]);
    final data = await service.resolve(
      query: 'Movie Title',
      tmdbId: '42',
      contentType: 'movie',
      season: 1,
      episode: 1,
    );
    expect((data['streams'] as List).length, 1);
  });

  group('SourceRanking', () {
    test('reads resolution from title', () {
      expect(SourceRanking.resolutionOf({'title': 'Movie 1080p WEB'}), 1080);
      expect(SourceRanking.resolutionOf({'quality': '4K'}), 2160);
      expect(SourceRanking.resolutionOf({'title': 'cam'}), isNull);
    });

    test('1080p direct beats 480p and embeds', () {
      final ranked = SourceRanking.rank(
        [
          {'url': 'e', 'title': '1080p', 'is_direct_link': false, 'addon_id': 'x'},
          {'url': 'l', 'title': '480p', 'is_direct_link': true, 'addon_id': 'x'},
          {'url': 'h', 'title': '1080p', 'is_direct_link': true, 'addon_id': 'x'},
        ],
        reliabilityOf: (_) => const AddonReliability(),
        orderOf: (_) => 0,
      );
      expect(ranked.map((s) => s['url']), ['h', 'l', 'e']);
    });

    test('a source that keeps failing drops below a reliable one', () {
      final ranked = SourceRanking.rank(
        [
          {'url': 'bad', 'title': '1080p', 'addon_id': 'bad'},
          {'url': 'good', 'title': '720p', 'addon_id': 'good'},
        ],
        reliabilityOf: (id) => id == 'bad'
            ? const AddonReliability(attempts: 10, hits: 10, playOk: 0, playFail: 10)
            : const AddonReliability(attempts: 10, hits: 10, playOk: 10, playFail: 0),
        orderOf: (_) => 0,
      );
      expect(ranked.first['url'], 'good');
    });

    test('Turkish tag wins a tie when the language is tr', () {
      final ranked = SourceRanking.rank(
        [
          {'url': 'en', 'title': '1080p', 'addon_id': 'x'},
          {'url': 'tr', 'title': '1080p Türkçe Dublaj', 'addon_id': 'x'},
        ],
        reliabilityOf: (_) => const AddonReliability(),
        orderOf: (_) => 0,
        language: 'tr',
      );
      expect(ranked.first['url'], 'tr');
    });
  });
}
