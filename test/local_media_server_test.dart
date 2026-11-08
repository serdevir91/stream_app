import 'package:flutter_test/flutter_test.dart';
import 'package:stream_app/core/player/local_media_server.dart';

void main() {
  test('rewritePlaylist wraps segments, keys and renditions', () {
    const body = '#EXTM3U\n'
        '#EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x1\n'
        '#EXT-X-MEDIA:TYPE=AUDIO,URI="audio/index.m3u8"\n'
        '#EXTINF:6.0,\n'
        'seg0.ts\n'
        '\n'
        'https://cdn.example.com/abs/seg1.ts\n';
    final base = Uri.parse('https://host.example.com/path/master.m3u8?t=1');
    final out = LocalMediaServer.rewritePlaylist(body, base, (u) => 'P[$u]');
    expect(out, contains('URI="P[https://host.example.com/path/key.bin]"'));
    expect(out, contains('URI="P[https://host.example.com/path/audio/index.m3u8]"'));
    expect(out, contains('P[https://host.example.com/path/seg0.ts]'));
    expect(out, contains('P[https://cdn.example.com/abs/seg1.ts]'));
    expect(out, contains('#EXTINF:6.0,'));
  });
}
