import 'package:hive/hive.dart';

import 'diary_entry.dart';

class DiaryEntryAdapter extends TypeAdapter<DiaryEntry> {
  @override
  final int typeId = 2;

  @override
  DiaryEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DiaryEntry(
      id: fields[0] as String,
      content: fields[1] as String,
      dateTime: DateTime.fromMillisecondsSinceEpoch(fields[2] as int),
      moodEmoji: fields[3] as String?,
      moodDesc: fields[4] as String?,
      weatherEmoji: fields[5] as String?,
      weatherDesc: fields[6] as String?,
      temp: fields[7] as String?,
      location: fields[8] as String?,
      imagePath: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, DiaryEntry obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.content)
      ..writeByte(2)
      ..write(obj.dateTime.millisecondsSinceEpoch)
      ..writeByte(3)
      ..write(obj.moodEmoji)
      ..writeByte(4)
      ..write(obj.moodDesc)
      ..writeByte(5)
      ..write(obj.weatherEmoji)
      ..writeByte(6)
      ..write(obj.weatherDesc)
      ..writeByte(7)
      ..write(obj.temp)
      ..writeByte(8)
      ..write(obj.location)
      ..writeByte(9)
      ..write(obj.imagePath);
  }
}
