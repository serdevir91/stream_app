import 'package:dio/dio.dart';
import '../../domain/entities/media_item.dart';
import '../../../sources/domain/entities/source.dart';

class SearchRepository {
  final Dio _dio;

  SearchRepository(this._dio);

  Future<List<MediaItem>> search(String query, List<Source> enabledSources) async {
    final List<MediaItem> results = [];

    for (var source in enabledSources) {
      if (!source.isEnabled) continue;

      try {
        final response = await _dio.get('${source.baseUrl}${source.searchEndpoint}?q=$query');
        
        if (response.statusCode == 200) {
          final data = response.data;
          // Assuming standard JSON format from the source:
          // { "results": [ { "id": "...", "title": "..." } ] }
          if (data['results'] != null) {
            final List<dynamic> items = data['results'];
            results.addAll(items.map((json) => MediaItem.fromJson(json, source.id)));
          }
        }
      } catch (e) {
        // Log error and continue to the next source
        print('Error searching source ${source.name}: $e');
      }
    }

    return results;
  }
}
