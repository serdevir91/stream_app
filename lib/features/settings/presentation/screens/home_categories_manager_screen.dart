import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_text.dart';
import '../../../../core/settings/app_settings.dart';
import '../../../../core/settings/app_settings_provider.dart';

class HomeCategoriesManagerScreen extends ConsumerWidget {
  const HomeCategoriesManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final text = ref.watch(appTextProvider);
    final activeCategories = settings.homeCategories;

    // Find all categories that are not currently active
    final availableCategories = defaultHomeCategories
        .where((cat) => !activeCategories.contains(cat))
        .toList();

    Future<void> updateCategories(List<String> nextCategories) async {
      final updatedSettings = settings.copyWith(homeCategories: nextCategories);
      await ref.read(appSettingsProvider.notifier).saveSettings(updatedSettings);
    }

    void onReorder(int oldIndex, int newIndex) {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final updated = List<String>.from(activeCategories);
      final item = updated.removeAt(oldIndex);
      updated.insert(newIndex, item);
      updateCategories(updated);
    }

    void removeCategory(String category) {
      final updated = List<String>.from(activeCategories)..remove(category);
      updateCategories(updated);
    }

    void addCategory(String category) {
      final updated = List<String>.from(activeCategories)..add(category);
      updateCategories(updated);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(text.t('homepage_categories')),
        centerTitle: true,
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text.t('active_categories'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.redAccent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    text.t('drag_to_reorder'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          if (activeCategories.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: Card(
                  elevation: 0,
                  color: Colors.grey.shade900.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade800),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Center(
                      child: Text(
                        text.t('no_active_categories'),
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    // Custom ReorderableList implementation inside CustomScrollView using ReorderableDelayForDragMode
                    // but wait, standard ReorderableListView is easier to wrap in a SliverToBoxAdapter.
                    // Let's use a standard ReorderableListView in a SliverToBoxAdapter for perfect stability.
                    return const SizedBox.shrink();
                  },
                  childCount: 0,
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: activeCategories.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade800),
                      ),
                      child: ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: activeCategories.length,
                        onReorder: onReorder,
                        itemBuilder: (context, index) {
                          final cat = activeCategories[index];
                          return Card(
                            key: ValueKey(cat),
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            color: Colors.grey.shade900,
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              leading: const Icon(
                                Icons.drag_indicator,
                                color: Colors.grey,
                              ),
                              title: Text(
                                text.t(cat),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () => removeCategory(cat),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                text.t('available_categories'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.greenAccent,
                ),
              ),
            ),
          ),
          if (availableCategories.isEmpty)
            const SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Center(
                    child: Text(
                      'Tüm kategoriler aktif durumda.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final cat = availableCategories[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: Colors.grey.shade900.withValues(alpha: 0.6),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Colors.grey.shade800),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        title: Text(
                          text.t(cat),
                          style: const TextStyle(fontSize: 14),
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.add_circle_outline,
                            color: Colors.greenAccent,
                          ),
                          onPressed: () => addCategory(cat),
                        ),
                      ),
                    );
                  },
                  childCount: availableCategories.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
