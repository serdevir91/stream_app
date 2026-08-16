import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/settings/tmdb_instructions_dialog.dart';

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
  late TextEditingController _syncServerUrlController;

  String _appLanguage = 'en';
  String _subtitleLanguage = 'en';
  String _themeMode = 'dark';
  bool _autoSelectSource = true;
  String _preferredSourceId = '';
  String _preferredMirror = 'auto';
  String _videoPlayer = 'native';
  bool _autoSelectSubtitle = false;
  double _defaultSubtitleOffset = 0.0;
  String _librarySort = 'recent';
  bool _watchHistoryEnabled = true;
  bool _newEpisodeNotificationsEnabled = true;
  int _completionPercentage = 90;

  bool _initialized = false;
  bool _isSaving = false;
  bool _isApiFieldsVisible = false;

  String _syncServerUrl = '';
  bool _isSyncRegistering = false;
  bool _isSyncing = false;
  bool _isExportingBackup = false;
  bool _isImportingBackup = false;

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
    if (_initialized) return;
    _appLanguage = settings.appLanguage;
    _subtitleLanguage = settings.subtitleLanguage;
    _themeMode = settings.themeMode;
    _autoSelectSource = settings.autoSelectSource;
    _preferredSourceId = settings.preferredSourceId;
    _preferredMirror = settings.preferredMirror;
    _videoPlayer = settings.videoPlayer;
    _autoSelectSubtitle = settings.autoSelectSubtitle;
    _defaultSubtitleOffset = settings.defaultSubtitleOffset;
    _librarySort = settings.librarySort;
    _watchHistoryEnabled = settings.watchHistoryEnabled;
    _newEpisodeNotificationsEnabled = settings.newEpisodeNotificationsEnabled;
    _completionPercentage = settings.completionPercentage;

    _tmdbTokenController = TextEditingController(text: settings.tmdbAccessToken);
    _wyzieApiKeyController = TextEditingController(text: settings.wyzieApiKey);
    _backendUrlController = TextEditingController(text: settings.backendUrl);
    _isApiFieldsVisible = settings.tmdbAccessToken.trim().isEmpty;
    _initialized = true;
  }

  String _maskToken(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return 'Not set';
    if (trimmed.length <= 8) return 'Configured';
    return '${trimmed.substring(0, 4)}****${trimmed.substring(trimmed.length - 4)}';
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

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
      themeMode: _themeMode,
      tmdbAccessToken: _tmdbTokenController.text.trim(),
      wyzieApiKey: _wyzieApiKeyController.text.trim(),
      backendUrl: _backendUrlController.text.trim(),
      autoSelectSource: _autoSelectSource,
      preferredSourceId: cleanedPreferredSourceId,
      preferredMirror: _preferredMirror,
      videoPlayer: _videoPlayer,
      autoSelectSubtitle: _autoSelectSubtitle,
      defaultSubtitleOffset: _defaultSubtitleOffset,
      librarySort: _librarySort,
      watchHistoryEnabled: _watchHistoryEnabled,
      newEpisodeNotificationsEnabled: _newEpisodeNotificationsEnabled,
      completionPercentage: _completionPercentage,
    );

    final syncStatus = await notifier.saveSettings(next);
    if (!mounted) return;

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
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    setState(() {
      _isSaving = false;
      _isApiFieldsVisible = false;
    });
  }

  Future<void> _loadSavedSyncServerUrl() async {
    final savedUrl = await DeviceIdentity.getServerUrl();
    if (!mounted || savedUrl == null || savedUrl.isEmpty) return;
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

    final deviceName = 'Device_${DateTime.now().millisecondsSinceEpoch}';
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
    if (_isExportingBackup) return;
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
      if (outputPath == null || outputPath.trim().isEmpty) return;

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
      if (mounted) setState(() => _isExportingBackup = false);
    }
  }

  Future<void> _importLocalBackup() async {
    final text = ref.read(appTextProvider);
    if (_isImportingBackup) return;
    setState(() => _isImportingBackup = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: text.t('loading_backup_title'),
        type: FileType.custom,
        allowedExtensions: const ['json'],
        allowMultiple: false,
      );
      final inputPath = picked?.files.single.path;
      if (inputPath == null || inputPath.trim().isEmpty) return;

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
      if (mounted) setState(() => _isImportingBackup = false);
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
      setState(() => _updateError = e.toString());
    } finally {
      setState(() => _isCheckingForUpdates = false);
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
      onProgress: (progress) => setState(() => _downloadProgress = progress),
      onComplete: () => setState(() => _isDownloadingUpdate = false),
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

  Widget _buildCardSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
    Widget? trailing,
    Color? iconColor,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171720) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (iconColor ?? theme.colorScheme.primary)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: iconColor ?? theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, thickness: 0.6),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
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
      appBar: AppBar(
        title: Text(text.t('settings')),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: text.t('save_settings'),
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline),
            onPressed: _isSaving ? null : _saveSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // 1. Appearance & Language
            _buildCardSection(
              title: text.t('appearance_and_theme'),
              icon: Icons.palette_outlined,
              iconColor: Colors.purpleAccent,
              children: [
                Text(
                  text.t('theme_mode'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'dark',
                      label: Text(text.t('theme_dark')),
                      icon: const Icon(Icons.dark_mode_outlined, size: 16),
                    ),
                    ButtonSegment(
                      value: 'amoled',
                      label: Text(text.t('theme_amoled')),
                      icon: const Icon(Icons.brightness_2, size: 16),
                    ),
                    ButtonSegment(
                      value: 'light',
                      label: Text(text.t('theme_light')),
                      icon: const Icon(Icons.light_mode_outlined, size: 16),
                    ),
                  ],
                  selected: {_themeMode},
                  onSelectionChanged: (set) {
                    setState(() {
                      _themeMode = set.first;
                    });
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  text.t('app_language'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
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
                    setState(() => _appLanguage = value);
                  },
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),

            // 2. Sources & VidBox Mirror Management
            _buildCardSection(
              title: text.t('source_and_mirror_settings'),
              icon: Icons.alt_route_rounded,
              iconColor: Colors.blueAccent,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _autoSelectSource,
                  onChanged: (value) =>
                      setState(() => _autoSelectSource = value),
                  title: Text(
                    text.t('source_auto_play'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    _autoSelectSource
                        ? text.t('source_auto_play_desc')
                        : text.t('source_manual_pick_desc'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
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
                      ? (value) =>
                            setState(() => _preferredSourceId = value ?? '')
                      : null,
                  decoration: InputDecoration(
                    labelText: text.t('source_preferred'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.dns_rounded,
                          size: 16,
                          color: Colors.amberAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          text.t('vidbox_preferred_mirror'),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amberAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _preferredMirror.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.amberAccent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  text.t('vidbox_preferred_mirror_desc'),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue:
                      supportedVidBoxMirrors.containsKey(_preferredMirror)
                      ? _preferredMirror
                      : 'auto',
                  items: supportedVidBoxMirrors.entries
                      .map(
                        (entry) => DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() => _preferredMirror = val);
                  },
                  decoration: InputDecoration(
                    labelText: text.t('vidbox_preferred_mirror'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _mirrorChip('auto', 'Auto (Fastest)'),
                    _mirrorChip('vidx', 'Vidx 1080p'),
                    _mirrorChip('cargo', 'Cargo 1080p'),
                    _mirrorChip('cabin', 'Cabin HD'),
                    _mirrorChip('boxr', 'Boxr 1080p'),
                    _mirrorChip('tile', 'Tile 1080p'),
                    _mirrorChip('cube', 'Cube HD'),
                    _mirrorChip('hatch', 'Hatch 1080p'),
                    _mirrorChip('gale', 'Gale HD'),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.extension_outlined, size: 16),
                        label: Text(
                          text.t('addons'),
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AddonManagerScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.cloud_outlined, size: 16),
                        label: Text(
                          text.t('sources'),
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SourcesScreen(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // 3. Subtitles & Drift Synchronization
            _buildCardSection(
              title: text.t('subtitles_and_sync'),
              icon: Icons.subtitles_rounded,
              iconColor: Colors.amberAccent,
              children: [
                Text(
                  text.t('subtitle_language'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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
                    setState(() => _subtitleLanguage = value);
                  },
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _autoSelectSubtitle,
                  onChanged: (value) =>
                      setState(() => _autoSelectSubtitle = value),
                  title: Text(
                    text.t('auto_select_subtitle'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    _autoSelectSubtitle
                        ? text.t('auto_select_subtitle_desc_enabled')
                        : text.t('auto_select_subtitle_desc_disabled'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      text.t('subtitle_sync_offset'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _defaultSubtitleOffset == 0.0
                            ? Colors.white10
                            : Colors.amberAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _defaultSubtitleOffset == 0.0
                            ? '0.00s (${text.t('reset')})'
                        : '${_defaultSubtitleOffset > 0 ? "+" : ""}${_defaultSubtitleOffset.toStringAsFixed(2)}s',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _defaultSubtitleOffset == 0.0
                              ? Colors.white70
                              : Colors.amberAccent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  text.t('subtitle_sync_desc'),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 6),
                Slider(
                  value: _defaultSubtitleOffset.clamp(-5.0, 5.0),
                  min: -5.0,
                  max: 5.0,
                  divisions: 100,
                  label: '${_defaultSubtitleOffset.toStringAsFixed(2)}s',
                  activeColor: Colors.amberAccent,
                  onChanged: (val) {
                    setState(() {
                      _defaultSubtitleOffset = double.parse(
                        val.toStringAsFixed(2),
                      );
                    });
                  },
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    _offsetButton('-1.0s', -1.0),
                    _offsetButton('-0.5s', -0.5),
                    _offsetButton('-0.1s', -0.1),
                    ActionChip(
                      avatar: const Icon(
                        Icons.restart_alt,
                        size: 14,
                        color: Colors.white70,
                      ),
                      label: Text(
                        text.t('reset'),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                      backgroundColor: Colors.white10,
                      side: BorderSide.none,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      onPressed: () =>
                          setState(() => _defaultSubtitleOffset = 0.0),
                    ),
                    _offsetButton('+0.1s', 0.1),
                    _offsetButton('+0.5s', 0.5),
                    _offsetButton('+1.0s', 1.0),
                  ],
                ),
              ],
            ),

            // 4. Player & Playback Engine
            _buildCardSection(
              title: text.t('player_and_playback'),
              icon: Icons.play_circle_filled_rounded,
              iconColor: Colors.redAccent,
              children: [
                Text(
                  text.t('video_player'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
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
                    setState(() => _videoPlayer = value);
                  },
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _watchHistoryEnabled,
                  onChanged: (value) =>
                      setState(() => _watchHistoryEnabled = value),
                  title: Text(
                    text.t('watch_history_setting'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    _watchHistoryEnabled
                        ? text.t('watch_history_desc_enabled')
                        : text.t('watch_history_desc_disabled'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (_watchHistoryEnabled) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        text.t('completion_percentage'),
                        style: const TextStyle(fontSize: 13),
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
                    onChanged: (value) =>
                        setState(() => _completionPercentage = value.round()),
                  ),
                  Text(
                    text.t('completion_percentage_desc'),
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.dashboard_customize_outlined),
                  title: Text(
                    text.t('homepage_categories'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    text.t('homepage_categories_desc'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const HomeCategoriesManagerScreen(),
                    ),
                  ),
                ),
              ],
            ),

            // 5. Library & Notifications
            _buildCardSection(
              title: text.t('library_and_history'),
              icon: Icons.video_library_rounded,
              iconColor: Colors.tealAccent,
              children: [
                Text(
                  text.t('watchlist_sort_order'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue:
                      supportedLibrarySortOptions.containsKey(_librarySort)
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
                    setState(() => _librarySort = value);
                  },
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _newEpisodeNotificationsEnabled,
                  onChanged: (value) => setState(
                    () => _newEpisodeNotificationsEnabled = value,
                  ),
                  title: Text(
                    text.t('new_episode_alerts'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    text.t('new_episode_alerts_desc'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),

            // 6. API & Backend Credentials
            _buildCardSection(
              title: text.t('api_backend_settings'),
              icon: Icons.vpn_key_rounded,
              iconColor: Colors.orangeAccent,
              trailing: TextButton.icon(
                icon: Icon(
                  _isApiFieldsVisible ? Icons.visibility_off : Icons.edit,
                  size: 16,
                ),
                label: Text(
                  _isApiFieldsVisible ? text.t('hide') : text.t('edit'),
                ),
                onPressed: () =>
                    setState(() => _isApiFieldsVisible = !_isApiFieldsVisible),
              ),
              children: [
                if (!_isApiFieldsVisible) ...[
                  Text(
                    'TMDB: $tmdbTokenPreview\nWyzie: $wyzieKeyPreview\nBackend: $backendPreview',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      height: 1.4,
                    ),
                  ),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        text.t('tmdb_token'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            showTmdbTokenInstructions(context, text),
                        icon: const Icon(Icons.help_outline, size: 14),
                        label: Text(
                          text.t('get_tmdb_token'),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _tmdbTokenController,
                    decoration: InputDecoration(
                      hintText: text.t('tmdb_token_hint'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    minLines: 2,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    text.t('wyzie_api_key'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _wyzieApiKeyController,
                    decoration: InputDecoration(
                      hintText: 'wyzie-...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    text.t('backend_url'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _backendUrlController,
                    decoration: InputDecoration(
                      hintText: 'http://127.0.0.1:8000',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  text.t('api_required'),
                  style: TextStyle(color: Colors.orange.shade300, fontSize: 11),
                ),
              ],
            ),

            // 7. Backup, Sync & Updates
            _buildCardSection(
              title: text.t('sync_title'),
              icon: Icons.cloud_sync_rounded,
              iconColor: Colors.lightGreenAccent,
              children: [
                _buildSyncSection(context, text),
                const SizedBox(height: 16),
                const Divider(height: 1, thickness: 0.5),
                const SizedBox(height: 16),
                _buildLocalBackupSection(),
                const SizedBox(height: 16),
                const Divider(height: 1, thickness: 0.5),
                const SizedBox(height: 16),
                _buildUpdateSection(context, text),
              ],
            ),

            const SizedBox(height: 8),

            // Main Save Button
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _isSaving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(
                  text.t('save_settings'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mirrorChip(String key, String label) {
    final isSelected = _preferredMirror == key;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _preferredMirror = key);
        }
      },
    );
  }

  Widget _offsetButton(String label, double delta) {
    return InkWell(
      onTap: () {
        setState(() {
          _defaultSubtitleOffset = double.parse(
            (_defaultSubtitleOffset + delta).toStringAsFixed(2),
          ).clamp(-10.0, 10.0);
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

