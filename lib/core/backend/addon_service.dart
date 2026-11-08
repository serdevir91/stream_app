import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'addons/addon_config_repository.dart';
import 'addons/base_addon.dart';
import 'addons/embed_addons.dart';
import 'addons/remote_addon.dart';
import 'addons/stremio_remote_addon.dart';
import 'addons/web_source_addon.dart';
import 'source_ranking.dart';

class AddonService {
  final AddonConfigRepository _configRepo;
  final String? tmdbAccessToken;

  AddonService({
    required AddonConfigRepository configRepo,
    this.tmdbAccessToken,
  }) : _configRepo = configRepo;

  final Map<String, BaseAddon> _addons = {};
  final Map<String, bool> _enabled = {};
  final Map<String, String> _customUrls = {};
  final Map<String, Map<String, dynamic>> _customManifests = {};
  final Set<String> _removedBuiltins = {};

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'application/json, */*',
  };

  static const String _manifestCacheBox = 'addon_manifest_cache';

  Box<String>? get _manifestCache => Hive.isBoxOpen(_manifestCacheBox)
      ? Hive.box<String>(_manifestCacheBox)
      : null;

  Map<String, dynamic>? _cachedManifest(String url) {
    final raw = _manifestCache?.get(url);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> init() async {
    if (!Hive.isBoxOpen(_manifestCacheBox)) {
      try {
        await Hive.openBox<String>(_manifestCacheBox);
      } catch (_) {}
    }
    _registerBuiltins();
    await _loadConfig();
  }

  /// Replaces every addon with [addons], all enabled. Tests only.
  @visibleForTesting
  void debugReplaceAddons(List<BaseAddon> addons) {
    _addons.clear();
    _enabled.clear();
    for (final addon in addons) {
      _addons[addon.manifest.id] = addon;
      _enabled[addon.manifest.id] = true;
    }
  }

  Future<void> reloadConfig() async {
    _addons.clear();
    _enabled.clear();
    _customUrls.clear();
    _customManifests.clear();
    _removedBuiltins.clear();
    _registerBuiltins();
    await _loadConfig();
  }

  void _registerBuiltins() {
    for (final factory in [
      () => VixSrcAddon(),
      () => VidBoxAddon(),
      () => VidSrcAddon(),
      () => TwoEmbedAddon(),
      () => SuperEmbedAddon(),
      () => VidLinkAddon(),
      () => EmbedSUAddon(),
      () => VidEasyAddon(),
      () => SmashyStreamAddon(),
      () => PStreamAddon(),
      () => VidSrcCcAddon(),
      () => StreamImdbAddon(),
      () => DemoDirectAddon(),
      () => AnimeEmbedAddon(),
    ]) {
      final addon = factory();
      final id = addon.manifest.id;
      if (!_removedBuiltins.contains(id)) {
        _addons[id] = addon;
        _enabled.putIfAbsent(id, () => true);
      }
    }
  }

  List<Map<String, dynamic>> listAddons() {
    final result = <Map<String, dynamic>>[];
    for (final entry in _addons.entries) {
      final manifest = entry.value.manifest;
      result.add({
        ...manifest.toJson(),
        'enabled': _enabled[entry.key] ?? true,
      });
    }
    return result;
  }

  List<BaseAddon> get enabledAddons {
    return _addons.entries
        .where((e) => _enabled[e.key] ?? true)
        .map((e) => e.value)
        .toList();
  }

  BaseAddon? getAddon(String addonId) {
    if (_addons.containsKey(addonId) && (_enabled[addonId] ?? true)) {
      return _addons[addonId];
    }
    return null;
  }

  bool isBuiltinRemoved(String addonId) => _removedBuiltins.contains(addonId);

  void registerBuiltin(BaseAddon addon) {
    final id = addon.manifest.id;
    _addons[id] = addon;
    _enabled.putIfAbsent(id, () => true);
  }

  Future<Map<String, dynamic>?> _fetchManifest(String normalizedUrl) async {
    final (_, manifestUrls) = _buildManifestCandidates(normalizedUrl);
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 10),
        followRedirects: true,
        headers: _headers,
      ),
    );
    for (final manifestUrl in manifestUrls) {
      try {
        final response = await dio.get(manifestUrl);
        if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
          final data = response.data as Map<String, dynamic>;
          try {
            await _manifestCache?.put(normalizedUrl, jsonEncode(data));
          } catch (_) {}
          return data;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Installs the addon at [url]. With [cachedData] the manifest is taken
  /// from the local cache and no request is made.
  Future<(AddonManifest?, String?)> installFromUrl(
    String url, {
    Map<String, dynamic>? cachedData,
  }) async {
    final normalizedUrl = _normalizeInputUrl(url);
    if (!normalizedUrl.startsWith('http')) {
      return (null, "url_must_start_with_http");
    }

    final (baseUrl, _) = _buildManifestCandidates(normalizedUrl);

    final data = cachedData ?? await _fetchManifest(normalizedUrl);

    if (data == null) {
      if (normalizedUrl.contains('vidbox.cx') ||
          normalizedUrl.contains('vidbox.to')) {
        final addon = VidBoxAddon();
        _addons[addon.manifest.id] = addon;
        _enabled[addon.manifest.id] = true;
        _removedBuiltins.remove(addon.manifest.id);
        await _saveConfig();
        return (addon.manifest, null);
      }

      final manifest = _buildWebSourceManifest(normalizedUrl);
      final addon = WebSourceAddon(
        sourceUrl: normalizedUrl,
        manifest: manifest,
      );
      _addons[manifest.id] = addon;
      _enabled[manifest.id] = true;
      _customUrls[manifest.id] = normalizedUrl;
      _customManifests.remove(manifest.id);
      await _saveConfig();
      return (manifest, null);
    }

    if (!data.containsKey('id') || !data.containsKey('name')) {
      return (null, "invalid_manifest_missing_id_name");
    }

    try {
      var manifestTypes = data['types'] as List?;
      if (manifestTypes == null || manifestTypes.isEmpty) {
        manifestTypes = [];
        final catalogs = data['catalogs'] as List? ?? [];
        for (final catalog in catalogs) {
          if (catalog is! Map) continue;
          var catalogType = (catalog['type'] ?? '').toString().toLowerCase();
          if (catalogType == 'tv') catalogType = 'series';
          if ((catalogType == 'movie' || catalogType == 'series') &&
              !manifestTypes.contains(catalogType)) {
            manifestTypes.add(catalogType);
          }
        }
        if (manifestTypes.isEmpty) {
          manifestTypes = ['movie', 'series'];
        }
      }

      final manifest = AddonManifest(
        id: data['id'].toString(),
        name: data['name'].toString(),
        description: (data['description'] ?? '').toString(),
        version: (data['version'] ?? '1.0').toString(),
        types: List<String>.from(manifestTypes),
        icon: (data['icon'] ?? data['logo'] ?? '🔌').toString(),
        isBuiltin: false,
      );

      final existing = _addons[manifest.id];
      if (existing != null && existing.manifest.isBuiltin) {
        return (null, "builtin_addon_cannot_overwrite");
      }

      final isStremio = _detectStremioManifest(data);
      BaseAddon addon;
      if (isStremio) {
        addon = StremioRemoteAddon(
          baseUrl: baseUrl,
          manifest: manifest,
          rawManifest: data,
          tmdbAccessToken: tmdbAccessToken,
        );
      } else {
        addon = RemoteAddon(baseUrl: baseUrl, manifest: manifest);
      }

      _addons[manifest.id] = addon;
      _enabled[manifest.id] = true;
      _customUrls[manifest.id] = normalizedUrl;
      _customManifests.remove(manifest.id);
      await _saveConfig();
      return (manifest, null);
    } catch (e) {
      return (null, "manifest_parse_error");
    }
  }

  Future<(AddonManifest?, String?)> installFromManifest(
    Map<String, dynamic> data, {
    String sourceLabel = 'local-manifest.json',
  }) async {
    if (data.isEmpty) return (null, 'manifest_invalid_json');

    var baseUrl =
        (data['transportUrl'] ?? data['transport_url'] ?? data['baseUrl'] ?? '')
            .toString()
            .trim()
            .replaceAll(RegExp(r'/+$'), '');

    if (baseUrl.isEmpty) {
      return (null, "manifest_missing_transport_url");
    }
    if (!baseUrl.startsWith('http')) {
      return (null, 'transport_url_must_start_with_http');
    }
    if (!data.containsKey('id') || !data.containsKey('name')) {
      return (null, "manifest_missing_id_name");
    }

    try {
      var manifestTypes = data['types'] as List?;
      if (manifestTypes == null || manifestTypes.isEmpty) {
        manifestTypes = [];
        final catalogs = data['catalogs'] as List? ?? [];
        for (final catalog in catalogs) {
          if (catalog is! Map) continue;
          var catalogType = (catalog['type'] ?? '').toString().toLowerCase();
          if (catalogType == 'tv') catalogType = 'series';
          if ((catalogType == 'movie' || catalogType == 'series') &&
              !manifestTypes.contains(catalogType)) {
            manifestTypes.add(catalogType);
          }
        }
        if (manifestTypes.isEmpty) {
          manifestTypes = ['movie', 'series'];
        }
      }

      final manifest = AddonManifest(
        id: data['id'].toString(),
        name: data['name'].toString(),
        description: (data['description'] ?? '').toString(),
        version: (data['version'] ?? '1.0').toString(),
        types: List<String>.from(manifestTypes),
        icon: (data['icon'] ?? data['logo'] ?? '🔌').toString(),
        isBuiltin: false,
      );

      final existing = _addons[manifest.id];
      if (existing != null && existing.manifest.isBuiltin) {
        return (null, "builtin_addon_cannot_overwrite");
      }

      final isStremio = _detectStremioManifest(data);
      BaseAddon addon;
      if (isStremio) {
        addon = StremioRemoteAddon(
          baseUrl: baseUrl,
          manifest: manifest,
          rawManifest: data,
          tmdbAccessToken: tmdbAccessToken,
        );
      } else {
        addon = RemoteAddon(baseUrl: baseUrl, manifest: manifest);
      }

      _addons[manifest.id] = addon;
      _enabled[manifest.id] = true;
      _customUrls.remove(manifest.id);

      final manifestPayload = Map<String, dynamic>.from(data);
      if (!manifestPayload.containsKey('transportUrl') &&
          !manifestPayload.containsKey('transport_url')) {
        manifestPayload['transportUrl'] = baseUrl;
      }
      _customManifests[manifest.id] = {
        'manifest': manifestPayload,
        'source_label': sourceLabel,
      };
      await _saveConfig();
      return (manifest, null);
    } catch (e) {
      return (null, 'manifest_parse_error');
    }
  }

  bool remove(String addonId) {
    if (!_addons.containsKey(addonId)) return false;
    final manifest = _addons[addonId]!.manifest;
    if (manifest.isBuiltin) {
      _removedBuiltins.add(addonId);
    }
    _addons.remove(addonId);
    _enabled.remove(addonId);
    _customUrls.remove(addonId);
    _customManifests.remove(addonId);
    _saveConfig();
    return true;
  }

  void setEnabled(String addonId, bool enabled) {
    if (_addons.containsKey(addonId)) {
      _enabled[addonId] = enabled;
      _saveConfig();
    }
  }

  /// Language whose dub/subtitle tags get a ranking bonus ('tr', 'ar', ...).
  String preferredLanguage = 'en';

  static const Duration _addonTimeout = Duration(seconds: 8);
  static const Duration _cacheTtl = Duration(minutes: 20);
  static const Duration _fastGrace = Duration(seconds: 3);

  final Map<String, _ResolveJob> _jobs = {};
  final Map<String, ({DateTime at, List<Map<String, dynamic>> streams})> _cache = {};

  static String _jobKey(
    String query,
    String contentType,
    int season,
    int episode,
    String? addonId,
    String? tmdbId,
  ) {
    final id = (tmdbId != null && tmdbId.isNotEmpty) ? tmdbId : query.toLowerCase();
    final s = contentType == 'movie' ? 0 : season;
    final e = contentType == 'movie' ? 0 : episode;
    return '$contentType|$id|$s|$e|${addonId ?? '*'}';
  }

  /// Streams for a title, emitted as each addon answers. Every event holds
  /// the full ranked list so far. All addons run at once, each capped at
  /// [_addonTimeout]; results are cached for [_cacheTtl] and a request for
  /// a title that is already resolving joins that run.
  Stream<ResolveProgress> resolveStream({
    required String query,
    required String contentType,
    required int season,
    required int episode,
    String? addonId,
    String? tmdbId,
    bool preferAnimeSources = false,
  }) {
    final key = _jobKey(query, contentType, season, episode, addonId, tmdbId);
    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.at) < _cacheTtl) {
      final ranked = _rank(cached.streams, preferAnimeSources);
      return Stream.value(ResolveProgress(ranked, 1, 1));
    }
    if (addonId != null) {
      // A prefetch over all addons already holds this addon's streams.
      final all = _cache[_jobKey(query, contentType, season, episode, null, tmdbId)];
      if (all != null && DateTime.now().difference(all.at) < _cacheTtl) {
        final mine = all.streams.where((s) => s['addon_id'] == addonId).toList();
        if (mine.isNotEmpty) {
          return Stream.value(ResolveProgress(_rank(mine, preferAnimeSources), 1, 1));
        }
      }
    }
    final job = _jobs[key] ??
        _startJob(
          key,
          query: query,
          contentType: contentType,
          season: season,
          episode: episode,
          addonId: addonId,
          tmdbId: tmdbId,
          preferAnimeSources: preferAnimeSources,
        );
    late final StreamController<ResolveProgress> controller;
    controller = StreamController<ResolveProgress>(
      onListen: () {
        controller.add(job.snapshot);
        if (job.isDone) {
          controller.close();
        } else {
          job.listeners.add(controller);
        }
      },
      onCancel: () => job.listeners.remove(controller),
    );
    return controller.stream;
  }

  /// Starts resolving in the background so a later play tap is instant.
  void prefetch({
    required String query,
    required String contentType,
    required int season,
    required int episode,
    String? tmdbId,
    bool preferAnimeSources = false,
  }) {
    final key = _jobKey(query, contentType, season, episode, null, tmdbId);
    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.at) < _cacheTtl) return;
    if (_jobs.containsKey(key)) return;
    _startJob(
      key,
      query: query,
      contentType: contentType,
      season: season,
      episode: episode,
      tmdbId: tmdbId,
      preferAnimeSources: preferAnimeSources,
    );
  }

  /// Feeds playback outcomes back into the ranking.
  void reportPlayback(String? addonId, {required bool ok}) {
    if (addonId == null || addonId.isEmpty) return;
    SourceStats.recordPlayback(addonId, ok: ok);
  }

  void invalidate({
    required String query,
    required String contentType,
    required int season,
    required int episode,
    String? tmdbId,
  }) {
    _cache.remove(_jobKey(query, contentType, season, episode, null, tmdbId));
  }

  List<Map<String, dynamic>> _rank(
    List<Map<String, dynamic>> streams,
    bool preferAnimeSources,
  ) {
    return SourceRanking.rank(
      streams,
      reliabilityOf: SourceStats.of,
      orderOf: (id) => _addonPriority(id, preferAnimeSources),
      language: preferredLanguage,
    );
  }

  _ResolveJob _startJob(
    String key, {
    required String query,
    required String contentType,
    required int season,
    required int episode,
    String? addonId,
    String? tmdbId,
    bool preferAnimeSources = false,
  }) {
    final List<BaseAddon> addons;
    if (addonId != null) {
      final addon = getAddon(addonId);
      addons = addon == null ? const [] : [addon];
    } else {
      addons = enabledAddons
          .where((a) => _addonSupportsType(a, contentType))
          .toList();
    }

    final job = _ResolveJob(addons.length, (raw) => _rank(raw, preferAnimeSources));
    if (addons.isEmpty) return job;
    _jobs[key] = job;

    for (final addon in addons) {
      final watch = Stopwatch()..start();
      _tryAddonStreams(
        addon,
        query,
        contentType,
        season,
        episode,
        tmdbId: tmdbId,
      )
          .timeout(_addonTimeout, onTimeout: () => const <StreamResult>[])
          .catchError((Object _) => const <StreamResult>[])
          .then((items) {
        SourceStats.recordResolve(
          addon.manifest.id,
          found: items.isNotEmpty,
          elapsedMs: watch.elapsedMilliseconds,
        );
        job.add([
          for (final item in items)
            {
              ...item.toJson(),
              'addon_id': addon.manifest.id,
              'provider': item.provider ?? addon.manifest.name,
            },
        ]);
        if (job.isDone) {
          _jobs.remove(key);
          if (job.raw.isNotEmpty) {
            _cache[key] = (at: DateTime.now(), streams: List.of(job.raw));
          }
        }
      });
    }
    return job;
  }

  Map<String, dynamic> _result(
    String query,
    String contentType,
    int season,
    int episode,
    List<Map<String, dynamic>> streams,
  ) {
    return {
      'success': true,
      'query': query,
      'type': contentType,
      'season': season,
      'episode': episode,
      'count': streams.length,
      'streams': streams,
    };
  }

  /// Every addon's streams, ranked best first.
  Future<Map<String, dynamic>> resolve({
    required String query,
    required String contentType,
    required int season,
    required int episode,
    String? addonId,
    String? tmdbId,
    bool preferAnimeSources = false,
  }) async {
    if (addonId != null && getAddon(addonId) == null) {
      return {
        'success': false,
        'error': 'addon_not_found_or_inactive',
        'streams': [],
      };
    }
    final last = await resolveStream(
      query: query,
      contentType: contentType,
      season: season,
      episode: episode,
      addonId: addonId,
      tmdbId: tmdbId,
      preferAnimeSources: preferAnimeSources,
    ).last;
    return _result(query, contentType, season, episode, last.streams);
  }

  /// Returns as soon as there is something good to play: at once when a
  /// trusted addon answered, otherwise after [_fastGrace] with whatever has
  /// arrived (or the first answer after that), or when all addons are done.
  /// Slower addons keep running and land in the cache.
  Future<Map<String, dynamic>> resolveFast({
    required String query,
    required String contentType,
    required int season,
    required int episode,
    String? addonId,
    String? tmdbId,
    bool preferAnimeSources = false,
  }) async {
    final completer = Completer<List<Map<String, dynamic>>>();
    var latest = const <Map<String, dynamic>>[];
    var graceOver = false;

    void finish() {
      if (!completer.isCompleted) completer.complete(latest);
    }

    final timer = Timer(_fastGrace, () {
      graceOver = true;
      if (latest.isNotEmpty) finish();
    });
    final sub = resolveStream(
      query: query,
      contentType: contentType,
      season: season,
      episode: episode,
      addonId: addonId,
      tmdbId: tmdbId,
      preferAnimeSources: preferAnimeSources,
    ).listen(
      (progress) {
        latest = progress.streams;
        if (progress.done) return finish();
        if (latest.isEmpty) return;
        final best = (latest.first['addon_id'] ?? '').toString();
        if (graceOver || SourceStats.of(best).isTrusted) finish();
      },
      onError: (Object _) => finish(),
      onDone: finish,
    );
    final streams = await completer.future;
    timer.cancel();
    await sub.cancel();
    return _result(query, contentType, season, episode, streams);
  }

  int _addonPriority(String addonId, bool preferAnimeSources) {
    final animeOrder = <String, int>{
      'builtin.anime_embed': 0,
      'builtin.vidbox': 1,
      'builtin.streamimdb': 2,
      'builtin.vidsrccc': 3,
      'builtin.vidsrc': 4,
      'builtin.videasy': 5,
      'builtin.embedsu': 6,
      'builtin.pstream': 7,
      'builtin.smashystream': 8,
      'builtin.vidlink': 9,
      'builtin.twoembed': 10,
      'builtin.superembed': 11,
    };
    final defaultOrder = <String, int>{
      'builtin.vidbox': 0,
      'builtin.vidsrc': 1,
      'builtin.vidsrccc': 2,
      'builtin.streamimdb': 3,
      'builtin.videasy': 4,
      'builtin.embedsu': 5,
      'builtin.pstream': 6,
      'builtin.smashystream': 7,
      'builtin.vidlink': 8,
      'builtin.twoembed': 9,
      'builtin.superembed': 10,
    };
    final order = preferAnimeSources ? animeOrder : defaultOrder;
    return order[addonId] ?? 100;
  }

  Future<List<StreamResult>> _tryAddonStreams(
    BaseAddon addon,
    String query,
    String contentType,
    int season,
    int episode, {
    String? tmdbId,
  }) async {
    Future<List<StreamResult>> attempt(String id) async {
      try {
        return await addon.getStreams(id, contentType, season, episode);
      } catch (_) {
        return const <StreamResult>[];
      }
    }

    List<StreamResult> dedupe(List<StreamResult> items) {
      final seen = <String>{};
      return [for (final item in items) if (seen.add(item.url)) item];
    }

    final hasTmdb = tmdbId != null && tmdbId.isNotEmpty;
    final askQuery = !hasTmdb || query != tmdbId;

    // Remote addons answer over the network, so the id and the title lookup
    // run side by side. Built-in embed addons build their URL from the id,
    // where a title lookup would only add a wasted request.
    final parallel = hasTmdb && askQuery && !addon.manifest.isBuiltin;
    final byTmdb = hasTmdb ? attempt(tmdbId) : null;
    final byQuery = parallel ? attempt(query) : null;

    if (byTmdb != null) {
      final found = await byTmdb;
      if (found.isNotEmpty) return dedupe(found);
    }
    if (askQuery) {
      final found = await (byQuery ?? attempt(query));
      if (found.isNotEmpty) return dedupe(found);
    }

    // Last resort: search the addon's catalog and try the first hits.
    try {
      final results = await addon.search(query, contentType);
      for (final result in results.take(5)) {
        final found = await attempt(result.id);
        if (found.isNotEmpty) return dedupe(found);
      }
    } catch (_) {}
    return const <StreamResult>[];
  }

  bool _addonSupportsType(BaseAddon addon, String contentType) {
    final allowed = addon.manifest.types.map((t) => t.toLowerCase()).toSet();
    if (contentType == 'anime') {
      return allowed.contains('anime') || allowed.contains('series') || allowed.contains('tv');
    }
    if (contentType == 'series') {
      return allowed.contains('series') || allowed.contains('tv');
    }
    return allowed.contains('movie');
  }

  Future<void> _saveConfig() async {
    await _configRepo.saveAll(
      enabled: _enabled,
      customUrls: _customUrls,
      customManifests: _customManifests,
      removedBuiltins: _removedBuiltins.toList(),
    );
  }

  Future<void> _loadConfig() async {
    final savedEnabled = _configRepo.getEnabled();
    final savedUrls = _configRepo.getCustomUrls();
    final savedManifests = _configRepo.getCustomManifests();
    final savedRemoved = _configRepo.getRemovedBuiltins();

    _removedBuiltins.addAll(savedRemoved);
    _enabled.addAll(savedEnabled);

    void restoreEnabled(AddonManifest? manifest) {
      if (manifest != null && savedEnabled.containsKey(manifest.id)) {
        _enabled[manifest.id] = savedEnabled[manifest.id]!;
      }
    }

    // Reinstall custom URLs: cached manifests load at once, the rest are
    // fetched side by side instead of one after another.
    final fetches = <Future<void>>[];
    final refresh = <String>[];
    for (final url in savedUrls.values) {
      final cached = _cachedManifest(url);
      if (cached != null) {
        final (manifest, _) = await installFromUrl(url, cachedData: cached);
        restoreEnabled(manifest);
        refresh.add(url);
      } else {
        fetches.add(
          installFromUrl(url)
              .timeout(
                const Duration(seconds: 12),
                onTimeout: () => (null, 'timeout'),
              )
              .then((result) => restoreEnabled(result.$1)),
        );
      }
    }
    await Future.wait(fetches);
    if (refresh.isNotEmpty) {
      unawaited(_refreshManifests(refresh));
    }

    // Reinstall custom manifests
    for (final item in savedManifests.values) {
      final payload = item['manifest'];
      if (payload is! Map<String, dynamic>) continue;
      final sourceLabel = (item['source_label'] ?? 'local-manifest.json')
          .toString();
      final (manifest, _) = await installFromManifest(
        payload,
        sourceLabel: sourceLabel,
      );
      if (manifest != null && savedEnabled.containsKey(manifest.id)) {
        _enabled[manifest.id] = savedEnabled[manifest.id]!;
      }
    }
  }

  /// Re-fetches cached manifests after startup. A failed fetch keeps the
  /// cached addon; the user's enabled/disabled choice is kept either way.
  Future<void> _refreshManifests(List<String> urls) async {
    await Future<void>.delayed(const Duration(seconds: 4));
    await Future.wait(
      urls.map((url) async {
        final before = _manifestCache?.get(url);
        final data = await _fetchManifest(url);
        if (data == null || _manifestCache?.get(url) == before) return;
        final enabledBefore = Map<String, bool>.of(_enabled);
        final (manifest, _) = await installFromUrl(url, cachedData: data);
        final previous = manifest == null ? null : enabledBefore[manifest.id];
        if (previous != null && _enabled[manifest!.id] != previous) {
          _enabled[manifest.id] = previous;
          await _saveConfig();
        }
      }),
    );
  }

  static String _normalizeInputUrl(String rawUrl) {
    var value = rawUrl.trim();
    if (value.startsWith('stremio://')) {
      value = 'https://${value.substring(10)}';
    }

    var parsed = Uri.tryParse(value);
    if (parsed == null || parsed.scheme.isEmpty) {
      value = 'https://$value';
      parsed = Uri.tryParse(value);
    }

    if (parsed == null) return value;

    final cleanPath = parsed.path.replaceAll(RegExp(r'/+$'), '');
    return parsed.replace(path: cleanPath, fragment: '').toString();
  }

  static (String, List<String>) _buildManifestCandidates(String normalizedUrl) {
    final parsed = Uri.tryParse(normalizedUrl);
    if (parsed == null) {
      return (normalizedUrl, ['$normalizedUrl/manifest.json']);
    }

    final path = parsed.path;

    if (path.endsWith('/manifest.json')) {
      final basePath = path.substring(0, path.length - '/manifest.json'.length);
      final manifestUrl = normalizedUrl;
      final baseUrl = Uri(
        scheme: parsed.scheme,
        userInfo: parsed.userInfo,
        host: parsed.host,
        port: parsed.port,
        path: basePath,
      ).toString().replaceAll(RegExp(r'/+$'), '');
      return (baseUrl, [manifestUrl]);
    }

    if (path.endsWith('.json')) {
      final basePath = path.substring(0, path.lastIndexOf('/'));
      final manifestUrl = normalizedUrl;
      final baseUrl = Uri(
        scheme: parsed.scheme,
        userInfo: parsed.userInfo,
        host: parsed.host,
        port: parsed.port,
        path: basePath,
      ).toString().replaceAll(RegExp(r'/+$'), '');
      return (baseUrl, [manifestUrl]);
    }

    final baseUrl = Uri(
      scheme: parsed.scheme,
      userInfo: parsed.userInfo,
      host: parsed.host,
      port: parsed.port,
      path: parsed.path,
    ).toString().replaceAll(RegExp(r'/+$'), '');
    return (
      baseUrl,
      [
        '$baseUrl/manifest.json',
        '$baseUrl/addon/manifest.json',
        '$baseUrl/stremio/v1/manifest.json',
      ],
    );
  }

  static bool _detectStremioManifest(Map<String, dynamic> data) {
    final resources = data['resources'];
    if (resources is List && resources.isNotEmpty) return true;
    return data.containsKey('idPrefixes') ||
        data.containsKey('catalogs') ||
        data.containsKey('behaviorHints');
  }

  static AddonManifest _buildWebSourceManifest(String url) {
    final parsed = Uri.tryParse(url);
    final host = parsed?.host ?? 'web-source';
    final digest = sha1.convert(utf8.encode(url)).toString().substring(0, 10);

    return AddonManifest(
      id: 'websource.$digest',
      name: 'Web Source ($host)',
      description: 'Streams extracted directly from web pages/links',
      version: '1.0',
      types: ['movie', 'series'],
      icon: '🌐',
      isBuiltin: false,
    );
  }
}

/// One step of a running resolve: the ranked streams so far and how many
/// addons have answered.
class ResolveProgress {
  final List<Map<String, dynamic>> streams;
  final int finished;
  final int total;

  const ResolveProgress(this.streams, this.finished, this.total);

  bool get done => finished >= total;
}

class _ResolveJob {
  final int total;
  final List<Map<String, dynamic>> Function(List<Map<String, dynamic>>) _rank;
  final List<Map<String, dynamic>> raw = [];
  final Set<String> _seen = {};
  final List<StreamController<ResolveProgress>> listeners = [];
  int finished = 0;
  List<Map<String, dynamic>> _ranked = const [];

  _ResolveJob(this.total, this._rank);

  bool get isDone => finished >= total;

  ResolveProgress get snapshot => ResolveProgress(_ranked, finished, total);

  void add(List<Map<String, dynamic>> streams) {
    for (final s in streams) {
      final url = (s['url'] ?? '').toString();
      if (url.isEmpty || !_seen.add(url)) continue;
      raw.add(s);
    }
    finished++;
    _ranked = _rank(raw);
    final progress = snapshot;
    for (final l in List.of(listeners)) {
      l.add(progress);
      if (progress.done) l.close();
    }
    if (progress.done) listeners.clear();
  }
}
