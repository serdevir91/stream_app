class Source {
  final String id;
  final String name;
  final String baseUrl;
  final String searchEndpoint;
  final bool isEnabled;

  Source({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.searchEndpoint,
    this.isEnabled = true,
  });

  Source copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? searchEndpoint,
    bool? isEnabled,
  }) {
    return Source(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      searchEndpoint: searchEndpoint ?? this.searchEndpoint,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}
