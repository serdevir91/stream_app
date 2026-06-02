import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:audio_session/audio_session.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:video_player/video_player.dart' as vp;
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as windows_webview;

import '../../../../core/backend/addon_service_provider.dart';
import '../../../../core/subtitles/online_subtitle_repository.dart';
import '../../../../core/i18n/app_text.dart';

import '../providers/player_provider.dart';
import '../../domain/entities/watch_history.dart';
import '../../../../core/settings/app_settings_provider.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final String mediaId;
  final String title;
  final String type; // 'movie' or 'tv'
  final int season;
  final int episode;
  final String? posterUrl;
  final String? backdropUrl;
  final String? sourceId;
  final String? initialStreamUrl;
  final String? initialProvider;
  final bool initialIsDirectLink;
  final String subtitleLanguage;
  final int? runtimeMinutes;
  final int? nextSeasonNumber;
  final int? nextEpisodeNumber;
  final String? nextEpisodeTitle;
  final int? totalEpisodesInSeason;
  final bool preferAnimeSources;

  const PlayerScreen({
    super.key,
    required this.mediaId,
    required this.title,
    required this.type,
    this.season = 1,
    this.episode = 1,
    this.posterUrl,
    this.backdropUrl,
    this.sourceId,
    this.initialStreamUrl,
    this.initialProvider,
    this.initialIsDirectLink = true,
    this.subtitleLanguage = 'tr',
    this.runtimeMinutes,
    this.nextSeasonNumber,
    this.nextEpisodeNumber,
    this.nextEpisodeTitle,
    this.totalEpisodesInSeason,
    this.preferAnimeSources = false,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  static const MethodChannel _androidWebViewChannel = MethodChannel(
    'stream_app/android_webview',
  );

  Player? _player;
  VideoController? _videoController;
  WebViewController? _embedWebViewController;
  windows_webview.WebviewController? _windowsEmbedController;
  bool _isDirectLink = true;
  bool _isDisposed = false;
  bool _isLoading = true;
  String? _errorMessageKey;
  String? _errorMessageParam;
  String _loadingStatusKey = 'searching_video_source';
  bool _initialized = false;
  String? _embedUrl;
  int _embedLoadAttempt = 0;
  int _directFallbackAttempt = 0;
  int _directAutoplayAttempt = 0;
  Timer? _progressAutosaveTimer;
  final Stopwatch _embedWatchStopwatch = Stopwatch();
  int _embedPositionOffsetMs = 0;
  int? _lastEmbedPositionMs;
  int? _lastEmbedDurationMs;
  bool _embedVideoPaused = true;
  String? _currentStreamUrl;
  int _savedPositionMs = 0;
  vp.VideoPlayerController? _nativeController;
  int _selectedSubtitleTrackIndex = -1;
  OnlineSubtitleResult? _activeOnlineSubtitle;
  bool _nativeSubtitlesEnabled = true;
  bool _embedSubtitlesEnabled = true;
  List<vp.Caption> _embedCaptions = const [];
  String _embedCaptionText = '';
  Timer? _embedSubtitleTimer;
  bool _embedSubtitleTickRunning = false;

  String get _selectedVideoPlayer {
    try {
      return ref.read(appSettingsProvider).videoPlayer;
    } catch (_) {
      return 'native';
    }
  }

  bool get _useNativePlayer => _selectedVideoPlayer == 'native';
  bool get _forceWebView => _selectedVideoPlayer == 'webview';

  Set<String> _trustedEmbedHosts = const {};
  bool _showOverlayControls = true;
  Timer? _overlayControlsTimer;
  bool _showNextEpisodeOverlay = false;
  bool _nextEpisodeDismissed = false;

  bool _isSeriesType(String value) {
    final type = value.trim().toLowerCase();
    return type == 'tv' || type == 'series' || type == 'show';
  }

  String get _normalizedMediaType =>
      _isSeriesType(widget.type) ? 'tv' : 'movie';

  String get _backendMediaType =>
      _isSeriesType(widget.type) ? 'series' : 'movie';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterFullscreenMode();
    _armControlsAutoHide();
    _configureAudioSession();
    WakelockPlus.enable();
  }

  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionMode: AVAudioSessionMode.moviePlayback,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.movie,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: true,
        ),
      );
    } catch (e) {
      debugPrint('Audio session config failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _stopAllPlayback();
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_isDirectLink) {
        if (_nativeController != null) {
          try {
            _nativeController?.pause();
          } catch (_) {}
        } else if (_player != null) {
          try {
            _savedPositionMs = _player!.state.position.inMilliseconds;
          } catch (_) {}
          _progressAutosaveTimer?.cancel();
          try {
            _player?.stop();
          } catch (_) {}
          try {
            _player?.dispose();
          } catch (_) {}
          setState(() {
            _player = null;
            _videoController = null;
          });
        }
      } else {
        // Embed: just pause the video via JS, don't destroy the WebView.
        _pauseEmbedPlayback();
      }
    }
    if (state == AppLifecycleState.resumed) {
      _enterFullscreenMode();
      if (_isDirectLink) {
        if (_nativeController != null) {
          try {
            _nativeController?.play();
          } catch (_) {}
        } else if (_player == null && _currentStreamUrl != null) {
          _reinitializeDirectPlayer();
        }
      } else {
        // Embed: resume the video via JS.
        _resumeEmbedPlayback();
      }
    }
  }

  /// Pauses embed video without destroying the WebView content.
  void _pauseEmbedPlayback() {
    const js =
        'document.querySelectorAll("video,audio").forEach(e=>e.pause());';
    try {
      _embedWebViewController?.runJavaScript(js);
    } catch (_) {}
    try {
      _windowsEmbedController?.executeScript(js);
    } catch (_) {}
  }

  /// Resumes embed video playback after returning from background.
  void _resumeEmbedPlayback() {
    const js =
        'document.querySelectorAll("video").forEach(e=>{if(e.paused)e.play().catch(()=>{})});';
    try {
      _embedWebViewController?.runJavaScript(js);
    } catch (_) {}
    try {
      _windowsEmbedController?.executeScript(js);
    } catch (_) {}
  }

  void _reinitializeDirectPlayer() {
    final url = _currentStreamUrl;
    if (url == null || url.isEmpty || _isDisposed) return;

    if (_useNativePlayer) {
      unawaited(
        _initNativePlayer(
          url,
          seekMs: _savedPositionMs,
        ).then((_) => _attachOnlineSubtitle(url)),
      );
    } else {
      final player = Player();
      final controller = VideoController(player);
      setState(() {
        _player = player;
        _videoController = controller;
        _isLoading = false;
      });
      player.open(Media(url), play: true);
      _ensureDirectPlaybackStarts(player);
      _startProgressAutosave();
      if (_savedPositionMs > 0) {
        _seekAfterReady(player, _savedPositionMs);
      }
      unawaited(_attachOnlineSubtitle(url));
    }
  }

  Future<void> _initNativePlayer(
    String url, {
    int seekMs = 0,
    Map<String, String>? headers,
  }) async {
    final prevNative = _nativeController;
    _nativeController = null;
    if (prevNative != null) {
      try {
        await prevNative.dispose();
      } catch (_) {}
    }

    final uri = Uri.parse(url);
    final ctrl = vp.VideoPlayerController.networkUrl(
      uri,
      httpHeaders: headers ?? const {},
    );
    try {
      await ctrl.initialize();
      if (_isDisposed) {
        ctrl.dispose();
        return;
      }
      if (seekMs > 0) {
        await ctrl.seekTo(Duration(milliseconds: seekMs));
      }
      await ctrl.play();
      setState(() {
        _nativeController = ctrl;
        _isLoading = false;
      });
      _startProgressAutosave();
    } catch (e) {
      debugPrint('Native player init failed: $e');
      ctrl.dispose();
      // Fallback to media_kit
      final player = Player();
      final controller = VideoController(player);
      setState(() {
        _player = player;
        _videoController = controller;
        _isLoading = false;
      });
      player.open(Media(url, httpHeaders: headers), play: true);
      _ensureDirectPlaybackStarts(player);
      _startProgressAutosave();
    }
  }

  Future<void> _attachOnlineSubtitle(String streamUrl) async {
    if (_isDisposed || !_isDirectLink) return;
    final settings = ref.read(appSettingsProvider);
    if (!settings.autoSelectSubtitle) return;

    final repo = ref.read(onlineSubtitleRepositoryProvider);
    final imdbId = await repo.resolveImdbId(
      mediaId: widget.mediaId,
      mediaType: _normalizedMediaType,
      streamUrl: streamUrl,
    );
    if (imdbId == null || _isDisposed || _currentStreamUrl != streamUrl) {
      return;
    }

    final subtitle = await repo.findBestSubtitle(
      imdbId: imdbId,
      mediaType: _normalizedMediaType,
      season: widget.season,
      episode: widget.episode,
      languageCode: widget.subtitleLanguage,
    );
    if (subtitle == null || _isDisposed || _currentStreamUrl != streamUrl) {
      return;
    }

    setState(() {
      _activeOnlineSubtitle = subtitle;
      _nativeSubtitlesEnabled = true;
    });

    final player = _player;
    if (player != null) {
      try {
        await player.setSubtitleTrack(
          SubtitleTrack.uri(
            subtitle.url,
            title: subtitle.label,
            language: subtitle.languageCode,
          ),
        );
        if (mounted) {
          setState(() {
            _selectedSubtitleTrackIndex = -2;
          });
        }
      } catch (e) {
        debugPrint('Media Kit subtitle attach failed: $e');
      }
      return;
    }

    await _applyNativeSubtitle(subtitle);
  }

  Future<void> _attachOnlineSubtitleToEmbed(
    String streamUrl,
    String expectedEmbedUrl,
  ) async {
    if (_isDisposed || _isDirectLink) return;
    final settings = ref.read(appSettingsProvider);
    if (!settings.autoSelectSubtitle) return;

    final repo = ref.read(onlineSubtitleRepositoryProvider);
    final imdbId = await repo.resolveImdbId(
      mediaId: widget.mediaId,
      mediaType: _normalizedMediaType,
      streamUrl: streamUrl,
    );
    if (imdbId == null || _isDisposed || _embedUrl != expectedEmbedUrl) {
      return;
    }

    final subtitle = await repo.findBestSubtitle(
      imdbId: imdbId,
      mediaType: _normalizedMediaType,
      season: widget.season,
      episode: widget.episode,
      languageCode: widget.subtitleLanguage,
    );
    if (subtitle == null || _isDisposed || _embedUrl != expectedEmbedUrl) {
      return;
    }

    try {
      final captionFile = await _loadClosedCaptionFile(subtitle);
      if (_isDisposed || _embedUrl != expectedEmbedUrl) return;
      setState(() {
        _activeOnlineSubtitle = subtitle;
        _embedCaptions = captionFile.captions;
        _embedSubtitlesEnabled = true;
        _embedCaptionText = '';
      });
      await _disableEmbedProviderSubtitles();
      _startEmbedSubtitleTimer();
    } catch (e) {
      debugPrint('Embed subtitle attach failed: $e');
    }
  }

  Future<void> _disableEmbedProviderSubtitles() async {
    const script = '''
      (function() {
        function disableIn(root) {
          try {
            var doc = root.document;
            doc.querySelectorAll('video track').forEach(function(track) {
              try { track.track.mode = 'disabled'; } catch (e) {}
              try { track.mode = 'disabled'; } catch (e) {}
            });
            doc.querySelectorAll('.subtitles,#subtitles,.subtitle-text,#subtitleText').forEach(function(el) {
              el.style.setProperty('display', 'none', 'important');
              el.style.setProperty('visibility', 'hidden', 'important');
              el.style.setProperty('opacity', '0', 'important');
            });
          } catch (e) {}
        }
        disableIn(window);
        try {
          document.querySelectorAll('iframe').forEach(function(frame) {
            try {
              if (frame.contentWindow) disableIn(frame.contentWindow);
            } catch (e) {}
          });
        } catch (e) {}
      })();
    ''';
    try {
      await _embedWebViewController?.runJavaScript(script);
    } catch (_) {}
    try {
      await _windowsEmbedController?.executeScript(script);
    } catch (_) {}
  }

  Future<void> _applyNativeSubtitle(OnlineSubtitleResult subtitle) async {
    final controller = _nativeController;
    if (controller == null) return;
    try {
      await controller.setClosedCaptionFile(_loadClosedCaptionFile(subtitle));
    } catch (e) {
      debugPrint('Native subtitle attach failed: $e');
    }
  }

  Future<vp.ClosedCaptionFile> _loadClosedCaptionFile(
    OnlineSubtitleResult subtitle,
  ) async {
    final response = await Dio().get<String>(
      subtitle.url,
      options: Options(
        responseType: ResponseType.plain,
        receiveTimeout: const Duration(seconds: 12),
        sendTimeout: const Duration(seconds: 8),
      ),
    );
    final content = response.data ?? '';
    if (subtitle.format.toLowerCase() == 'vtt' ||
        content.trimLeft().startsWith('WEBVTT')) {
      return vp.WebVTTCaptionFile(content);
    }
    return vp.SubRipCaptionFile(content);
  }

  void _startEmbedSubtitleTimer() {
    _embedSubtitleTimer?.cancel();
    if (_embedCaptions.isEmpty) return;
    _embedSubtitleTimer = Timer.periodic(const Duration(milliseconds: 500), (
      _,
    ) {
      if (_embedSubtitleTickRunning || _isDisposed || _isDirectLink) {
        return;
      }
      _embedSubtitleTickRunning = true;
      unawaited(_updateEmbedSubtitleText());
    });
    unawaited(_updateEmbedSubtitleText());
  }

  Future<void> _updateEmbedSubtitleText() async {
    try {
      if (_embedCaptions.isEmpty || !_embedSubtitlesEnabled) {
        if (mounted && _embedCaptionText.isNotEmpty) {
          setState(() {
            _embedCaptionText = '';
          });
        }
        return;
      }
      final positionMs = await _getEmbedVideoPositionMs();
      final position = Duration(milliseconds: positionMs);
      final nextText = _captionTextAt(position);
      if (mounted && nextText != _embedCaptionText) {
        setState(() {
          _embedCaptionText = nextText;
        });
      }
    } catch (_) {
      // Position polling can fail during WebView navigations; the next tick retries.
    } finally {
      _embedSubtitleTickRunning = false;
    }
  }

  String _captionTextAt(Duration position) {
    for (final caption in _embedCaptions) {
      if (position >= caption.start && position <= caption.end) {
        return caption.text;
      }
    }
    return '';
  }

  Future<void> _seekAfterReady(Player player, int positionMs) async {
    for (int i = 0; i < 30; i++) {
      if (_isDisposed || _player != player) return;
      if (player.state.duration.inMilliseconds > 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (_isDisposed || _player != player) return;
    try {
      await player.seek(Duration(milliseconds: positionMs));
      await player.play();
    } catch (_) {}
  }

  void _stopAllPlayback() {
    _embedSubtitleTimer?.cancel();
    try {
      _player?.pause();
    } catch (_) {}
    try {
      _player?.stop();
    } catch (_) {}
    try {
      _nativeController?.pause();
    } catch (_) {}
    try {
      _embedWebViewController?.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}
    try {
      _embedWebViewController?.runJavaScript(
        'document.querySelectorAll("video,audio").forEach(e=>{e.pause();e.src=""});',
      );
    } catch (_) {}
    try {
      _windowsEmbedController?.postWebMessage('{"action":"pause"}');
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      if (widget.initialStreamUrl != null &&
          widget.initialStreamUrl!.isNotEmpty) {
        _initializePlayer(
          widget.initialStreamUrl!,
          provider: widget.initialProvider,
          isDirectLink: widget.initialIsDirectLink,
        );
      } else {
        _fetchStreamAndInitialize();
      }
    }
  }

  void _enterFullscreenMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  void _restoreSystemUiMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  void _armControlsAutoHide() {
    _overlayControlsTimer?.cancel();
    _overlayControlsTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showOverlayControls = false;
      });
    });
  }

  void _toggleOverlayControls() {
    setState(() {
      _showOverlayControls = !_showOverlayControls;
    });
    if (_showOverlayControls) {
      _armControlsAutoHide();
    } else {
      _overlayControlsTimer?.cancel();
    }
  }

  int _episodeRuntimeMs() {
    final runtimeMinutes =
        widget.runtimeMinutes ?? (_normalizedMediaType == 'tv' ? 45 : 120);
    return runtimeMinutes * 60 * 1000;
  }

  int get _currentEmbedPositionMs =>
      _embedPositionOffsetMs + _embedWatchStopwatch.elapsedMilliseconds;

  Future<int> _getEmbedVideoPositionMs() async {
    if (_embedVideoPaused && _lastEmbedPositionMs != null) {
      return _lastEmbedPositionMs!;
    }
    if (_lastEmbedPositionMs != null) {
      return _currentEmbedPositionMs;
    }
    const js =
        '(function(){var v=document.querySelector("video");return v?v.currentTime:0;})()';
    try {
      final result = await _embedWebViewController
          ?.runJavaScriptReturningResult(js);
      final seconds = double.tryParse(result.toString()) ?? 0;
      if (seconds > 1) return (seconds * 1000).toInt();
    } catch (_) {}
    try {
      if (_windowsEmbedController != null) {
        final result = await _windowsEmbedController?.executeScript(js);
        final seconds = double.tryParse(result.toString()) ?? 0;
        if (seconds > 1) return (seconds * 1000).toInt();
      }
    } catch (_) {}
    return _currentEmbedPositionMs;
  }

  Future<int> _getEmbedVideoDurationMs() async {
    if (_lastEmbedDurationMs != null && _lastEmbedDurationMs! > 0) {
      return _lastEmbedDurationMs!;
    }
    const js =
        '(function(){var v=document.querySelector("video");return v?v.duration:0;})()';
    try {
      final result = await _embedWebViewController
          ?.runJavaScriptReturningResult(js);
      final seconds = double.tryParse(result.toString()) ?? 0;
      if (seconds > 1) return (seconds * 1000).toInt();
    } catch (_) {}
    try {
      if (_windowsEmbedController != null) {
        final result = await _windowsEmbedController?.executeScript(js);
        final seconds = double.tryParse(result.toString()) ?? 0;
        if (seconds > 1) return (seconds * 1000).toInt();
      }
    } catch (_) {}
    return _episodeRuntimeMs();
  }

  void _handleEmbedMessage(dynamic messageData) {
    try {
      final Map<dynamic, dynamic> data;
      if (messageData is String) {
        final decoded = jsonDecode(messageData);
        if (decoded is Map) {
          data = decoded;
        } else {
          return;
        }
      } else if (messageData is Map) {
        data = messageData;
      } else {
        return;
      }

      final currentTimeSec = double.tryParse(
        data['currentTime']?.toString() ?? '',
      );
      final durationSec = double.tryParse(data['duration']?.toString() ?? '');
      final paused = data['paused'] == true;

      if (currentTimeSec != null) {
        final positionMs = (currentTimeSec * 1000).toInt();
        _lastEmbedPositionMs = positionMs;
        _embedPositionOffsetMs = positionMs;
        _embedWatchStopwatch.reset();
        if (!paused && !_isDisposed && mounted) {
          if (!_embedWatchStopwatch.isRunning) {
            _embedWatchStopwatch.start();
          }
        } else {
          if (_embedWatchStopwatch.isRunning) {
            _embedWatchStopwatch.stop();
          }
        }
      }

      if (durationSec != null && durationSec > 0) {
        _lastEmbedDurationMs = (durationSec * 1000).toInt();
      }
      _embedVideoPaused = paused;
    } catch (e) {
      debugPrint("Error handling embed message: $e");
    }
  }

  void _skipSeconds(int seconds) {
    if (_nativeController != null && _nativeController!.value.isInitialized) {
      final pos = _nativeController!.value.position;
      final dur = _nativeController!.value.duration;
      final targetMs = (pos.inMilliseconds + (seconds * 1000)).clamp(
        0,
        dur.inMilliseconds,
      );
      _nativeController!.seekTo(Duration(milliseconds: targetMs));
    } else if (_player != null) {
      final pos = _player!.state.position;
      final dur = _player!.state.duration;
      final target = (pos + Duration(seconds: seconds));
      final clamped = Duration(
        milliseconds: target.inMilliseconds.clamp(0, dur.inMilliseconds),
      );
      _player!.seek(clamped);
    }
    _armControlsAutoHide();
  }

  Future<void> _initializePlayer(
    String streamUrl, {
    String? message,
    String? provider,
    bool isDirectLink = true,
  }) async {
    if (_isDisposed) return;

    // Force WebView if user explicitly selected it in settings
    if (_forceWebView) {
      isDirectLink = false;
    }

    final previousPlayer = _player;
    final previousWindowsController = _windowsEmbedController;

    _currentStreamUrl = isDirectLink ? streamUrl : null;
    setState(() {
      _isDirectLink = isDirectLink;
      _errorMessageKey = null;
      _errorMessageParam = null;
      _embedUrl = null;
      _player = null;
      _videoController = null;
      _embedWebViewController = null;
      _windowsEmbedController = null;
      _showOverlayControls = true;
      _selectedSubtitleTrackIndex = -1;
      _activeOnlineSubtitle = null;
      _nativeSubtitlesEnabled = true;
      _embedSubtitlesEnabled = true;
      _embedCaptions = const [];
      _embedCaptionText = '';
    });
    _embedSubtitleTimer?.cancel();
    _armControlsAutoHide();
    _directFallbackAttempt += 1;
    _progressAutosaveTimer?.cancel();
    _embedWatchStopwatch
      ..stop()
      ..reset();
    _embedPositionOffsetMs = 0;
    _directAutoplayAttempt += 1;
    if (previousPlayer != null) {
      unawaited(previousPlayer.dispose());
    }
    if (previousWindowsController != null) {
      unawaited(previousWindowsController.dispose());
    }

    if (isDirectLink) {
      setState(() {
        _loadingStatusKey = 'loading_video';
      });
      if (_useNativePlayer) {
        await _initNativePlayer(streamUrl);
        unawaited(_attachOnlineSubtitle(streamUrl));
      } else {
        final player = Player();
        _player = player;
        _videoController = VideoController(player);
        player.open(Media(streamUrl), play: true);
        _ensureDirectPlaybackStarts(player);
        setState(() {
          _isLoading = false;
        });
        _startProgressAutosave();
        unawaited(_attachOnlineSubtitle(streamUrl));
      }
    } else {
      final localizedUrl = _applyEmbedSubtitleLanguage(streamUrl);
      setState(() {
        _embedUrl = localizedUrl;
        _loadingStatusKey = 'preparing_in_app_player';
        _isLoading = true;
      });
      _initializeEmbedPlayer(localizedUrl);
      _startProgressAutosave();
      unawaited(_attachOnlineSubtitleToEmbed(streamUrl, localizedUrl));
    }

    if (provider != null && provider.isNotEmpty) {
      debugPrint('Playing stream from provider: $provider');
    }
    if (message != null && message.isNotEmpty) {
      debugPrint('Player message: $message');
    }

    _initPlaybackPosition();
  }

  String _applyEmbedSubtitleLanguage(String url) {
    try {
      var uri = Uri.parse(url);
      var host = uri.host.toLowerCase();
      if (!host.contains('vidsrc') && !_isStreamImdbEmbedHost(host)) {
        return url;
      }

      // streamimdb.ru/brightpathsignals are wrappers around the VidAPI/Vaplayer
      // player. Loading Vaplayer directly keeps our subtitle-language and
      // text-fix script in the same frame as the actual subtitle renderer.
      if (host.contains('streamimdb') || host.contains('brightpathsignals')) {
        uri = uri.replace(scheme: 'https', host: 'vaplayer.ru');
        host = uri.host.toLowerCase();
      }

      final lang = widget.subtitleLanguage.trim().isEmpty
          ? 'tr'
          : widget.subtitleLanguage.trim().toLowerCase();

      final updatedParams = Map<String, String>.from(uri.queryParameters);
      if (host.contains('vidsrc')) {
        updatedParams['ds_lang'] = lang;
      } else if (_isStreamImdbEmbedHost(host)) {
        final osLang = _streamImdbSubtitleLanguage;
        updatedParams['osLang'] = osLang;
        updatedParams['lang'] = osLang;
        updatedParams['ds_lang'] = osLang;
        updatedParams['langOrder'] = osLang == 'eng' ? 'eng' : '$osLang,eng';
      }
      return uri.replace(queryParameters: updatedParams).toString();
    } catch (_) {
      return url;
    }
  }

  String get _normalizedSubtitleLanguage {
    final raw = widget.subtitleLanguage.trim().toLowerCase();
    return raw.isEmpty ? 'tr' : raw;
  }

  bool _isStreamImdbEmbedHost(String host) {
    final normalized = host.toLowerCase();
    return normalized.contains('streamimdb') ||
        normalized.contains('vaplayer') ||
        normalized.contains('brightpathsignals');
  }

  String get _streamImdbSubtitleLanguage {
    const openSubtitlesLanguageCodes = <String, String>{
      'tr': 'tur',
      'en': 'eng',
      'es': 'spa',
      'de': 'ger',
      'fr': 'fre',
      'it': 'ita',
      'pt': 'por',
      'ru': 'rus',
      'ar': 'ara',
    };
    return openSubtitlesLanguageCodes[_normalizedSubtitleLanguage] ??
        _normalizedSubtitleLanguage;
  }

  String _buildStreamImdbSubtitleBootstrapScript([int startAtMs = 0]) {
    final osLang = jsonEncode(_streamImdbSubtitleLanguage);
    final lang2 = jsonEncode(_normalizedSubtitleLanguage);
    return '''
      (function() {
        var osLang = $osLang;
        var lang2 = $lang2;
        var startAtMs = $startAtMs;
        function applySubtitleLanguage() {
          try { localStorage.setItem('subtitleLang', osLang); } catch (e) {}
          try { localStorage.setItem('lastSubLang', lang2); } catch (e) {}
          try {
            var frame = document.getElementById('pf') || document.querySelector('iframe');
            if (frame && frame.contentWindow) {
              frame.contentWindow.postMessage({
                type: 'STORAGE_INIT',
                data: { subtitleLang: osLang, lastSubLang: lang2 }
              }, '*');
            }
          } catch (e) {}
        }
        applySubtitleLanguage();
        setTimeout(applySubtitleLanguage, 250);
        setTimeout(applySubtitleLanguage, 1000);

        function fixTurkishMojibake(text) {
          if (!text || typeof text !== 'string') return text;
          var map = {
            '\\u00d0': '\\u011e', '\\u00f0': '\\u011f',
            '\\u00dd': '\\u0130', '\\u00fd': '\\u0131',
            '\\u00de': '\\u015e', '\\u00fe': '\\u015f',
            '\\u00c3\\u00a7': '\\u00e7', '\\u00c3\\u0087': '\\u00c7',
            '\\u00c3\\u00b6': '\\u00f6', '\\u00c3\\u0096': '\\u00d6',
            '\\u00c3\\u00bc': '\\u00fc', '\\u00c3\\u009c': '\\u00dc',
            '\\u00c4\\u009f': '\\u011f', '\\u00c4\\u009e': '\\u011e',
            '\\u00c4\\u00b1': '\\u0131', '\\u00c4\\u00b0': '\\u0130',
            '\\u00c5\\u009f': '\\u015f', '\\u00c5\\u009e': '\\u015e'
          };
          return text.replace(/\\u00c3[\\u0080-\\u00bf]|\\u00c4[\\u0080-\\u00bf]|\\u00c5[\\u0080-\\u00bf]|[\\u00d0\\u00f0\\u00dd\\u00fd\\u00de\\u00fe]/g, function(match) {
            return map[match] || match;
          });
        }

        function fixTextNode(node) {
          var fixed = fixTurkishMojibake(node.nodeValue);
          if (fixed !== node.nodeValue) node.nodeValue = fixed;
        }

        function fixTextTracks(rootWindow) {
          try {
            var videos = rootWindow.document.querySelectorAll('video');
            videos.forEach(function(video) {
              try {
                var tracks = video.textTracks || [];
                for (var i = 0; i < tracks.length; i++) {
                  var cueLists = [tracks[i].cues, tracks[i].activeCues];
                  for (var j = 0; j < cueLists.length; j++) {
                    var cues = cueLists[j];
                    if (!cues) continue;
                    for (var k = 0; k < cues.length; k++) {
                      var cue = cues[k];
                      if (!cue || typeof cue.text !== 'string') continue;
                      var fixed = fixTurkishMojibake(cue.text);
                      if (fixed !== cue.text) cue.text = fixed;
                    }
                  }
                }
              } catch (e) {}
            });
          } catch (e) {}
        }

        function patchTextSetters(rootWindow) {
          try {
            if (rootWindow.__streamAppTurkishSetterFixInstalled) return;
            rootWindow.__streamAppTurkishSetterFixInstalled = true;

            var elementProto = rootWindow.Element && rootWindow.Element.prototype;
            var nodeProto = rootWindow.Node && rootWindow.Node.prototype;

            function patchSetter(proto, prop) {
              if (!proto) return;
              var desc = rootWindow.Object.getOwnPropertyDescriptor(proto, prop);
              if (!desc || !desc.set || !desc.get) return;
              rootWindow.Object.defineProperty(proto, prop, {
                configurable: true,
                enumerable: desc.enumerable,
                get: desc.get,
                set: function(value) {
                  if (typeof value === 'string') {
                    value = fixTurkishMojibake(value);
                  }
                  return desc.set.call(this, value);
                }
              });
            }

            patchSetter(elementProto, 'innerHTML');
            patchSetter(nodeProto, 'textContent');
            patchSetter(nodeProto, 'nodeValue');
          } catch (e) {}
        }

        function patchFetchForTurkishSubtitles(rootWindow) {
          try {
            if (rootWindow.__streamAppTurkishFetchFixInstalled) return;
            rootWindow.__streamAppTurkishFetchFixInstalled = true;
            var originalFetch = rootWindow.fetch;
            if (!originalFetch) return;
            rootWindow.fetch = function(input, init) {
              try {
                var url = typeof input === 'string' ? input : (input && input.url) || '';
                if (url.indexOf('sub.wyzie.io/') !== -1 && url.indexOf('encoding=') !== -1) {
                  url = url.replace(/encoding=[^&]*/i, 'encoding=windows-1254');
                  if (typeof input === 'string') {
                    input = url;
                  } else if (rootWindow.Request && input instanceof rootWindow.Request) {
                    input = new rootWindow.Request(url, input);
                  }
                }
              } catch (e) {}
              return originalFetch.call(this, input, init).then(function(response) {
                try {
                  var responseUrl = response && response.url ? response.url : '';
                  if (responseUrl.indexOf('sub.wyzie.io/') === -1) return response;
                  return response.clone().text().then(function(text) {
                    var fixed = fixTurkishMojibake(text);
                    if (fixed === text) return response;
                    return new rootWindow.Response(fixed, {
                      status: response.status,
                      statusText: response.statusText,
                      headers: response.headers
                    });
                  }).catch(function() { return response; });
                } catch (e) {
                  return response;
                }
              });
            };
          } catch (e) {}
        }

        function patchTextDecoderForTurkishSubtitles(rootWindow) {
          try {
            if (osLang !== 'tur') return;
            if (rootWindow.__streamAppTurkishDecoderFixInstalled) return;
            rootWindow.__streamAppTurkishDecoderFixInstalled = true;

            var NativeTextDecoder = rootWindow.TextDecoder;
            if (!NativeTextDecoder) return;
            var windows1254Decoder = new NativeTextDecoder('windows-1254');

            function scoreTurkish(text) {
              if (!text || typeof text !== 'string') return -999;
              var score = 0;
              var good = text.match(/[ğĞıİşŞçÇöÖüÜ]/g);
              var bad = text.match(/[ðÐýÝþÞ]|Ã.|Ä.|Å.|/g);
              if (good) score += good.length * 3;
              if (bad) score -= bad.length * 5;
              if (/\\b(ve|bir|için|değil|çok|şey|evet|hayır|öyle)\\b/i.test(text)) {
                score += 2;
              }
              return score;
            }

            rootWindow.TextDecoder = function(label, options) {
              var requested = String(label || 'utf-8').toLowerCase();
              var nativeDecoder = new NativeTextDecoder(label, options);
              var shouldPrefer1254 =
                requested === 'utf-8' ||
                requested === 'utf8' ||
                requested === 'windows-1252' ||
                requested === 'iso-8859-1' ||
                requested === 'latin1' ||
                requested === 'us-ascii';

              return {
                get encoding() { return nativeDecoder.encoding; },
                get fatal() { return nativeDecoder.fatal; },
                get ignoreBOM() { return nativeDecoder.ignoreBOM; },
                decode: function(input, decodeOptions) {
                  var decoded = nativeDecoder.decode(input, decodeOptions);
                  if (!shouldPrefer1254 || !input) {
                    return fixTurkishMojibake(decoded);
                  }
                  try {
                    var candidate = windows1254Decoder.decode(input, decodeOptions);
                    var fixedDecoded = fixTurkishMojibake(decoded);
                    return scoreTurkish(candidate) > scoreTurkish(fixedDecoded)
                      ? candidate
                      : fixedDecoded;
                  } catch (e) {
                    return fixTurkishMojibake(decoded);
                  }
                }
              };
            };
            rootWindow.TextDecoder.prototype = NativeTextDecoder.prototype;
          } catch (e) {}
        }

        function fixRoot(root) {
          try {
            var walker = root.document.createTreeWalker(
              root.document.body || root.document,
              root.NodeFilter.SHOW_TEXT
            );
            var node;
            while ((node = walker.nextNode())) fixTextNode(node);
          } catch (e) {}
        }

        function installSubtitleTextFix(rootWindow) {
          try {
            var doc = rootWindow.document;
            if (!doc || doc.__streamAppTurkishFixInstalled) return;
            doc.__streamAppTurkishFixInstalled = true;

            patchTextSetters(rootWindow);
            patchFetchForTurkishSubtitles(rootWindow);
            patchTextDecoderForTurkishSubtitles(rootWindow);
            var apply = function() { fixRoot(rootWindow); };
            fixTextTracks(rootWindow);
            apply();
            new rootWindow.MutationObserver(function(mutations) {
              for (var i = 0; i < mutations.length; i++) {
                var m = mutations[i];
                if (m.type === 'characterData') {
                  fixTextNode(m.target);
                } else {
                  apply();
                }
              }
            }).observe(doc.documentElement || doc.body, {
              childList: true,
              subtree: true,
              characterData: true
            });
          } catch (e) {}
        }

        function installAllTextFixes() {
          installSubtitleTextFix(window);
          patchTextSetters(window);
          patchFetchForTurkishSubtitles(window);
          patchTextDecoderForTurkishSubtitles(window);
          fixTextTracks(window);
          try {
            document.querySelectorAll('iframe').forEach(function(frame) {
              try {
                if (frame.contentWindow && frame.contentWindow.document) {
                  installSubtitleTextFix(frame.contentWindow);
                  fixTextTracks(frame.contentWindow);
                }
              } catch (e) {}
            });
          } catch (e) {}
        }

        function trackVideo(win) {
          try {
            var videos = win.document.querySelectorAll('video');
            videos.forEach(function(video) {
              if (video.__streamAppTracked) return;
              video.__streamAppTracked = true;

              if (startAtMs > 0 && !win.top.__streamAppSeeked) {
                win.top.__streamAppSeeked = true;
                if (video.readyState >= 1) {
                  video.currentTime = startAtMs / 1000.0;
                } else {
                  video.addEventListener('loadedmetadata', function() {
                    video.currentTime = startAtMs / 1000.0;
                  }, { once: true });
                }
              }

              function reportState() {
                var msg = {
                  currentTime: video.currentTime,
                  duration: video.duration,
                  paused: video.paused
                };
                if (win.top.StreamAppChannel && win.top.StreamAppChannel.postMessage) {
                  win.top.StreamAppChannel.postMessage(JSON.stringify(msg));
                }
                if (win.top.chrome && win.top.chrome.webview && win.top.chrome.webview.postMessage) {
                  win.top.chrome.webview.postMessage(msg);
                }
              }

              video.addEventListener('play', reportState);
              video.addEventListener('playing', reportState);
              video.addEventListener('pause', reportState);
              video.addEventListener('timeupdate', reportState);
              video.addEventListener('durationchange', reportState);
              video.addEventListener('ended', reportState);

              reportState();
            });
          } catch (e) {}
        }

        function trackAllVideos() {
          trackVideo(window);
          try {
            document.querySelectorAll('iframe').forEach(function(frame) {
              try {
                if (frame.contentWindow) {
                  trackVideo(frame.contentWindow);
                }
              } catch (e) {}
            });
          } catch (e) {}
        }

        installAllTextFixes();
        trackAllVideos();
        setInterval(function() {
          installAllTextFixes();
          fixRoot(window);
          fixTextTracks(window);
          trackAllVideos();
        }, 500);
      })();
    ''';
  }

  Future<void> _syncEmbedSubtitleLanguage(
    Uri entryUri, {
    WebViewController? webController,
    windows_webview.WebviewController? windowsController,
  }) async {
    if (!_isStreamImdbEmbedHost(entryUri.host)) {
      return;
    }
    final script = _buildStreamImdbSubtitleBootstrapScript();
    try {
      await (webController ?? _embedWebViewController)?.runJavaScript(script);
    } catch (_) {}
    try {
      await (windowsController ?? _windowsEmbedController)?.executeScript(
        script,
      );
    } catch (_) {}
  }

  Future<void> _initializeEmbedPlayer(String url) async {
    const userAgent =
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

    try {
      final uri = Uri.parse(url);
      _trustedEmbedHosts = _buildTrustedEmbedHosts(uri);

      // Reset embed tracking variables
      _lastEmbedPositionMs = null;
      _lastEmbedDurationMs = null;
      _embedVideoPaused = true;

      final repo = ref.read(watchHistoryRepositoryProvider);
      final history = repo.getProgress(
        widget.mediaId,
        mediaType: _normalizedMediaType,
        season: widget.season,
        episode: widget.episode,
      );
      int startAtMs = 0;
      if (history != null && history.lastPosition > 0 && !history.isWatched) {
        startAtMs = history.lastPosition;
      }
      _embedPositionOffsetMs = startAtMs;

      if (defaultTargetPlatform == TargetPlatform.windows) {
        final controller = windows_webview.WebviewController();
        await controller.initialize();
        await controller.setPopupWindowPolicy(
          windows_webview.WebviewPopupWindowPolicy.deny,
        );
        await _addWindowsDocumentStartScript(uri, controller, startAtMs);

        controller.webMessage.listen((dynamic message) {
          _handleEmbedMessage(message);
        });

        await controller.loadUrl(uri.toString());
        await _syncEmbedSubtitleLanguage(uri, windowsController: controller);

        if (_isDisposed || !mounted) {
          await controller.dispose();
          return;
        }

        setState(() {
          _windowsEmbedController = controller;
          _isLoading = false;
        });
        if (!_embedWatchStopwatch.isRunning) {
          _embedWatchStopwatch.start();
        }
        return;
      }

      final attemptId = ++_embedLoadAttempt;
      final controller = WebViewController();
      controller
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black)
        ..setUserAgent(userAgent)
        ..addJavaScriptChannel(
          'StreamAppChannel',
          onMessageReceived: (JavaScriptMessage message) {
            _handleEmbedMessage(message.message);
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) {
              if (_isDisposed || !mounted || attemptId != _embedLoadAttempt) {
                return;
              }
              unawaited(
                _syncEmbedSubtitleLanguage(uri, webController: controller),
              );
              setState(() {
                _loadingStatusKey = 'loading_embed_source';
              });
            },
            onPageFinished: (_) {
              if (_isDisposed || !mounted || attemptId != _embedLoadAttempt) {
                return;
              }
              unawaited(_injectEmbedAntiPopupScript(controller));
              unawaited(
                _syncEmbedSubtitleLanguage(uri, webController: controller),
              );
              if (!_embedWatchStopwatch.isRunning) {
                _embedWatchStopwatch.start();
              }
              if (_isLoading) {
                setState(() {
                  _isLoading = false;
                });
              }
            },
            onNavigationRequest: (NavigationRequest request) {
              if (_isAllowedNavigation(request.url)) {
                return NavigationDecision.navigate;
              }
              return NavigationDecision.prevent;
            },
            onWebResourceError: (WebResourceError error) {
              final isMainFrame = error.isForMainFrame ?? true;
              if (_isDisposed ||
                  !mounted ||
                  attemptId != _embedLoadAttempt ||
                  !isMainFrame) {
                return;
              }
              setState(() {
                _errorMessageKey = 'page_load_failed_with';
                _errorMessageParam = error.description;
                _isLoading = false;
              });
            },
          ),
        );

      _startEmbedTimeoutGuard(attemptId);
      await _addAndroidDocumentStartScript(uri, controller, startAtMs);
      await controller.loadRequest(uri);

      if (_isDisposed || !mounted) {
        return;
      }

      setState(() {
        _embedWebViewController = controller;
      });
    } catch (e) {
      if (_isDisposed || !mounted) return;
      setState(() {
        _errorMessageKey = 'in_app_player_failed_with';
        _errorMessageParam = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _addWindowsDocumentStartScript(
    Uri entryUri,
    windows_webview.WebviewController controller,
    int startAtMs,
  ) async {
    try {
      // Inject anti-popup and overlay click bypass script for Windows WebViews
      await controller.addScriptToExecuteOnDocumentCreated(
        _getAntiPopupScript(),
      );

      if (_isStreamImdbEmbedHost(entryUri.host)) {
        await controller.addScriptToExecuteOnDocumentCreated(
          _buildStreamImdbSubtitleBootstrapScript(startAtMs),
        );
      }
    } catch (_) {}
  }

  Future<void> _addAndroidDocumentStartScript(
    Uri entryUri,
    WebViewController controller,
    int startAtMs,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.android ||
        !_isStreamImdbEmbedHost(entryUri.host)) {
      return;
    }

    try {
      final platformController = controller.platform;
      if (platformController is! AndroidWebViewController) {
        return;
      }

      await _androidWebViewChannel
          .invokeMethod<bool>('addDocumentStartScript', <String, Object?>{
            'webViewIdentifier': platformController.webViewIdentifier,
            'script': _buildStreamImdbSubtitleBootstrapScript(startAtMs),
          });
    } catch (_) {}
  }

  bool _isAllowedNavigation(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return false;
    }

    final scheme = uri.scheme.toLowerCase();
    if (!(scheme == 'http' ||
        scheme == 'https' ||
        scheme == 'about' ||
        scheme == 'data' ||
        scheme == 'blob')) {
      return false;
    }

    if (scheme == 'about' || scheme == 'data' || scheme == 'blob') {
      return true;
    }

    if (_hasBlockedAdPattern(url)) {
      return false;
    }

    // On mobile embed pages, keep ad domains blocked but allow plausible
    // playback hosts so player startup does not get stuck.
    if (defaultTargetPlatform != TargetPlatform.windows && !_isDirectLink) {
      if (_isTrustedEmbedHost(uri.host) || _looksLikePlaybackUri(uri)) {
        return true;
      }
      debugPrint('Blocked embed navigation: $url');
      return false;
    }

    return true;
  }

  Set<String> _buildTrustedEmbedHosts(Uri entryUri) {
    final host = entryUri.host.toLowerCase();
    final hosts = <String>{
      if (host.isNotEmpty) host,
      'vidsrc.net',
      'vidsrc.xyz',
      'vidsrc.me',
      'vidsrc.pm',
      'vidsrc.icu',
      'vidsrc.in',
      'vidsrc.ink',
      'vidsrc.to',
      'vidsrc.dev',
      'vaplayer.ru',
      'brightpathsignals.com',
      'streamimdb.ru',
      'vidplay.site',
      'vidplay.online',
      'mcloud.to',
      'rabbitstream.net',
      'megacloud.tv',
      'googlevideo.com',
      'gstatic.com',
      'cloudflare.com',
      'akamaized.net',
      'jwplayer.com',
    };
    return hosts;
  }

  bool _isTrustedEmbedHost(String host) {
    final normalized = host.toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    for (final trusted in _trustedEmbedHosts) {
      if (normalized == trusted || normalized.endsWith('.$trusted')) {
        return true;
      }
    }
    return false;
  }

  bool _hasBlockedAdPattern(String url) {
    final lower = url.toLowerCase();
    const blockedFragments = <String>[
      'doubleclick',
      'googlesyndication',
      'googletagmanager',
      'popads',
      'popcash',
      'adservice',
      '/ads?',
      '&ads=',
      '?ads=',
      'utm_campaign=',
      'onclick=',
      'redirect=',
    ];
    for (final fragment in blockedFragments) {
      if (lower.contains(fragment)) {
        return true;
      }
    }
    return false;
  }

  bool _looksLikePlaybackUri(Uri uri) {
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();

    const mediaExtensions = <String>[
      '.m3u8',
      '.mpd',
      '.ts',
      '.m4s',
      '.mp4',
      '.webm',
      '.vtt',
      '.srt',
    ];
    for (final ext in mediaExtensions) {
      if (path.endsWith(ext)) {
        return true;
      }
    }

    const mediaHostHints = <String>[
      'video',
      'stream',
      'cdn',
      'cloud',
      'hls',
      'embed',
      'player',
      'play',
      'vid',
    ];
    for (final hint in mediaHostHints) {
      if (host.contains(hint)) {
        return true;
      }
    }

    return false;
  }

  String _getAntiPopupScript() {
    return '''
      (function() {
        window.open = function() { return null; };
        
        var anchors = document.querySelectorAll('a[target="_blank"]');
        anchors.forEach(function(a) { a.removeAttribute('target'); });
        
        document.addEventListener('click', function(evt) {
          var node = evt.target;
          while (node && node.tagName !== 'A') {
            node = node.parentElement;
          }
          if (!node || !node.href) { return; }
          if (node.target === '_blank') {
            evt.preventDefault();
            evt.stopPropagation();
          }
        }, true);

        // Inject CSS styling to disable tap highlights and pointer events on transparent overlays
        var style = document.createElement('style');
        style.innerHTML = `
          * {
            -webkit-tap-highlight-color: transparent !important;
            -webkit-tap-highlight-color: rgba(0,0,0,0) !important;
          }
          div[style*="position: absolute"][style*="z-index"][style*="width: 100%"][style*="height: 100%"],
          div[style*="position: fixed"][style*="z-index"][style*="width: 100%"][style*="height: 100%"],
          div[style*="position: absolute"][style*="z-index: 2147483647"],
          div[style*="position: fixed"][style*="z-index: 2147483647"],
          div[class*="overlay"],
          div[id*="overlay"],
          div[class*="popup"],
          div[id*="popup"],
          #player_overlay,
          .player-overlay,
          #play-overlay,
          .play-overlay,
          div[onclick*="window.open"],
          div[style*="z-index"][onclick] {
            pointer-events: none !important;
            background: transparent !important;
            display: none !important;
            opacity: 0 !important;
            visibility: hidden !important;
          }
        `;
        document.head.appendChild(style);

        // Scan periodically to remove/disable viewport-covering overlays
        setInterval(function() {
          var divs = document.getElementsByTagName('div');
          for (var i = 0; i < divs.length; i++) {
            var div = divs[i];
            var styleStr = window.getComputedStyle(div);
            var zIndex = parseInt(styleStr.zIndex);
            if (!isNaN(zIndex) && zIndex > 10) {
              var rect = div.getBoundingClientRect();
              var isOverlay = rect.width > window.innerWidth * 0.9 && rect.height > window.innerHeight * 0.9;
              var hasVideo = div.getElementsByTagName('video').length > 0 || div.getElementsByTagName('iframe').length > 0;
              if (isOverlay && !hasVideo) {
                div.style.pointerEvents = 'none';
                div.style.display = 'none';
                div.style.zIndex = '-9999';
              }
            }
          }
          var adClasses = ['banner', 'ads', 'popunder', 'clickforce', 'mgid', 'exoclick'];
          adClasses.forEach(function(cls) {
            var elements = document.querySelectorAll('.' + cls + ', [id*="' + cls + '"], [class*="' + cls + '"]');
            elements.forEach(function(el) {
              el.remove();
            });
          });
        }, 500);
      })();
    ''';
  }

  Future<void> _injectEmbedAntiPopupScript(WebViewController controller) async {
    try {
      await controller.runJavaScript(_getAntiPopupScript());
    } catch (_) {
      // Non-fatal; keep playback going.
    }
  }

  void _startEmbedTimeoutGuard(int attemptId) {
    Future<void>.delayed(const Duration(seconds: 20), () {
      if (_isDisposed || !mounted || attemptId != _embedLoadAttempt) {
        return;
      }
      if (_isLoading && _errorMessageKey == null) {
        setState(() {
          _errorMessageKey = 'embed_player_failed_to_open';
          _errorMessageParam = null;
          _isLoading = false;
        });
      }
    });
  }

  Map<String, dynamic>? _selectPreferredStream(
    List<Map<String, dynamic>> streams,
  ) {
    if (streams.isEmpty) {
      return null;
    }

    // On mobile prefer direct links to avoid embed ad redirects.
    if (defaultTargetPlatform != TargetPlatform.windows) {
      final sorted = List<Map<String, dynamic>>.from(streams)
        ..sort((a, b) {
          final directCompare = (b['is_direct_link'] == true ? 1 : 0).compareTo(
            a['is_direct_link'] == true ? 1 : 0,
          );
          if (directCompare != 0) return directCompare;
          return _streamProviderScore(a).compareTo(_streamProviderScore(b));
        });
      for (final stream in sorted) {
        if (stream['is_direct_link'] == true &&
            (stream['url']?.toString().isNotEmpty ?? false)) {
          return stream;
        }
      }
    }

    return streams.firstWhere(
      (stream) => stream['url']?.toString().isNotEmpty ?? false,
      orElse: () => streams.first,
    );
  }

  int _streamProviderScore(Map<String, dynamic> stream) {
    if (!widget.preferAnimeSources) {
      return 0;
    }
    final addonId = stream['addon_id']?.toString().toLowerCase() ?? '';
    final provider = stream['provider']?.toString().toLowerCase() ?? '';
    if (addonId.contains('streamimdb') || provider.contains('streamimdb')) {
      return 0;
    }
    if (addonId.contains('vidsrccc') || provider.contains('vidsrc.cc')) {
      return 1;
    }
    if (addonId.contains('vidsrc') || provider.contains('vidsrc')) return 2;
    if (addonId.contains('videasy') || provider.contains('videasy')) return 3;
    if (addonId.contains('embedsu') || provider.contains('embedsu')) return 4;
    return 10;
  }

  void _startProgressAutosave() {
    _progressAutosaveTimer?.cancel();
    _progressAutosaveTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_saveProgress());
      _checkEpisodeCompletion();
    });
  }

  Future<void> _checkEpisodeCompletion() async {
    if (!_isTvPlayback || _nextEpisodeDismissed || _showNextEpisodeOverlay) {
      return;
    }
    if (widget.nextEpisodeNumber == null) return;

    bool isNearEnd = false;
    if (_isDirectLink && _player != null) {
      try {
        final pos = _player!.state.position;
        final dur = _player!.state.duration;
        if (dur.inMilliseconds > 0) {
          isNearEnd = (dur.inMilliseconds - pos.inMilliseconds) <= 45000;
        }
      } catch (_) {}
    } else {
      final elapsed = _currentEmbedPositionMs;
      final runtimeMs = _episodeRuntimeMs();
      isNearEnd = elapsed >= (runtimeMs - 45000);
    }

    if (isNearEnd && mounted) {
      setState(() {
        _showNextEpisodeOverlay = true;
      });
    }
  }

  void _ensureDirectPlaybackStarts(Player player) {
    final attempt = ++_directAutoplayAttempt;

    Future<void> tryPlay(int retriesLeft) async {
      if (_isDisposed ||
          _player != player ||
          attempt != _directAutoplayAttempt) {
        return;
      }
      try {
        await player.play();
      } catch (_) {}
      if (player.state.playing || retriesLeft <= 0) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await tryPlay(retriesLeft - 1);
    }

    unawaited(tryPlay(5));
  }

  void _startDirectLinkFallbackIfNeeded({
    required List<Map<String, dynamic>> streams,
    required Map<String, dynamic>? selectedStream,
  }) {
    if (selectedStream == null || selectedStream['is_direct_link'] != true) {
      return;
    }

    Map<String, dynamic>? embedFallback;
    for (final stream in streams) {
      final isDirect = stream['is_direct_link'] == true;
      final hasUrl = stream['url']?.toString().isNotEmpty ?? false;
      if (!isDirect && hasUrl) {
        embedFallback = stream;
        break;
      }
    }
    if (embedFallback == null) {
      return;
    }

    final attempt = ++_directFallbackAttempt;
    Future<void>.delayed(const Duration(seconds: 4), () async {
      if (_isDisposed || !mounted || attempt != _directFallbackAttempt) {
        return;
      }
      if (!_isDirectLink || (_player == null && _nativeController == null)) {
        return;
      }

      bool hasStartedPlayback = false;
      if (_nativeController != null) {
        final val = _nativeController!.value;
        hasStartedPlayback = val.isPlaying || val.position.inMilliseconds > 0;
      } else if (_player != null) {
        final state = _player!.state;
        hasStartedPlayback = state.playing || state.position.inMilliseconds > 0;
      }

      if (hasStartedPlayback) {
        return;
      }

      final fallbackUrl = embedFallback!['url']?.toString();
      if (fallbackUrl == null || fallbackUrl.isEmpty) {
        return;
      }

      _stopAllPlayback();

      if (_isDisposed || !mounted || attempt != _directFallbackAttempt) {
        return;
      }

      _initializePlayer(
        fallbackUrl,
        provider: embedFallback['provider']?.toString(),
        isDirectLink: false,
      );
      final text = ref.read(appTextProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text.t('direct_source_failed')),
          duration: const Duration(seconds: 3),
        ),
      );
    });
  }

  Future<void> _fetchStreamAndInitialize() async {
    try {
      final addonService = ref.read(addonServiceProvider);

      setState(() {
        _loadingStatusKey = 'resolving_stream';
      });

      final data = await addonService.resolveFast(
        query: widget.title,
        tmdbId: widget.mediaId,
        contentType: _backendMediaType,
        season: widget.season,
        episode: widget.episode,
        addonId: widget.sourceId,
        preferAnimeSources: widget.preferAnimeSources,
      );

      final streams = (data['streams'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      if (streams.isNotEmpty) {
        final selectedStream = _selectPreferredStream(streams);
        final stream = selectedStream ?? streams.first;
        if (_isDisposed) return;
        _initializePlayer(
          stream['url'].toString(),
          provider: stream['provider']?.toString(),
          isDirectLink: stream['is_direct_link'] ?? true,
        );
        _startDirectLinkFallbackIfNeeded(
          streams: streams,
          selectedStream: selectedStream,
        );
      } else {
        setState(() {
          _errorMessageKey = 'stream_source_not_found';
          _errorMessageParam = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Stream fetch failed: $e');
      setState(() {
        _errorMessageKey = 'stream_source_not_found';
        _errorMessageParam = null;
        _isLoading = false;
      });
    }
  }

  Future<void> _initPlaybackPosition() async {
    if (!ref.read(appSettingsProvider).watchHistoryEnabled) {
      return;
    }
    final repo = ref.read(watchHistoryRepositoryProvider);
    final history = repo.getProgress(
      widget.mediaId,
      mediaType: _normalizedMediaType,
      season: widget.season,
      episode: widget.episode,
    );
    if (history == null || history.lastPosition <= 0 || history.isWatched) {
      return;
    }

    // Native player resume
    if (_nativeController != null) {
      try {
        for (int i = 0; i < 20; i++) {
          if (_isDisposed || _nativeController == null) return;
          if (_nativeController!.value.isInitialized &&
              _nativeController!.value.duration.inMilliseconds > 0) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        if (_isDisposed || _nativeController == null) return;
        final rawTarget = history.duration > 0
            ? history.lastPosition.clamp(0, history.duration - 1500)
            : history.lastPosition;
        await _nativeController!.seekTo(Duration(milliseconds: rawTarget));
        await _nativeController!.play();
      } catch (e) {
        debugPrint('Native resume seek failed: $e');
      }
      return;
    }

    if (_player == null) {
      return;
    }

    try {
      // Wait for player to be ready.
      for (int i = 0; i < 20; i++) {
        if (_isDisposed || _player == null) {
          return;
        }
        if (_player!.state.duration.inMilliseconds > 0) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }

      if (_isDisposed || _player == null) {
        return;
      }

      final rawTarget = history.duration > 0
          ? history.lastPosition.clamp(0, history.duration - 1500)
          : history.lastPosition;
      await _player!.seek(Duration(milliseconds: rawTarget));
      await _player!.play();
    } catch (e) {
      debugPrint('Resume seek failed: $e');
    }
  }

  Future<void> _saveProgress() async {
    if (!ref.read(appSettingsProvider).watchHistoryEnabled) {
      return;
    }
    final repo = ref.read(watchHistoryRepositoryProvider);
    final completionThreshold =
        ref.read(appSettingsProvider).completionPercentage / 100.0;

    if (!_isDirectLink) {
      try {
        final elapsed = await _getEmbedVideoPositionMs();
        if (elapsed < 10000) {
          return;
        }

        final runtimeMs = await _getEmbedVideoDurationMs();
        final position = elapsed.clamp(10000, runtimeMs - 1000);
        final isWatched = position >= (runtimeMs * completionThreshold);

        await repo.saveProgress(
          WatchHistory(
            mediaId: widget.mediaId,
            title: widget.title,
            mediaType: _normalizedMediaType,
            season: widget.season,
            episode: widget.episode,
            posterUrl: widget.posterUrl,
            backdropUrl: widget.backdropUrl,
            sourceId: widget.sourceId,
            lastPosition: position,
            duration: runtimeMs,
            isWatched: isWatched,
          ),
        );
      } catch (e) {
        debugPrint("Error saving embed progress: $e");
      }
      return;
    }

    // Native player (video_player package)
    if (_nativeController != null && _nativeController!.value.isInitialized) {
      try {
        final pos = _nativeController!.value.position;
        final dur = _nativeController!.value.duration;
        if (pos.inMilliseconds > 0 && dur.inMilliseconds > 0) {
          final isWatched =
              pos.inMilliseconds >= dur.inMilliseconds * completionThreshold;
          await repo.saveProgress(
            WatchHistory(
              mediaId: widget.mediaId,
              title: widget.title,
              mediaType: _normalizedMediaType,
              season: widget.season,
              episode: widget.episode,
              posterUrl: widget.posterUrl,
              backdropUrl: widget.backdropUrl,
              sourceId: widget.sourceId,
              lastPosition: pos.inMilliseconds,
              duration: dur.inMilliseconds,
              isWatched: isWatched,
            ),
          );
        }
      } catch (e) {
        debugPrint("Error saving native progress: $e");
      }
      return;
    }

    // Media kit player
    if (_player == null) return;
    try {
      final position = _player!.state.position;
      final duration = _player!.state.duration;

      if (position.inMilliseconds > 0 && duration.inMilliseconds > 0) {
        final isWatched =
            position.inMilliseconds >=
            duration.inMilliseconds * completionThreshold;

        await repo.saveProgress(
          WatchHistory(
            mediaId: widget.mediaId,
            title: widget.title,
            mediaType: _normalizedMediaType,
            season: widget.season,
            episode: widget.episode,
            posterUrl: widget.posterUrl,
            backdropUrl: widget.backdropUrl,
            sourceId: widget.sourceId,
            lastPosition: position.inMilliseconds,
            duration: duration.inMilliseconds,
            isWatched: isWatched,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error saving progress: $e");
    }
  }

  void _retryCurrentPlayback() {
    if (_isDisposed) {
      return;
    }

    setState(() {
      _errorMessageKey = null;
      _errorMessageParam = null;
      _isLoading = true;
      _loadingStatusKey = 'searching_video_source';
    });

    if (widget.initialStreamUrl != null &&
        widget.initialStreamUrl!.isNotEmpty) {
      _initializePlayer(
        widget.initialStreamUrl!,
        provider: widget.initialProvider,
        isDirectLink: widget.initialIsDirectLink,
      );
      return;
    }

    _fetchStreamAndInitialize();
  }

  bool get _isTvPlayback => _normalizedMediaType == 'tv';

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _overlayControlsTimer?.cancel();
    _progressAutosaveTimer?.cancel();
    _embedSubtitleTimer?.cancel();
    _isDisposed = true;

    // Capture progress BEFORE stopping/nulling controllers.
    final player = _player;
    final win = _windowsEmbedController;
    final embedElapsedMs = _currentEmbedPositionMs;
    _embedWatchStopwatch.stop();

    int? capturedPositionMs;
    int? capturedDurationMs;
    if (_isDirectLink &&
        _nativeController != null &&
        _nativeController!.value.isInitialized) {
      try {
        capturedPositionMs = _nativeController!.value.position.inMilliseconds;
        capturedDurationMs = _nativeController!.value.duration.inMilliseconds;
      } catch (_) {}
    } else if (_isDirectLink && player != null) {
      try {
        capturedPositionMs = player.state.position.inMilliseconds;
        capturedDurationMs = player.state.duration.inMilliseconds;
      } catch (_) {}
    }

    // Stop all playback to prevent background audio.
    _stopAllPlayback();

    _player = null;
    _videoController = null;
    _embedWebViewController = null;
    _windowsEmbedController = null;
    final nativeCtrl = _nativeController;
    _nativeController = null;

    // Dispose controllers.
    if (player != null) {
      unawaited(player.dispose());
    }
    if (win != null) {
      try {
        win.dispose();
      } catch (_) {}
    }
    if (nativeCtrl != null) {
      try {
        nativeCtrl.dispose();
      } catch (_) {}
    }

    _saveFinalProgress(
      capturedPositionMs: capturedPositionMs,
      capturedDurationMs: capturedDurationMs,
      embedElapsedMs: embedElapsedMs,
    );
    WakelockPlus.disable();
    _restoreSystemUiMode();
    super.dispose();
  }

  Future<void> _saveFinalProgress({
    int? capturedPositionMs,
    int? capturedDurationMs,
    required int embedElapsedMs,
  }) async {
    if (!ref.read(appSettingsProvider).watchHistoryEnabled) {
      return;
    }
    final repo = ref.read(watchHistoryRepositoryProvider);
    final completionThreshold =
        ref.read(appSettingsProvider).completionPercentage / 100.0;

    if (_isDirectLink &&
        capturedPositionMs != null &&
        capturedDurationMs != null &&
        capturedDurationMs > 0) {
      final isWatched =
          capturedPositionMs >= capturedDurationMs * completionThreshold;
      try {
        await repo.saveProgress(
          WatchHistory(
            mediaId: widget.mediaId,
            title: widget.title,
            mediaType: _normalizedMediaType,
            season: widget.season,
            episode: widget.episode,
            posterUrl: widget.posterUrl,
            backdropUrl: widget.backdropUrl,
            sourceId: widget.sourceId,
            lastPosition: capturedPositionMs,
            duration: capturedDurationMs,
            isWatched: isWatched,
          ),
        );
      } catch (e) {
        debugPrint("Error saving final progress: $e");
      }
      return;
    }

    // Embed mode fallback.
    if (embedElapsedMs < 10000) return;
    final runtimeMs = _episodeRuntimeMs();
    final position = embedElapsedMs.clamp(10000, runtimeMs - 1000);
    final isWatched = position >= (runtimeMs * completionThreshold);
    try {
      await repo.saveProgress(
        WatchHistory(
          mediaId: widget.mediaId,
          title: widget.title,
          mediaType: _normalizedMediaType,
          season: widget.season,
          episode: widget.episode,
          posterUrl: widget.posterUrl,
          backdropUrl: widget.backdropUrl,
          sourceId: widget.sourceId,
          lastPosition: position,
          duration: runtimeMs,
          isWatched: isWatched,
        ),
      );
    } catch (e) {
      debugPrint("Error saving final embed progress: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = ref.watch(appTextProvider);
    final String? errorMessage = _errorMessageKey != null
        ? (_errorMessageParam != null
              ? text
                    .t(_errorMessageKey!)
                    .replaceAll('{param}', _errorMessageParam!)
              : text.t(_errorMessageKey!))
        : null;

    final content = _isLoading
        ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                text.t(_loadingStatusKey),
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          )
        : errorMessage != null
        ? Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.redAccent,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  errorMessage,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _retryCurrentPlayback,
                  icon: const Icon(Icons.refresh),
                  label: Text(text.t('try_again')),
                ),
              ],
            ),
          )
        : !_isDirectLink && _embedUrl != null
        ? _buildEmbedView()
        : _nativeController != null && _nativeController!.value.isInitialized
        ? AspectRatio(
            aspectRatio: _nativeController!.value.aspectRatio,
            child: vp.VideoPlayer(_nativeController!),
          )
        : _videoController != null
        ? Video(controller: _videoController!, controls: NoVideoControls)
        : const SizedBox();
    final shouldBlockPlaybackSurfacePointer =
        _showOverlayControls &&
        !_isLoading &&
        errorMessage == null &&
        _isDirectLink;
    final renderedContent = shouldBlockPlaybackSurfacePointer
        ? AbsorbPointer(absorbing: true, child: content)
        : content;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _stopAllPlayback();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _isDirectLink
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleOverlayControls,
                child: _buildPlayerStack(renderedContent),
              )
            : _buildPlayerStack(renderedContent),
      ),
    );
  }

  Widget _buildPlayerStack(Widget renderedContent) {
    final text = ref.watch(appTextProvider);
    return Stack(
      children: [
        Positioned.fill(child: Center(child: renderedContent)),
        if (_nativeController != null && _nativeSubtitlesEnabled)
          _buildNativeClosedCaption(),
        if (!_isDirectLink &&
            _embedSubtitlesEnabled &&
            _embedCaptionText.isNotEmpty)
          _buildEmbedClosedCaption(),
        if (_showOverlayControls) ...[
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        _stopAllPlayback();
                        Navigator.of(context).maybePop();
                      },
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (_isTvPlayback)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'S${widget.season}:E${widget.episode}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    const SizedBox(width: 4),
                    if (_isDirectLink || _embedCaptions.isNotEmpty)
                      _buildSubtitleButton(),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSeekBar(),
                    const SizedBox(height: 4),
                    _buildPlaybackControls(),
                  ],
                ),
              ),
            ),
          ),
        ],
        if (!_showOverlayControls && !_isDirectLink)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 80,
            child: SafeArea(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  setState(() {
                    _showOverlayControls = true;
                  });
                  _armControlsAutoHide();
                },
                child: const SizedBox.expand(),
              ),
            ),
          ),
        if (_showNextEpisodeOverlay)
          Positioned.fill(
            child: Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.skip_next, color: Colors.white, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      text.t('next_episode_overlay'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'S${widget.nextSeasonNumber ?? widget.season}:E${widget.nextEpisodeNumber} - ${widget.nextEpisodeTitle ?? ''}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _showNextEpisodeOverlay = false;
                              _nextEpisodeDismissed = true;
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                          ),
                          child: Text(text.t('cancel')),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: _playNextEpisode,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(text.t('watch')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNativeClosedCaption() {
    final controller = _nativeController;
    if (controller == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 24,
      right: 24,
      bottom: _showOverlayControls ? 112 : 32,
      child: IgnorePointer(
        child: ValueListenableBuilder<vp.VideoPlayerValue>(
          valueListenable: controller,
          builder: (context, value, child) {
            final caption = value.caption.text;
            if (caption.isEmpty) {
              return const SizedBox.shrink();
            }
            return Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Text(
                    caption,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmbedClosedCaption() {
    return Positioned(
      left: 24,
      right: 24,
      bottom: _showOverlayControls ? 112 : 32,
      child: IgnorePointer(
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                _embedCaptionText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _playNextEpisode() {
    if (widget.nextEpisodeNumber == null) return;
    _stopAllPlayback();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          mediaId: widget.mediaId,
          title: widget.title,
          type: widget.type,
          season: widget.nextSeasonNumber ?? widget.season,
          episode: widget.nextEpisodeNumber!,
          posterUrl: widget.posterUrl,
          backdropUrl: widget.backdropUrl,
          subtitleLanguage: widget.subtitleLanguage,
          runtimeMinutes: widget.runtimeMinutes,
          preferAnimeSources: widget.preferAnimeSources,
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  static const _speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  double _currentSpeed = 1.0;

  Widget _buildSeekBar() {
    // Native player seekbar
    if (_nativeController != null && _nativeController!.value.isInitialized) {
      return ValueListenableBuilder<vp.VideoPlayerValue>(
        valueListenable: _nativeController!,
        builder: (context, value, child) {
          final position = value.position;
          final duration = value.duration;
          final max = duration.inMilliseconds > 0
              ? duration.inMilliseconds.toDouble()
              : 1.0;
          return Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  _formatDuration(position),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              Expanded(
                child: Slider(
                  value: position.inMilliseconds.toDouble().clamp(0, max),
                  min: 0,
                  max: max,
                  activeColor: Colors.red,
                  inactiveColor: Colors.white30,
                  onChanged: (v) {
                    _nativeController!.seekTo(
                      Duration(milliseconds: v.toInt()),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  _formatDuration(duration),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          );
        },
      );
    }

    // media_kit seekbar
    if (_player != null) {
      return StreamBuilder<Duration>(
        stream: _player!.stream.position,
        builder: (context, snapshot) {
          final position = snapshot.data ?? Duration.zero;
          final duration = _player!.state.duration;
          final max = duration.inMilliseconds > 0
              ? duration.inMilliseconds.toDouble()
              : 1.0;
          return Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  _formatDuration(position),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              Expanded(
                child: Slider(
                  value: position.inMilliseconds.toDouble().clamp(0, max),
                  min: 0,
                  max: max,
                  activeColor: Colors.red,
                  inactiveColor: Colors.white30,
                  onChanged: (v) {
                    _player!.seek(Duration(milliseconds: v.toInt()));
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  _formatDuration(duration),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          );
        },
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildPlaybackControls() {
    // Native player controls
    if (_nativeController != null && _nativeController!.value.isInitialized) {
      return ValueListenableBuilder<vp.VideoPlayerValue>(
        valueListenable: _nativeController!,
        builder: (context, value, child) {
          final isPlaying = value.isPlaying;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSpeedButton(),
              const SizedBox(width: 16),
              IconButton(
                onPressed: () => _skipSeconds(-10),
                icon: const Icon(
                  Icons.replay_10,
                  size: 32,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  if (isPlaying) {
                    _nativeController?.pause();
                  } else {
                    _nativeController?.play();
                  }
                  _armControlsAutoHide();
                },
                icon: Icon(
                  isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                  size: 48,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _skipSeconds(10),
                icon: const Icon(
                  Icons.forward_10,
                  size: 32,
                  color: Colors.white,
                ),
              ),
            ],
          );
        },
      );
    }

    // media_kit controls
    if (_player != null) {
      return StreamBuilder<bool>(
        stream: _player!.stream.playing,
        builder: (context, snapshot) {
          final isPlaying = snapshot.data ?? false;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSpeedButton(),
              const SizedBox(width: 16),
              IconButton(
                onPressed: () => _skipSeconds(-10),
                icon: const Icon(
                  Icons.replay_10,
                  size: 32,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () async {
                  final p = _player;
                  if (p == null) return;
                  if (isPlaying) {
                    await p.pause();
                  } else {
                    await p.play();
                  }
                  _armControlsAutoHide();
                },
                icon: Icon(
                  isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                  size: 48,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _skipSeconds(10),
                icon: const Icon(
                  Icons.forward_10,
                  size: 32,
                  color: Colors.white,
                ),
              ),
            ],
          );
        },
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildSpeedButton() {
    return GestureDetector(
      onTap: () {
        final currentIndex = _speedOptions.indexOf(_currentSpeed);
        final nextIndex = (currentIndex + 1) % _speedOptions.length;
        final newSpeed = _speedOptions[nextIndex];
        setState(() => _currentSpeed = newSpeed);
        if (_nativeController != null) {
          _nativeController!.setPlaybackSpeed(newSpeed);
        } else if (_player != null) {
          _player!.setRate(newSpeed);
        }
        _armControlsAutoHide();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '${_currentSpeed}x',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitleButton() {
    final subtitlesActive = _player != null
        ? _selectedSubtitleTrackIndex != -1
        : _isDirectLink
        ? _activeOnlineSubtitle != null && _nativeSubtitlesEnabled
        : _embedCaptions.isNotEmpty && _embedSubtitlesEnabled;
    return IconButton(
      icon: Icon(
        subtitlesActive ? Icons.closed_caption : Icons.closed_caption_off,
        color: Colors.white,
        size: 24,
      ),
      onPressed: () {
        _armControlsAutoHide();
        _showSubtitleSelector();
      },
    );
  }

  void _showSubtitleSelector() {
    final text = ref.read(appTextProvider);
    if (!_isDirectLink) {
      final subtitle = _activeOnlineSubtitle;
      if (subtitle == null || _embedCaptions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(text.t('online_subtitle_not_found'))),
        );
        return;
      }

      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.grey.shade900,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (sheetContext) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    text.t('subtitle_selection'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(
                    !_embedSubtitlesEnabled
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: Colors.white,
                  ),
                  title: Text(
                    text.t('off'),
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    setState(() {
                      _embedSubtitlesEnabled = false;
                      _embedCaptionText = '';
                    });
                    Navigator.pop(sheetContext);
                  },
                ),
                ListTile(
                  leading: Icon(
                    _embedSubtitlesEnabled
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: Colors.white,
                  ),
                  title: Text(
                    subtitle.label.isEmpty ? 'Wyzie Subs' : subtitle.label,
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    setState(() {
                      _embedSubtitlesEnabled = true;
                    });
                    unawaited(_disableEmbedProviderSubtitles());
                    _startEmbedSubtitleTimer();
                    Navigator.pop(sheetContext);
                  },
                ),
              ],
            ),
          );
        },
      );
      return;
    }

    // media_kit subtitle tracks
    if (_player != null) {
      final tracks = _player!.state.tracks.subtitle;
      if (tracks.isEmpty && _activeOnlineSubtitle == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(text.t('subtitle_track_not_found'))),
        );
        return;
      }
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.grey.shade900,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (sheetContext) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    text.t('subtitle_selection'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(
                    _selectedSubtitleTrackIndex < 0
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: Colors.white,
                  ),
                  title: Text(
                    text.t('off'),
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    _player!.setSubtitleTrack(SubtitleTrack.no());
                    setState(() => _selectedSubtitleTrackIndex = -1);
                    Navigator.pop(sheetContext);
                  },
                ),
                if (_activeOnlineSubtitle != null)
                  ListTile(
                    leading: Icon(
                      _selectedSubtitleTrackIndex == -2
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: Colors.white,
                    ),
                    title: Text(
                      _activeOnlineSubtitle!.label.isEmpty
                          ? 'Wyzie Subs'
                          : _activeOnlineSubtitle!.label,
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      _player!.setSubtitleTrack(
                        SubtitleTrack.uri(
                          _activeOnlineSubtitle!.url,
                          title: _activeOnlineSubtitle!.label,
                          language: _activeOnlineSubtitle!.languageCode,
                        ),
                      );
                      setState(() => _selectedSubtitleTrackIndex = -2);
                      Navigator.pop(sheetContext);
                    },
                  ),
                ...List.generate(tracks.length, (index) {
                  final track = tracks[index];
                  final label =
                      track.title ?? track.language ?? 'Track ${index + 1}';
                  return ListTile(
                    leading: Icon(
                      _selectedSubtitleTrackIndex == index
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: Colors.white,
                    ),
                    title: Text(
                      label,
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      _player!.setSubtitleTrack(track);
                      setState(() => _selectedSubtitleTrackIndex = index);
                      Navigator.pop(sheetContext);
                    },
                  );
                }),
              ],
            ),
          );
        },
      );
      return;
    }

    if (_nativeController != null) {
      final subtitle = _activeOnlineSubtitle;
      if (subtitle == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(text.t('online_subtitle_not_found'))),
        );
        return;
      }

      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.grey.shade900,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (sheetContext) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    text.t('subtitle_selection'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(
                    !_nativeSubtitlesEnabled
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: Colors.white,
                  ),
                  title: Text(
                    text.t('off'),
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    _nativeController!.setClosedCaptionFile(null);
                    setState(() {
                      _nativeSubtitlesEnabled = false;
                    });
                    Navigator.pop(sheetContext);
                  },
                ),
                ListTile(
                  leading: Icon(
                    _nativeSubtitlesEnabled
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: Colors.white,
                  ),
                  title: Text(
                    subtitle.label.isEmpty ? 'Wyzie Subs' : subtitle.label,
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    setState(() {
                      _nativeSubtitlesEnabled = true;
                    });
                    unawaited(_applyNativeSubtitle(subtitle));
                    Navigator.pop(sheetContext);
                  },
                ),
              ],
            ),
          );
        },
      );
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text.t('subtitle_track_not_found'))));
  }

  Widget _buildEmbedView() {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      if (_windowsEmbedController == null) {
        return const Center(child: CircularProgressIndicator());
      }

      return windows_webview.Webview(_windowsEmbedController!);
    }

    if (_embedWebViewController == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: WebViewWidget(
          controller: _embedWebViewController!,
          gestureRecognizers: {
            Factory<OneSequenceGestureRecognizer>(
              () => EagerGestureRecognizer(),
            ),
          },
        ),
      ),
    );
  }
}
