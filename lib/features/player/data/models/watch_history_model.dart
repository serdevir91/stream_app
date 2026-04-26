import 'package:hive/hive.dart';
import '../../domain/entities/watch_history.dart';

class WatchHistoryModel extends WatchHistory {
  WatchHistoryModel({
    super.historyId,
    required super.mediaId,
    required super.title,
    super.mediaType,
    super.season,
    super.episode,
    super.posterUrl,
    super.backdropUrl,
    required super.lastPosition,
    required super.duration,
    super.isWatched,
    super.updatedAtMs,
  });

  factory WatchHistoryModel.fromEntity(WatchHistory entity) {
    return WatchHistoryModel(
      historyId: entity.historyId,
      mediaId: entity.mediaId,
      title: entity.title,
      mediaType: entity.mediaType,
      season: entity.season,
      episode: entity.episode,
      posterUrl: entity.posterUrl,
      backdropUrl: entity.backdropUrl,
      lastPosition: entity.lastPosition,
      duration: entity.duration,
      isWatched: entity.isWatched,
      updatedAtMs: entity.updatedAtMs,
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

    final mediaId = (fields[0] ?? '').toString();
    final mediaType = (fields[5] ?? 'movie').toString();
    final season = fields[6] as int? ?? 1;
    final episode = fields[7] as int? ?? 1;
    final fallbackHistoryId = mediaType == 'tv'
        ? 'tv_${mediaId}_s${season}_e$episode'
        : 'movie_$mediaId';

    return WatchHistoryModel(
      historyId: (fields[11] ?? fallbackHistoryId).toString(),
      mediaId: mediaId,
      title: (fields[1] ?? '').toString(),
      lastPosition: fields[2] as int? ?? 0,
      duration: fields[3] as int? ?? 0,
      isWatched: fields[4] as bool? ?? false,
      mediaType: mediaType,
      season: season,
      episode: episode,
      updatedAtMs: fields[8] as int? ?? DateTime.now().millisecondsSinceEpoch,
      posterUrl: fields[9] as String?,
      backdropUrl: fields[10] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, WatchHistoryModel obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.mediaId)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.lastPosition)
      ..writeByte(3)
      ..write(obj.duration)
      ..writeByte(4)
      ..write(obj.isWatched)
      ..writeByte(5)
      ..write(obj.mediaType)
      ..writeByte(6)
      ..write(obj.season)
      ..writeByte(7)
      ..write(obj.episode)
      ..writeByte(8)
      ..write(obj.updatedAtMs)
      ..writeByte(9)
      ..write(obj.posterUrl)
      ..writeByte(10)
      ..write(obj.backdropUrl)
      ..writeByte(11)
      ..write(obj.historyId);
  }
}
