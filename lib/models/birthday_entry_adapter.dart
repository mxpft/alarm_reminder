import 'package:hive/hive.dart';
import 'birthday_entry.dart';
import 'birthday_type.dart';

/// Hive 的 TypeAdapter（手动实现，字段按固定顺序编号，保证向前兼容）。
class BirthdayEntryAdapter extends TypeAdapter<BirthdayEntry> {
  @override
  final int typeId = 0;

  @override
  BirthdayEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BirthdayEntry(
      id: fields[0] as String,
      name: fields[1] as String,
      remark: fields[2] as String?,
      type: BirthdayType.values[fields[3] as int],
      year: fields[4] as int,
      month: fields[5] as int,
      day: fields[6] as int,
      isLeap: fields[7] as bool,
      // 新增字段：老数据没有时用默认值（9:00 + 提前3天提醒）。
      remindHour: fields[8] as int? ?? 9,
      remindMinute: fields[9] as int? ?? 0,
      notify3DaysBefore: fields[10] as bool? ?? true,
      avatarPath: fields[11] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, BirthdayEntry obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.remark)
      ..writeByte(3)
      ..write(obj.type.index)
      ..writeByte(4)
      ..write(obj.year)
      ..writeByte(5)
      ..write(obj.month)
      ..writeByte(6)
      ..write(obj.day)
      ..writeByte(7)
      ..write(obj.isLeap)
      ..writeByte(8)
      ..write(obj.remindHour)
      ..writeByte(9)
      ..write(obj.remindMinute)
      ..writeByte(10)
      ..write(obj.notify3DaysBefore)
      ..writeByte(11)
      ..write(obj.avatarPath);
  }
}
