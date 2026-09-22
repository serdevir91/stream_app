import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/download_service.dart';
import '../../domain/entities/download_item.dart';
import '../../../player/presentation/providers/player_provider.dart';

DownloadService? _globalDownloadService;

void initDownloadService(DownloadService service) {
  _globalDownloadService = service;
}

final downloadServiceProvider = Provider<DownloadService>((ref) {
  if (_globalDownloadService != null) {
    return _globalDownloadService!;
  }
  final subtitleRepo = ref.watch(onlineSubtitleRepositoryProvider);
  final service = DownloadService(subtitleRepo: subtitleRepo);
  _globalDownloadService = service;
  return service;
});

final downloadsStreamProvider = StreamProvider<List<DownloadItem>>((ref) {
  final service = ref.watch(downloadServiceProvider);
  return service.watchDownloads();
});

final allDownloadsProvider = Provider<List<DownloadItem>>((ref) {
  final asyncVal = ref.watch(downloadsStreamProvider);
  final service = ref.watch(downloadServiceProvider);
  return asyncVal.asData?.value ?? service.getAllDownloads();
});

final activeDownloadsProvider = Provider<List<DownloadItem>>((ref) {
  final all = ref.watch(allDownloadsProvider);
  return all
      .where((item) => item.status == 'downloading' || item.status == 'queued')
      .toList();
});

final completedDownloadsProvider = Provider<List<DownloadItem>>((ref) {
  final all = ref.watch(allDownloadsProvider);
  return all.where((item) => item.status == 'completed').toList();
});
