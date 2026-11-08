import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_app/features/downloads/data/services/hls.dart';
import 'package:stream_app/features/downloads/data/services/segment_crypto.dart';

void main() {
  final base = Uri.parse('https://cdn.example.com/hls/title/master.m3u8?token=a');

  test('parseMaster reads variants and audio renditions', () {
    const text = '#EXTM3U\n'
        '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="Italiano",LANGUAGE="ita",DEFAULT=YES,URI="a/ita.m3u8"\n'
        '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="English",LANGUAGE="eng",URI="a/eng.m3u8"\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=1280x720,CODECS="avc1.64001f,mp4a.40.2",AUDIO="aud"\n'
        'v/720.m3u8\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=4500000,RESOLUTION=1920x1080,AUDIO="aud"\n'
        'v/1080.m3u8\n';
    final master = Hls.parseMaster(text, base);
    expect(master.variants.length, 2);
    expect(master.variants.first.uri.toString(), 'https://cdn.example.com/hls/title/v/720.m3u8');
    expect(master.variants.first.codecs, 'avc1.64001f,mp4a.40.2');
    expect(Hls.pickVariant(master.variants, '1080p').height, 1080);
    expect(Hls.pickVariant(master.variants, '720p').height, 720);
    expect(Hls.pickVariant(master.variants, '480p').height, 720);
    expect(Hls.pickVariant(master.variants, 'Auto').height, 1080);
    final audio = Hls.pickAudio(master.audios, master.variants.first, preferredLanguages: ['en']);
    expect(audio!.name, 'English');
    expect(Hls.pickAudio(master.audios, master.variants.first)!.name, 'Italiano');
  });

  test('parseMedia keeps keys, sequence numbers and durations', () {
    const text = '#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXT-X-MEDIA-SEQUENCE:7\n'
        '#EXT-X-KEY:METHOD=AES-128,URI="https://keys.example.com/k1"\n'
        '#EXTINF:5.5,\nseg7.ts\n'
        '#EXT-X-KEY:METHOD=AES-128,URI="k2",IV=0x000000000000000000000000000000FF\n'
        '#EXTINF:6.0,\nseg8.ts\n#EXT-X-ENDLIST\n';
    final media = Hls.parseMedia(text, base);
    expect(media.segments.length, 2);
    expect(media.segments[0].sequence, 7);
    expect(media.segments[0].duration, 5.5);
    expect(media.segments[0].key!.uri.toString(), 'https://keys.example.com/k1');
    expect(media.segments[0].iv.last, 7);
    expect(media.segments[0].iv.sublist(0, 15).every((b) => b == 0), isTrue);
    expect(media.segments[1].key!.uri.toString(), 'https://cdn.example.com/hls/title/k2');
    expect(media.segments[1].iv.last, 0xFF);
  });

  test('aes-128 round trip with pkcs7 padding', () {
    final key = Uint8List.fromList(List.generate(16, (i) => i));
    final iv = Uint8List.fromList(List.generate(16, (i) => 15 - i));
    final plain = Uint8List.fromList(List.generate(1000, (i) => i % 251));
    final enc = Encrypter(AES(Key(key), mode: AESMode.cbc))
        .encryptBytes(plain, iv: IV(iv))
        .bytes;
    expect(enc.length % 16, 0);
    final dec = SegmentCrypto.decryptAes128(enc, key, iv);
    expect(dec, plain);
  });

  test('pkcs7Unpad leaves invalid padding alone', () {
    final data = Uint8List.fromList([1, 2, 3, 9]);
    expect(Hls.pkcs7Unpad(data), data);
  });

  test('buildLocalMedia writes a VOD playlist', () {
    final out = Hls.buildLocalMedia(
      durations: [4.0, 6.2],
      fileNames: ['v_00000.ts', 'v_00001.ts'],
      targetDuration: 6,
    );
    expect(out, contains('#EXT-X-TARGETDURATION:7'));
    expect(out, contains('#EXTINF:6.200,\nv_00001.ts'));
    expect(out.trim().endsWith('#EXT-X-ENDLIST'), isTrue);
  });
}
