import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

/// Starts local backend automatically for desktop builds when possible.
class BackendBootstrapService {
  static Process? _backendProcess;
  static bool _isStarting = false;

  static Future<void> ensureBackendRunning({
    String tmdbAccessToken = '',
  }) async {
    if (kIsWeb ||
        !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return;
    }

    if (await _isBackendHealthy()) {
      return;
    }

    if (_isStarting) {
      return;
    }

    _isStarting = true;
    try {
      final backendDir = await _findBackendDirectory();
      if (backendDir == null) {
        debugPrint('[BackendBootstrap] backend/main.py not found.');
        return;
      }

      await _startBackendProcess(backendDir, tmdbAccessToken: tmdbAccessToken);

      final started = await _waitForBackendHealth();
      if (!started) {
        debugPrint(
          '[BackendBootstrap] Backend did not become healthy in time.',
        );
      }
    } catch (error) {
      debugPrint('[BackendBootstrap] Failed to start backend: $error');
    } finally {
      _isStarting = false;
    }
  }

  static Future<void> _startBackendProcess(
    Directory backendDir, {
    required String tmdbAccessToken,
  }) async {
    if (_backendProcess != null) {
      return;
    }

    final env = <String, String>{
      ...Platform.environment,
      if (tmdbAccessToken.trim().isNotEmpty)
        'TMDB_ACCESS_TOKEN': tmdbAccessToken.trim(),
    };

    _backendProcess = await Process.start(
      'python',
      const [
        '-m',
        'uvicorn',
        'main:app',
        '--host',
        '127.0.0.1',
        '--port',
        '8000',
      ],
      workingDirectory: backendDir.path,
      runInShell: true,
      environment: env,
    );

    unawaited(
      _backendProcess!.stdout.transform(SystemEncoding().decoder).forEach((
        line,
      ) {
        debugPrint('[Backend] $line');
      }),
    );

    unawaited(
      _backendProcess!.stderr.transform(SystemEncoding().decoder).forEach((
        line,
      ) {
        debugPrint('[Backend:ERR] $line');
      }),
    );

    unawaited(
      _backendProcess!.exitCode.then((code) {
        debugPrint('[BackendBootstrap] Backend exited with code $code');
        _backendProcess = null;
      }),
    );
  }

  static Future<void> syncTmdbToken(String tmdbAccessToken) async {
    if (kIsWeb ||
        !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return;
    }
    if (!await _isBackendHealthy()) {
      return;
    }
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: 'http://127.0.0.1:8000',
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      await dio.post(
        '/api/settings/tmdb',
        data: {'tmdb_access_token': tmdbAccessToken.trim()},
      );
    } catch (_) {
      // ignore sync errors during app bootstrap
    }
  }

  static Future<bool> _waitForBackendHealth() async {
    for (int i = 0; i < 16; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (await _isBackendHealthy()) {
        return true;
      }
    }
    return false;
  }

  static Future<bool> _isBackendHealthy() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 1);
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:8000/api/health'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 1),
      );
      client.close(force: true);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<Directory?> _findBackendDirectory() async {
    final candidates = <Directory>{
      Directory('${Directory.current.path}${Platform.pathSeparator}backend'),
    };

    final executableDir = File(Platform.resolvedExecutable).parent;
    Directory? pointer = executableDir;
    for (int i = 0; i < 7 && pointer != null; i++) {
      candidates.add(
        Directory('${pointer.path}${Platform.pathSeparator}backend'),
      );
      if (pointer.path == pointer.parent.path) {
        break;
      }
      pointer = pointer.parent;
    }

    for (final dir in candidates) {
      final mainFile = File('${dir.path}${Platform.pathSeparator}main.py');
      if (await mainFile.exists()) {
        return dir;
      }
    }

    return null;
  }
}
