import 'package:hive/hive.dart';
import '../../domain/entities/source.dart';

class SourceModel extends Source {
  SourceModel({
    required super.id,
    required super.name,
    required super.baseUrl,
    required super.searchEndpoint,
    super.isEnabled,
  });

  factory SourceModel.fromEntity(Source entity) {
    return SourceModel(
      id: entity.id,
      name: entity.name,
      baseUrl: entity.baseUrl,
      searchEndpoint: entity.searchEndpoint,
      isEnabled: entity.isEnabled,
    );
  }
}

class SourceModelAdapter extends TypeAdapter<SourceModel> {
  @override
  final int typeId = 0; // Unique ID for this type

  @override
  SourceModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SourceModel(
      id: fields[0] as String,
      name: fields[1] as String,
      baseUrl: fields[2] as String,
      searchEndpoint: fields[3] as String,
      isEnabled: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, SourceModel obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.baseUrl)
      ..writeByte(3)
      ..write(obj.searchEndpoint)
      ..writeByte(4)
      ..write(obj.isEnabled);
  }
}
