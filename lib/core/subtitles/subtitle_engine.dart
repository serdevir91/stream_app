import 'dart:convert';
import 'dart:io';

/// One timed subtitle line.
class SubtitleCue {
  final Duration start;
  final Duration end;
  final String text;

  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });
}

/// Timing correction applied on top of the raw cue times.
///
/// A cue shown at raw time `t` is displayed at `t * scale + offset`.
/// A positive [offsetSeconds] shows subtitles later, a negative one earlier.
class SubtitleTiming {
  final double offsetSeconds;
  final double scale;

  const SubtitleTiming({this.offsetSeconds = 0.0, this.scale = 1.0});

  static const SubtitleTiming identity = SubtitleTiming();

  SubtitleTiming copyWith({double? offsetSeconds, double? scale}) =>
      SubtitleTiming(
        offsetSeconds: offsetSeconds ?? this.offsetSeconds,
        scale: scale ?? this.scale,
      );

  Duration apply(Duration raw) {
    final ms = raw.inMilliseconds * scale + offsetSeconds * 1000;
    return Duration(milliseconds: ms.round());
  }

  /// Maps a playback position back to the raw subtitle timeline.
  Duration invert(Duration position) {
    final ms = (position.inMilliseconds - offsetSeconds * 1000) / scale;
    return Duration(milliseconds: ms.round());
  }
}

/// Parsed subtitle file with fast lookup.
class SubtitleDocument {
  final List<SubtitleCue> cues;

  SubtitleDocument(List<SubtitleCue> cues)
      : cues = List.unmodifiable(
          [...cues]..sort((a, b) => a.start.compareTo(b.start)),
        );

  static final SubtitleDocument empty = SubtitleDocument(const []);

  bool get isEmpty => cues.isEmpty;
  bool get isNotEmpty => cues.isNotEmpty;

  Duration get lastCueEnd => cues.isEmpty
      ? Duration.zero
      : cues.map((c) => c.end).reduce((a, b) => a > b ? a : b);

  /// Text visible at [position] (playback time) after [timing] is applied.
  /// Overlapping cues are joined with a newline.
  String textAt(Duration position, [SubtitleTiming timing = SubtitleTiming.identity]) {
    if (cues.isEmpty) return '';
    final raw = timing.invert(position);
    // Binary search for the last cue whose start <= raw.
    var lo = 0;
    var hi = cues.length - 1;
    var idx = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (cues[mid].start <= raw) {
        idx = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (idx < 0) return '';
    final visible = <String>[];
    // Walk back over a few cues to catch long overlapping ones.
    for (var i = idx; i >= 0 && i >= idx - 8; i--) {
      final c = cues[i];
      if (raw >= c.start && raw <= c.end) visible.insert(0, c.text);
    }
    return visible.join('\n');
  }

  /// Serialises to SRT with [timing] baked in (for external players).
  String toSrt([SubtitleTiming timing = SubtitleTiming.identity]) {
    final buf = StringBuffer();
    var n = 1;
    for (final c in cues) {
      var start = timing.apply(c.start);
      var end = timing.apply(c.end);
      if (end <= Duration.zero) continue;
      if (start.isNegative) start = Duration.zero;
      if (end <= start) end = start + const Duration(milliseconds: 500);
      buf
        ..writeln(n++)
        ..writeln('${_srtTime(start)} --> ${_srtTime(end)}')
        ..writeln(c.text)
        ..writeln();
    }
    return buf.toString();
  }

  static String _srtTime(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final ms = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$h:$m:$s,$ms';
  }
}

class SubtitleEngine {
  SubtitleEngine._();

