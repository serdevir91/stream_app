import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_text.dart';
import '../../../search/presentation/screens/media_details_screen.dart';
import '../providers/home_provider.dart';

class CategoryMediaScreen extends ConsumerWidget {
  final String categoryKey;
  final String title;
  final int crossAxisCount;

  const CategoryMediaScreen({
    super.key,
    required this.categoryKey,
    required this.title,
    this.crossAxisCount = 3,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(appTextProvider);
    final mediaAsync = ref.watch(categoryMediaProvider(categoryKey));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: mediaAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Text(text.t('no_data')),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: crossAxisCount == 3 ? 0.62 : 0.68,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MediaDetailsScreen(mediaItem: item),
                    ),
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (item.posterUrl != null && item.posterUrl!.isNotEmpty)
                              Image.network(
                                item.posterUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => const ColoredBox(
                                  color: Colors.grey,
                                  child: Icon(Icons.movie, size: 50),
                                ),
                              )
                            else
                              const ColoredBox(
                                color: Colors.grey,
                                child: Icon(Icons.movie, size: 50),
                              ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star, color: Colors.amber, size: 12),
                                    const SizedBox(width: 4),
                                    Text(
                                      item.rating?.toStringAsFixed(1) ?? 'N/A',
                                      style: const TextStyle(
                                        fontSize: 10, 
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      text.t(item.type).toUpperCase(),
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                    ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
      ),
    );
  }
}
