import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

const String currentAppVersionFallback = '1.0.9';

class AppUpdateInfo {
  final String latestVersion;
  final String releaseNotes;
  final String downloadUrl;
  final String githubUrl;
  final String fileName;

  AppUpdateInfo({
    required this.latestVersion,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.githubUrl,
    required this.fileName,
  });
}

class AppUpdaterService {
  final Dio _dio = Dio();
  static const String _repoUrl =
      'https://api.github.com/repos/serdevir91/stream_app/releases/latest';
  static const MethodChannel _updaterChannel = MethodChannel(
    'stream_app/app_updater',
  );

  Future<String> getCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      if (version.isNotEmpty) {
        return version;
      }
    } catch (e) {
      debugPrint('Read app version failed: $e');
    }
    return currentAppVersionFallback;
  }

  bool _isNewerVersion(String current, String latest) {
    try {
      final currentParts = _parseVersionParts(current);
      final latestParts = _parseVersionParts(latest);

      for (var i = 0; i < currentParts.length; i++) {
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  List<int> _parseVersionParts(String value) {
    final clean = value
        .toLowerCase()
        .replaceFirst(RegExp(r'^v'), '')
        .split('+')
        .first
        .split('-')
        .first
        .trim();
    final parts = clean
        .split('.')
        .map(
          (part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
        )
        .toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts.take(3).toList();
  }

  Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final currentVersion = await getCurrentVersion();
      final response = await _dio.get(
        _repoUrl,
        options: Options(
          headers: {
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'stream-app-updater',
          },
        ),
      );

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data;
        final latestTag = (data['tag_name'] ?? '').toString();
        final htmlUrl = (data['html_url'] ?? '').toString();
        final body = (data['body'] ?? '').toString();

        if (latestTag.isEmpty) return null;

        if (_isNewerVersion(currentVersion, latestTag)) {
          final assets = data['assets'] as List?;
          String downloadUrl = '';
          String fileName = '';

          if (assets != null) {
            if (kIsWeb) {
              return null;
            } else if (Platform.isWindows) {
              // Try to find .exe or .zip for Windows
              final winAsset = assets.firstWhere(
                (a) =>
                    a['name'].toString().toLowerCase().endsWith('.exe') ||
                    a['name'].toString().toLowerCase().endsWith('.zip'),
                orElse: () => null,
              );
              if (winAsset != null) {
                downloadUrl = winAsset['browser_download_url'].toString();
                fileName = winAsset['name'].toString();
              }
            } else if (Platform.isAndroid) {
              // Try to find .apk for Android
              final apkAsset = assets.firstWhere(
                (a) => a['name'].toString().toLowerCase().endsWith('.apk'),
                orElse: () => null,
              );
              if (apkAsset != null) {
                downloadUrl = apkAsset['browser_download_url'].toString();
                fileName = apkAsset['name'].toString();
              }
            }
          }

          // Fallback if no specific asset matches but a release page exists
          if (downloadUrl.isEmpty) {
            downloadUrl = htmlUrl;
          }

          return AppUpdateInfo(
            latestVersion: latestTag,
            releaseNotes: body,
            downloadUrl: downloadUrl,
            githubUrl: htmlUrl,
            fileName: fileName,
          );
        }
      }
    } catch (e) {
      debugPrint('Check for update failed: $e');
    }
    return null;
  }

  Future<void> performUpdate(
    AppUpdateInfo updateInfo, {
    required Function(double progress) onProgress,
    required VoidCallback onComplete,
    required Function(String error) onError,
  }) async {
    final downloadUrl = updateInfo.downloadUrl;

    if (downloadUrl.isEmpty) {
      onError('Download URL is empty.');
      return;
    }

    if (kIsWeb || !downloadUrl.startsWith('http')) {
      try {
        final uri = Uri.parse(downloadUrl);
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          onComplete();
        } else {
          onError('Could not open browser for update.');
        }
      } catch (e) {
        onError('Error launching browser: $e');
      }
      return;
    }

    try {
      final fileName = _resolveFileName(updateInfo);

      if (Platform.isAndroid && fileName.toLowerCase().endsWith('.apk')) {
        final tempDir = await getTemporaryDirectory();
        final tempFilePath =
            '${tempDir.path}${Platform.pathSeparator}$fileName';

        await _dio.download(
          downloadUrl,
          tempFilePath,
          onReceiveProgress: (received, total) {
            if (total > 0) {
              onProgress(received / total);
            }
          },
        );

        final downloadedFile = File(tempFilePath);
        if (!await downloadedFile.exists()) {
          onError('Downloaded APK could not be found.');
          return;
        }

        final installed = await _updaterChannel.invokeMethod<bool>(
          'installApk',
          {'path': tempFilePath},
        );
        if (installed == true) {
          onComplete();
        } else {
          onError('Could not start APK installer.');
        }
        return;
      }

      if (!Platform.isWindows) {
        final uri = Uri.parse(downloadUrl);
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          onComplete();
        } else {
          onError('Could not open browser for update.');
        }
        return;
      }

      final tempDir = Directory.systemTemp;
      final tempFilePath = '${tempDir.path}\\$fileName';

      await _dio.download(
        downloadUrl,
        tempFilePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress(received / total);
          }
        },
      );

      // Check if downloaded file exists
      final downloadedFile = File(tempFilePath);
      if (!await downloadedFile.exists()) {
        onError('Downloaded file could not be found.');
        return;
      }

      onComplete();

      // Trigger installer or hot-swapping script
      if (fileName.toLowerCase() == 'stream_app.exe') {
        // Standalone executable hot-replacement
        final currentExePath = Platform.resolvedExecutable;
        final batContent =
            '''
@echo off
timeout /t 2 /nobreak > nul
move /y "$tempFilePath" "$currentExePath"
start "" "$currentExePath"
del "%~f0"
''';
        final batFile = File('${tempDir.path}\\update_stream_app.bat');
        await batFile.writeAsString(batContent);

        await Process.start('cmd.exe', ['/c', batFile.path], runInShell: true);
        exit(0);
      } else {
        // Setup installer execution
        await Process.start('cmd.exe', [
          '/c',
          'start',
          '',
          tempFilePath,
        ], runInShell: true);
        exit(0);
      }
    } catch (e) {
      onError('Update failed: $e');
    }
  }

  String _resolveFileName(AppUpdateInfo updateInfo) {
    final assetName = updateInfo.fileName.trim();
    if (assetName.isNotEmpty) {
      return assetName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    }
    final parsed = Uri.tryParse(updateInfo.downloadUrl);
    final pathName = parsed?.pathSegments.isNotEmpty == true
        ? parsed!.pathSegments.last
        : '';
    if (pathName.isNotEmpty) {
      return pathName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    }
    return 'stream_app_update';
  }
}
