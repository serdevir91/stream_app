import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_app/core/subtitles/subtitle_engine.dart';

void main() {
  group('parseTimestamp', () {
    test('srt, vtt, short and ass forms', () {
      expect(SubtitleEngine.parseTimestamp('01:02:03,456'),
          const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 456));
      expect(SubtitleEngine.parseTimestamp('02:03.5'),
          const Duration(minutes: 2, seconds: 3, milliseconds: 500));
      expect(SubtitleEngine.parseTimestamp('0:00:01.20'),
          const Duration(seconds: 1, milliseconds: 200));
      expect(SubtitleEngine.parseTimestamp('garbage'), isNull);
    });
  });

  group('parse', () {
    test('srt with tags, missing blank line and CRLF', () {
      const srt = '1\r\n00:00:01,000 --> 00:00:02,500\r\n<i>Merhaba</i>\r\n'
          '2\r\n00:00:03,000 --> 00:00:04,000\r\nDünya\r\n';
      final doc = SubtitleEngine.parse(srt);
      expect(doc.cues.length, 2);
      expect(doc.cues[0].text, 'Merhaba');
      expect(doc.cues[1].text, 'Dünya');
    });

    test('vtt with header and cue settings', () {
      const vtt = 'WEBVTT\n\n00:01.000 --> 00:02.000 align:start\nHello\n';
      final doc = SubtitleEngine.parse(vtt);
      expect(doc.cues.single.start, const Duration(seconds: 1));
      expect(doc.cues.single.text, 'Hello');
    });

    test('ass dialogue with override tags and commas', () {
      const ass = '[Script Info]\nTitle: x\n\n[Events]\n'
          'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
          'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,{\\i1}Selam, nasılsın\\Niyi\n';
      final doc = SubtitleEngine.parse(ass);
      expect(doc.cues.single.text, 'Selam, nasılsın\niyi');
    });
  });

  group('decode', () {
    test('utf8 bom is stripped', () {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('ğış')];
      expect(SubtitleEngine.decode(bytes), 'ğış');
    });

    test('windows-1254 turkish letters', () {
      // "Işığı Şöyle" in cp1254
      final bytes = [0x49, 0xFE, 0xFD, 0xF0, 0xFD, 0x20, 0xDE, 0xF6, 0x79, 0x6C, 0x65];
      expect(SubtitleEngine.decode(bytes), 'Işığı Şöyle');
    });
  });

  group('timing', () {
    final doc = SubtitleEngine.parse(
      '1\n00:00:10,000 --> 00:00:12,000\nA\n\n'
      '2\n00:00:11,000 --> 00:00:13,000\nB\n\n'
      '3\n00:00:20,000 --> 00:00:21,000\nC\n',
    );

    test('lookup and overlap', () {
      expect(doc.textAt(const Duration(seconds: 9)), '');
      expect(doc.textAt(const Duration(milliseconds: 11500)), 'A\nB');
      expect(doc.textAt(const Duration(seconds: 20, milliseconds: 500)), 'C');
    });

    test('positive offset shows later', () {
      const t = SubtitleTiming(offsetSeconds: 2);
      expect(doc.textAt(const Duration(seconds: 10, milliseconds: 500), t), '');
      expect(doc.textAt(const Duration(seconds: 12, milliseconds: 100), t), 'A');
    });

    test('toSrt bakes timing in', () {
      final out = doc.toSrt(const SubtitleTiming(offsetSeconds: 1, scale: 2));
      expect(out, contains('00:00:21,000 --> 00:00:25,000'));
    });
  });

  group('fps', () {
    test('scaleForFps', () {
      expect(SubtitleEngine.scaleForFps(25, 23.976), closeTo(1.0427, 0.0005));
      expect(SubtitleEngine.scaleForFps(23.98, 23.976), 1.0);
      expect(SubtitleEngine.scaleForFps(null, 25), 1.0);
    });

    test('detectScaleFromDuration only when subtitle overruns', () {
      const video = Duration(minutes: 100);
      final overrun = Duration(milliseconds: (video.inMilliseconds * 25 / 23.976).round());
      expect(SubtitleEngine.detectScaleFromDuration(overrun, video),
          closeTo(23.976 / 25, 0.0005));
      expect(SubtitleEngine.detectScaleFromDuration(const Duration(minutes: 94), video), 1.0);
    });
  });
}
