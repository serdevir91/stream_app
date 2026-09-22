import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter/foundation.dart' hide Key;
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/backend/extractors/vixsrc_extractor.dart';
import '../../../../core/subtitles/online_subtitle_repository.dart';
import '../../domain/entities/download_item.dart';

class DownloadService {
  static const String boxName = 'downloads_box';
  final Dio _dio;
  final OnlineSubtitleRepository? _subtitleRepo;
  final VixSrcExtractor _vixSrcExtractor;
  Box? _box;

  final Map<String, DownloadItem> _cachedItems = {};
  final Map<String, CancelToken> _cancelTokens = {};
  final Set<String> _canceledItemIds = {};
  final List<String> _downloadQueue = [];
  final Set<String> _activeRunningIds = {};
  static const int maxConcurrentDownloads = 1;

  final StreamController<List<DownloadItem>> _itemsStreamController =
      StreamController<List<DownloadItem>>.broadcast();

  DateTime _lastNotifyTime = DateTime.now();

  DownloadService({
    Dio? dio,
    OnlineSubtitleRepository? subtitleRepo,
    VixSrcExtractor? vixSrcExtractor,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(minutes: 60),
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                },
              ),
            ),
        _subtitleRepo = subtitleRepo,
        _vixSrcExtractor = vixSrcExtractor ?? VixSrcExtractor(dio: dio);

  Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) {
      _box = await Hive.openBox(boxName);
    } else {
      _box = Hive.box(boxName);
    }
    _loadCacheFromBox();
  }

  void _loadCacheFromBox() {
    if (_box == null) return;
    _cachedItems.clear();
    for (final raw in _box!.values) {
      if (raw is Map) {
        try {
          final item = DownloadItem.fromMap(raw);
          _cachedItems[item.id] = item;
          if (item.status == 'queued') {
            if (!_downloadQueue.contains(item.id)) {
              _downloadQueue.add(item.id);
            }
          }
        } catch (_) {}
      }
    }
  }

  Stream<List<DownloadItem>> watchDownloads() {
    return _itemsStreamController.stream;
  }

  void _notify({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastNotifyTime).inMilliseconds < 750) {
      return;
    }
    _lastNotifyTime = now;
    if (!_itemsStreamController.isClosed) {
      _itemsStreamController.add(getAllDownloads());
    }
  }

  List<DownloadItem> getAllDownloads() {
    final items = _cachedItems.values.toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  DownloadItem? getItem(String id) {
    return _cachedItems[id];
  }

  Future<void> saveItem(DownloadItem item, {bool immediateDbWrite = true}) async {
    _cachedItems[item.id] = item;
    if (immediateDbWrite) {
      if (_box == null) await init();
      await _box!.put(item.id, item.toMap());
    }
    _notify(force: immediateDbWrite);
  }

  Future<String> getDownloadsDirectoryPath() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final downloadsDir = Directory('${baseDir.path}/downloads');
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }
    return downloadsDir.path;
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  bool _isDirectVideoLink(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('vixsrc') ||
        lower.contains('embed') ||
        lower.contains('cinesrc') ||
        lower.contains('vidsrc') ||
        lower.contains('playlist') ||
        lower.contains('.m3u8')) {
      return false;
    }
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mov');
  }

  Future<void> startDownload(DownloadItem item) async {
    if (_box == null) await init();

    // Check if this item is already active
    if (_activeRunningIds.contains(item.id)) return;

    // If concurrency limit reached, add to queue
    if (_activeRunningIds.length >= maxConcurrentDownloads) {
      final queuedItem = item.copyWith(
        status: 'queued',
        speed: '',
      );
      if (!_downloadQueue.contains(item.id)) {
        _downloadQueue.add(item.id);
      }
      await saveItem(queuedItem, immediateDbWrite: true);
      return;
    }

    _downloadQueue.remove(item.id);
    _activeRunningIds.add(item.id);

    unawaited(_executeDownload(item));
  }

  Future<void> _processQueue() async {
    while (_activeRunningIds.length < maxConcurrentDownloads && _downloadQueue.isNotEmpty) {
      final nextId = _downloadQueue.removeAt(0);
      final nextItem = getItem(nextId);
      if (nextItem != null && nextItem.status == 'queued') {
        _activeRunningIds.add(nextId);
        unawaited(_executeDownload(nextItem));
      }
    }
  }

  Future<void> _executeDownload(DownloadItem item) async {
    final dirPath = await getDownloadsDirectoryPath();
    final safeBase = _sanitizeFileName(item.id);
    final ext = item.streamUrl.contains('.mkv') ? '.mkv' : '.mp4';
    final videoPath = '$dirPath/$safeBase$ext';

    _canceledItemIds.remove(item.id);
    final cancelToken = CancelToken();
    _cancelTokens[item.id] = cancelToken;

    var currentItem = item.copyWith(
      status: 'downloading',
      progress: 0.0,
      downloadedBytes: 0,
      speed: '0 KB/s',
      localVideoPath: videoPath,
      errorMessage: null,
    );
    await saveItem(currentItem, immediateDbWrite: true);

    // 1. Asynchronously fetch & save subtitle if repository is present
    unawaited(_fetchAndSaveSubtitle(currentItem, dirPath, safeBase));

    // 2. Execute download strategy
    try {
      if (_isDirectVideoLink(item.streamUrl)) {
        await _downloadDirectFile(currentItem, videoPath, cancelToken);
      } else {
        await _downloadHlsStream(currentItem, dirPath, safeBase, cancelToken);
      }
    } catch (e) {
      if (cancelToken.isCancelled || _canceledItemIds.contains(item.id)) {
        currentItem = currentItem.copyWith(
          status: 'canceled',
          speed: '',
        );
      } else {
        currentItem = currentItem.copyWith(
          status: 'failed',
          errorMessage: e.toString(),
          speed: '',
        );
      }
      await saveItem(currentItem, immediateDbWrite: true);
    } finally {
      _cancelTokens.remove(item.id);
      _canceledItemIds.remove(item.id);
      _activeRunningIds.remove(item.id);
      unawaited(_processQueue());
    }
  }

  Future<void> _downloadDirectFile(
    DownloadItem item,
    String videoPath,
    CancelToken cancelToken,
  ) async {
    var currentItem = item;
    int lastBytes = 0;
    DateTime lastTime = DateTime.now();

    await _dio.download(
      currentItem.streamUrl,
      videoPath,
      cancelToken: cancelToken,
      deleteOnError: true,
      onReceiveProgress: (received, total) {
        if (cancelToken.isCancelled) return;

        final now = DateTime.now();
        final elapsedMs = now.difference(lastTime).inMilliseconds;
        String speedStr = currentItem.speed;

        if (elapsedMs >= 800) {
          final deltaBytes = received - lastBytes;
          final bytesPerSec = (deltaBytes / (elapsedMs / 1000.0));
          speedStr = _formatSpeed(bytesPerSec);
          lastBytes = received;
          lastTime = now;
        }

        final progress = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;

        currentItem = currentItem.copyWith(
          status: 'downloading',
          progress: progress,
          downloadedBytes: received,
          totalBytes: total > 0 ? total : currentItem.totalBytes,
          speed: speedStr,
        );
        saveItem(currentItem, immediateDbWrite: false);
      },
    );

    final downloadedFile = File(videoPath);
    final exists = await downloadedFile.exists();
    final fileSize = exists ? await downloadedFile.length() : 0;

    if (exists && fileSize > 0) {
      currentItem = currentItem.copyWith(
        status: 'completed',
        progress: 1.0,
        downloadedBytes: fileSize,
        totalBytes: fileSize,
        speed: '',
      );
    } else {
      currentItem = currentItem.copyWith(
        status: 'failed',
        errorMessage: 'Dosya indirilemedi veya boş.',
        speed: '',
      );
    }
    await saveItem(currentItem, immediateDbWrite: true);
  }

  Future<void> _downloadHlsStream(
    DownloadItem item,
    String dirPath,
    String safeBase,
    CancelToken cancelToken,
  ) async {
    var currentItem = item;

    // 1. Resolve direct HLS stream via VixSrcExtractor
    final vixRes = await _vixSrcExtractor.extract(
      tmdbId: item.mediaId,
      mediaType: item.mediaType,
      season: item.season,
      episode: item.episode,
    );

    if (vixRes == null || vixRes.videoVariants.isEmpty) {
      throw Exception('HLS akış kaynağı çözülemedi (VixSrc).');
    }

    if (cancelToken.isCancelled || _canceledItemIds.contains(item.id)) return;

    final videoVariant = vixRes.getBestVideoVariant(item.quality) ?? vixRes.videoVariants.first;
    final audioVariant = vixRes.getAudioTrack('eng') ??
        (vixRes.audioTracks.isNotEmpty ? vixRes.audioTracks.first : null);

    final videoDetails = await _vixSrcExtractor.parsePlaylistDetails(videoVariant.url);
    if (videoDetails == null || videoDetails.segmentUrls.isEmpty) {
      throw Exception('Video segment listesi alınamadı.');
    }

    final audioDetails = audioVariant != null
        ? await _vixSrcExtractor.parsePlaylistDetails(audioVariant.url)
        : null;

    if (cancelToken.isCancelled || _canceledItemIds.contains(item.id)) return;

    // 2. Fetch encryption key
    final keyUrl = videoDetails.keyUrl ?? 'https://vixsrc.to/storage/enc.key';
    final keyRes = await _dio.get<List<int>>(
      keyUrl,
      options: Options(responseType: ResponseType.bytes),
      cancelToken: cancelToken,
    );
    if (keyRes.data == null || keyRes.data!.isEmpty) {
      throw Exception('Akış şifre çözme anahtarı alınamadı.');
    }

    final keyBytes = Uint8List.fromList(keyRes.data!);
    final vIvBytes = _parseIvBytes(videoDetails.ivHex);
    final aIvBytes = _parseIvBytes(audioDetails?.ivHex);

    // 3. Prepare local HLS directory
    final itemDir = Directory('$dirPath/${safeBase}_hls');
    if (!await itemDir.exists()) {
      await itemDir.create(recursive: true);
    }

    final totalVideoSegs = videoDetails.segmentUrls.length;
    final totalAudioSegs = audioDetails?.segmentUrls.length ?? 0;
    final totalSegs = totalVideoSegs + totalAudioSegs;

    int completedSegs = 0;
    int totalBytesAccum = 0;
    int lastBytes = 0;
    DateTime lastTime = DateTime.now();
    String currentSpeed = '0 KB/s';

    // 4. Download and decrypt video segments with concurrency limit
    // Reduced concurrency from 4 to 2 to minimize network & device resource strain
    const int concurrency = 2;

    Future<void> runBatchWorkers(
      List<String> urls,
      String prefix,
      Uint8List ivBytes,
    ) async {
      int nextIdx = 0;

      Future<void> worker() async {
        while (nextIdx < urls.length) {
          if (cancelToken.isCancelled || _canceledItemIds.contains(item.id)) {
            return;
          }
          final idx = nextIdx++;
          final segUrl = urls[idx];
          final targetSegPath = '${itemDir.path}/${prefix}_$idx.ts';

          try {
            final segRes = await _dio.get<List<int>>(
              segUrl,
              options: Options(responseType: ResponseType.bytes),
              cancelToken: cancelToken,
            );

            if (segRes.data != null && segRes.data!.isNotEmpty) {
              // Offload AES decryption and file write to background isolate
              final decLength = await _decryptAndWriteSegmentBackground(
                encryptedBytes: Uint8List.fromList(segRes.data!),
                keyBytes: keyBytes,
                ivBytes: ivBytes,
                targetFilePath: targetSegPath,
              );
              totalBytesAccum += decLength;
            }
          } catch (e) {
            if (cancelToken.isCancelled || _canceledItemIds.contains(item.id)) return;
            // Retry once on failure
            try {
              final retryRes = await _dio.get<List<int>>(
                segUrl,
                options: Options(responseType: ResponseType.bytes),
                cancelToken: cancelToken,
              );
              if (retryRes.data != null && retryRes.data!.isNotEmpty) {
                final decLength = await _decryptAndWriteSegmentBackground(
                  encryptedBytes: Uint8List.fromList(retryRes.data!),
                  keyBytes: keyBytes,
                  ivBytes: ivBytes,
                  targetFilePath: targetSegPath,
                );
                totalBytesAccum += decLength;
              }
            } catch (_) {}
          }

          completedSegs++;
          final now = DateTime.now();
          final elapsedMs = now.difference(lastTime).inMilliseconds;
          if (elapsedMs >= 800) {
            final deltaBytes = totalBytesAccum - lastBytes;
            final bytesPerSec = (deltaBytes / (elapsedMs / 1000.0));
            currentSpeed = _formatSpeed(bytesPerSec);
            lastBytes = totalBytesAccum;
            lastTime = now;

            final progress = totalSegs > 0 ? (completedSegs / totalSegs).clamp(0.0, 0.95) : 0.0;
            currentItem = currentItem.copyWith(
              progress: progress,
              downloadedBytes: totalBytesAccum,
              speed: currentSpeed,
            );
            saveItem(currentItem, immediateDbWrite: false);
          }
        }
      }

      final workers = List.generate(
        concurrency,
        (_) => worker(),
      );
      await Future.wait(workers);
    }

    // Download video segments
    await runBatchWorkers(videoDetails.segmentUrls, 'v', vIvBytes);
    if (cancelToken.isCancelled || _canceledItemIds.contains(item.id)) return;

    // Download audio segments
    if (audioDetails != null && audioDetails.segmentUrls.isNotEmpty) {
      await runBatchWorkers(audioDetails.segmentUrls, 'a', aIvBytes);
    }
    if (cancelToken.isCancelled || _canceledItemIds.contains(item.id)) return;

    // 5. Write local M3U8 playlists
    // video.m3u8
    final vM3u8 = StringBuffer('#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:10\n#EXT-X-PLAYLIST-TYPE:VOD\n');
    for (int i = 0; i < videoDetails.segmentUrls.length; i++) {
      final dur = i < videoDetails.segmentDurations.length ? videoDetails.segmentDurations[i] : 8.0;
      vM3u8.writeln('#EXTINF:$dur,');
      vM3u8.writeln('v_$i.ts');
    }
    vM3u8.writeln('#EXT-X-ENDLIST');
    await File('${itemDir.path}/video.m3u8').writeAsString(vM3u8.toString());

    // audio.m3u8
    if (audioDetails != null && audioDetails.segmentUrls.isNotEmpty) {
      final aM3u8 = StringBuffer('#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:10\n#EXT-X-PLAYLIST-TYPE:VOD\n');
      for (int i = 0; i < audioDetails.segmentUrls.length; i++) {
        final dur = i < audioDetails.segmentDurations.length ? audioDetails.segmentDurations[i] : 8.0;
        aM3u8.writeln('#EXTINF:$dur,');
        aM3u8.writeln('a_$i.ts');
      }
      aM3u8.writeln('#EXT-X-ENDLIST');
      await File('${itemDir.path}/audio.m3u8').writeAsString(aM3u8.toString());
    }

    // master.m3u8
    final masterBuffer = StringBuffer('#EXTM3U\n');
    if (audioDetails != null && audioDetails.segmentUrls.isNotEmpty) {
      masterBuffer.writeln(
        '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE="eng",URI="audio.m3u8"',
      );
      masterBuffer.writeln(
        '#EXT-X-STREAM-INF:BANDWIDTH=${videoVariant.bandwidth},RESOLUTION=${videoVariant.resolution ?? "1280x720"},AUDIO="audio"',
      );
    } else {
      masterBuffer.writeln(
        '#EXT-X-STREAM-INF:BANDWIDTH=${videoVariant.bandwidth},RESOLUTION=${videoVariant.resolution ?? "1280x720"}',
      );
    }
    masterBuffer.writeln('video.m3u8');
    final masterPath = '${itemDir.path}/master.m3u8';
    await File(masterPath).writeAsString(masterBuffer.toString());

    // 6. Remux to MP4 if ffmpeg is available on system
    bool ffmpegRemuxSuccess = false;
    final finalMp4Path = '$dirPath/$safeBase.mp4';

    try {
      final remuxRes = await Process.run('ffmpeg', [
        '-y',
        '-protocol_whitelist',
        'file,crypto,data',
        '-i',
        masterPath,
        '-c',
        'copy',
        '-movflags',
        '+faststart',
        finalMp4Path,
      ]);

      if (remuxRes.exitCode == 0) {
        final mp4File = File(finalMp4Path);
        if (await mp4File.exists() && (await mp4File.length()) > 1000) {
          ffmpegRemuxSuccess = true;
          try {
            await itemDir.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {
      ffmpegRemuxSuccess = false;
    }

    final finalLocalPath = ffmpegRemuxSuccess ? finalMp4Path : masterPath;
    final finalFile = File(finalLocalPath);
    final finalSize = await finalFile.exists() ? await finalFile.length() : totalBytesAccum;

    currentItem = currentItem.copyWith(
      status: 'completed',
      progress: 1.0,
      downloadedBytes: finalSize,
      totalBytes: finalSize,
      speed: '',
      localVideoPath: finalLocalPath,
    );
    await saveItem(currentItem, immediateDbWrite: true);
  }

  static Uint8List _parseIvBytes(String? hex) {
    final bytes = Uint8List(16);
    if (hex != null && hex.length >= 32) {
      for (int i = 0; i < 16; i++) {
        bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      }
    }
    return bytes;
  }

  /// Runs AES-CBC decryption and direct disk write in a background isolate
  /// so Flutter's main UI thread is completely unaffected.
  static Future<int> _decryptAndWriteSegmentBackground({
    required Uint8List encryptedBytes,
    required Uint8List keyBytes,
    required Uint8List ivBytes,
    required String targetFilePath,
  }) async {
    return await Isolate.run(() async {
      final key = Key(keyBytes);
      final iv = IV(ivBytes);
      final encrypter = Encrypter(AES(key, mode: AESMode.cbc, padding: null));
      final decrypted = encrypter.decryptBytes(
        Encrypted(encryptedBytes),
        iv: iv,
      );
      final file = File(targetFilePath);
      await file.writeAsBytes(decrypted);
      return decrypted.length;
    });
  }

  Future<void> _fetchAndSaveSubtitle(
    DownloadItem item,
    String dirPath,
    String safeBase,
  ) async {
    if (_subtitleRepo == null) return;
    try {
      final imdbId = await _subtitleRepo.resolveImdbId(
        mediaId: item.mediaId,
        mediaType: item.mediaType,
        streamUrl: item.streamUrl,
      );

      if (imdbId == null || imdbId.isEmpty) return;

      final subtitleResult = await _subtitleRepo.findBestSubtitle(
        imdbId: imdbId,
        mediaType: item.mediaType,
        season: item.season ?? 1,
        episode: item.episode ?? 1,
        languageCode: item.subtitleLanguage,
      );

      if (subtitleResult != null && subtitleResult.url.isNotEmpty) {
        final subPath = '$dirPath/$safeBase.srt';
        final subResponse = await _dio.get<List<int>>(
          subtitleResult.url,
          options: Options(responseType: ResponseType.bytes),
        );
        if (subResponse.data != null && subResponse.data!.isNotEmpty) {
          final content = _decodeTurkishSubtitleBytes(subResponse.data!);
          final subFile = File(subPath);
          await subFile.writeAsString(content);

          final latest = getItem(item.id);
          if (latest != null) {
            await saveItem(latest.copyWith(localSubtitlePath: subPath), immediateDbWrite: true);
          }
        }
      }
    } catch (e) {
      debugPrint('Auto subtitle download failed: $e');
    }
  }

  static String _decodeTurkishSubtitleBytes(List<int> bytes) {
    if (bytes.isEmpty) return '';
    List<int> raw = bytes;
    if (raw.length > 2 && raw[0] == 0x1f && raw[1] == 0x8b) {
      try {
        raw = gzip.decode(raw);
      } catch (_) {}
    }
    String text;
    try {
      text = utf8.decode(raw);
    } catch (_) {
      try {
        text = latin1.decode(raw);
      } catch (_) {
        text = String.fromCharCodes(raw);
      }
    }

    const mojibakeMap = <String, String>{
      'Ã§': 'ç', 'Ã‡': 'Ç',
      'Ã¶': 'ö', 'Ã–': 'Ö',
      'Ã¼': 'ü', 'Ãœ': 'Ü',
      'ÄŸ': 'ğ', 'Äž': 'Ğ',
      'Ä±': 'ı', 'Ä°': 'İ',
      'ÅŸ': 'ş', 'Åž': 'Ş',
      'Ã½': 'ı', 'Ã ': 'à', 'Ã©': 'é',
      'ð': 'ğ', 'Ð': 'Ğ',
      'ý': 'ı', 'Ý': 'İ',
      'þ': 'ş', 'Þ': 'Ş',
      'Ãž': 'Ş',
    };

    mojibakeMap.forEach((wrong, correct) {
      text = text.replaceAll(wrong, correct);
    });

    return text;
  }

  Future<void> cancelDownload(String id) async {
    _canceledItemIds.add(id);
    _downloadQueue.remove(id);
    final token = _cancelTokens[id];
    if (token != null && !token.isCancelled) {
      token.cancel('User canceled');
    }
    final item = getItem(id);
    if (item != null) {
      await saveItem(item.copyWith(status: 'canceled', speed: ''), immediateDbWrite: true);
    }
    _activeRunningIds.remove(id);
    unawaited(_processQueue());
  }

  Future<void> deleteDownload(String id) async {
    await cancelDownload(id);
    final item = getItem(id);
    if (item != null) {
      try {
        if (item.localVideoPath.isNotEmpty) {
          final videoFile = File(item.localVideoPath);
          if (await videoFile.exists()) {
            await videoFile.delete();
          }
          final parentDir = videoFile.parent;
          if (parentDir.path.endsWith('${_sanitizeFileName(item.id)}_hls') &&
              await parentDir.exists()) {
            await parentDir.delete(recursive: true);
          }
        }
      } catch (_) {}
      try {
        if (item.localSubtitlePath != null && item.localSubtitlePath!.isNotEmpty) {
          final subFile = File(item.localSubtitlePath!);
          if (await subFile.exists()) {
            await subFile.delete();
          }
        }
      } catch (_) {}
    }
    _cachedItems.remove(id);
    if (_box != null) {
      await _box!.delete(id);
    }
    _notify(force: true);
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
