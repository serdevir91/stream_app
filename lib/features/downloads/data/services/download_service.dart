import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/background/keep_alive_service.dart';
import '../../../../core/backend/extractors/vixsrc_extractor.dart';
import '../../../../core/subtitles/online_subtitle_repository.dart';
import '../../../../core/subtitles/subtitle_engine.dart';
import '../../domain/entities/download_item.dart';
import 'hls.dart';
import 'segment_crypto.dart';

/// Thrown when a signed stream URL expired (HTTP 403/410) so the source can
/// be resolved again and the download resumed.
class _SourceExpired implements Exception {
  const _SourceExpired();
}

class _Source {
  final String url;
  final Map<String, String> headers;
  final bool isHls;

  const _Source(this.url, this.headers, {required this.isHls});
}

class _SegmentTask {
  final Uri uri;
  final String fileName;
  final HlsKey? key;
  final Uint8List iv;

  _SegmentTask(this.uri, this.fileName, this.key, this.iv);
}

/// Downloads movies and episodes for offline playback.
///
/// - HLS: any playlist (master or media), AES-128 with per-URI keys and the
///   RFC 8216 media-sequence IV, PKCS#7 unpadding, fMP4 init segments,
///   parallel segments with retries. A missing segment fails the item.
/// - Direct files resume with HTTP Range.
/// - Each finished part is renamed from `.part`, so a restart skips it.
/// - A foreground service keeps the queue running in the background.
class DownloadService {
  static const String boxName = 'downloads_box';
  static const int maxConcurrentDownloads = 1;
  static const int segmentConcurrency = 5;
  static const int _maxAttempts = 3;
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  final Dio _dio;
  final OnlineSubtitleRepository? _subtitleRepo;
  final OnlineSubtitleRepository? Function()? _subtitleRepoBuilder;
  final VixSrcExtractor _vixSrcExtractor;
  final SegmentCrypto _crypto = SegmentCrypto();
  Box? _box;

  final Map<String, DownloadItem> _cachedItems = {};
  final Map<String, ValueNotifier<DownloadItem?>> _live = {};
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, Future<void>> _running = {};
  final List<String> _queue = [];
  final Set<String> _dirty = {};
  Timer? _persistTimer;
  bool _permissionAsked = false;

  final StreamController<List<DownloadItem>> _itemsStreamController =
      StreamController<List<DownloadItem>>.broadcast();

