import 'package:hive/hive.dart';
import '../../domain/entities/watch_history.dart';

class WatchHistoryModel extends WatchHistory {
  WatchHistoryModel({
    required super.mediaId,
    required super.title,
    required super.lastPosition,
    required super.duration,
    super.isWatched,
  });

  factory WatchHistoryModel.fromEntity(WatchHistory entity) {
    return WatchHistoryModel(
      mediaId: entity.mediaId,
      title: entity.title,
      lastPosition: entity.lastPosition,
      duration: entity.duration,
      isWatched: entity.isWatched,
    );
  }
}

class WatchHistoryModelAdapter extends TypeAdapter<WatchHistoryModel> {
  @override
  final int typeId = 1;

  @override
  WatchHistoryModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return WatchHistoryModel(
      mediaId: fields[0] as String,
      title: fields[1] as String,
      lastPosition: fields[2] as int,
      duration: fields[3] as int,
      isWatched: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, WatchHistoryModel obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.mediaId)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.lastPosition)
      ..writeByte(3)
      ..write(obj.duration)
      ..writeByte(4)
      ..write(obj.isWatched);
  }
}
