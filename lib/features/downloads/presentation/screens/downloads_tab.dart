import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_text.dart';
import '../../../player/presentation/screens/player_screen.dart';
import '../../data/services/download_service.dart';
import '../../domain/entities/download_item.dart';
import '../providers/download_provider.dart';

class DownloadsTab extends ConsumerWidget {
  const DownloadsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(appTextProvider);
    final isTr = text.languageCode == 'tr';
    final isAr = text.languageCode == 'ar';
    final isFa = text.languageCode == 'fa';

    final allDownloads = ref.watch(allDownloadsProvider);
    final activeDownloads = ref.watch(activeDownloadsProvider);
    final completedDownloads = ref.watch(completedDownloadsProvider);

    if (allDownloads.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.download_for_offline_outlined,
                  size: 48,
                  color: Colors.cyanAccent,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                isTr
                    ? 'Henüz İndirilen İçerik Yok'
                    : isAr
                        ? 'لا توجد تنزيلات حتى الآن'
                        : isFa
                            ? 'هنوز محتوای دانلودی وجود ندارد'
                            : 'No Downloads Yet',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isTr
                    ? 'Film ve dizi sayfalarındaki İndir butonunu kullanarak içerikleri çevrimdışı izlemek için buraya ekleyebilirsiniz.'
                    : isAr
                        ? 'يمكنك تنزيل الأفلام والحلقات للمشاهدة بدون إنترنت عبر زر التحميل في صفحة التفاصيل.'
                        : isFa
                            ? 'می‌توانید با دکمه دانلود در صفحه فیلم و سریال، محتوا را برای تماشای آفلاین اضافه کنید.'
                            : 'Use the download button on movie or series details to watch your favorite media offline.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // Active Downloads Section
        if (activeDownloads.isNotEmpty) ...[
          Row(
            children: [
              const Icon(Icons.downloading_rounded,
                  color: Colors.cyanAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                isTr
                    ? 'İndiriliyor (${activeDownloads.length})'
                    : isAr
                        ? 'قيد التنزيل (${activeDownloads.length})'
                        : isFa
                            ? 'در حال دانلود (${activeDownloads.length})'
                            : 'Downloading (${activeDownloads.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...activeDownloads.map(
            (item) => _ActiveDownloadCard(item: item),
          ),
          const SizedBox(height: 20),
        ],

        // Completed Downloads Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.greenAccent, size: 20),
                const SizedBox(width: 8),
                Text(
                  isTr
                      ? 'Tamamlananlar (${completedDownloads.length})'
                      : isAr
                          ? 'المكتملة (${completedDownloads.length})'
                          : isFa
                              ? 'تکمیل شده‌ها (${completedDownloads.length})'
                              : 'Completed (${completedDownloads.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (completedDownloads.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Center(
              child: Text(
                isTr
                    ? 'Tamamlanmış indirme bulunmuyor.'
                    : 'No completed downloads.',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          )
        else
          ...completedDownloads.map(
            (item) => _CompletedDownloadCard(item: item),
          ),
      ],
    );
  }
}

class _ActiveDownloadCard extends ConsumerWidget {
  final DownloadItem item;

  const _ActiveDownloadCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(downloadServiceProvider);
    final percent = (item.progress * 100).toStringAsFixed(1);
    final downloadedStr = DownloadService.formatBytes(item.downloadedBytes);
    final totalStr = item.totalBytes > 0
        ? DownloadService.formatBytes(item.totalBytes)
        : '...';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: item.posterUrl != null && item.posterUrl!.isNotEmpty
                    ? Image.network(
                        item.posterUrl!,
                        width: 48,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _fallbackThumb(),
                      )
                    : _fallbackThumb(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (item.isSeries &&
                        item.season != null &&
                        item.episode != null)
                      Text(
                        'S${item.season} • E${item.episode}${item.episodeTitle != null ? " - ${item.episodeTitle}" : ""}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.quality,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (item.speed.isNotEmpty)
                          Text(
                            item.speed,
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: () => service.cancelDownload(item.id),
                tooltip: 'İptal Et',
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: item.progress > 0 ? item.progress : null,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation(Colors.cyanAccent),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$downloadedStr / $totalStr',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
              Text(
                '%$percent',
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fallbackThumb() {
    return Container(
      width: 48,
      height: 64,
      color: Colors.white10,
      child: const Icon(Icons.movie_rounded, color: Colors.white38),
    );
  }
}

class _CompletedDownloadCard extends ConsumerWidget {
  final DownloadItem item;

  const _CompletedDownloadCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(appTextProvider);
    final service = ref.watch(downloadServiceProvider);
    final totalStr = DownloadService.formatBytes(item.totalBytes);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: item.posterUrl != null && item.posterUrl!.isNotEmpty
                ? Image.network(
                    item.posterUrl!,
                    width: 52,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _fallbackThumb(),
                  )
                : _fallbackThumb(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                if (item.isSeries &&
                    item.season != null &&
                    item.episode != null)
                  Text(
                    'S${item.season} • E${item.episode}${item.episodeTitle != null ? " - ${item.episodeTitle}" : ""}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.quality,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        totalStr,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    if (item.localSubtitlePath != null &&
                        File(item.localSubtitlePath!).existsSync())
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.subtitles_rounded,
                                size: 11, color: Colors.greenAccent),
                            SizedBox(width: 3),
                            Text(
                              'Altyazılı',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.greenAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            children: [
              IconButton.filled(
                icon: const Icon(Icons.play_arrow_rounded, size: 24),
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlayerScreen(
                        mediaId: item.mediaId,
                        title: item.title,
                        type: item.mediaType,
                        season: item.season ?? 1,
                        episode: item.episode ?? 1,
                        posterUrl: item.posterUrl,
                        backdropUrl: item.backdropUrl,
                        localVideoPath: item.localVideoPath,
                        localSubtitlePath: item.localSubtitlePath,
                      ),
                    ),
                  );
                },
                tooltip: text.t('play_now'),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 20, color: Colors.redAccent),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(text.languageCode == 'tr'
                          ? 'İndirmeyi Sil'
                          : 'Delete Download'),
                      content: Text(text.languageCode == 'tr'
                          ? 'Bu içerik cihazınızdan kalıcı olarak silinecek. Emin misiniz?'
                          : 'This media will be permanently deleted from your device. Are you sure?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: Text(text.languageCode == 'tr'
                              ? 'Vazgeç'
                              : 'Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: Text(
                            text.languageCode == 'tr' ? 'Sil' : 'Delete',
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await service.deleteDownload(item.id);
                  }
                },
                tooltip: 'Sil',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fallbackThumb() {
    return Container(
      width: 52,
      height: 72,
      color: Colors.white10,
      child: const Icon(Icons.movie_rounded, color: Colors.white38),
    );
  }
}
