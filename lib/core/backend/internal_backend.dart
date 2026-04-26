import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../features/addons/presentation/screens/addon_manager_screen.dart';

/// Models for the internal backend
class LocalStreamResult {
  final String url;
  final String title;
  final String quality;
  final String provider;
  final bool isDirectLink;

  LocalStreamResult({
    required this.url,
    required this.title,
    required this.quality,
    required this.provider,
    required this.isDirectLink,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'quality': quality,
        'provider': provider,
        'is_direct_link': isDirectLink,
      };
}

/// A Dart implementation of the backend logic to allow standalone Android usage.
class InternalBackendService {
  static final InternalBackendService _instance = InternalBackendService._internal();
  factory InternalBackendService() => _instance;
  InternalBackendService._internal();

  String? _tmdbToken;

  void setTmdbToken(String? token) {
    _tmdbToken = token;
  }

  /// Mimics GET /api/addons
  Future<Map<String, dynamic>> getAddons() async {
    return {
      'addons': [
        {
          'id': 'builtin.vidsrc',
          'name': 'VidSrc (Local)',
          'description': 'Internal VidSrc resolver (No PC required)',
          'version': '1.0.0',
          'types': ['movie', 'series'],
          'is_builtin': true,
          'enabled': true,
        }
      ]
    };
  }

  /// Mimics GET /api/resolve
  Future<Map<String, dynamic>> resolve({
    required String query,
    required String tmdbId,
    required String type,
    int season = 1,
    int episode = 1,
  }) async {
    final streams = <LocalStreamResult>[];
    
    // Logic from vidsrc.py ported to Dart
    final isImdb = tmdbId.startsWith('tt');
    final isMovie = type == 'movie';
    
    String url;
    if (isMovie) {
      if (isImdb) {
        url = 'https://vidsrc-embed.ru/embed/movie?imdb=$tmdbId&ds_lang=tr';
      } else {
        url = 'https://vidsrc-embed.ru/embed/movie?tmdb=$tmdbId&ds_lang=tr';
      }
    } else {
      if (isImdb) {
        url = 'https://vidsrc-embed.ru/embed/tv?imdb=$tmdbId&season=$season&episode=$episode&ds_lang=tr&autonext=1';
      } else {
        url = 'https://vidsrc-embed.ru/embed/tv?tmdb=$tmdbId&season=$season&episode=$episode&ds_lang=tr&autonext=1';
      }
    }

    streams.add(LocalStreamResult(
      url: url,
      title: 'VidSrc (Internal)',
      quality: 'HD',
      provider: 'VidSrc',
      isDirectLink: false,
    ));

    return {
      'success': true,
      'streams': streams.map((s) => s.toJson()).toList(),
    };
  }

  /// Mimics GET /api/search (Used by some complex add-ons, though VidSrc doesn't use it)
  Future<Map<String, dynamic>> search(String query, String type) async {
    // Ported from vidsrc.py: VidSrc doesn't provide title search
    return {'results': []};
  }
}
