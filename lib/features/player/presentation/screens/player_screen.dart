import 'dart:async';


import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:audio_session/audio_session.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as windows_webview;

import '../../../../core/backend/addon_service_provider.dart';
import '../../../../core/i18n/app_text.dart';

import '../providers/player_provider.dart';
import '../../domain/entities/watch_history.dart';

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
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  Player? _player;
  VideoController? _videoController;
  WebViewController? _embedWebViewController;
  windows_webview.WebviewController? _windowsEmbedController;
  bool _isDirectLink = true;
  bool _isDisposed = false;
  bool _isLoading = true;
  String? _errorMessage;
  String _loadingStatus = 'Video kaynagi araniyor...';
  bool _initialized = false;
  String? _embedUrl;
  int _embedLoadAttempt = 0;
  int _directFallbackAttempt = 0;
  int _directAutoplayAttempt = 0;
  Timer? _progressAutosaveTimer;
  final Stopwatch _embedWatchStopwatch = Stopwatch();
  int _embedPositionOffsetMs = 0;
  late final Stream<int> _embedPositionTickStream = Stream<int>.periodic(
    const Duration(seconds: 1),
    (tick) => tick,
  ).asBroadcastStream();
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
      // Only stop embed playback on background. Direct links continue playing.
      if (!_isDirectLink) {
        _stopEmbedPlayback();
      }
    }
  }

  void _stopEmbedPlayback() {
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

  void _stopAllPlayback() {
    try {
      _player?.pause();
    } catch (_) {}
    try {
      _player?.stop();
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
    _overlayControlsTimer = Timer(const Duration(seconds: 4), () {
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
        widget.runtimeMinutes ?? (_normalizedMediaType == 'tv' ? 25 : 90);
    return runtimeMinutes * 60 * 1000;
  }

  int get _currentEmbedPositionMs =>
      _embedPositionOffsetMs + _embedWatchStopwatch.elapsedMilliseconds;



  Future<void> _seekDirectPlayback(Duration target) async {
    final player = _player;
    if (player == null) return;

    var nextPosition = target;
    if (nextPosition.isNegative) {
      nextPosition = Duration.zero;
    }

    final duration = player.state.duration;
    if (duration.inMilliseconds > 0 && nextPosition > duration) {
      nextPosition = duration;
    }

    await player.seek(nextPosition);
    _armControlsAutoHide();
  }

  Future<void> _seekEmbedPlayback(Duration target) async {
    final safeMs = target.inMilliseconds.clamp(0, _episodeRuntimeMs());
    final targetSeconds = (safeMs / 1000).toStringAsFixed(3);
    final script =
        '''
      (function() {
        var target = $targetSeconds;
        function seekVideos(root) {
          try {
            root.querySelectorAll('video').forEach(function(video) {
              try {
                var duration = Number(video.duration);
                var safeTarget = isNaN(duration) || duration <= 0
                    ? target
                    : Math.min(Math.max(0, target), duration);
                video.currentTime = safeTarget;
                if (video.paused) { video.play().catch(function(){}); }
              } catch (_) {}
            });
          } catch (_) {}
        }
        seekVideos(document);
        document.querySelectorAll('iframe').forEach(function(frame) {
          try {
            if (frame.contentWindow && frame.contentWindow.document) {
              seekVideos(frame.contentWindow.document);
            }
          } catch (_) {}
        });
      })();
    ''';

    try {
      await _embedWebViewController?.runJavaScript(script);
    } catch (_) {}
    try {
      await _windowsEmbedController?.executeScript(script);
    } catch (_) {}

    _embedPositionOffsetMs = safeMs;
    if (_embedWatchStopwatch.isRunning) {
      _embedWatchStopwatch.reset();
    } else {
      _embedWatchStopwatch
        ..reset()
        ..start();
    }
    _armControlsAutoHide();
  }

  Future<void> _seekPlayback(Duration target) async {
    if (_isDirectLink) {
      await _seekDirectPlayback(target);
      return;
    }
    await _seekEmbedPlayback(target);
  }



  void _initializePlayer(
    String streamUrl, {
    String? message,
    String? provider,
    bool isDirectLink = true,
  }) {
    if (_isDisposed) return;
    final previousPlayer = _player;
    final previousWindowsController = _windowsEmbedController;

    setState(() {
      _isDirectLink = isDirectLink;
      _errorMessage = null;
      _embedUrl = null;
      _player = null;
      _videoController = null;
      _embedWebViewController = null;
      _windowsEmbedController = null;
    });
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
        _loadingStatus = 'Video yukleniyor...';
      });
      final player = Player();
      _player = player;
      _videoController = VideoController(player);
      player.open(Media(streamUrl), play: true);
      _ensureDirectPlaybackStarts(player);
      setState(() {
        _isLoading = false;
      });
      _startProgressAutosave();
    } else {
      final localizedUrl = _applyEmbedSubtitleLanguage(streamUrl);
      setState(() {
        _embedUrl = localizedUrl;
        _loadingStatus = 'Uygulama ici oynatici hazirlaniyor...';
        _isLoading = true;
      });
      _initializeEmbedPlayer(localizedUrl);
      _startProgressAutosave();
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
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      if (!host.contains('vidsrc')) {
        return url;
      }

      final lang = widget.subtitleLanguage.trim().isEmpty
          ? 'tr'
          : widget.subtitleLanguage.trim().toLowerCase();
      final updatedParams = Map<String, String>.from(uri.queryParameters)
        ..['ds_lang'] = lang;
      return uri.replace(queryParameters: updatedParams).toString();
    } catch (_) {
      return url;
    }
  }

  Future<void> _initializeEmbedPlayer(String url) async {
    const userAgent =
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

    try {
      final uri = Uri.parse(url);
      _trustedEmbedHosts = _buildTrustedEmbedHosts(uri);

      if (defaultTargetPlatform == TargetPlatform.windows) {
        final controller = windows_webview.WebviewController();
        await controller.initialize();
        await controller.setPopupWindowPolicy(
          windows_webview.WebviewPopupWindowPolicy.deny,
        );
        await controller.loadUrl(uri.toString());

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
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) {
              if (_isDisposed || !mounted || attemptId != _embedLoadAttempt) {
                return;
              }
              setState(() {
                _loadingStatus = 'Embed kaynagi yukleniyor...';
              });
            },
            onPageFinished: (_) {
              if (_isDisposed || !mounted || attemptId != _embedLoadAttempt) {
                return;
              }
              unawaited(_injectEmbedAntiPopupScript(controller));
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
                _errorMessage = 'Sayfa yuklenemedi: ${error.description}';
                _isLoading = false;
              });
            },
          ),
        );

      _startEmbedTimeoutGuard(attemptId);
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
        _errorMessage = 'Uygulama ici oynatici baslatilamadi: $e';
        _isLoading = false;
      });
    }
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

  Future<void> _injectEmbedAntiPopupScript(WebViewController controller) async {
    const script = '''
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
      })();
    ''';
    try {
      await controller.runJavaScript(script);
    } catch (_) {
      // Non-fatal; keep playback going.
    }
  }

  void _startEmbedTimeoutGuard(int attemptId) {
    Future<void>.delayed(const Duration(seconds: 20), () {
      if (_isDisposed || !mounted || attemptId != _embedLoadAttempt) {
        return;
      }
      if (_isLoading && _errorMessage == null) {
        setState(() {
          _errorMessage =
              'Embed oynatici acilamadi. Lutfen baska bir kaynak deneyin.';
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
      for (final stream in streams) {
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
      if (!_isDirectLink || _player == null) {
        return;
      }

      final state = _player!.state;
      final hasStartedPlayback =
          state.playing || (state.position.inMilliseconds > 0);
      if (hasStartedPlayback) {
        return;
      }

      final fallbackUrl = embedFallback!['url']?.toString();
      if (fallbackUrl == null || fallbackUrl.isEmpty) {
        return;
      }

      try {
        await _player?.dispose();
      } catch (_) {}
      if (_isDisposed || !mounted || attempt != _directFallbackAttempt) {
        return;
      }

      _initializePlayer(
        fallbackUrl,
        provider: embedFallback['provider']?.toString(),
        isDirectLink: false,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Direkt kaynak acilamadi, embed oynaticiya gecildi.'),
          duration: Duration(seconds: 3),
        ),
      );
    });
  }

  Future<void> _fetchStreamAndInitialize() async {
    try {
      final addonService = ref.read(addonServiceProvider);

      setState(() {
        _loadingStatus = 'Yayin cozumleniyor...';
      });

      final data = await addonService.resolveFast(
        query: widget.title,
        tmdbId: widget.mediaId,
        contentType: _backendMediaType,
        season: widget.season,
        episode: widget.episode,
        addonId: widget.sourceId,
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
          _errorMessage = 'Yayin kaynagi bulunamadi';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Stream fetch failed: $e');
      setState(() {
        _errorMessage = 'Yayin kaynagi bulunamadi';
        _isLoading = false;
      });
    }
  }

  Future<void> _initPlaybackPosition() async {
    if (_player == null) {
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
    final repo = ref.read(watchHistoryRepositoryProvider);

    if (!_isDirectLink) {
      try {
        final elapsed = _currentEmbedPositionMs;
        if (elapsed < 10000) {
          return;
        }

        final runtimeMs = _episodeRuntimeMs();
        final position = elapsed.clamp(10000, runtimeMs - 1000);
        final isWatched = position >= (runtimeMs * 0.85);

        await repo.saveProgress(
          WatchHistory(
            mediaId: widget.mediaId,
            title: widget.title,
            mediaType: _normalizedMediaType,
            season: widget.season,
            episode: widget.episode,
            posterUrl: widget.posterUrl,
            backdropUrl: widget.backdropUrl,
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

    if (_player == null) return;
    try {
      final position = _player!.state.position;
      final duration = _player!.state.duration;

      if (position.inMilliseconds > 0 && duration.inMilliseconds > 0) {
        final isWatched =
            position.inMilliseconds >= duration.inMilliseconds * 0.9;

        await repo.saveProgress(
          WatchHistory(
            mediaId: widget.mediaId,
            title: widget.title,
            mediaType: _normalizedMediaType,
            season: widget.season,
            episode: widget.episode,
            posterUrl: widget.posterUrl,
            backdropUrl: widget.backdropUrl,
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
      _errorMessage = null;
      _isLoading = true;
      _loadingStatus = 'Video kaynagi araniyor...';
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
    _isDisposed = true;

    // Capture progress BEFORE stopping/nulling controllers.
    final player = _player;
    final win = _windowsEmbedController;
    final embedElapsedMs = _currentEmbedPositionMs;
    _embedWatchStopwatch.stop();

    int? capturedPositionMs;
    int? capturedDurationMs;
    if (_isDirectLink && player != null) {
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

    // Dispose controllers.
    if (player != null) {
      unawaited(player.dispose());
    }
    if (win != null) {
      try {
        win.dispose();
      } catch (_) {}
    }

    // Save progress using captured values.
    _saveFinalProgress(
      capturedPositionMs: capturedPositionMs,
      capturedDurationMs: capturedDurationMs,
      embedElapsedMs: embedElapsedMs,
    );
    _restoreSystemUiMode();
    super.dispose();
  }

  Future<void> _saveFinalProgress({
    int? capturedPositionMs,
    int? capturedDurationMs,
    required int embedElapsedMs,
  }) async {
    final repo = ref.read(watchHistoryRepositoryProvider);

    if (_isDirectLink &&
        capturedPositionMs != null &&
        capturedDurationMs != null &&
        capturedDurationMs > 0) {
      final isWatched = capturedPositionMs >= capturedDurationMs * 0.9;
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
    final isWatched = position >= (runtimeMs * 0.85);
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
    final content = _isLoading
        ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                _loadingStatus,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          )
        : _errorMessage != null
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
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _retryCurrentPlayback,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tekrar Dene'),
                ),
              ],
            ),
          )
        : !_isDirectLink && _embedUrl != null
        ? _buildEmbedView()
        : _videoController != null
        ? Video(controller: _videoController!, controls: NoVideoControls)
        : const SizedBox();
    final shouldBlockPlaybackSurfacePointer =
        _showOverlayControls &&
        !_isLoading &&
        _errorMessage == null &&
        ((_isDirectLink && _player != null) ||
            (!_isDirectLink && _embedUrl != null));
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
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleOverlayControls,
          child: Stack(
            children: [
              Positioned.fill(child: Center(child: renderedContent)),
              if (_showOverlayControls) ...[
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
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
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                            ),
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
                          if (_player != null)
                            StreamBuilder<Duration>(
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
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Text(
                                        _formatDuration(position),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Slider(
                                        value: position.inMilliseconds
                                            .toDouble()
                                            .clamp(0, max),
                                        min: 0,
                                        max: max,
                                        activeColor: Colors.red,
                                        inactiveColor: Colors.white30,
                                        onChanged: (value) {
                                          _player!.seek(
                                            Duration(
                                              milliseconds: value.toInt(),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Text(
                                        _formatDuration(duration),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_player != null)
                                StreamBuilder<bool>(
                                  stream: _player!.stream.playing,
                                  builder: (context, snapshot) {
                                    final isPlaying = snapshot.data ?? false;
                                    return IconButton(
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
                                        size: 44,
                                      ),
                                    );
                                  },
                                ),
                              const SizedBox(width: 8),
                              _buildSpeedButton(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              ],
              if (_showNextEpisodeOverlay)
                Positioned.fill(
                  child: Container(
                    color: Colors.black87,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.skip_next,
                            color: Colors.white,
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Sonraki Bolum',
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
                                child: const Text('Iptal'),
                              ),
                              const SizedBox(width: 16),
                              ElevatedButton.icon(
                                onPressed: _playNextEpisode,
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Izle'),
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

  Widget _buildSpeedButton() {
    if (_player == null) return const SizedBox.shrink();
    return StreamBuilder<double>(
      stream: _player!.stream.rate,
      builder: (context, snapshot) {
        final speed = snapshot.data ?? 1.0;
        return GestureDetector(
          onTap: () {
            final currentIndex = _speedOptions.indexOf(speed);
            final nextIndex = (currentIndex + 1) % _speedOptions.length;
            _player!.setRate(_speedOptions[nextIndex]);
            _armControlsAutoHide();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${speed}x',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      },
    );
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
        child: WebViewWidget(controller: _embedWebViewController!),
      ),
    );
  }
}
