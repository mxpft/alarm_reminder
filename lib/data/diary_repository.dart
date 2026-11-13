import 'package:hive/hive.dart';

import '../models/diary_entry.dart';

class DiaryRepository {
  static const String boxName = 'diaries';

  /// 每月时间轴颜色（按「年-月」存 color 的 int 值）
  static const String colorBoxName = 'diary_month_colors';

  late final Box<DiaryEntry> _box;
  late final Box<int> _colorBox;

  Future<void> open() async {
    _box = await Hive.openBox<DiaryEntry>(boxName);
    _colorBox = await Hive.openBox<int>(colorBoxName);
  }

  Box<DiaryEntry> get box => _box;

  Box<int> get colorBox => _colorBox;

  static String monthColorKey(int year, int month) => '$year-$month';

  /// 该月的自定义颜色（ARGB int），未设置返回 null
  int? monthColorValue(int year, int month) =>
      _colorBox.get(monthColorKey(year, month));

  /// 设置 / 清除该月时间轴颜色（传 null 即恢复默认）
  Future<void> setMonthColor(int year, int month, int? colorValue) async {
    final key = monthColorKey(year, month);
    if (colorValue == null) {
      await _colorBox.delete(key);
    } else {
      await _colorBox.put(key, colorValue);
    }
  }

  /// 全部日记，按时间倒序。
  List<DiaryEntry> getAll() {
    final list = _box.values.toList();
    list.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return list;
  }

  /// 指定年份的日记，按时间倒序。
  List<DiaryEntry> getByYear(int year) {
    return getAll().where((e) => e.dateTime.year == year).toList();
  }

  /// 已存在的年份（倒序），并保证包含当前年份。
  List<int> availableYears() {
    final years = <int>{DateTime.now().year};
    for (final e in _box.values) {
      years.add(e.dateTime.year);
    }
    final list = years.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  Future<void> save(DiaryEntry entry) => _box.put(entry.id, entry);

  Future<void> delete(String id) => _box.delete(id);

  int get count => _box.length;

  static String generateId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final rand =
        (DateTime.now().millisecondsSinceEpoch * 2654435761) & 0xffffffff;
    return '${ts}_$rand';
  }
}
