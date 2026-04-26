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
          title: Text(existingSource == null ? 'Add Source' : 'Edit Source'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name (e.g., My API)',
                  ),
                ),
                TextField(
                  controller: baseUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Base URL (e.g., https://api.example.com)',
                  ),
                ),
                TextField(
                  controller: searchEndpointController,
                  decoration: const InputDecoration(
                    labelText: 'Search Endpoint (e.g., /search)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
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
              child: Text(existingSource == null ? 'Add' : 'Save'),
            ),
          ],
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Source source) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Source'),
          content: Text('Are you sure you want to delete ${source.name}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                ref.read(sourcesProvider.notifier).removeSource(source.id);
                Navigator.of(context).pop();
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
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
