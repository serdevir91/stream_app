class AddonManifest {
  final String id;
  final String name;
  final String description;
  final String version;
  final List<String> types;
  final String? icon;
  final bool isBuiltin;

  AddonManifest({
    required this.id,
    required this.name,
    this.description = '',
    this.version = '1.0.0',
    this.types = const ['movie', 'series'],
    this.icon,
    this.isBuiltin = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'version': version,
        'types': types,
        'icon': icon,
        'is_builtin': isBuiltin,
      };

  factory AddonManifest.fromJson(Map<String, dynamic> json) {
    return AddonManifest(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      version: json['version'] ?? '1.0.0',
      types: List<String>.from(json['types'] ?? ['movie', 'series']),
      icon: json['icon'],
      isBuiltin: json['is_builtin'] ?? false,
    );
  }
}

class StreamResult {
  final String url;
  final String title;
  final String? quality;
  final String? provider;
  final bool isDirectLink;

  StreamResult({
    required this.url,
    required this.title,
    this.quality,
    this.provider,
    this.isDirectLink = true,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'quality': quality,
        'provider': provider,
        'is_direct_link': isDirectLink,
      };
}

class SearchResult {
  final String id;
  final String title;
  final String type;
  final String? year;
  final String? poster;
  final String? description;

  SearchResult({
    required this.id,
    required this.title,
    required this.type,
    this.year,
    this.poster,
    this.description,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type,
        'year': year,
        'poster': poster,
        'description': description,
      };
}

abstract class BaseAddon {
  AddonManifest get manifest;
  Future<List<SearchResult>> search(String query, String contentType);
  Future<List<StreamResult>> getStreams(
    String contentId,
    String contentType,
    int season,
    int episode,
  );
}
