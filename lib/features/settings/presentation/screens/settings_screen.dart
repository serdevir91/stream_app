import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/theme/theme_x.dart';

import '../../../../core/app_baseline.dart';
import '../../../../core/backup/local_backup_service.dart';
import '../../../../core/i18n/app_text.dart';
import '../../../../core/settings/app_settings.dart';
import '../../../../core/settings/app_settings_provider.dart';
import '../../../../core/settings/tmdb_instructions_dialog.dart';
import '../../../../core/sync/device_identity.dart';
import '../../../../core/sync/sync_provider.dart';
import '../../../../core/tutorial/onboarding_tutorial_dialog.dart';
import '../../../../core/updater/app_updater_service.dart';
import '../../../library/presentation/providers/library_provider.dart';
import '../../../library/presentation/providers/watched_provider.dart';
import '../../../addons/presentation/screens/addon_manager_screen.dart';
import '../../../anime/data/providers/anime_extensions_provider.dart';
import '../../../anime/presentation/screens/anime_extensions_screen.dart';
import '../../../sources/presentation/providers/sources_provider.dart';
import '../../../../core/player/external_player_service.dart';

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
  String _externalPlayer = '';
  List<ExternalPlayerApp> _externalApps = const [];
  bool _externalAppsRequested = false;
  bool _autoSelectSubtitle = false;
  double _defaultSubtitleOffset = 0.0;
  String _librarySort = 'recent';
  bool _watchHistoryEnabled = true;
  bool _newEpisodeNotificationsEnabled = true;
  int _completionPercentage = 90;

  bool _initialized = false;
  bool _isSaving = false;

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
    _externalPlayer = settings.externalPlayer;
    if (!_externalAppsRequested && ExternalPlayerService.isSupported) {
      _externalAppsRequested = true;
      ExternalPlayerService.installedPlayers().then((apps) {
        if (mounted) setState(() => _externalApps = apps);
      });
    }
    _autoSelectSubtitle = settings.autoSelectSubtitle;
    _defaultSubtitleOffset = settings.defaultSubtitleOffset;
    _librarySort = settings.librarySort;
    _watchHistoryEnabled = settings.watchHistoryEnabled;
    _newEpisodeNotificationsEnabled = settings.newEpisodeNotificationsEnabled;
    _completionPercentage = settings.completionPercentage;

    _tmdbTokenController = TextEditingController(text: settings.tmdbAccessToken);
    _wyzieApiKeyController = TextEditingController(text: settings.wyzieApiKey);
    _backendUrlController = TextEditingController(text: settings.backendUrl);
    _initialized = true;
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final current = ref.read(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

    final next = current.copyWith(
      appLanguage: _appLanguage,
      subtitleLanguage: _subtitleLanguage,
      themeMode: _themeMode,
      tmdbAccessToken: _tmdbTokenController.text.trim(),
      wyzieApiKey: _wyzieApiKeyController.text.trim(),
      backendUrl: _backendUrlController.text.trim(),
      autoSelectSource: _autoSelectSource,
      preferredSourceId: _preferredSourceId,
      preferredMirror: _preferredMirror,
      videoPlayer: _videoPlayer,
      externalPlayer: _externalPlayer,
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
        backgroundColor = Colors.deepPurpleAccent;
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
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    setState(() {
      _isSaving = false;
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
          : text.t('sync_register_failed_with').replaceAll('{param}', text.t(error));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? text.t('device_registered_success') : failedMessage),
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
          'stream_app_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.json';
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
      ref.invalidate(syncRegisteredProvider);
      ref.invalidate(syncStatusProvider);

      await _loadSavedSyncServerUrl();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${text.t('backup_restored')}. ${text.t('library_title')}: ${result.libraryCount}, ${text.t('watched')}: ${result.watchedCount}',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${text.t('backup_restore_failed')}: $e'),
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
      if (!mounted) return;

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
            content: Text('${text.t('new_update_found')}: ${info.latestVersion}'),
            backgroundColor: Colors.deepPurpleAccent,
          ),
        );
      }
    } catch (e) {
      setState(() => _updateError = e.toString());
    } finally {
      if (mounted) setState(() => _isCheckingForUpdates = false);
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

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final text = ref.watch(appTextProvider);
    final animeExtensions = ref.watch(animeExtensionsProvider);
    _ensureInitialized(settings);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        title: Text(
          text.t('settings'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.deepPurpleAccent.withValues(alpha: 0.2),
                foregroundColor: Colors.deepPurpleAccent,
              ),
              onPressed: _isSaving ? null : _saveSettings,
              icon: _isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.deepPurpleAccent),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(text.t('save')),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          // -----------------------------------------------------------
          // Section 1: Appearance & Localization
          // -----------------------------------------------------------
          _buildSectionHeader(
            icon: Icons.palette_rounded,
            title: text.languageCode == 'tr' ? 'Görünüm & Dil' : 'Appearance & Language',
            color: Colors.deepPurpleAccent,
          ),
          _buildCard(
            children: [
              // Theme Mode (Light, Dark, AMOLED Pure Black per workspace rules)
              ListTile(
                leading: Icon(Icons.brightness_medium_rounded, color: context.fgMuted),
                title: Text(text.t('theme_mode'), style: TextStyle(color: context.fg, fontSize: 14)),
                subtitle: Text(
                  _themeMode == 'amoled'
                      ? text.t('theme_amoled')
                      : (_themeMode == 'light' ? text.t('theme_light') : text.t('theme_dark')),
                  style: TextStyle(color: context.fgFaint, fontSize: 12),
                ),
                trailing: DropdownButton<String>(
                  value: _themeMode,
                  dropdownColor: context.card,
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem(value: 'dark', child: Text(text.t('theme_dark'))),
                    DropdownMenuItem(value: 'light', child: Text(text.t('theme_light'))),
                    DropdownMenuItem(value: 'amoled', child: Text(text.t('theme_amoled'))),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _themeMode = val);
                      _saveSettings();
                    }
                  },
                ),
              ),
              Divider(color: context.line, height: 1),

              // App Language
              ListTile(
                leading: Icon(Icons.language_rounded, color: context.fgMuted),
                title: Text(text.t('app_language'), style: TextStyle(color: context.fg, fontSize: 14)),
                subtitle: Text(
                  _appLanguage == 'tr' ? 'Türkçe' : (_appLanguage == 'ar' ? 'العربية' : (_appLanguage == 'fa' ? 'فارسی' : 'English')),
                  style: TextStyle(color: context.fgFaint, fontSize: 12),
                ),
                trailing: DropdownButton<String>(
                  value: _appLanguage,
                  dropdownColor: context.card,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'tr', child: Text('Türkçe')),
                    DropdownMenuItem(value: 'ar', child: Text('العربية')),
                    DropdownMenuItem(value: 'fa', child: Text('فارسی')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _appLanguage = val);
                      _saveSettings();
                    }
                  },
                ),
              ),
              Divider(color: context.line, height: 1),

              // Subtitle Language
              ListTile(
                leading: Icon(Icons.subtitles_rounded, color: context.fgMuted),
                title: Text(text.t('subtitle_language'), style: TextStyle(color: context.fg, fontSize: 14)),
                trailing: DropdownButton<String>(
                  value: _subtitleLanguage,
                  dropdownColor: context.card,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'tr', child: Text('Türkçe')),
                    DropdownMenuItem(value: 'ar', child: Text('العربية')),
                    DropdownMenuItem(value: 'de', child: Text('Deutsch')),
                    DropdownMenuItem(value: 'fr', child: Text('Français')),
                    DropdownMenuItem(value: 'es', child: Text('Español')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _subtitleLanguage = val);
                      _saveSettings();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // -----------------------------------------------------------
          // Section 2: Anime Sources & Extensions (Completely Separate!)
          // -----------------------------------------------------------
          _buildSectionHeader(
            icon: Icons.movie_filter_rounded,
            title: text.languageCode == 'tr' ? 'Anime Kaynakları & Eklentileri' : 'Anime Extensions & Sources',
            color: Colors.amberAccent,
          ),
          _buildCard(
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.extension_rounded, color: Colors.amberAccent, size: 22),
                ),
                title: Text(
                  text.languageCode == 'tr' ? 'Anime Eklentileri Yöneticisi' : 'Anime Extensions Manager',
                  style: TextStyle(color: context.fg, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Text(
                  '${animeExtensions.where((e) => e.isEnabled).length}/${animeExtensions.length} ${text.languageCode == 'tr' ? 'kaynak aktif (VidSrc, 2Embed, AniWave...)' : 'sources active'}',
                  style: TextStyle(color: context.fgFaint, fontSize: 12),
                ),
                trailing: Icon(Icons.arrow_forward_ios_rounded, color: context.fgFaint, size: 14),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AnimeExtensionsScreen()),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 20),

          // -----------------------------------------------------------
          // Section 3: Movies & TV Shows Sources
          // -----------------------------------------------------------
          _buildSectionHeader(
            icon: Icons.movie_rounded,
            title: text.languageCode == 'tr' ? 'Film & Dizi Kaynakları' : 'Movie & Series Sources',
            color: Colors.cyanAccent,
          ),
          _buildCard(
            children: [
              // TMDB Token Status
              ListTile(
                leading: Icon(Icons.vpn_key_rounded, color: context.fgMuted),
                title: Text('TMDB API Access Token', style: TextStyle(color: context.fg, fontSize: 14)),
                subtitle: Text(
                  _tmdbTokenController.text.trim().isNotEmpty
                      ? '● Connected'
                      : (text.languageCode == 'tr' ? 'Ayarlanmadı (Dokunarak girin)' : 'Not configured (Tap to configure)'),
                  style: TextStyle(
                    color: _tmdbTokenController.text.trim().isNotEmpty ? const Color(0xFF00E054) : Colors.orange,
                    fontSize: 12,
                  ),
                ),
                trailing: Icon(Icons.edit_rounded, color: context.fgFaint, size: 16),
                onTap: () => _openTmdbModal(context, text),
              ),
              Divider(color: context.line, height: 1),

              // Movies Addons Manager
              ListTile(
                leading: Icon(Icons.hub_rounded, color: context.fgMuted),
                title: Text(text.languageCode == 'tr' ? 'Film & Dizi Eklentileri' : 'Movie & TV Addons',
                    style: TextStyle(color: context.fg, fontSize: 14)),
                subtitle: Text(text.languageCode == 'tr' ? '13+ Dahili ve Harici Sağlayıcı' : '13+ Streaming Addons',
                    style: TextStyle(color: context.fgFaint, fontSize: 12)),
                trailing: Icon(Icons.arrow_forward_ios_rounded, color: context.fgFaint, size: 14),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AddonManagerScreen()),
                  );
                },
              ),
              Divider(color: context.line, height: 1),

              // Preferred Mirror
              ListTile(
                leading: Icon(Icons.dns_rounded, color: context.fgMuted),
                title: Text(text.languageCode == 'tr' ? 'Tercih Edilen Ayna (Mirror)' : 'Preferred Mirror',
                    style: TextStyle(color: context.fg, fontSize: 14)),
                trailing: DropdownButton<String>(
                  value: _preferredMirror,
                  dropdownColor: context.card,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('Auto')),
                    DropdownMenuItem(value: 'vidx', child: Text('Vidx')),
                    DropdownMenuItem(value: 'cargo', child: Text('Cargo')),
                    DropdownMenuItem(value: 'cabin', child: Text('Cabin')),
                    DropdownMenuItem(value: 'gale', child: Text('Gale')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _preferredMirror = val);
                      _saveSettings();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // -----------------------------------------------------------
          // Section 4: Playback & Player Engine
          // -----------------------------------------------------------
          _buildSectionHeader(
            icon: Icons.play_circle_rounded,
            title: text.languageCode == 'tr' ? 'Oynatıcı & Akış' : 'Player & Playback',
            color: const Color(0xFF00E054),
          ),
          _buildCard(
            children: [
              // Video Player Engine
              ListTile(
                leading: Icon(Icons.smart_display_rounded, color: context.fgMuted),
                title: Text(text.t('video_player'), style: TextStyle(color: context.fg, fontSize: 14)),
                trailing: DropdownButton<String>(
                  value: _videoPlayer,
                  dropdownColor: context.card,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'native', child: Text('Native (VideoPlayer)')),
                    DropdownMenuItem(value: 'media_kit', child: Text('MediaKit (MPV)')),
                    DropdownMenuItem(value: 'webview', child: Text('WebView Sandboxed')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _videoPlayer = val);
                      _saveSettings();
                    }
                  },
                ),
              ),
              if (ExternalPlayerService.isSupported) ...[
                Divider(color: context.line, height: 1),
                _buildExternalPlayerTile(text),
              ],
              Divider(color: context.line, height: 1),

              // Auto Select Source
              SwitchListTile(
                secondary: Icon(Icons.flash_auto_rounded, color: context.fgMuted),
                title: Text(text.t('auto_select_source'), style: TextStyle(color: context.fg, fontSize: 14)),
                subtitle: Text(
                  text.languageCode == 'tr'
                      ? 'En hızlı kaynağı otomatik seçerek başlatır'
                      : 'Automatically play the best available source',
                  style: TextStyle(color: context.fgFaint, fontSize: 12),
                ),
                value: _autoSelectSource,
                activeTrackColor: Colors.deepPurpleAccent,
                onChanged: (val) {
                  setState(() => _autoSelectSource = val);
                  _saveSettings();
                },
              ),
              Divider(color: context.line, height: 1),

              // Auto Select Subtitles
              SwitchListTile(
                secondary: Icon(Icons.closed_caption_rounded, color: context.fgMuted),
                title: Text(text.t('auto_select_subtitle'), style: TextStyle(color: context.fg, fontSize: 14)),
                value: _autoSelectSubtitle,
                activeTrackColor: Colors.deepPurpleAccent,
                onChanged: (val) {
                  setState(() => _autoSelectSubtitle = val);
                  _saveSettings();
                },
              ),
            ],
          ),
          const SizedBox(height: 20),

          // -----------------------------------------------------------
          // Section 5: Data & Backup
          // -----------------------------------------------------------
          _buildSectionHeader(
            icon: Icons.sync_rounded,
            title: text.languageCode == 'tr' ? 'Veri & Yedekleme' : 'Data & Backup',
            color: Colors.blueAccent,
          ),
          _buildCard(
            children: [
              // Watch History Toggle
              SwitchListTile(
                secondary: Icon(Icons.history_rounded, color: context.fgMuted),
                title: Text(text.t('save_watch_history'), style: TextStyle(color: context.fg, fontSize: 14)),
                value: _watchHistoryEnabled,
                activeTrackColor: Colors.deepPurpleAccent,
                onChanged: (val) {
                  setState(() => _watchHistoryEnabled = val);
                  _saveSettings();
                },
              ),
              Divider(color: context.line, height: 1),

              // Export Backup
              ListTile(
                leading: Icon(Icons.file_upload_outlined, color: context.fgMuted),
                title: Text(text.t('export_backup'), style: TextStyle(color: context.fg, fontSize: 14)),
                trailing: _isExportingBackup
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.chevron_right_rounded, color: context.fgFaint),
                onTap: _isExportingBackup ? null : _exportLocalBackup,
              ),
              Divider(color: context.line, height: 1),

              // Import Backup
              ListTile(
                leading: Icon(Icons.file_download_outlined, color: context.fgMuted),
                title: Text(text.t('import_backup'), style: TextStyle(color: context.fg, fontSize: 14)),
                trailing: _isImportingBackup
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.chevron_right_rounded, color: context.fgFaint),
                onTap: _isImportingBackup ? null : _importLocalBackup,
              ),
              Divider(color: context.line, height: 1),

              // Cloud Sync Server Settings
              ListTile(
                leading: Icon(Icons.cloud_queue_rounded, color: context.fgMuted),
                title: Text(text.languageCode == 'tr' ? 'Bulut Senkronizasyon Sunucusu' : 'Cloud Sync Server', style: TextStyle(color: context.fg, fontSize: 14)),
                subtitle: Text(
                  _syncServerUrl.isNotEmpty ? _syncServerUrl : (text.languageCode == 'tr' ? 'Yapılandırılmadı' : 'Not configured'),
                  style: TextStyle(color: context.fgFaint, fontSize: 12),
                ),
                trailing: Icon(Icons.chevron_right_rounded, color: context.fgFaint),
                onTap: () => _openSyncServerModal(context, text),
              ),
              Divider(color: context.line, height: 1),

              // Manual Cloud Sync
              ListTile(
                leading: Icon(Icons.cloud_sync_rounded, color: context.fgMuted),
                title: Text(text.t('sync_now'), style: TextStyle(color: context.fg, fontSize: 14)),
                trailing: _isSyncing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.sync_rounded, color: context.fgFaint),
                onTap: _isSyncing ? null : _manualSync,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // -----------------------------------------------------------
          // Section 6: About & Updates
          // -----------------------------------------------------------
          _buildSectionHeader(
            icon: Icons.info_outline_rounded,
            title: text.languageCode == 'tr' ? 'Hakkında & Güncellemeler' : 'About & Updates',
            color: Colors.orangeAccent,
          ),
          _buildCard(
            children: [
              ListTile(
                leading: Icon(Icons.app_shortcut_rounded, color: context.fgMuted),
                title: Text('StreamApp', style: TextStyle(color: context.fg, fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text('Version $_currentVersion', style: TextStyle(color: context.fgFaint, fontSize: 12)),
                trailing: FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: context.fg.withValues(alpha: 0.08),
                  ),
                  onPressed: _isCheckingForUpdates ? null : _checkUpdates,
                  child: _isCheckingForUpdates
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(text.t('check_for_updates')),
                ),
              ),
              if (_updateInfo != null) ...[
                Divider(color: context.line, height: 1),
                ListTile(
                  leading: const Icon(Icons.system_update_rounded, color: Colors.deepPurpleAccent),
                  title: Text(
                    '${text.t('new_update_found')}: ${_updateInfo!.latestVersion}',
                    style: TextStyle(color: context.fg, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  subtitle: _isDownloadingUpdate
                      ? LinearProgressIndicator(value: _downloadProgress, color: Colors.deepPurpleAccent)
                      : null,
                  trailing: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                    onPressed: _isDownloadingUpdate ? null : _installUpdate,
                    child: Text(text.t('install_update')),
                  ),
                ),
              ],
              if (_updateError.isNotEmpty) ...[
                Divider(color: context.line, height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(_updateError, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                ),
              ],
              Divider(color: context.line, height: 1),
              ListTile(
                leading: const Icon(Icons.star_rate_rounded, color: Colors.amber),
                title: Text(text.t('rate_app'), style: TextStyle(color: context.fg, fontSize: 14)),
                subtitle: Text(text.t('rate_app_desc'), style: TextStyle(color: context.fgFaint, fontSize: 12)),
                trailing: Icon(Icons.open_in_new_rounded, color: context.fgFaint, size: 18),
                onTap: AppBaseline.openRepo,
              ),
              if (AppBaseline.donationUrl.isNotEmpty) ...[
                Divider(color: context.line, height: 1),
                ListTile(
                  leading: const Icon(Icons.favorite_rounded, color: Colors.pinkAccent),
                  title: Text(text.t('support_app'), style: TextStyle(color: context.fg, fontSize: 14)),
                  subtitle: Text(text.t('support_app_desc'), style: TextStyle(color: context.fgFaint, fontSize: 12)),
                  trailing: Icon(Icons.open_in_new_rounded, color: context.fgFaint, size: 18),
                  onTap: AppBaseline.openDonation,
                ),
              ],
              Divider(color: context.line, height: 1),
              ListTile(
                leading: Icon(Icons.help_outline_rounded, color: context.fgMuted),
                title: Text(text.t('tutorial_title'), style: TextStyle(color: context.fg, fontSize: 14)),
                trailing: Icon(Icons.chevron_right_rounded, color: context.fgFaint),
                onTap: () => OnboardingTutorialDialog.show(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExternalPlayerTile(AppText text) {
    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem(value: '', child: Text(text.t('in_app_player'))),
      DropdownMenuItem(
        value: ExternalPlayerService.askValue,
        child: Text(text.t('external_player_ask')),
      ),
      for (final app in _externalApps)
        DropdownMenuItem(value: app.packageName, child: Text(app.label)),
    ];
    final known = items.any((i) => i.value == _externalPlayer);
    if (!known) {
      items.add(
        DropdownMenuItem(value: _externalPlayer, child: Text(_externalPlayer)),
      );
    }
    return ListTile(
      leading: Icon(Icons.open_in_new_rounded, color: context.fgMuted),
      title: Text(
        text.t('video_player_app'),
        style: TextStyle(color: context.fg, fontSize: 14),
      ),
      subtitle: Text(
        text.t('video_player_app_desc'),
        style: TextStyle(color: context.fgFaint, fontSize: 12),
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 150),
        child: DropdownButton<String>(
          value: _externalPlayer,
          isExpanded: true,
          dropdownColor: context.card,
          underline: const SizedBox.shrink(),
          items: items,
          onChanged: (val) {
            if (val == null) return;
            setState(() => _externalPlayer = val);
            _saveSettings();
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: context.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.fg.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: children,
        ),
      ),
    );
  }

  void _openTmdbModal(BuildContext context, AppText text) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.cs.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'TMDB Access Token',
                style: TextStyle(color: context.fg, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                text.languageCode == 'tr'
                    ? 'Film ve dizi afişleri ve metaverileri için TMDB Read Access Token (v4) gereklidir.'
                    : 'Required for movies and TV series posters, metadata and discovery.',
                style: TextStyle(color: context.fgMuted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _tmdbTokenController,
                maxLines: 2,
                style: TextStyle(color: context.fg, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
                  hintStyle: TextStyle(color: context.cs.outline),
                  filled: true,
                  fillColor: context.cardHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.line),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.help_outline, size: 16),
                    label: Text(text.t('how_to_get_token')),
                    onPressed: () => showTmdbTokenInstructions(context, text),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _saveSettings();
                    },
                    child: Text(text.t('save')),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _openSyncServerModal(BuildContext context, AppText text) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx2).viewInsets.bottom + 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.cs.outline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    text.t('sync_title'),
                    style: TextStyle(color: context.fg, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    text.t('sync_desc'),
                    style: TextStyle(color: context.fgMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _syncServerUrlController,
                    style: TextStyle(color: context.fg, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'https://sync.example.com',
                      hintStyle: TextStyle(color: context.cs.outline),
                      filled: true,
                      fillColor: context.cardHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: context.line),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                      onPressed: _isSyncRegistering
                          ? null
                          : () async {
                              setModalState(() => _isSyncRegistering = true);
                              await _registerSyncDevice();
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                      icon: _isSyncRegistering
                          ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: context.fg))
                          : const Icon(Icons.app_registration_rounded),
                      label: Text(text.t('register_device')),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
