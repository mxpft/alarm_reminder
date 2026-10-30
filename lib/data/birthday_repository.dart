import 'package:hive/hive.dart';
import '../models/birthday_entry.dart';
import '../models/birthday_type.dart';

/// 生日记录的本地持久化仓库（Hive）。
/// 数据只存在本机，卸载 App 才清空。
class BirthdayRepository {
  static const String boxName = 'birthdays';

  late final Box<BirthdayEntry> _box;

  Future<void> open() async {
    _box = await Hive.openBox<BirthdayEntry>(boxName);
  }

  Box<BirthdayEntry> get box => _box;

  /// 全部记录。
  List<BirthdayEntry> getAll() => _box.values.toList();

  /// 新增 / 更新：用 [BirthdayEntry.id] 作为 key，
  /// 同一 id 再次 put 即为覆盖更新。
  Future<void> save(BirthdayEntry entry) => _box.put(entry.id, entry);

  Future<void> delete(String id) => _box.delete(id);

  Future<void> clear() => _box.clear();

  int get count => _box.length;

  /// 便捷：从弹窗结果生成一条新记录（带 UUID）。
  static BirthdayEntry create(
    String name,
    String? remark,
    BirthdayType type,
    int year,
    int month,
    int day, {
    bool isLeap = false,
  }) {
    return BirthdayEntry(
      id: generateId(),
      name: name,
      remark: remark,
      type: type,
      year: year,
      month: month,
      day: day,
      isLeap: isLeap,
    );
  }

  /// 生成一条本地唯一 id（时间戳 + 随机数，无外部依赖）。
  static String generateId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final rand = (DateTime.now().millisecondsSinceEpoch * 2654435761) & 0xffffffff;
    return '${ts}_$rand';
  }
}
