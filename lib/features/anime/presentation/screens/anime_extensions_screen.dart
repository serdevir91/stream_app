import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/theme_x.dart';

import '../../../../core/i18n/app_text.dart';
import '../../data/providers/anime_extensions_provider.dart';

class AnimeExtensionsScreen extends ConsumerWidget {
  const AnimeExtensionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(appTextProvider);
    final extensions = ref.watch(animeExtensionsProvider);
    final notifier = ref.read(animeExtensionsProvider.notifier);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        title: Text(
          text.languageCode == 'tr' ? 'Anime Eklentileri & Kaynaklar' : 'Anime Extensions & Sources',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: text.languageCode == 'tr' ? 'Varsayılana Sıfırla' : 'Reset to Defaults',
            icon: Icon(Icons.restore_rounded, color: context.fgMuted),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: context.card,
                  title: Text(text.languageCode == 'tr' ? 'Sıfırla' : 'Reset'),
                  content: Text(
                    text.languageCode == 'tr'
                        ? 'Tüm anime eklentileri varsayılan ayarlara döndürülsün mü?'
                        : 'Reset all anime extensions to default settings?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(text.t('cancel'), style: TextStyle(color: context.fgMuted)),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(text.languageCode == 'tr' ? 'Evet' : 'Yes'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                notifier.resetToDefaults();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Info banner
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.deepPurple.withValues(alpha: 0.15),
                  Colors.indigo.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.deepPurpleAccent, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text.languageCode == 'tr'
                        ? 'Animeler için kullanılan kaynakları buradan bağımsız olarak açıp kapatabilir ve sürükleyerek öncelik sırasını değiştirebilirsiniz.'
                        : 'Manage dedicated anime streaming providers independently. Toggle on/off and reorder to set server priority.',
                    style: TextStyle(color: context.fgMuted, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),

          // Reorderable List
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: extensions.length,
              onReorderItem: (oldIndex, newIndex) {
                HapticFeedback.lightImpact();
                notifier.reorderExtensionsDirect(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final ext = extensions[index];
                return Container(
                  key: ValueKey(ext.id),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: context.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: ext.isEnabled
                          ? Colors.deepPurpleAccent.withValues(alpha: 0.3)
                          : context.fg.withValues(alpha: 0.05),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    leading: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ext.isEnabled
                            ? Colors.deepPurpleAccent.withValues(alpha: 0.15)
                            : context.fg.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        ext.icon,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            ext.name,
                            style: TextStyle(
                              color: ext.isEnabled ? context.fg : context.fgMuted,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: context.fg.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'v${ext.version}',
                            style: TextStyle(color: context.fgFaint, fontSize: 10),
                          ),
                        ),
                        if (ext.isDirectStream) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E054).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Direct',
                              style: TextStyle(color: Color(0xFF00E054), fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        ext.description,
                        style: TextStyle(color: context.fgFaint, fontSize: 11, height: 1.3),
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: ext.isEnabled,
                          activeThumbColor: Colors.deepPurpleAccent,
                          activeTrackColor: Colors.deepPurpleAccent.withValues(alpha: 0.4),
                          inactiveThumbColor: context.fgFaint,
                          inactiveTrackColor: context.line,
                          onChanged: (val) {
                            HapticFeedback.selectionClick();
                            notifier.toggleExtension(ext.id, val);
                          },
                        ),
                        const SizedBox(width: 4),
                        ReorderableDragStartListener(
                          index: index,
                          child: Icon(Icons.drag_handle_rounded, color: context.fgFaint),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
