import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_text.dart';
import '../../../../core/settings/app_settings.dart';
import '../../../../core/settings/app_settings_provider.dart';

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
  bool _initialized = false;
  bool _isSaving = false;

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
    _tmdbTokenController = TextEditingController(
      text: settings.tmdbAccessToken,
    );
    _backendUrlController = TextEditingController(
      text: settings.backendUrl,
    );
    _initialized = true;
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

    final next = current.copyWith(
      appLanguage: _appLanguage,
      subtitleLanguage: _subtitleLanguage,
      tmdbAccessToken: _tmdbTokenController.text.trim(),
      backendUrl: _backendUrlController.text.trim(),
    );

    final syncStatus = await notifier.saveSettings(next);

    if (mounted) {
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
        SnackBar(content: Text(message), backgroundColor: backgroundColor),
      );
    }

    if (mounted) {
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    _ensureInitialized(settings);

    final text = ref.watch(appTextProvider);

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
            text.t('backend_url') ?? 'Backend URL',
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
          const SizedBox(height: 8),
          Text(
            text.t('api_required'),
            style: TextStyle(color: Colors.orange.shade300, fontSize: 12),
          ),
          const SizedBox(height: 24),
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
