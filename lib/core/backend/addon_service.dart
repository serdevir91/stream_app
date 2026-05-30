import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'addons/addon_config_repository.dart';
import 'addons/base_addon.dart';
import 'addons/embed_addons.dart';
import 'addons/remote_addon.dart';
import 'addons/stremio_remote_addon.dart';
import 'addons/web_source_addon.dart';

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

  Future<void> init() async {
    _registerBuiltins();
    await _loadConfig();
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

  Future<(AddonManifest?, String?)> installFromUrl(String url) async {
    final normalizedUrl = _normalizeInputUrl(url);
    if (!normalizedUrl.startsWith('http')) {
      return (null, "url_must_start_with_http");
    }

    final (baseUrl, manifestUrls) = _buildManifestCandidates(normalizedUrl);

    Map<String, dynamic>? data;
    for (final manifestUrl in manifestUrls) {
      try {
        final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          followRedirects: true,
          headers: _headers,
        ));
        final response = await dio.get(manifestUrl);
        if (response.statusCode == 200) {
          data = response.data as Map<String, dynamic>;
          break;
        }
      } catch (_) {}
    }

    if (data == null) {
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
      return (
        null,
        "invalid_manifest_missing_id_name"
      );
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

    var baseUrl = (data['transportUrl'] ??
            data['transport_url'] ??
            data['baseUrl'] ??
            '')
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

  Future<Map<String, dynamic>> resolve({
    required String query,
    required String contentType,
    required int season,
    required int episode,
    String? addonId,
    String? tmdbId,
  }) async {
    final streams = <Map<String, dynamic>>[];
    final seenUrls = <String>{};

    void appendStreams(BaseAddon addon, List<StreamResult> items) {
      for (final item in items) {
        if (seenUrls.contains(item.url)) continue;
        seenUrls.add(item.url);
        streams.add({
          ...item.toJson(),
          'addon_id': addon.manifest.id,
          'provider': item.provider ?? addon.manifest.name,
        });
      }
    }

    if (addonId != null) {
      final addon = getAddon(addonId);
      if (addon == null) {
        return {'success': false, 'error': "addon_not_found_or_inactive", 'streams': []};
      }
      final addonStreams = await _tryAddonStreams(addon, query, contentType, season, episode, tmdbId: tmdbId);
      appendStreams(addon, addonStreams);
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

    for (final addon in enabledAddons) {
      if (!_addonSupportsType(addon, contentType)) continue;
      final addonStreams = await _tryAddonStreams(addon, query, contentType, season, episode, tmdbId: tmdbId);
      if (addonStreams.isNotEmpty) {
        appendStreams(addon, addonStreams);
      }
    }

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

  Future<Map<String, dynamic>> resolveFast({
    required String query,
    required String contentType,
    required int season,
    required int episode,
    String? addonId,
    String? tmdbId,
  }) async {
    if (addonId != null) {
      return resolve(
        query: query,
        contentType: contentType,
        season: season,
        episode: episode,
        addonId: addonId,
        tmdbId: tmdbId,
      );
    }

    final enabled = enabledAddons
        .where((a) => _addonSupportsType(a, contentType))
        .toList();

    const embedIds = {
      'builtin.vidsrc',
      'builtin.twoembed',
      'builtin.superembed',
      'builtin.vidlink',
      'builtin.embedsu',
    };
    enabled.sort((a, b) {
      final aIsEmbed = embedIds.contains(a.manifest.id) ? 0 : 1;
      final bIsEmbed = embedIds.contains(b.manifest.id) ? 0 : 1;
      return aIsEmbed.compareTo(bIsEmbed);
    });

    for (final addon in enabled) {
      final addonStreams = await _tryAddonStreams(addon, query, contentType, season, episode, tmdbId: tmdbId);
      if (addonStreams.isNotEmpty) {
        final seenUrls = <String>{};
        final streams = <Map<String, dynamic>>[];
        for (final item in addonStreams) {
          if (seenUrls.contains(item.url)) continue;
          seenUrls.add(item.url);
          streams.add({
            ...item.toJson(),
            'addon_id': addon.manifest.id,
            'provider': item.provider ?? addon.manifest.name,
          });
        }
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
    }

    return {
      'success': true,
      'query': query,
      'type': contentType,
      'season': season,
      'episode': episode,
      'count': 0,
      'streams': <Map<String, dynamic>>[],
    };
  }

  Future<List<StreamResult>> _tryAddonStreams(
    BaseAddon addon,
    String query,
    String contentType,
    int season,
    int episode, {
    String? tmdbId,
  }) async {
    final streams = <StreamResult>[];
    final seenUrls = <String>{};

    void dedupeAndAppend(List<StreamResult> items) {
      for (final item in items) {
        if (seenUrls.contains(item.url)) continue;
        seenUrls.add(item.url);
        streams.add(item);
      }
    }

    // 1) Try TMDB ID first for Stremio-like addons
    if (tmdbId != null && tmdbId.isNotEmpty) {
      try {
        final directTmdb = await addon.getStreams(tmdbId, contentType, season, episode);
        dedupeAndAppend(directTmdb);
      } catch (_) {}
    }

    // 2) Try direct query as content_id
    if (streams.isEmpty) {
      try {
        final directQuery = await addon.getStreams(query, contentType, season, episode);
        dedupeAndAppend(directQuery);
      } catch (_) {}
    }

    // 3) Search then resolve with found IDs
    if (streams.isEmpty) {
      try {
        final results = await addon.search(query, contentType);
        for (final result in results.take(5)) {
          final found = await addon.getStreams(result.id, contentType, season, episode);
          if (found.isNotEmpty) {
            dedupeAndAppend(found);
            break;
          }
        }
      } catch (_) {}
    }

    return streams;
  }

  bool _addonSupportsType(BaseAddon addon, String contentType) {
    final allowed = addon.manifest.types.map((t) => t.toLowerCase()).toSet();
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

    // Reinstall custom URLs
    for (final url in savedUrls.values) {
      final (manifest, _) = await installFromUrl(url);
      if (manifest != null && savedEnabled.containsKey(manifest.id)) {
        _enabled[manifest.id] = savedEnabled[manifest.id]!;
      }
    }

    // Reinstall custom manifests
    for (final item in savedManifests.values) {
      final payload = item['manifest'];
      if (payload is! Map<String, dynamic>) continue;
      final sourceLabel = (item['source_label'] ?? 'local-manifest.json').toString();
      final (manifest, _) = await installFromManifest(payload, sourceLabel: sourceLabel);
      if (manifest != null && savedEnabled.containsKey(manifest.id)) {
        _enabled[manifest.id] = savedEnabled[manifest.id]!;
      }
    }
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
    if (parsed == null) return (normalizedUrl, ['$normalizedUrl/manifest.json']);

    final path = parsed.path;

    if (path.endsWith('/manifest.json')) {
      final basePath = path.substring(0, path.length - '/manifest.json'.length);
      final manifestUrl = normalizedUrl;
      final baseUrl = Uri(scheme: parsed.scheme, userInfo: parsed.userInfo, host: parsed.host, port: parsed.port, path: basePath).toString().replaceAll(RegExp(r'/+$'), '');
      return (baseUrl, [manifestUrl]);
    }

    if (path.endsWith('.json')) {
      final basePath = path.substring(0, path.lastIndexOf('/'));
      final manifestUrl = normalizedUrl;
      final baseUrl = Uri(scheme: parsed.scheme, userInfo: parsed.userInfo, host: parsed.host, port: parsed.port, path: basePath).toString().replaceAll(RegExp(r'/+$'), '');
      return (baseUrl, [manifestUrl]);
    }

    final baseUrl = Uri(scheme: parsed.scheme, userInfo: parsed.userInfo, host: parsed.host, port: parsed.port, path: parsed.path).toString().replaceAll(RegExp(r'/+$'), '');
    return (baseUrl, [
      '$baseUrl/manifest.json',
      '$baseUrl/addon/manifest.json',
      '$baseUrl/stremio/v1/manifest.json',
    ]);
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