  /// Decodes raw subtitle bytes: gzip, BOMs, UTF-8, UTF-16, Windows-1254.
  static String decode(List<int> input) {
    var bytes = input;
    if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      try {
        bytes = gzip.decode(bytes);
      } catch (_) {}
    }
    if (bytes.isEmpty) return '';
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: false);
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return decodeWindows1254(bytes);
    }
  }

  static String _decodeUtf16(List<int> bytes, {required bool littleEndian}) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add(littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(units);
  }

  /// Windows-1254 (Turkish) code page. 0x80-0x9F use the cp1252 layout,
  /// and six Latin-1 slots are replaced by Turkish letters.
  static String decodeWindows1254(List<int> bytes) {
    final out = StringBuffer();
    for (final b in bytes) {
      if (b < 0x80) {
        out.writeCharCode(b);
      } else if (b < 0xA0) {
        out.writeCharCode(_cp125xHigh[b - 0x80]);
      } else {
        out.writeCharCode(_cp1254Turkish[b] ?? b);
      }
    }
    return out.toString();
  }

  static const List<int> _cp125xHigh = [
    0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x008E, 0x008F,
    0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x009E, 0x0178,
  ];

  static const Map<int, int> _cp1254Turkish = {
    0xD0: 0x011E, // Ğ
    0xDD: 0x0130, // İ
    0xDE: 0x015E, // Ş
    0xF0: 0x011F, // ğ
    0xFD: 0x0131, // ı
    0xFE: 0x015F, // ş
  };

  /// Parses SRT, WebVTT or ASS/SSA content.
  static SubtitleDocument parse(String content, {String? format}) {
    var text = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (text.startsWith('﻿')) text = text.substring(1);
    final head = text.trimLeft();
    final fmt = (format ?? '').toLowerCase();
    if (fmt == 'ass' ||
        fmt == 'ssa' ||
        head.startsWith('[Script Info]') ||
        text.contains('\nDialogue:')) {
      return _parseAss(text);
    }
    return _parseSrtOrVtt(text);
  }

  static SubtitleDocument parseBytes(List<int> bytes, {String? format}) =>
      parse(decode(bytes), format: format);

  static final RegExp _timeLine = RegExp(
    r'((?:\d+:)?\d{1,2}:\d{1,2}(?:[.,]\d{1,3})?)\s*-->\s*((?:\d+:)?\d{1,2}:\d{1,2}(?:[.,]\d{1,3})?)',
  );

  static SubtitleDocument _parseSrtOrVtt(String text) {
    final cues = <SubtitleCue>[];
    final lines = text.split('\n');
    var i = 0;
    while (i < lines.length) {
      final m = _timeLine.firstMatch(lines[i]);
      if (m == null) {
        i++;
        continue;
      }
      final start = parseTimestamp(m.group(1)!);
      final end = parseTimestamp(m.group(2)!);
      i++;
      final body = <String>[];
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        // A missing blank line before the next cue: stop at the next timing.
        if (_timeLine.hasMatch(lines[i])) break;
        body.add(lines[i]);
        i++;
      }
      // Drop a trailing numeric index that belongs to the next cue.
      if (body.isNotEmpty &&
          i < lines.length &&
          _timeLine.hasMatch(lines[i]) &&
          RegExp(r'^\d+$').hasMatch(body.last.trim())) {
        body.removeLast();
      }
      final cleaned = cleanText(body.join('\n'));
      if (start != null && end != null && cleaned.isNotEmpty) {
        cues.add(SubtitleCue(start: start, end: end, text: cleaned));
      }
    }
    return SubtitleDocument(cues);
  }

  static SubtitleDocument _parseAss(String text) {
    final cues = <SubtitleCue>[];
    var fields = <String>[];
    var inEvents = false;
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('[')) {
        inEvents = line.toLowerCase() == '[events]';
        continue;
      }
      if (!inEvents) continue;
      if (line.startsWith('Format:')) {
        fields = line
            .substring(7)
            .split(',')
            .map((f) => f.trim().toLowerCase())
            .toList();
        continue;
      }
      if (!line.startsWith('Dialogue:') || fields.isEmpty) continue;
      final parts = line.substring(9).split(',');
      if (parts.length < fields.length) continue;
      final textIdx = fields.indexOf('text');
      final startIdx = fields.indexOf('start');
      final endIdx = fields.indexOf('end');
      if (textIdx < 0 || startIdx < 0 || endIdx < 0) continue;
      final body = parts.sublist(textIdx).join(',');
      final start = parseTimestamp(parts[startIdx].trim());
      final end = parseTimestamp(parts[endIdx].trim());
      final cleaned = cleanText(
        body
            .replaceAll(RegExp(r'\{[^}]*\}'), '')
            .replaceAll(r'\N', '\n')
            .replaceAll(r'\n', '\n')
            .replaceAll(r'\h', ' '),
      );
      if (start != null && end != null && cleaned.isNotEmpty) {
        cues.add(SubtitleCue(start: start, end: end, text: cleaned));
      }
    }
    return SubtitleDocument(cues);
  }

  /// Parses `hh:mm:ss,mmm`, `mm:ss.mmm`, `h:mm:ss.cc` (ASS centiseconds).
  static Duration? parseTimestamp(String value) {
    final v = value.trim().replaceAll(',', '.');
    final parts = v.split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    final hours = parts.length == 3 ? int.tryParse(parts[0]) : 0;
    final minutes = int.tryParse(parts[parts.length - 2]);
    final secParts = parts.last.split('.');
    final seconds = int.tryParse(secParts[0]);
    if (hours == null || minutes == null || seconds == null) return null;
    var ms = 0;
    if (secParts.length > 1 && secParts[1].isNotEmpty) {
      final frac = secParts[1];
      // "5" = 500 ms, "50" = 500 ms, "500" = 500 ms.
      ms = int.tryParse(frac.padRight(3, '0').substring(0, 3)) ?? 0;
    }
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: ms,
    );
  }

  /// Strips HTML-like tags and VTT cue settings, keeps line breaks.
  static String cleanText(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .join('\n');
  }

  static const List<double> _knownFps = [23.976, 24.0, 25.0, 29.97, 30.0];

  /// Scale factor that maps a subtitle made for [subtitleFps] onto a video
  /// running at [videoFps]. Returns 1.0 when either is unknown or they match.
  static double scaleForFps(double? subtitleFps, double? videoFps) {
    if (subtitleFps == null || videoFps == null) return 1.0;
    if (subtitleFps <= 0 || videoFps <= 0) return 1.0;
    final sub = _snapFps(subtitleFps);
    final vid = _snapFps(videoFps);
    final ratio = sub / vid;
    if ((ratio - 1).abs() < 0.005) return 1.0;
    if (ratio < 0.75 || ratio > 1.35) return 1.0;
    return ratio;
  }

  static double _snapFps(double fps) {
    for (final k in _knownFps) {
      if ((fps - k).abs() < 0.05) return k;
    }
    return fps;
  }

  /// Detects a frame-rate mismatch from timing alone. Only acts when the
  /// subtitle clearly runs past the end of the video, because a subtitle that
  /// ends early can simply mean end credits.
  static double detectScaleFromDuration(
    Duration lastCueEnd,
    Duration videoDuration,
  ) {
    if (videoDuration.inSeconds < 600 || lastCueEnd <= Duration.zero) {
      return 1.0;
    }
    final r = lastCueEnd.inMilliseconds / videoDuration.inMilliseconds;
    if (r <= 1.01) return 1.0;
    const candidates = [25 / 23.976, 25 / 24, 24 / 23.976, 30 / 25, 29.97 / 25];
    for (final c in candidates) {
      if ((r - c).abs() < 0.006) return 1 / c;
    }
    return 1.0;
  }
}
