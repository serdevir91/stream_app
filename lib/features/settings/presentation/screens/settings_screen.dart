import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/backup/local_backup_service.dart';
import '../../../../core/i18n/app_text.dart';
import '../../../../core/settings/app_settings.dart';
import '../../../../core/settings/app_settings_provider.dart';
import '../../../../core/sync/device_identity.dart';
import '../../../../core/sync/sync_provider.dart';
import '../../../library/presentation/providers/library_provider.dart';
import '../../../library/presentation/providers/watched_provider.dart';
import '../../../addons/presentation/screens/addon_manager_screen.dart';
import '../../../sources/presentation/providers/sources_provider.dart';
import '../../../sources/presentation/screens/sources_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _tmdbTokenController;
  late TextEditingController _wyzieApiKeyController;
  late TextEditingController _backendUrlController;
  String _appLanguage = 'en';
  String _subtitleLanguage = 'en';
  bool _autoSelectSource = true;
  bool _autoSelectSubtitle = true;
  String _librarySort = 'recent';
  bool _watchHistoryEnabled = true;
  bool _newEpisodeNotificationsEnabled = true;
  int _completionPercentage = 90;
  String _preferredSourceId = '';
  bool _initialized = false;
  bool _isSaving = false;
  bool _isApiFieldsVisible = false;
  String _videoPlayer = 'native';
  late final TextEditingController _syncServerUrlController;

  @override
  void initState() {
    super.initState();
    _syncServerUrlController = TextEditingController(text: _syncServerUrl);
    _loadSavedSyncServerUrl();
  }

  @override
  void dispose() {
    if (_initialized) {
      _tmdbTokenController.dispose();
      _wyzieApiKeyController.dispose();
      _backendUrlController.dispose();
    }
    _syncServerUrlController.dispose();
    super.dispose();
  }

  void _ensureInitialized(AppSettings settings) {
    if (_initialized) {
      return;
    }
    _appLanguage = settings.appLanguage;
    _subtitleLanguage = settings.subtitleLanguage;
    _autoSelectSource = settings.autoSelectSource;
    _autoSelectSubtitle = settings.autoSelectSubtitle;
    _librarySort = settings.librarySort;
    _watchHistoryEnabled = settings.watchHistoryEnabled;
    _newEpisodeNotificationsEnabled = settings.newEpisodeNotificationsEnabled;
    _completionPercentage = settings.completionPercentage;
    _preferredSourceId = settings.preferredSourceId;
    _videoPlayer = settings.videoPlayer;
    _tmdbTokenController = TextEditingController(
      text: settings.tmdbAccessToken,
    );
    _wyzieApiKeyController = TextEditingController(text: settings.wyzieApiKey);
    _backendUrlController = TextEditingController(text: settings.backendUrl);
    _isApiFieldsVisible = settings.tmdbAccessToken.trim().isEmpty;
    _initialized = true;
  }

  String _maskToken(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      return 'Not set';
    }
    if (trimmed.length <= 8) {
      return 'Configured';
    }
    final first = trimmed.substring(0, 4);
    final last = trimmed.substring(trimmed.length - 4);
    return '$first****$last';
  }

  Future<void> _saveSettings() async {
    if (_isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final current = ref.read(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final activeAddonIds = ref
        .read(addonsProvider)
        .where((addon) => addon.enabled)
        .map((addon) => addon.id)
        .toSet();
    final cleanedPreferredSourceId =
        _preferredSourceId.isNotEmpty &&
            !activeAddonIds.contains(_preferredSourceId)
        ? ''
        : _preferredSourceId;

    final next = current.copyWith(
      appLanguage: _appLanguage,
      subtitleLanguage: _subtitleLanguage,
      tmdbAccessToken: _tmdbTokenController.text.trim(),
      wyzieApiKey: _wyzieApiKeyController.text.trim(),
      backendUrl: _backendUrlController.text.trim(),
      autoSelectSource: _autoSelectSource,
      autoSelectSubtitle: _autoSelectSubtitle,
      librarySort: _librarySort,
      watchHistoryEnabled: _watchHistoryEnabled,
      newEpisodeNotificationsEnabled: _newEpisodeNotificationsEnabled,
      completionPercentage: _completionPercentage,
      preferredSourceId: cleanedPreferredSourceId,
      videoPlayer: _videoPlayer,
    );

    final syncStatus = await notifier.saveSettings(next);

    if (!mounted) {
      return;
    }

    final text = ref.read(appTextProvider);
    late final String message;
    late final Color backgroundColor;

    switch (syncStatus) {
      case TmdbSyncStatus.synced:
        message = text.t('settings_saved_backend');
        backgroundColor = Colors.green;
        break;
      case TmdbSyncStatus.skipped:
        message = text.t('settings_saved');
        backgroundColor = Colors.blueGrey;
        break;
      case TmdbSyncStatus.failed:
        message = text.t('settings_saved_backend_fail');
        backgroundColor = Colors.orange;
        break;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 13)),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );

    setState(() {
      _isSaving = false;
      _isApiFieldsVisible = false;
    });
  }

  String _syncServerUrl = '';
  bool _isSyncRegistering = false;
  bool _isSyncing = false;
  bool _isExportingBackup = false;
  bool _isImportingBackup = false;

  Future<void> _loadSavedSyncServerUrl() async {
    final savedUrl = await DeviceIdentity.getServerUrl();
    if (!mounted || savedUrl == null || savedUrl.isEmpty) {
      return;
    }

    setState(() {
      _syncServerUrl = savedUrl;
      _syncServerUrlController.text = savedUrl;
    });
  }

  Future<void> _registerSyncDevice() async {
    setState(() => _isSyncRegistering = true);
    final syncService = ref.read(syncServiceProvider);
    if (syncService == null) {
      setState(() => _isSyncRegistering = false);
      return;
    }

    _syncServerUrl = _syncServerUrlController.text.trim();
    if (_syncServerUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lutfen kendi sync sunucu adresinizi girin.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isSyncRegistering = false);
      return;
    }

    final deviceName = 'Flutter_${DateTime.now().millisecondsSinceEpoch}';
    final success = await syncService.register(
      serverUrl: _syncServerUrl,
      deviceName: deviceName,
      tmdbAccessToken: _tmdbTokenController.text.trim(),
    );

    if (mounted) {
      if (success) {
        ref.invalidate(syncRegisteredProvider);
        ref.invalidate(syncStatusProvider);
      }
      final error = syncService.lastRegisterError;
      final failedMessage = error == null || error.isEmpty
          ? 'Kayit basarisiz. Sunucu adresini kontrol edin.'
          : 'Kayit basarisiz: $error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Cihaz basariyla kaydedildi!' : failedMessage,
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
    setState(() => _isSyncRegistering = false);
  }

  Future<void> _exportLocalBackup() async {
    if (_isExportingBackup) {
      return;
    }
    setState(() => _isExportingBackup = true);

    try {
      final now = DateTime.now();
      final fileName =
          'stream_app_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.json';
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Yedek dosya konumunu secin',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (outputPath == null || outputPath.trim().isEmpty) {
        return;
      }

      final savedPath = await LocalBackupService.exportToPath(outputPath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Yedek disa aktarildi: $savedPath'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Yedek disa aktarma basarisiz: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isExportingBackup = false);
      }
    }
  }

  Future<void> _importLocalBackup() async {
    if (_isImportingBackup) {
      return;
    }
    setState(() => _isImportingBackup = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'Geri yuklenecek yedek dosyasini secin',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        allowMultiple: false,
      );
      final inputPath = picked?.files.single.path;
      if (inputPath == null || inputPath.trim().isEmpty) {
        return;
      }

      final result = await LocalBackupService.importFromPath(inputPath);

      ref.invalidate(appSettingsProvider);
      ref.invalidate(libraryProvider);
      ref.invalidate(watchedProvider);
      ref.invalidate(sourcesProvider);
      ref.invalidate(addonsProvider);
      ref.invalidate(syncRegisteredProvider);
      ref.invalidate(syncStatusProvider);

      await _loadSavedSyncServerUrl();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Yedek geri yuklendi. Kaynak: ${result.sourceCount}, Gecmis: ${result.watchHistoryCount}, Kutuphane: ${result.libraryCount}, Izlenen: ${result.watchedCount}',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Yedek geri yukleme basarisiz: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isImportingBackup = false);
      }
    }
  }

  Future<void> _manualSync() async {
    setState(() => _isSyncing = true);
    final syncService = ref.read(syncServiceProvider);
    if (syncService != null) {
      await syncService.syncNow();
    }
    if (mounted) {
      ref.invalidate(syncStatusProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Senkron tamamlandi!'),
          backgroundColor: Colors.green,
        ),
      );
    }
    setState(() => _isSyncing = false);
  }

  Widget _buildSyncSection(BuildContext context, AppText text) {
    final syncStatus = ref.watch(syncStatusProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.sync, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Cihazlar Arasi Senkron',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Izleme verisini cihazlar arasinda sadece kendi girdiginiz sunucuda esitleyin. Paylasilan varsayilan sunucu kullanilmaz.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Sunucu Adresi',
            hintText: 'http://kendi-sunucun:8000',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.dns),
          ),
          controller: _syncServerUrlController,
          onChanged: (v) => _syncServerUrl = v.trim(),
        ),
        const SizedBox(height: 12),
        syncStatus.when(
          data: (status) {
            if (!status.isEnabled) {
              return Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSyncRegistering
                          ? null
                          : _registerSyncDevice,
                      icon: _isSyncRegistering
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.app_registration),
                      label: const Text('Cihazi Kaydet'),
                    ),
                  ),
                ],
              );
            }
            return Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: const Text('Senkron Aktif'),
                  subtitle: Text('Son senkron: ${status.lastSyncFormatted}'),
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSyncing ? null : _manualSync,
                    icon: _isSyncing
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: const Text('Simdi Senkronla'),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              Text('Hata: $e', style: const TextStyle(color: Colors.red)),
        ),
      ],
    );
  }

  Widget _buildLocalBackupSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.folder_zip_outlined, size: 20),
            SizedBox(width: 8),
            Text(
              'Lokal Yedekleme',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Veriyi JSON olarak disa aktarabilir ve ayni formatla geri yukleyebilirsiniz.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isExportingBackup ? null : _exportLocalBackup,
            icon: _isExportingBackup
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file),
            label: const Text('Veriyi Disa Aktar (JSON)'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isImportingBackup ? null : _importLocalBackup,
            icon: _isImportingBackup
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_for_offline_outlined),
            label: const Text('Yedekten Geri Yukle (JSON)'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    _ensureInitialized(settings);

    final text = ref.watch(appTextProvider);
    final addons = ref
        .watch(addonsProvider)
        .where((addon) => addon.enabled)
        .toList();
    final sourceIds = <String>{'', ...addons.map((addon) => addon.id)};
    final selectedSourceId = sourceIds.contains(_preferredSourceId)
        ? _preferredSourceId
        : '';

    final tmdbTokenPreview = _maskToken(_tmdbTokenController.text);
    final wyzieKeyPreview = _maskToken(_wyzieApiKeyController.text);
    final backendPreview = _backendUrlController.text.trim().isEmpty
        ? 'Not set'
        : _backendUrlController.text.trim();

    return Scaffold(
      appBar: AppBar(title: Text(text.t('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            text.t('app_language'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _appLanguage,
            items: supportedAppLanguages.entries
                .map(
                  (entry) => DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _appLanguage = value;
              });
            },
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          Text(
            text.t('subtitle_language'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _autoSelectSubtitle,
            onChanged: (value) {
              setState(() {
                _autoSelectSubtitle = value;
              });
            },
            title: const Text('Otomatik Altyazı Seçici'),
            subtitle: Text(
              _autoSelectSubtitle
                  ? 'Gömülü oynatıcıda dil zorlanır; direkt oynatıcıda Wyzie/OpenSubtitles altyazısı otomatik yüklenir.'
                  : 'Oynatıcının kendi altyazı seçimine izin verilir.',
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _subtitleLanguage,
            items: supportedSubtitleLanguages.entries
                .map(
                  (entry) => DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _subtitleLanguage = value;
              });
            },
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          Text(
            text.t('video_player'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _videoPlayer,
            items: supportedVideoPlayers.entries
                .map(
                  (entry) => DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _videoPlayer = value;
              });
            },
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _autoSelectSource,
            onChanged: (value) {
              setState(() {
                _autoSelectSource = value;
              });
            },
            title: Text(text.t('source_auto_play')),
            subtitle: Text(
              _autoSelectSource
                  ? text.t('source_auto_play_desc')
                  : text.t('source_manual_pick_desc'),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: selectedSourceId,
            items: [
              DropdownMenuItem<String>(
                value: '',
                child: Text(text.t('source_preferred_auto')),
              ),
              ...addons.map(
                (addon) => DropdownMenuItem<String>(
                  value: addon.id,
                  child: Text(addon.name),
                ),
              ),
            ],
            onChanged: _autoSelectSource
                ? (value) {
                    setState(() {
                      _preferredSourceId = value ?? '';
                    });
                  }
                : null,
            decoration: InputDecoration(
              labelText: text.t('source_preferred'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Library & Watch History',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: supportedLibrarySortOptions.containsKey(_librarySort)
                ? _librarySort
                : 'recent',
            items: supportedLibrarySortOptions.entries
                .map(
                  (entry) => DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _librarySort = value;
              });
            },
            decoration: const InputDecoration(
              labelText: 'Watchlist sort order',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _watchHistoryEnabled,
            onChanged: (value) {
              setState(() {
                _watchHistoryEnabled = value;
              });
            },
            title: const Text('Watch history'),
            subtitle: Text(
              _watchHistoryEnabled
                  ? 'Progress and continue watching entries are saved.'
                  : 'New playback progress will not be saved.',
            ),
          ),
          if (_watchHistoryEnabled) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  text.t('completion_percentage'),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  '%$_completionPercentage',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                  ),
                ),
              ],
            ),
            Slider(
              value: _completionPercentage.toDouble(),
              min: 50,
              max: 95,
              divisions: 9,
              label: '%$_completionPercentage',
              activeColor: Colors.redAccent,
              onChanged: (value) {
                setState(() {
                  _completionPercentage = value.round();
                });
              },
            ),
            Text(
              text.t('completion_percentage_desc'),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
          ],
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _newEpisodeNotificationsEnabled,
            onChanged: (value) {
              setState(() {
                _newEpisodeNotificationsEnabled = value;
              });
            },
            title: const Text('New episode alerts'),
            subtitle: const Text(
              'Library shows recently aired, unwatched episodes from saved series.',
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _isApiFieldsVisible ? Icons.lock_open : Icons.lock_outline,
            ),
            title: const Text('API & Backend Settings'),
            subtitle: Text(
              _isApiFieldsVisible
                  ? 'Hide sensitive fields'
                  : 'TMDB: $tmdbTokenPreview\nWyzie: $wyzieKeyPreview\nBackend: $backendPreview',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: TextButton(
              onPressed: () {
                setState(() {
                  _isApiFieldsVisible = !_isApiFieldsVisible;
                });
              },
              child: Text(_isApiFieldsVisible ? 'Hide' : 'Edit'),
            ),
          ),
          if (_isApiFieldsVisible) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  text.t('tmdb_token'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final Uri url = Uri.parse(
                      'https://www.themoviedb.org/settings/api',
                    );
                    try {
                      if (!await launchUrl(
                        url,
                        mode: LaunchMode.externalApplication,
                      )) {
                        throw Exception('Could not launch $url');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
                      }
                    }
                  },
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: Text(
                    text.t('get_tmdb_token'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tmdbTokenController,
              decoration: InputDecoration(
                hintText: text.t('tmdb_token_hint'),
                border: const OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            const Text(
              'Wyzie Subs API Key',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _wyzieApiKeyController,
              decoration: const InputDecoration(
                hintText: 'wyzie-...',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            Text(
              text.t('backend_url'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _backendUrlController,
              decoration: const InputDecoration(
                hintText: 'http://192.168.1.x:8000',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            text.t('api_required'),
            style: TextStyle(color: Colors.orange.shade300, fontSize: 12),
          ),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.storage_outlined),
            title: Text(text.t('sources')),
            subtitle: Text(text.t('source_settings_nav_desc')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SourcesScreen()));
            },
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.extension),
            title: Text(text.t('addons')),
            subtitle: Text(text.t('addon_settings_nav_desc')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AddonManagerScreen()),
              );
            },
          ),
          const SizedBox(height: 16),
          const Divider(),
          _buildLocalBackupSection(),
          const SizedBox(height: 16),
          const Divider(),
          _buildSyncSection(context, text),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveSettings,
              icon: _isSaving
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(text.t('save_settings')),
            ),
          ),
        ],
      ),
    );
  }
}