  DownloadService({
    Dio? dio,
    OnlineSubtitleRepository? subtitleRepo,
    OnlineSubtitleRepository? Function()? subtitleRepoBuilder,
    VixSrcExtractor? vixSrcExtractor,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 60),
                headers: {'User-Agent': _userAgent},
              ),
            ),
        _subtitleRepo = subtitleRepo,
        _subtitleRepoBuilder = subtitleRepoBuilder,
        _vixSrcExtractor = vixSrcExtractor ?? VixSrcExtractor(dio: dio);

  OnlineSubtitleRepository? get _subtitles =>
      _subtitleRepo ?? _subtitleRepoBuilder?.call();

  // ---------------------------------------------------------------------
  // Storage and change notification
  // ---------------------------------------------------------------------

  Future<void>? _initFuture;

  /// Opens the box and restores the queue once; later calls share that run.
  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    if (!Hive.isBoxOpen(boxName)) {
      _box = await Hive.openBox(boxName);
    } else {
      _box = Hive.box(boxName);
    }
    _loadCacheFromBox();
    if (_queue.isNotEmpty) {
      // Resume after the first frame so the foreground service starts from
      // a visible activity.
      Timer(const Duration(seconds: 2), () => unawaited(_processQueue()));
    }
  }

  void _loadCacheFromBox() {
    final box = _box;
    if (box == null) return;
    _cachedItems.clear();
    final restored = <DownloadItem>[];
    for (final raw in box.values) {
      if (raw is! Map) continue;
      try {
        var item = DownloadItem.fromMap(raw);
        if (item.status == 'downloading') {
          // Interrupted by a kill or crash: queue it again.
          item = item.copyWith(status: 'queued', speed: '');
          box.put(item.id, item.toMap());
        }
        _cachedItems[item.id] = item;
        if (item.status == 'queued') restored.add(item);
      } catch (e) {
        debugPrint('Bad download entry: $e');
      }
    }
    restored.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _queue
      ..clear()
      ..addAll(restored.map((e) => e.id));
    _notify();
  }

  Stream<List<DownloadItem>> watchDownloads() => _itemsStreamController.stream;

  void _notify() {
    if (!_itemsStreamController.isClosed) {
      _itemsStreamController.add(getAllDownloads());
    }
  }

  List<DownloadItem> getAllDownloads() {
    final items = _cachedItems.values.toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  DownloadItem? getItem(String id) => _cachedItems[id];

  /// Live value of one item; progress ticks update only this, not the list.
  ValueListenable<DownloadItem?> watchItem(String id) =>
      _live.putIfAbsent(id, () => ValueNotifier<DownloadItem?>(_cachedItems[id]));

  /// Stores [item]. [immediateDbWrite] false is for progress ticks: the
  /// item's listener updates now, the box is written within two seconds and
  /// the list stream is not re-emitted.
  Future<void> saveItem(DownloadItem item, {bool immediateDbWrite = true}) async {
    final previous = _cachedItems[item.id];
    _cachedItems[item.id] = item;
    _live[item.id]?.value = item;
    if (immediateDbWrite) {
      _dirty.remove(item.id);
      if (_box == null) await init();
      await _box?.put(item.id, item.toMap());
    } else {
      _dirty.add(item.id);
      _persistTimer ??= Timer(const Duration(seconds: 2), _flushDirty);
    }
    if (immediateDbWrite || previous?.status != item.status) _notify();
  }

  void _flushDirty() {
    _persistTimer = null;
    final box = _box;
    if (box == null) return;
    for (final id in _dirty.toList()) {
      final item = _cachedItems[id];
      if (item != null) box.put(id, item.toMap());
    }
    _dirty.clear();
  }

  Future<String> getDownloadsDirectoryPath() async {
    final dir = await getApplicationDocumentsDirectory();
    final downloadsDir = Directory('${dir.path}/downloads');
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }
    return downloadsDir.path;
  }

  String _sanitizeFileName(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_').trim();

  Future<Directory> _itemDirectory(DownloadItem item) async {
    final root = await getDownloadsDirectoryPath();
    final dir = Directory('$root/${_sanitizeFileName(item.id)}');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ---------------------------------------------------------------------
  // Queue
  // ---------------------------------------------------------------------

  bool _isActive(DownloadItem item) =>
      item.status == 'queued' || item.status == 'downloading';

  /// Queues [item]. Returns false when the same item is already queued,
  /// downloading or downloaded.
  Future<bool> startDownload(DownloadItem item) async {
    if (_box == null) await init();
    if (item.streamUrl.isEmpty) return false;
    final existing = getItem(item.id);
    if (existing != null) {
      if (_isActive(existing)) return false;
      if (existing.isCompleted &&
          existing.localVideoPath.isNotEmpty &&
          File(existing.localVideoPath).existsSync()) {
        return false;
      }
    }
    final queued = item.copyWith(
      status: 'queued',
      progress: 0,
      speed: '',
      errorMessage: null,
    );
    await saveItem(queued);
    if (!_queue.contains(item.id)) _queue.add(item.id);
    if (!_permissionAsked) {
      _permissionAsked = true;
      await KeepAliveService.requestPermission();
    }
    unawaited(_processQueue());
    return true;
  }

  /// Puts a failed or canceled item back in the queue; finished segments
  /// are kept and skipped.
  Future<void> retryDownload(String id) async {
    final item = getItem(id);
    if (item == null || _isActive(item)) return;
    await saveItem(item.copyWith(status: 'queued', speed: '', errorMessage: null));
    if (!_queue.contains(id)) _queue.add(id);
    unawaited(_processQueue());
  }

  Future<void> _processQueue() async {
    while (_running.length < maxConcurrentDownloads && _queue.isNotEmpty) {
      final id = _queue.removeAt(0);
      final item = getItem(id);
      if (item == null || item.status != 'queued' || _running.containsKey(id)) {
        continue;
      }
      _running[id] = _execute(item).whenComplete(() {
        _running.remove(id);
        unawaited(_processQueue());
      });
    }
    if (_running.isEmpty && _queue.isEmpty) {
      await KeepAliveService.release(KeepAliveReason.download);
    }
  }

  Future<void> _execute(DownloadItem start) async {
    final cancelToken = CancelToken();
    _cancelTokens[start.id] = cancelToken;
    var item = start.copyWith(status: 'downloading', speed: '', errorMessage: null);
    await saveItem(item);
    await KeepAliveService.acquire(
      KeepAliveReason.download,
      title: item.title,
      text: 'Downloading…',
    );

    try {
      final dir = await _itemDirectory(item);
      final subtitleJob = _fetchSubtitle(item, dir).catchError((Object e) {
        debugPrint('Subtitle download failed: $e');
      });

      var source = await _resolveSource(item, cancelToken);
      String path;
      var refreshed = false;
      while (true) {
        try {
          path = source.isHls
              ? await _downloadHls(item, source, dir, cancelToken)
              : await _downloadFile(item, source, dir, cancelToken);
          break;
        } on _SourceExpired {
          final fresh = refreshed ? null : await _refreshSource(item);
          if (fresh == null) {
            throw Exception('The stream link expired. Try another source.');
          }
          refreshed = true;
          source = fresh;
        }
      }
      if (cancelToken.isCancelled) return;
      await subtitleJob;

      final size = await _sizeOf(path);
      item = (getItem(item.id) ?? item).copyWith(
        status: 'completed',
        progress: 1.0,
        speed: '',
        localVideoPath: path,
        downloadedBytes: size,
        totalBytes: size,
        errorMessage: null,
      );
      await saveItem(item);
    } catch (e) {
      if (cancelToken.isCancelled || (e is DioException && CancelToken.isCancel(e))) {
        return;
      }
      debugPrint('Download failed for ${item.id}: $e');
      final latest = getItem(item.id) ?? item;
      await saveItem(
        latest.copyWith(status: 'failed', speed: '', errorMessage: _friendlyError(e)),
      );
    } finally {
      _cancelTokens.remove(start.id);
    }
  }

  String _friendlyError(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code != null) return 'Server answered HTTP $code.';
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'Connection timed out.';
      }
      return 'Network error.';
    }
    final text = e.toString().replaceFirst('Exception: ', '');
    return text.length > 160 ? text.substring(0, 160) : text;
  }

  Future<int> _sizeOf(String path) async {
    final file = File(path);
    if (path.endsWith('.m3u8')) {
      var total = 0;
      await for (final entity in file.parent.list()) {
        if (entity is File) total += await entity.length();
      }
      return total;
    }
    return await file.exists() ? file.length() : 0;
  }

  // ---------------------------------------------------------------------
  // Source resolution
  // ---------------------------------------------------------------------

  Map<String, String> _headersFor(DownloadItem item) => {
        'User-Agent': _userAgent,
        ...item.headers,
      };

  static bool _pathEndsWith(String url, List<String> exts) {
    final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
    return exts.any(path.endsWith);
  }

  Future<_Source> _resolveSource(DownloadItem item, CancelToken token) async {
    final url = item.streamUrl;
    final headers = _headersFor(item);
    if (_pathEndsWith(url, const ['.m3u8', '.m3u'])) {
      return _Source(url, headers, isHls: true);
    }
    if (_pathEndsWith(url, const ['.mp4', '.mkv', '.webm', '.mov', '.avi', '.m4v'])) {
      return _Source(url, headers, isHls: false);
    }

    // Unknown extension: look at the first bytes.
    try {
      final res = await _dio.get<List<int>>(
        url,
        cancelToken: token,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {...headers, 'Range': 'bytes=0-2047'},
          validateStatus: (s) => s != null && s < 400,
        ),
      );
      final type = (res.headers.value('content-type') ?? '').toLowerCase();
      final head = utf8.decode(res.data ?? const [], allowMalformed: true);
      if (type.contains('mpegurl') || head.trimLeft().startsWith('#EXTM3U')) {
        return _Source(res.realUri.toString(), headers, isHls: true);
      }
      if (type.startsWith('video/') ||
          type.contains('octet-stream') ||
          type.contains('matroska')) {
        return _Source(url, headers, isHls: false);
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
    }

    // Embed page: VixSrc can still give a direct HLS stream for TMDB titles.
    final fresh = await _refreshSource(item, force: true);
    if (fresh != null) return fresh;
    throw Exception('This source cannot be downloaded. Pick a direct source.');
  }

  /// New signed VixSrc link for a TMDB title, or null.
  Future<_Source?> _refreshSource(DownloadItem item, {bool force = false}) async {
    final isVix = item.streamUrl.toLowerCase().contains('vixsrc');
    if (!force && !isVix) return null;
    if (int.tryParse(item.mediaId) == null) return null;
    final res = await _vixSrcExtractor.extract(
      tmdbId: item.mediaId,
      mediaType: item.mediaType,
      season: item.season,
      episode: item.episode,
    );
    if (res == null || res.masterUrl.isEmpty) return null;
    return _Source(
      res.masterUrl,
      {'User-Agent': _userAgent, ...res.headers},
      isHls: true,
    );
  }

  // ---------------------------------------------------------------------
  // HTTP helpers
  // ---------------------------------------------------------------------

  Future<Response<T>> _get<T>(
    String url,
    Map<String, String> headers,
    CancelToken token, {
    ResponseType type = ResponseType.bytes,
  }) async {
    for (var attempt = 1;; attempt++) {
      try {
        return await _dio.get<T>(
          url,
          cancelToken: token,
          options: Options(responseType: type, headers: headers),
        );
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        final code = e.response?.statusCode;
        if (code == 403 || code == 410) throw const _SourceExpired();
        if (code == 404 || attempt >= _maxAttempts) rethrow;
        await Future<void>.delayed(Duration(seconds: 1 << (attempt - 1)));
      }
    }
  }

  // ---------------------------------------------------------------------
  // HLS
  // ---------------------------------------------------------------------

  Future<String> _downloadHls(
    DownloadItem item,
    _Source source,
    Directory dir,
    CancelToken token,
  ) async {
    final headers = source.headers;
    final first = await _get<String>(source.url, headers, token, type: ResponseType.plain);
    final firstText = first.data ?? '';
    final firstUri = first.realUri;

    HlsVariant? variant;
    HlsAudio? audio;
    HlsMedia video;
    HlsMedia? audioMedia;
    if (Hls.isMaster(firstText)) {
      final master = Hls.parseMaster(firstText, firstUri);
      if (master.variants.isEmpty) throw Exception('Playlist has no video.');
      variant = Hls.pickVariant(master.variants, item.quality);
      audio = Hls.pickAudio(master.audios, variant, preferredLanguages: const ['en']);
      final videoRes = await _get<String>(
        variant.uri.toString(),
        headers,
        token,
        type: ResponseType.plain,
      );
      video = Hls.parseMedia(videoRes.data ?? '', videoRes.realUri);
      if (audio?.uri != null) {
        final audioRes = await _get<String>(
          audio!.uri.toString(),
          headers,
          token,
          type: ResponseType.plain,
        );
        audioMedia = Hls.parseMedia(audioRes.data ?? '', audioRes.realUri);
      }
    } else {
      video = Hls.parseMedia(firstText, firstUri);
    }

    if (video.segments.isEmpty) throw Exception('Playlist has no segments.');
    for (final media in [video, ?audioMedia]) {
      if (media.usesByteRange) {
        throw Exception('Byte-range playlists are not supported.');
      }
      if (media.segments.any((s) => s.key != null && !s.key!.isAes128)) {
        throw Exception('This stream is DRM protected.');
      }
    }

    final tasks = <_SegmentTask>[];
    String? videoInit;
    String? audioInit;
    List<String> addMedia(HlsMedia media, String prefix, String fallbackExt) {
      final names = <String>[];
      if (media.initSegment != null) {
        final name = '${prefix}_init${Hls.segmentExtension(media.initSegment!, fallback: '.mp4')}';
        tasks.add(_SegmentTask(media.initSegment!, name, media.initKey, Uint8List(16)));
        if (prefix == 'v') {
          videoInit = name;
        } else {
          audioInit = name;
        }
      }
      for (var i = 0; i < media.segments.length; i++) {
        final seg = media.segments[i];
        final ext = Hls.segmentExtension(seg.uri, fallback: fallbackExt);
        final name = '${prefix}_${i.toString().padLeft(5, '0')}$ext';
        tasks.add(_SegmentTask(seg.uri, name, seg.key, seg.iv));
        names.add(name);
      }
      return names;
    }

    final videoNames = addMedia(video, 'v', video.initSegment != null ? '.m4s' : '.ts');
    final audioNames = audioMedia == null
        ? const <String>[]
        : addMedia(audioMedia, 'a', audioMedia.initSegment != null ? '.m4s' : '.aac');

    await _runSegmentTasks(item, tasks, dir, headers, token);
    if (token.isCancelled) return '';

    await File('${dir.path}/video.m3u8').writeAsString(
      Hls.buildLocalMedia(
        durations: video.segments.map((s) => s.duration).toList(),
        fileNames: videoNames,
        targetDuration: video.targetDuration,
        initFileName: videoInit,
      ),
    );
    if (audioMedia == null) {
      return _maybeRemux('${dir.path}/video.m3u8', dir);
    }
    await File('${dir.path}/audio.m3u8').writeAsString(
      Hls.buildLocalMedia(
        durations: audioMedia.segments.map((s) => s.duration).toList(),
        fileNames: audioNames,
        targetDuration: audioMedia.targetDuration,
        initFileName: audioInit,
      ),
    );
    final v = variant!;
    final lang = audio?.language;
    final master = StringBuffer('#EXTM3U\n#EXT-X-INDEPENDENT-SEGMENTS\n')
      ..writeln(
        '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="${audio?.name ?? 'Audio'}",'
        '${lang != null ? 'LANGUAGE="$lang",' : ''}DEFAULT=YES,AUTOSELECT=YES,URI="audio.m3u8"',
      )
      ..writeln(
        '#EXT-X-STREAM-INF:BANDWIDTH=${v.bandwidth > 0 ? v.bandwidth : 2000000}'
        '${v.resolution != null ? ',RESOLUTION=${v.resolution}' : ''}'
        '${v.codecs != null ? ',CODECS="${v.codecs}"' : ''},AUDIO="audio"',
      )
      ..writeln('video.m3u8');
    await File('${dir.path}/master.m3u8').writeAsString(master.toString());
    return _maybeRemux('${dir.path}/master.m3u8', dir);
  }

  Future<void> _runSegmentTasks(
    DownloadItem item,
    List<_SegmentTask> tasks,
    Directory dir,
    Map<String, String> headers,
    CancelToken token,
  ) async {
    final keyCache = <String, Future<Uint8List>>{};
    Future<Uint8List> keyFor(HlsKey key) {
      final uri = key.uri;
      if (uri == null) throw Exception('Encryption key URL missing.');
      return keyCache.putIfAbsent(uri.toString(), () async {
        final res = await _get<List<int>>(uri.toString(), headers, token);
        final bytes = Uint8List.fromList(res.data ?? const []);
        if (bytes.length != 16) throw Exception('Invalid encryption key.');
        return bytes;
      });
    }

    var done = 0;
    var bytes = 0;
    var lastBytes = 0;
    var lastTick = DateTime.now();
    var failed = 0;
    Object? fatal;
    var next = 0;

    Future<void> report() async {
      final now = DateTime.now();
      final ms = now.difference(lastTick).inMilliseconds;
      if (ms < 1000 && done < tasks.length) return;
      final speed = ms > 0 ? (bytes - lastBytes) * 1000 / ms : 0.0;
      lastTick = now;
      lastBytes = bytes;
      final progress = tasks.isEmpty ? 0.0 : (done / tasks.length).clamp(0.0, 0.99);
      final latest = getItem(item.id) ?? item;
      if (latest.status != 'downloading') return;
      final avg = done > 0 ? bytes / done : 0;
      await saveItem(
        latest.copyWith(
          progress: progress,
          downloadedBytes: bytes,
          totalBytes: (avg * tasks.length).round(),
          speed: _formatSpeed(speed),
        ),
        immediateDbWrite: false,
      );
      unawaited(
        KeepAliveService.update(
          title: item.title,
          text: '${(progress * 100).toStringAsFixed(0)}% · ${_formatSpeed(speed)}',
        ),
      );
    }

    Future<void> worker() async {
      while (fatal == null && !token.isCancelled) {
        if (next >= tasks.length) return;
        final task = tasks[next++];
        final target = File('${dir.path}/${task.fileName}');
        try {
          if (await target.exists() && await target.length() > 0) {
            bytes += await target.length();
          } else {
            final res = await _get<List<int>>(task.uri.toString(), headers, token);
            final data = Uint8List.fromList(res.data ?? const []);
            if (data.isEmpty) throw Exception('Empty segment');
            final part = '${target.path}.part';
            final key = task.key;
            if (key != null && key.isAes128) {
              bytes += await _crypto.decryptToFile(data, await keyFor(key), task.iv, part);
            } else {
              await File(part).writeAsBytes(data, flush: false);
              bytes += data.length;
            }
            await File(part).rename(target.path);
          }
          done++;
          await report();
        } on _SourceExpired catch (e) {
          fatal = e;
        } catch (e) {
          if (token.isCancelled || (e is DioException && CancelToken.isCancel(e))) return;
          failed++;
          debugPrint('Segment ${task.fileName} failed: $e');
          // Several failed segments usually mean the source is gone.
          if (failed > 3) fatal = e;
        }
      }
    }

    await Future.wait(List.generate(segmentConcurrency, (_) => worker()));
    if (token.isCancelled) return;
    if (fatal != null) throw fatal!;
    if (failed > 0) {
      throw Exception('$failed segment(s) could not be downloaded. Retry to resume.');
    }
  }

  /// Desktop builds with ffmpeg on PATH get a single MP4.
  Future<String> _maybeRemux(String playlistPath, Directory dir) async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return playlistPath;
    }
    final mp4 = '${dir.path}/video.mp4';
    try {
      final res = await Process.run('ffmpeg', [
        '-y',
        '-allowed_extensions', 'ALL',
        '-protocol_whitelist', 'file,crypto,data',
        '-i', playlistPath,
        '-c', 'copy',
        '-movflags', '+faststart',
        mp4,
      ]);
      if (res.exitCode == 0 && await File(mp4).exists() && await File(mp4).length() > 1000) {
        await for (final entity in dir.list()) {
          if (entity is File && !entity.path.endsWith('.mp4') && !entity.path.endsWith('.srt')) {
            await entity.delete();
          }
        }
        return mp4;
      }
    } catch (_) {}
    return playlistPath;
  }

  // ---------------------------------------------------------------------
  // Direct files
  // ---------------------------------------------------------------------

  Future<String> _downloadFile(
    DownloadItem item,
    _Source source,
    Directory dir,
    CancelToken token,
  ) async {
    final path = Uri.tryParse(source.url)?.path.toLowerCase() ?? '';
    final ext = RegExp(r'\.(mp4|mkv|webm|mov|avi|m4v)$').firstMatch(path)?.group(0) ?? '.mp4';
    final target = File('${dir.path}/video$ext');
    if (await target.exists() && await target.length() > 0) return target.path;
    final part = File('${target.path}.part');

    for (var attempt = 1;; attempt++) {
      try {
        await _downloadRange(item, source, part, token);
        break;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        final code = e.response?.statusCode;
        if (code == 403 || code == 410) throw const _SourceExpired();
        if (code == 404 || attempt >= _maxAttempts) rethrow;
        await Future<void>.delayed(Duration(seconds: 1 << (attempt - 1)));
      }
    }
    if (token.isCancelled) return '';
    await part.rename(target.path);
    return target.path;
  }

  Future<void> _downloadRange(
    DownloadItem item,
    _Source source,
    File part,
    CancelToken token,
  ) async {
    var start = await part.exists() ? await part.length() : 0;
    final res = await _dio.get<ResponseBody>(
      source.url,
      cancelToken: token,
      options: Options(
        responseType: ResponseType.stream,
        headers: {...source.headers, if (start > 0) 'Range': 'bytes=$start-'},
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    if (start > 0 && res.statusCode != 206) start = 0;
    var total = 0;
    final range = res.headers.value('content-range');
    if (range != null && range.contains('/')) {
      total = int.tryParse(range.split('/').last) ?? 0;
    }
    if (total <= 0) {
      final length = int.tryParse(res.headers.value('content-length') ?? '') ?? 0;
      total = length > 0 ? length + start : 0;
    }

    final sink = await part.open(mode: start > 0 ? FileMode.append : FileMode.write);
    var received = start;
    var lastBytes = start;
    var lastTick = DateTime.now();
    try {
      await for (final chunk in res.data!.stream) {
        await sink.writeFrom(chunk);
        received += chunk.length;
        final now = DateTime.now();
        final ms = now.difference(lastTick).inMilliseconds;
        if (ms >= 1000) {
          final speed = (received - lastBytes) * 1000 / ms;
          lastBytes = received;
          lastTick = now;
          final progress = total > 0 ? (received / total).clamp(0.0, 0.99) : 0.0;
          final latest = getItem(item.id) ?? item;
          if (latest.status == 'downloading') {
            await saveItem(
              latest.copyWith(
                progress: progress,
                downloadedBytes: received,
                totalBytes: total,
                speed: _formatSpeed(speed),
              ),
              immediateDbWrite: false,
            );
            unawaited(
              KeepAliveService.update(
                title: item.title,
                text: '${(progress * 100).toStringAsFixed(0)}% · ${_formatSpeed(speed)}',
              ),
            );
          }
        }
      }
    } finally {
      await sink.close();
    }
    if (total > 0 && received < total) {
      throw DioException(
        requestOptions: res.requestOptions,
        type: DioExceptionType.unknown,
        error: 'Connection closed early',
      );
    }
  }

  // ---------------------------------------------------------------------
  // Subtitles
  // ---------------------------------------------------------------------

  static bool _langMatches(String? value, String lang) {
    if (value == null) return false;
    final v = value.toLowerCase();
    final l = lang.toLowerCase();
    const alias = {'tr': ['tur', 'turkish', 'türkçe'], 'en': ['eng', 'english']};
    return v == l || v.startsWith('$l-') || (alias[l]?.contains(v) ?? false);
  }

  /// Saves one UTF-8 SRT next to the video: a stream-provided track in the
  /// preferred language, else the best online match, else English.
  Future<void> _fetchSubtitle(DownloadItem item, Directory dir) async {
    final existing = item.localSubtitlePath;
    if (existing != null && existing.isNotEmpty && File(existing).existsSync()) {
      return;
    }
    final preferred = item.subtitleLanguage.isEmpty ? 'tr' : item.subtitleLanguage;
    final languages = preferred == 'en' ? ['en'] : [preferred, 'en'];

    for (final lang in languages) {
      final fromStream = item.streamSubtitles
          .where((s) => _langMatches(s['language'], lang) || _langMatches(s['label'], lang))
          .firstOrNull;
      String? url = fromStream?['url'];
      String? format = fromStream?['format'];
      Map<String, String> headers = fromStream != null ? _headersFor(item) : {'User-Agent': _userAgent};

      if (url == null) {
        final repo = _subtitles;
        if (repo == null) continue;
        final imdbId = await repo.resolveImdbId(
          mediaId: item.mediaId,
          mediaType: item.mediaType,
          streamUrl: item.streamUrl,
        );
        if (imdbId == null || imdbId.isEmpty) continue;
        final result = await repo.findBestSubtitle(
          imdbId: imdbId,
          mediaType: item.mediaType,
          season: item.season ?? 1,
          episode: item.episode ?? 1,
          languageCode: lang,
          releaseHint: item.title,
        );
        if (result == null || result.url.isEmpty) continue;
        url = result.url;
        format = result.format;
      }

      try {
        final res = await _dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes, headers: headers),
        );
        final doc = SubtitleEngine.parseBytes(res.data ?? const [], format: format);
        if (doc.isEmpty) continue;
        final path = '${dir.path}/subtitle.$lang.srt';
        await File(path).writeAsString(doc.toSrt());
        final latest = getItem(item.id) ?? item;
        await saveItem(latest.copyWith(localSubtitlePath: path));
        return;
      } catch (e) {
        debugPrint('Subtitle fetch ($lang) failed: $e');
      }
    }
  }

  // ---------------------------------------------------------------------
  // Cancel / delete
  // ---------------------------------------------------------------------

  /// Stops the item, waits for its task to end and removes partial files.
  Future<void> cancelDownload(String id) async {
    _queue.remove(id);
    final token = _cancelTokens[id];
    if (token != null && !token.isCancelled) token.cancel('User canceled');
    final running = _running[id];
    if (running != null) {
      try {
        await running;
      } catch (_) {}
    }
    final item = getItem(id);
    if (item != null && !item.isCompleted) {
      await saveItem(item.copyWith(status: 'canceled', speed: '', progress: 0));
      await _deleteFiles(item);
    }
    unawaited(_processQueue());
  }

  Future<void> deleteDownload(String id) async {
    final item = getItem(id);
    if (item != null && _isActive(item)) {
      await cancelDownload(id);
    }
    final latest = getItem(id);
    if (latest != null) await _deleteFiles(latest);
    _cachedItems.remove(id);
    _dirty.remove(id);
    _live.remove(id)?.value = null;
    await _box?.delete(id);
    _notify();
  }

  Future<void> _deleteFiles(DownloadItem item) async {
    try {
      final root = await getDownloadsDirectoryPath();
      final itemDir = Directory('$root/${_sanitizeFileName(item.id)}');
      if (await itemDir.exists()) await itemDir.delete(recursive: true);
      // Layout before 1.0.29: files in the root and a "<id>_hls" folder.
      for (final path in [item.localVideoPath, item.localSubtitlePath]) {
        if (path == null || path.isEmpty) continue;
        final file = File(path);
        if (await file.exists()) await file.delete();
        final parent = file.parent;
        if (parent.path != root && parent.path.endsWith('_hls') && await parent.exists()) {
          await parent.delete(recursive: true);
        }
      }
    } catch (e) {
      debugPrint('Delete download files failed: $e');
    }
  }

  void dispose() {
    _flushDirty();
    _persistTimer?.cancel();
    _crypto.dispose();
    _itemsStreamController.close();
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '0 KB/s';
    if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(0)} KB/s';
    }
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(1)} ${suffixes[i]}';
  }
}
