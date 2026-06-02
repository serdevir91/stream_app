import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/updater/app_updater_service.dart';

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
import 'home_categories_manager_screen.dart';

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
  bool _autoSelectSubtitle = false;
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

  final AppUpdaterService _updaterService = AppUpdaterService();
  AppUpdateInfo? _updateInfo;
  bool _isCheckingForUpdates = false;
  bool _isDownloadingUpdate = false;
  double _downloadProgress = 0.0;
  String _updateError = '';
  String _currentVersion = currentAppVersionFallback;

  @override
  void initState() {
    super.initState();
    _syncServerUrlController = TextEditingController(text: _syncServerUrl);
    _loadSavedSyncServerUrl();
    _loadCurrentVersion();
  }

  Future<void> _loadCurrentVersion() async {
    final version = await _updaterService.getCurrentVersion();
    if (!mounted) return;
    setState(() {
      _currentVersion = version;
    });
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
    final text = ref.read(appTextProvider);
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
          SnackBar(
            content: Text(text.t('please_enter_sync_address')),
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
          ? text.t('sync_register_failed')
          : text
                .t('sync_register_failed_with')
                .replaceAll('{param}', text.t(error));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? text.t('device_registered_success') : failedMessage,
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
    setState(() => _isSyncRegistering = false);
  }

  Future<void> _exportLocalBackup() async {
    final text = ref.read(appTextProvider);
    if (_isExportingBackup) {
      return;
    }
    setState(() => _isExportingBackup = true);

    try {
      final now = DateTime.now();
      final fileName =
          'stream_app_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.json';
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: text.t('saving_backup_title'),
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
          content: Text('${text.t('backup_exported')}: $savedPath'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${text.t('backup_export_failed')}: $e'),
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
    final text = ref.read(appTextProvider);
    if (_isImportingBackup) {
      return;
    }
    setState(() => _isImportingBackup = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: text.t('loading_backup_title'),
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
            '${text.t('backup_restored')}. ${text.t('sources')}: ${result.sourceCount}, ${text.t('watch_history')}: ${result.watchHistoryCount}, ${text.t('library_title')}: ${result.libraryCount}, ${text.t('watched')}: ${result.watchedCount}',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final errorMessage = e is LocalBackupException
          ? text.t(e.message)
          : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${text.t('backup_restore_failed')}: $errorMessage'),
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
    final text = ref.read(appTextProvider);
    setState(() => _isSyncing = true);
    final syncService = ref.read(syncServiceProvider);
    if (syncService != null) {
      await syncService.syncNow();
    }
    if (mounted) {
      ref.invalidate(syncStatusProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text.t('sync_completed')),
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
            Text(
              text.t('sync_title'),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          text.t('sync_desc'),
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: InputDecoration(
            labelText: text.t('server_address'),
            hintText: text.t('server_address_hint'),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.dns),
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
                      label: Text(text.t('register_device')),
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
                  title: Text(text.t('sync_active')),
                  subtitle: Text(
                    '${text.t('last_sync')}: ${status.lastSyncMs == 0 ? text.t('never_synced') : status.lastSyncFormatted}',
                  ),
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
                    label: Text(text.t('sync_now')),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text(
            '${text.t('error_prefix')}: $e',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }

  Widget _buildLocalBackupSection() {
    final text = ref.watch(appTextProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.folder_zip_outlined, size: 20),
            const SizedBox(width: 8),
            Text(
              text.t('local_backup'),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          text.t('local_backup_desc'),
          style: const TextStyle(color: Colors.grey, fontSize: 13),
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
            label: Text(text.t('export_data')),
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
            label: Text(text.t('import_data')),
          ),
        ),
      ],
    );
  }

  Future<void> _checkUpdates() async {
    final text = ref.read(appTextProvider);
    setState(() {
      _isCheckingForUpdates = true;
      _updateError = '';
    });

    try {
      final info = await _updaterService.checkForUpdate();
      setState(() {
        _updateInfo = info;
      });
      if (mounted) {
        if (info == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(text.t('app_up_to_date')),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${text.t('new_update_found')}: ${info.latestVersion}',
              ),
              backgroundColor: Colors.blueAccent,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _updateError = e.toString();
      });
    } finally {
      setState(() {
        _isCheckingForUpdates = false;
      });
    }
  }

  Future<void> _installUpdate() async {
    if (_updateInfo == null) return;

    setState(() {
      _isDownloadingUpdate = true;
      _downloadProgress = 0.0;
    });

    await _updaterService.performUpdate(
      _updateInfo!,
      onProgress: (progress) {
        setState(() {
          _downloadProgress = progress;
        });
      },
      onComplete: () {
        setState(() {
          _isDownloadingUpdate = false;
        });
      },
      onError: (err) {
        final text = ref.read(appTextProvider);
        setState(() {
          _isDownloadingUpdate = false;
          _updateError = err;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${text.t('error_prefix')}: $err'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
  }

  Widget _buildUpdateSection(BuildContext context, AppText text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.system_update_outlined, size: 20),
            const SizedBox(width: 8),
            Text(
              text.t('app_update'),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${text.t('current_version')}: $_currentVersion',
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 12),
        if (_isCheckingForUpdates)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_isDownloadingUpdate)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${text.t('downloading_update')}: %${(_downloadProgress * 100).toStringAsFixed(1)}',
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _downloadProgress),
            ],
          )
        else if (_updateInfo != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${text.t('new_version')}: ${_updateInfo!.latestVersion}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.greenAccent,
                  ),
                ),
                if (_updateInfo!.releaseNotes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    _updateInfo!.releaseNotes,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _installUpdate,
                    icon: const Icon(Icons.download),
                    label: Text(text.t('update_now')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _checkUpdates,
              icon: const Icon(Icons.refresh),
              label: Text(text.t('check_for_updates')),
            ),
          ),
        if (_updateError.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '${text.t('error_prefix')}: $_updateError',
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
          ),
        ],
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
            title: Text(text.t('auto_select_subtitle')),
            subtitle: Text(
              _autoSelectSubtitle
                  ? text.t('auto_select_subtitle_desc_enabled')
                  : text.t('auto_select_subtitle_desc_disabled'),
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
          Text(
            text.t('library_and_history'),
            style: const TextStyle(fontWeight: FontWeight.w600),
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
            decoration: InputDecoration(
              labelText: text.t('watchlist_sort_order'),
              border: const OutlineInputBorder(),
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
            title: Text(text.t('watch_history_setting')),
            subtitle: Text(
              _watchHistoryEnabled
                  ? text.t('watch_history_desc_enabled')
                  : text.t('watch_history_desc_disabled'),
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
            title: Text(text.t('new_episode_alerts')),
            subtitle: Text(text.t('new_episode_alerts_desc')),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _isApiFieldsVisible ? Icons.lock_open : Icons.lock_outline,
            ),
            title: Text(text.t('api_backend_settings')),
            subtitle: Text(
              _isApiFieldsVisible
                  ? text.t('hide_sensitive_fields')
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
              child: Text(
                _isApiFieldsVisible ? text.t('hide') : text.t('edit'),
              ),
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${text.t('error_prefix')}: $e'),
                          ),
                        );
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
            Text(
              text.t('wyzie_api_key'),
              style: const TextStyle(fontWeight: FontWeight.w600),
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
            leading: const Icon(Icons.dashboard_customize_outlined),
            title: Text(text.t('homepage_categories')),
            subtitle: Text(text.t('homepage_categories_desc')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const HomeCategoriesManagerScreen(),
                ),
              );
            },
          ),
          const Divider(),
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
          const Divider(),
          _buildUpdateSection(context, text),
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
