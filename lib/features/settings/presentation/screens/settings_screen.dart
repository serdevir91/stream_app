import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_text.dart';
import '../../../../core/settings/app_settings.dart';
import '../../../../core/settings/app_settings_provider.dart';
import '../../../addons/presentation/screens/addon_manager_screen.dart';
import '../../../sources/presentation/screens/sources_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _tmdbTokenController;
  late TextEditingController _backendUrlController;
  String _appLanguage = 'en';
  String _subtitleLanguage = 'en';
  bool _autoSelectSource = true;
  String _preferredSourceId = '';
  bool _initialized = false;
  bool _isSaving = false;
  bool _isApiFieldsVisible = false;

  @override
  void dispose() {
    if (_initialized) {
      _tmdbTokenController.dispose();
      _backendUrlController.dispose();
    }
    super.dispose();
  }

  void _ensureInitialized(AppSettings settings) {
    if (_initialized) {
      return;
    }
    _appLanguage = settings.appLanguage;
    _subtitleLanguage = settings.subtitleLanguage;
    _autoSelectSource = settings.autoSelectSource;
    _preferredSourceId = settings.preferredSourceId;
    _tmdbTokenController = TextEditingController(text: settings.tmdbAccessToken);
    _backendUrlController = TextEditingController(text: settings.backendUrl);
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
    final cleanedPreferredSourceId = _preferredSourceId.isNotEmpty &&
            !activeAddonIds.contains(_preferredSourceId)
        ? ''
        : _preferredSourceId;

    final next = current.copyWith(
      appLanguage: _appLanguage,
      subtitleLanguage: _subtitleLanguage,
      tmdbAccessToken: _tmdbTokenController.text.trim(),
      backendUrl: _backendUrlController.text.trim(),
      autoSelectSource: _autoSelectSource,
      preferredSourceId: cleanedPreferredSourceId,
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
                  : 'TMDB: $tmdbTokenPreview\nBackend: $backendPreview',
              maxLines: 2,
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
            Text(
              text.t('tmdb_token'),
              style: const TextStyle(fontWeight: FontWeight.w600),
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
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SourcesScreen()),
              );
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
