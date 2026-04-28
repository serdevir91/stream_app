import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_text.dart';
import '../../../../core/settings/app_settings_provider.dart';
import '../../../../core/backend/internal_backend.dart';

class AddonInfo {
  final String id;
  final String name;
  final String description;
  final String version;
  final List<String> types;
  final String? icon;
  final bool isBuiltin;
  bool enabled;

  AddonInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.types,
    this.icon,
    required this.isBuiltin,
    required this.enabled,
  });

  factory AddonInfo.fromJson(Map<String, dynamic> json) {
    return AddonInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      version: json['version'] ?? '1.0',
      types: List<String>.from(json['types'] ?? []),
      icon: json['icon'],
      isBuiltin: json['is_builtin'] ?? false,
      enabled: json['enabled'] ?? true,
    );
  }
}

class AddonsNotifier extends Notifier<List<AddonInfo>> {
  late Dio _dio;
  late InternalBackendService _internalBackend;

  @override
  List<AddonInfo> build() {
    final settings = ref.watch(appSettingsProvider);
    _internalBackend = InternalBackendService();

    _dio = Dio(
      BaseOptions(
        baseUrl: settings.backendUrl,
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 5),
      ),
    );
    
    Future.microtask(() => fetchAddons());
    
    return [];
  }

  Future<void> fetchAddons() async {
    try {
      final response = await _dio.get('/api/addons');
      if (response.statusCode == 200) {
        final List addons = response.data['addons'];
        state = addons.map((a) => AddonInfo.fromJson(a)).toList();
      }
    } catch (e) {
      debugPrint('External backend unreachable, using internal backend: $e');
      final internalData = await _internalBackend.getAddons();
      final List addons = internalData['addons'];
      state = addons.map((a) => AddonInfo.fromJson(a)).toList();
    }
  }

  Future<String?> installAddon(String url) async {
    if (url.trim().isEmpty) {
      return 'URL is empty';
    }
    return _installWithPayload({'url': url});
  }

  Future<String?> installAddonManifest(
    Map<String, dynamic> manifest, {
    String sourceLabel = 'local-manifest.json',
  }) async {
    return _installWithPayload(
      {'manifest': manifest, 'source_label': sourceLabel},
      useManifestEndpoint: true,
    );
  }

  Future<String?> _installWithPayload(
    Map<String, dynamic> payload, {
    bool useManifestEndpoint = false,
  }) async {
    try {
      final response = await _dio.post(
        useManifestEndpoint
            ? '/api/addons/install/manifest'
            : '/api/addons/install',
        data: payload,
      );
      if (response.statusCode == 200 && response.data['success']) {
        await fetchAddons();
        return null;
      }
      return response.data['detail'] ?? 'Unknown error';
    } on DioException catch (e) {
      final detail = e.response?.data;
      if (detail is Map) {
        return detail['detail'] ?? 'Add-on could not be installed';
      }
      return 'Server error: ${e.message}';
    } catch (e) {
      return 'Unexpected error: $e';
    }
  }

  Future<bool> removeAddon(String addonId) async {
    try {
      final response = await _dio.post('/api/addons/remove/$addonId');
      if (response.statusCode == 200 && response.data['success']) {
        await fetchAddons();
        return true;
      }
    } catch (e) {
      debugPrint('Error removing addon: $e');
    }
    return false;
  }

  Future<void> toggleAddon(String addonId, bool enabled) async {
    try {
      await _dio.post(
        '/api/addons/toggle',
        data: {'addon_id': addonId, 'enabled': enabled},
      );

      state = [
        for (final addon in state)
          if (addon.id == addonId)
            AddonInfo(
              id: addon.id,
              name: addon.name,
              description: addon.description,
              version: addon.version,
              types: addon.types,
              icon: addon.icon,
              isBuiltin: addon.isBuiltin,
              enabled: enabled,
            )
          else
            addon,
      ];
    } catch (e) {
      debugPrint('Error toggling addon: $e');
    }
  }
}

