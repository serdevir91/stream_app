import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as windows_webview;
import 'package:dio/dio.dart';
import '../providers/player_provider.dart';
import '../../domain/entities/watch_history.dart';
import '../../../../core/settings/app_settings_provider.dart';
import '../../../../core/backend/internal_backend.dart';

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
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  VlcPlayerController? _videoPlayerController;
  WebViewController? _embedWebViewController;
  windows_webview.WebviewController? _windowsEmbedController;
  bool _isDirectLink = true;
  bool _isDisposed = false;
  bool _isLoading = true;
  String? _errorMessage;
  String _loadingStatus = 'Video kaynağı aranıyor...';
  bool _initialized = false;
  String? _embedUrl;
  int _embedLoadAttempt = 0;
  int _directFallbackAttempt = 0;
  int _directAutoplayAttempt = 0;
  Timer? _progressAutosaveTimer;
  final Stopwatch _embedWatchStopwatch = Stopwatch();
  Set<String> _trustedEmbedHosts = const {};

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

  void _initializePlayer(
    String streamUrl, {
    String? message,
    String? provider,
    bool isDirectLink = true,
  }) {
    if (_isDisposed) return;
    final previousVideoController = _videoPlayerController;
    final previousWindowsController = _windowsEmbedController;

    setState(() {
      _isDirectLink = isDirectLink;
      _errorMessage = null;
      _embedUrl = null;
      _videoPlayerController = null;
      _embedWebViewController = null;
      _windowsEmbedController = null;
    });
    _directFallbackAttempt += 1;
    _progressAutosaveTimer?.cancel();
    _embedWatchStopwatch
      ..stop()
      ..reset();
    _directAutoplayAttempt += 1;
    if (previousVideoController != null) {
      unawaited(previousVideoController.stopRendererScanning());
      unawaited(previousVideoController.dispose());
    }
    if (previousWindowsController != null) {
      unawaited(previousWindowsController.dispose());
    }

    if (isDirectLink) {
      setState(() {
        _loadingStatus = 'Video yükleniyor...';
      });
      _videoPlayerController = VlcPlayerController.network(
        streamUrl,
        hwAcc: HwAcc.full,
        autoPlay: true,
        options: VlcPlayerOptions(),
      );
      _ensureDirectPlaybackStarts(_videoPlayerController!);
      setState(() {
        _isLoading = false;
      });
      _startProgressAutosave();
    } else {
      final localizedUrl = _applyEmbedSubtitleLanguage(streamUrl);
      // Embed URL — render inside the app with WebView
      setState(() {
        _embedUrl = localizedUrl;
        _loadingStatus = 'Uygulama ici oynatici hazirlaniyor...';
        _isLoading = true;
      });
      _initializeEmbedPlayer(localizedUrl);
      _startProgressAutosave();
    }

    if (provider != null && provider.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Kaynak: $provider'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      });
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
    });
  }

  void _ensureDirectPlaybackStarts(VlcPlayerController controller) {
    final attempt = ++_directAutoplayAttempt;

    Future<void> tryPlay(int retriesLeft) async {
      if (_isDisposed ||
          _videoPlayerController != controller ||
          attempt != _directAutoplayAttempt) {
        return;
      }
      try {
        await controller.play();
      } catch (_) {}
      if (controller.value.isPlaying || retriesLeft <= 0) {
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
      if (!_isDirectLink || _videoPlayerController == null) {
        return;
      }

      final value = _videoPlayerController!.value;
      final hasStartedPlayback =
          value.isPlaying ||
          (value.position.inMilliseconds > 0 && value.isInitialized);
      if (hasStartedPlayback) {
        return;
      }

      final fallbackUrl = embedFallback!['url']?.toString();
      if (fallbackUrl == null || fallbackUrl.isEmpty) {
        return;
      }

      try {
        await _videoPlayerController?.stopRendererScanning();
        await _videoPlayerController?.dispose();
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
      final settings = ref.read(appSettingsProvider);
      final dio = Dio(
        BaseOptions(
          baseUrl: settings.backendUrl,
          connectTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 18),
        ),
      );

      setState(() {
        _loadingStatus = 'Sunucuya bağlanılıyor...';
      });

      final response = await dio.get(
        '/api/stream',
        queryParameters: {
          'query': widget.title,
          'tmdb_id': widget.mediaId,
          'type': _backendMediaType,
          'season': widget.season,
          'episode': widget.episode,
          'fast': true,
          if (widget.sourceId != null) 'addon_id': widget.sourceId,
        },
      );

      if (response.statusCode == 200 && response.data['success']) {
        final responseMap = Map<String, dynamic>.from(response.data as Map);
        final streams =
            (responseMap['streams'] as List<dynamic>? ?? <dynamic>[])
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
        final selectedStream = _selectPreferredStream(streams);

        final streamUrl = selectedStream?['url'] ?? responseMap['stream_url'];
        final message = response.data['message'];
        final provider =
            selectedStream?['provider']?.toString() ??
            response.data['provider']?.toString();
        final isDirectLink =
            selectedStream?['is_direct_link'] ??
            response.data['is_direct_link'] ??
            true;

        if (_isDisposed) return;

        _initializePlayer(
          streamUrl.toString(),
          message: message?.toString(),
          provider: provider,
          isDirectLink: isDirectLink,
        );
        _startDirectLinkFallbackIfNeeded(
          streams: streams,
          selectedStream: selectedStream,
        );

        // Show fallback message if provided
        if (message != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(message),
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          });
        }
      } else {
        throw Exception('Stream endpoint returned failure');
      }
    } catch (e) {
      debugPrint('External stream fetch failed, trying internal: $e');

      final internalBackend = InternalBackendService();
      final data = await internalBackend.resolve(
        query: widget.title,
        tmdbId: widget.mediaId,
        type: _backendMediaType,
        season: widget.season,
        episode: widget.episode,
      );

      final List streams = data['streams'] ?? [];
      if (streams.isNotEmpty) {
        final stream = streams.first;
        if (_isDisposed) return;
        _initializePlayer(
          stream['url'].toString(),
          message: 'Internal Resolver',
          provider: stream['provider'],
          isDirectLink: stream['is_direct_link'] ?? false,
        );
      } else {
        setState(() {
          _errorMessage = 'Yayın kaynağı bulunamadı (Yerel hata)';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _initPlaybackPosition() async {
    if (_videoPlayerController == null) {
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
      for (int i = 0; i < 20; i++) {
        if (_isDisposed || _videoPlayerController == null) {
          return;
        }
        if (_videoPlayerController!.value.isInitialized) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }

      if (_isDisposed || _videoPlayerController == null) {
        return;
      }

      final rawTarget = history.duration > 0
          ? history.lastPosition.clamp(0, history.duration - 1500)
          : history.lastPosition;
      final seekTargetMs = rawTarget;
      await _videoPlayerController!.seekTo(
        Duration(milliseconds: seekTargetMs),
      );
      await _videoPlayerController!.play();
    } catch (e) {
      debugPrint('Resume seek failed: $e');
    }
  }

  Future<void> _saveProgress() async {
    final repo = ref.read(watchHistoryRepositoryProvider);

    if (!_isDirectLink) {
      try {
        final elapsed = _embedWatchStopwatch.elapsedMilliseconds;
        if (elapsed < 10000) {
          return;
        }

        final defaultDuration = _normalizedMediaType == 'tv'
            ? 45 * 60 * 1000
            : 2 * 60 * 60 * 1000;
        final position = elapsed.clamp(10000, defaultDuration - 1000);
        final isWatched = position >= (defaultDuration * 0.9);

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
            duration: defaultDuration,
            isWatched: isWatched,
          ),
        );
      } catch (e) {
        debugPrint("Error saving embed progress: $e");
      }
      return;
    }

    if (_videoPlayerController == null) return;
    try {
      final position = await _videoPlayerController!.getPosition();
      final duration = await _videoPlayerController!.getDuration();

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

  @override
  void dispose() {
    _progressAutosaveTimer?.cancel();
    _embedWatchStopwatch.stop();
    _isDisposed = true;
    _saveProgress().then((_) async {
      if (_videoPlayerController != null) {
        await _videoPlayerController!.stopRendererScanning();
        await _videoPlayerController!.dispose();
      }
      if (_windowsEmbedController != null) {
        await _windowsEmbedController!.dispose();
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.title),
        elevation: 0,
      ),
      body: Center(
        child: _isLoading
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
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 16,
                      ),
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
            // Embed (VidSrc) — show info card + open in browser button
            ? _buildEmbedView()
            : _videoPlayerController != null
            ? VlcPlayer(
                controller: _videoPlayerController!,
                aspectRatio: 16 / 9,
                placeholder: const Center(child: CircularProgressIndicator()),
              )
            : const SizedBox(),
      ),
      floatingActionButton: _videoPlayerController != null
          ? ValueListenableBuilder<VlcPlayerValue>(
              valueListenable: _videoPlayerController!,
              builder: (context, value, _) {
                final isPlaying = value.isPlaying;
                return FloatingActionButton(
                  onPressed: () async {
                    final controller = _videoPlayerController;
                    if (controller == null) {
                      return;
                    }
                    if (!value.isInitialized) {
                      await controller.play();
                      return;
                    }
                    if (isPlaying) {
                      await controller.pause();
                    } else {
                      await controller.play();
                    }
                  },
                  child: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                );
              },
            )
          : null,
    );
  }

  Widget _buildEmbedView() {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      if (_windowsEmbedController == null) {
        return const Center(child: CircularProgressIndicator());
      }

      return Column(
        children: [
          Expanded(child: windows_webview.Webview(_windowsEmbedController!)),
          if (_embedUrl != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Text(
                _embedUrl!,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      );
    }

    if (_embedWebViewController == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: WebViewWidget(controller: _embedWebViewController!),
            ),
          ),
          if (_embedUrl != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _embedUrl!,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}
