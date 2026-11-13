import 'birthday_type.dart';

/// 农历月中文名（农历 1=正月 … 12=腊月）。
const List<String> kLunarMonthNames = [
  '正月',
  '二月',
  '三月',
  '四月',
  '五月',
  '六月',
  '七月',
  '八月',
  '九月',
  '十月',
  '冬月',
  '腊月',
];

String lunarMonthNameOf(int month) => kLunarMonthNames[month - 1];

/// 农历日中文名（初一 … 三十）。
const List<String> kLunarDayNames = [
  '初一',
  '初二',
  '初三',
  '初四',
  '初五',
  '初六',
  '初七',
  '初八',
  '初九',
  '初十',
  '十一',
  '十二',
  '十三',
  '十四',
  '十五',
  '十六',
  '十七',
  '十八',
  '十九',
  '二十',
  '廿一',
  '廿二',
  '廿三',
  '廿四',
  '廿五',
  '廿六',
  '廿七',
  '廿八',
  '廿九',
  '三十',
];

String lunarDayNameOf(int day) => kLunarDayNames[day - 1];

/// 一条生日记录。
///
/// 存储规则（核心）：
/// —— 原始日期【原样保存】，不做「农历一次性转公历写死」：
///   · 公历：存公历年/月/日（year/month/day）
///   · 农历：存农历年/月/日（year/month/day）+ 闰月标记 isLeap
/// —— 每次计算时，由 [BirthdayCalculator] 动态换算「当年对应的公历日期」。
///
/// Hive 序列化通过 [BirthdayEntryAdapter]（手动实现，无需 build_runner）。
class BirthdayEntry {
  /// 唯一 ID（新增时生成，作为 Hive 的 key，天然去重）。
  final String id;

  /// 姓名（必填）。
  String name;

  /// 备注（选填）。
  String? remark;

  /// 生日类型（公历 / 农历）。
  BirthdayType type;

  /// 原始年份。
  int year;

  /// 原始月份（农历月份：1 = 正月 … 12 = 腊月）。
  int month;

  /// 原始日。
  int day;

  /// 闰月标记：仅对农历有意义。true 表示录的是「闰X月」的生日。
  bool isLeap;

  /// 提醒时间：当天几点提醒（0-23）。
  int remindHour;

  /// 提醒时间：当天几分提醒（0-59）。
  int remindMinute;

  /// 是否提前 3 天也提醒一次。
  bool notify3DaysBefore;

  /// 头像本地文件路径（未上传为 null）。
  String? avatarPath;

  /// 系统日历事件ID（写入日历时生成，用来删除/更新）。
  String? calendarEventId;

  BirthdayEntry({
    required this.id,
    required this.name,
    this.remark,
    required this.type,
    required this.year,
    required this.month,
    required this.day,
    this.isLeap = false,
    this.remindHour = 9,
    this.remindMinute = 0,
    this.notify3DaysBefore = true,
    this.avatarPath,
    this.calendarEventId,
  });

  /// 只读展示用的农历月名（农历 1=正月 … 12=腊月）。
  String get lunarMonthName => lunarMonthNameOf(month);
}
