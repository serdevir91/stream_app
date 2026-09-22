import 'package:flutter_test/flutter_test.dart';
import 'package:stream_app/core/backend/extractors/vixsrc_extractor.dart';

void main() {
  group('VixSrcExtractor Unit Tests', () {
    final extractor = VixSrcExtractor();

    test('extract Rick and Morty S1E1 streams', () async {
      final res = await extractor.extract(
        tmdbId: '60625',
        mediaType: 'tv',
        season: 1,
        episode: 1,
      );

      expect(res, isNotNull);
      expect(res!.masterUrl, contains('vixsrc.to'));
      expect(res.videoVariants, isNotEmpty);
      expect(res.audioTracks, isNotEmpty);

      final bestVideo = res.getBestVideoVariant('720p');
      expect(bestVideo, isNotNull);

      final details = await extractor.parsePlaylistDetails(bestVideo!.url);
      expect(details, isNotNull);
      expect(details!.segmentUrls, isNotEmpty);
      expect(details.ivHex, isNotNull);
    });
  });
}
