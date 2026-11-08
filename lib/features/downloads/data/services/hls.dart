import 'dart:typed_data';

/// One rendition of a master playlist (EXT-X-STREAM-INF).
class HlsVariant {
  final Uri uri;
  final int bandwidth;
  final int? height;
  final String? resolution;
  final String? codecs;
  final String? audioGroup;

  const HlsVariant({
    required this.uri,
    required this.bandwidth,
    this.height,
    this.resolution,
    this.codecs,
    this.audioGroup,
  });
}

/// Alternate audio rendition (EXT-X-MEDIA TYPE=AUDIO).
class HlsAudio {
  final Uri? uri;
  final String groupId;
  final String? language;
  final String name;
  final bool isDefault;

  const HlsAudio({
    required this.uri,
    required this.groupId,
    required this.name,
    this.language,
    this.isDefault = false,
  });
}

class HlsMaster {
  final List<HlsVariant> variants;
  final List<HlsAudio> audios;

  const HlsMaster(this.variants, this.audios);
}

class HlsKey {
  final String method; // NONE, AES-128, SAMPLE-AES
  final Uri? uri;
  final Uint8List? iv;

  const HlsKey(this.method, {this.uri, this.iv});

  bool get isAes128 => method == 'AES-128';
}

class HlsSegment {
  final Uri uri;
  final double duration;
  final int sequence;
  final HlsKey? key;

  const HlsSegment({
    required this.uri,
    required this.duration,
    required this.sequence,
    this.key,
  });

  /// RFC 8216 5.2: without an IV attribute, the IV is the media sequence
  /// number as a 128-bit big-endian integer.
  Uint8List get iv {
    final explicit = key?.iv;
    if (explicit != null) return explicit;
    final out = Uint8List(16);
    var n = sequence;
    for (var i = 15; i >= 0 && n > 0; i--) {
      out[i] = n & 0xff;
      n >>= 8;
    }
    return out;
  }
}

class HlsMedia {
  final List<HlsSegment> segments;
  final double targetDuration;
  final Uri? initSegment; // EXT-X-MAP (fMP4)
  final HlsKey? initKey;
  final bool usesByteRange;

  const HlsMedia({
    required this.segments,
    required this.targetDuration,
    this.initSegment,
    this.initKey,
    this.usesByteRange = false,
  });
}

class Hls {
  Hls._();

  static bool isMaster(String text) => text.contains('#EXT-X-STREAM-INF');

