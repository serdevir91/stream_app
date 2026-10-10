class AnimeExtension {
  final String id;
  final String name;
  final String description;
  final String version;
  final String icon;
  final bool isDirectStream;
  final bool isEnabled;
  final int priority;

  const AnimeExtension({
    required this.id,
    required this.name,
    required this.description,
    this.version = '1.0.0',
    this.icon = '⚡',
    this.isDirectStream = false,
    this.isEnabled = true,
    this.priority = 0,
  });

  AnimeExtension copyWith({
    String? id,
    String? name,
    String? description,
    String? version,
    String? icon,
    bool? isDirectStream,
    bool? isEnabled,
    int? priority,
  }) {
    return AnimeExtension(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      version: version ?? this.version,
      icon: icon ?? this.icon,
      isDirectStream: isDirectStream ?? this.isDirectStream,
      isEnabled: isEnabled ?? this.isEnabled,
      priority: priority ?? this.priority,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'version': version,
        'icon': icon,
        'is_direct_stream': isDirectStream,
        'is_enabled': isEnabled,
        'priority': priority,
      };

  factory AnimeExtension.fromJson(Map<String, dynamic> json) {
    return AnimeExtension(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      icon: json['icon'] as String? ?? '⚡',
      isDirectStream: json['is_direct_stream'] as bool? ?? false,
      isEnabled: json['is_enabled'] as bool? ?? true,
      priority: json['priority'] as int? ?? 0,
    );
  }
}
