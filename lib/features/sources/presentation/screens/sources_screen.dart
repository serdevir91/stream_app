import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/i18n/app_text.dart';
import '../providers/sources_provider.dart';
import '../../domain/entities/source.dart';

class SourcesScreen extends ConsumerWidget {
  const SourcesScreen({super.key});

  void _showSourceDialog(
    BuildContext context,
    WidgetRef ref, {
    Source? existingSource,
  }) {
    final text = ref.read(appTextProvider);
    final nameController = TextEditingController(
      text: existingSource?.name ?? '',
    );
    final baseUrlController = TextEditingController(
      text: existingSource?.baseUrl ?? '',
    );
    final searchEndpointController = TextEditingController(
      text: existingSource?.searchEndpoint ?? '',
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(existingSource == null ? text.t('add_source') : text.t('edit_source')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: text.t('source_name_label'),
                  ),
                ),
                TextField(
                  controller: baseUrlController,
                  decoration: InputDecoration(
                    labelText: text.t('source_url_label'),
                  ),
                ),
                TextField(
                  controller: searchEndpointController,
                  decoration: InputDecoration(
                    labelText: text.t('source_search_endpoint_label'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(text.t('cancel')),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isNotEmpty &&
                    baseUrlController.text.isNotEmpty) {
                  ref
                      .read(sourcesProvider.notifier)
                      .addSource(
                        Source(
                          id:
                              existingSource?.id ??
                              DateTime.now().millisecondsSinceEpoch.toString(),
                          name: nameController.text,
                          baseUrl: baseUrlController.text,
                          searchEndpoint: searchEndpointController.text,
                          isEnabled: existingSource?.isEnabled ?? true,
                        ),
                      );
                  Navigator.of(context).pop();
                }
              },
              child: Text(existingSource == null ? text.t('add') : text.t('save')),
            ),
          ],
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Source source) {
    final text = ref.read(appTextProvider);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(text.t('delete_source')),
          content: Text(text.t('delete_source_confirm').replaceAll('{param}', source.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(text.t('cancel')),
            ),
            TextButton(
              onPressed: () {
                ref.read(sourcesProvider.notifier).removeSource(source.id);
                Navigator.of(context).pop();
              },
              child: Text(text.t('delete_button'), style: const TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(appTextProvider);
    final sources = ref.watch(sourcesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(text.t('sources'))),
      body: sources.isEmpty
          ? Center(child: Text(text.t('no_data')))
          : ListView.builder(
              itemCount: sources.length,
              itemBuilder: (context, index) {
                final source = sources[index];
                return ListTile(
                  title: Text(source.name),
                  subtitle: Text(source.baseUrl),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: source.isEnabled,
                        onChanged: (val) {
                          ref
                              .read(sourcesProvider.notifier)
                              .toggleSource(source.id, val);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showSourceDialog(
                          context,
                          ref,
                          existingSource: source,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _confirmDelete(context, ref, source),
                      ),
                    ],
                  ),
                  onTap: () =>
                      _showSourceDialog(context, ref, existingSource: source),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showSourceDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }
}