  static Map<String, String> attributes(String line) {
    final idx = line.indexOf(':');
    final body = idx < 0 ? '' : line.substring(idx + 1);
    final out = <String, String>{};
    final re = RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)');
    for (final m in re.allMatches(body)) {
      var v = m.group(2)!;
      if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
        v = v.substring(1, v.length - 1);
      }
      out[m.group(1)!] = v;
    }
    return out;
  }

  static List<String> _lines(String text) => text
      .replaceAll('\r', '')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  static HlsMaster parseMaster(String text, Uri base) {
    final lines = _lines(text);
    final variants = <HlsVariant>[];
    final audios = <HlsAudio>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('#EXT-X-MEDIA:')) {
        final a = attributes(line);
        if (a['TYPE'] != 'AUDIO') continue;
        final uri = a['URI'];
        audios.add(
          HlsAudio(
            uri: uri == null ? null : base.resolve(uri),
            groupId: a['GROUP-ID'] ?? '',
            language: a['LANGUAGE'],
            name: a['NAME'] ?? a['LANGUAGE'] ?? 'Audio',
            isDefault: a['DEFAULT'] == 'YES',
          ),
        );
      } else if (line.startsWith('#EXT-X-STREAM-INF:')) {
        final a = attributes(line);
        String? uriLine;
        for (var j = i + 1; j < lines.length; j++) {
          if (!lines[j].startsWith('#')) {
            uriLine = lines[j];
            i = j;
            break;
          }
        }
        if (uriLine == null) continue;
        final res = a['RESOLUTION'];
        final height = res != null && res.contains('x')
            ? int.tryParse(res.split('x').last)
            : null;
        variants.add(
          HlsVariant(
            uri: base.resolve(uriLine),
            bandwidth: int.tryParse(a['BANDWIDTH'] ?? '') ?? 0,
            height: height,
            resolution: res,
            codecs: a['CODECS'],
            audioGroup: a['AUDIO'],
          ),
        );
      }
    }
    return HlsMaster(variants, audios);
  }

  static Uint8List? _parseIv(String? hex) {
    if (hex == null) return null;
    var h = hex.trim();
    if (h.startsWith('0x') || h.startsWith('0X')) h = h.substring(2);
    if (h.isEmpty || h.length > 32) return null;
    h = h.padLeft(32, '0');
    final out = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      final b = int.tryParse(h.substring(i * 2, i * 2 + 2), radix: 16);
      if (b == null) return null;
      out[i] = b;
    }
    return out;
  }

  static HlsMedia parseMedia(String text, Uri base) {
    final lines = _lines(text);
    final segments = <HlsSegment>[];
    var sequence = 0;
    var target = 0.0;
    double? pendingDuration;
    HlsKey? key;
    Uri? init;
    HlsKey? initKey;
    var byteRange = false;
    for (final line in lines) {
      if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        sequence = int.tryParse(line.split(':').last) ?? 0;
      } else if (line.startsWith('#EXT-X-TARGETDURATION:')) {
        target = double.tryParse(line.split(':').last) ?? 0;
      } else if (line.startsWith('#EXTINF:')) {
        final value = line.substring(8).split(',').first;
        pendingDuration = double.tryParse(value) ?? 0;
      } else if (line.startsWith('#EXT-X-KEY:')) {
        final a = attributes(line);
        final method = a['METHOD'] ?? 'NONE';
        final uri = a['URI'];
        key = method == 'NONE'
            ? null
            : HlsKey(
                method,
                uri: uri == null ? null : base.resolve(uri),
                iv: _parseIv(a['IV']),
              );
      } else if (line.startsWith('#EXT-X-MAP:')) {
        final a = attributes(line);
        final uri = a['URI'];
        if (uri != null) {
          init = base.resolve(uri);
          initKey = key;
        }
        if (a.containsKey('BYTERANGE')) byteRange = true;
      } else if (line.startsWith('#EXT-X-BYTERANGE')) {
        byteRange = true;
      } else if (!line.startsWith('#')) {
        segments.add(
          HlsSegment(
            uri: base.resolve(line),
            duration: pendingDuration ?? target,
            sequence: sequence,
            key: key,
          ),
        );
        sequence++;
        pendingDuration = null;
      }
    }
    if (target <= 0 && segments.isNotEmpty) {
      target = segments.map((s) => s.duration).reduce((a, b) => a > b ? a : b);
    }
    return HlsMedia(
      segments: segments,
      targetDuration: target,
      initSegment: init,
      initKey: initKey,
      usesByteRange: byteRange,
    );
  }

  /// Variant for a quality label such as '1080p' or 'Auto': the tallest
  /// rendition not above the target, else the smallest one above it.
  static HlsVariant pickVariant(List<HlsVariant> variants, String quality) {
    final sorted = [...variants]..sort((a, b) {
        final h = (a.height ?? 0).compareTo(b.height ?? 0);
        return h != 0 ? h : a.bandwidth.compareTo(b.bandwidth);
      });
    final wanted = int.tryParse(RegExp(r'(\d{3,4})').firstMatch(quality)?.group(1) ?? '');
    if (wanted == null || sorted.every((v) => v.height == null)) {
      return sorted.last;
    }
    final fitting = sorted.where((v) => (v.height ?? 0) <= wanted).toList();
    return fitting.isNotEmpty ? fitting.last : sorted.first;
  }

  /// Audio rendition for [variant]: the language asked for, else the
  /// default, else the first one with its own URI.
  static HlsAudio? pickAudio(
    List<HlsAudio> audios,
    HlsVariant variant, {
    List<String> preferredLanguages = const [],
  }) {
    final group = audios
        .where((a) => a.uri != null && (variant.audioGroup == null || a.groupId == variant.audioGroup))
        .toList();
    if (group.isEmpty) return null;
    for (final lang in preferredLanguages) {
      final match = group.where((a) => _langMatches(a.language, lang)).firstOrNull;
      if (match != null) return match;
    }
    return group.where((a) => a.isDefault).firstOrNull ?? group.first;
  }

  static bool _langMatches(String? value, String lang) {
    if (value == null) return false;
    final v = value.toLowerCase();
    final l = lang.toLowerCase();
    if (v == l || v.startsWith('$l-')) return true;
    const alias = {'tr': 'tur', 'en': 'eng', 'ar': 'ara', 'fa': 'per'};
    return alias[l] == v;
  }

  /// Removes PKCS#7 padding; returns [data] unchanged when it is not valid
  /// padding.
  static Uint8List pkcs7Unpad(Uint8List data) {
    if (data.isEmpty) return data;
    final pad = data.last;
    if (pad < 1 || pad > 16 || pad > data.length) return data;
    for (var i = data.length - pad; i < data.length; i++) {
      if (data[i] != pad) return data;
    }
    return Uint8List.sublistView(data, 0, data.length - pad);
  }

  static String segmentExtension(Uri uri, {String fallback = '.ts'}) {
    final last = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last.toLowerCase();
    final dot = last.lastIndexOf('.');
    if (dot < 0) return fallback;
    final ext = last.substring(dot);
    const known = {'.ts', '.m4s', '.mp4', '.aac', '.m4a', '.mp3', '.vtt', '.webvtt'};
    return known.contains(ext) ? ext : fallback;
  }

  /// Local VOD playlist that points at the downloaded files.
  static String buildLocalMedia({
    required List<double> durations,
    required List<String> fileNames,
    required double targetDuration,
    String? initFileName,
  }) {
    final maxDur = durations.isEmpty
        ? targetDuration
        : durations.reduce((a, b) => a > b ? a : b);
    final target = (maxDur > targetDuration ? maxDur : targetDuration).ceil();
    final b = StringBuffer('#EXTM3U\n')
      ..writeln('#EXT-X-VERSION:${initFileName != null ? 7 : 3}')
      ..writeln('#EXT-X-TARGETDURATION:${target < 1 ? 1 : target}')
      ..writeln('#EXT-X-MEDIA-SEQUENCE:0')
      ..writeln('#EXT-X-PLAYLIST-TYPE:VOD');
    if (initFileName != null) b.writeln('#EXT-X-MAP:URI="$initFileName"');
    for (var i = 0; i < fileNames.length; i++) {
      b
        ..writeln('#EXTINF:${durations[i].toStringAsFixed(3)},')
        ..writeln(fileNames[i]);
    }
    b.writeln('#EXT-X-ENDLIST');
    return b.toString();
  }
}