final addonsProvider = NotifierProvider<AddonsNotifier, List<AddonInfo>>(
  AddonsNotifier.new,
);

class AddonManagerScreen extends ConsumerWidget {
  const AddonManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(appTextProvider);
    final addons = ref.watch(addonsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          text.t('addon_management'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(addonsProvider.notifier).fetchAddons(),
          ),
        ],
      ),
      body: addons.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.extension_off,
                      size: 48,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      text.t('no_addons_title'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      text.t('no_addons_desc'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () =>
                          ref.read(addonsProvider.notifier).fetchAddons(),
                      icon: const Icon(Icons.refresh),
                      label: Text(text.t('refresh')),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              itemCount: addons.length,
              itemBuilder: (context, index) {
                final addon = addons[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: Colors.grey.shade900,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: addon.enabled
                                  ? Colors.deepPurple
                                  : Colors.grey.shade700,
                              radius: 22,
                              child: Text(
                                addon.icon ?? '+',
                                style: const TextStyle(fontSize: 20),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                addon.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            Switch(
                              value: addon.enabled,
                              onChanged: (val) {
                                ref
                                    .read(addonsProvider.notifier)
                                    .toggleAddon(addon.id, val);
                              },
                              activeThumbColor: Colors.greenAccent,
                            ),
                          ],
                        ),
                        if (addon.isBuiltin)
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.shade700,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              text.t('builtin'),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          addon.description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey.shade300),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade800,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'v${addon.version}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade300,
                                ),
                              ),
                            ),
                            ...addon.types.map(
                              (t) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade800,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  t,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(text.t('remove_addon')),
                                  content: Text(
                                    '"${addon.name}" ${text.t('remove_addon_confirm')}',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: Text(text.t('cancel')),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, true),
                                      child: Text(
                                        text.t('remove_button'),
                                        style: const TextStyle(
                                          color: Colors.red,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                ref
                                    .read(addonsProvider.notifier)
                                    .removeAddon(addon.id);
                              }
                            },
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                            label: Text(
                              text.t('remove_button'),
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showInstallOptions(context, ref),
        icon: const Icon(Icons.add),
        label: Text(text.t('add_source_addon')),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
    );
  }

  void _showInstallOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Install from URL'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showInstallDialog(context, ref);
                },
              ),
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: const Text('Install from file (.json)'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndInstallManifestFile(context, ref);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndInstallManifestFile(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File could not be read.', style: TextStyle(fontSize: 13)),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            duration: Duration(seconds: 3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
          ),
        );
      }
      return;
    }

    try {
      final content = utf8.decode(bytes);
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        throw const FormatException('Manifest must be a JSON object');
      }
      final manifest = Map<String, dynamic>.from(decoded);

      final error = await ref.read(addonsProvider.notifier).installAddonManifest(
        manifest,
        sourceLabel: file.name,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error == null ? 'OK' : 'Error: $error', style: const TextStyle(fontSize: 13)),
            backgroundColor: error == null ? Colors.green : Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            duration: Duration(seconds: error == null ? 2 : 5),
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Manifest parse error: $e', style: const TextStyle(fontSize: 13)),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            duration: const Duration(seconds: 5),
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
          ),
        );
      }
    }
  }

  void _showInstallDialog(BuildContext context, WidgetRef ref) {
    final text = ref.read(appTextProvider);
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(text.t('add_addon')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${text.t('install_help')}\n'
              'Example: https://example-addon.com/manifest.json\n'
              'Example: https://example-site.com/movie-page',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'https://addon-or-site-link',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(text.t('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isEmpty) {
                return;
              }

              Navigator.pop(ctx);
              final error = await ref
                  .read(addonsProvider.notifier)
                  .installAddon(url);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(error == null ? 'OK' : 'Error: $error', style: const TextStyle(fontSize: 13)),
                    backgroundColor: error == null ? Colors.green : Colors.red,
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    duration: Duration(seconds: error == null ? 2 : 5),
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
                  ),
                );
              }
            },
            child: Text(text.t('add')),
          ),
        ],
      ),
    );
  }
}
