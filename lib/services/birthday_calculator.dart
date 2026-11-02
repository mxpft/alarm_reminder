// import 'package:lunar_flutter/lunar.dart';
import 'package:lunar/lunar.dart';
import '../models/birthday_entry.dart';
import '../models/birthday_type.dart';

/// 一次换算的结果：某条生日「下一次」对应的公历日期。
class BirthdayOccurrence {
  /// 本次生日对应的公历日期（提醒基准日）。
  final DateTime date;

  /// 是否落在当前自然年（false 表示已过，指向下一年或更远的闰月年）。
  final bool isThisYear;

  BirthdayOccurrence(this.date, {required this.isThisYear});
}

/// 生日计算核心服务。
///
/// 业务规则（对应需求文档「生日计算规则」）：
/// 1. 拿到当年生日对应的公历日期，作为基准提醒日；
/// 2. 若当年该农历日期不存在（例：腊月三十，部分年份只有腊月廿九）→ 自动落到该月最后一天；
/// 3. 闰月生日：仅在有对应闰月的年份触发；无闰月的年份当年不触发；
/// 4. 若当年生日已过 → 自动计算下一年的公历日期。
///
/// 重要：**不做一次性转公历写死**，每次调用都基于【原始农历年月日 + 闰月标记】动态换算。
class BirthdayCalculator {
  /// 求某条生日「距离今天最近」的一次公历日期（总是 >= 今天）。
  static BirthdayOccurrence nextOccurrence(BirthdayEntry entry, DateTime today) {
    final todayOnly = DateTime(today.year, today.month, today.day);

    if (entry.type == BirthdayType.gregorian) {
      // 公历分支必然非空（_occurrenceForYear 对公历始终返回 DateTime）。
      final thisYear = _occurrenceForYear(entry, todayOnly.year)!;
      if (!thisYear.isBefore(todayOnly)) {
        return BirthdayOccurrence(thisYear, isThisYear: true);
      }
      return BirthdayOccurrence(
        _occurrenceForYear(entry, todayOnly.year + 1)!,
        isThisYear: false,
      );
    }

    // 农历：从今年向后搜索，找到第一个「存在且未过」的触发年份。
    // 对闰月生日：无对应闰月的年份 _occurrenceForYear 返回 null，继续向后找。
    for (var y = todayOnly.year; y <= todayOnly.year + 30; y++) {
      final target = _occurrenceForYear(entry, y);
      if (target == null) continue; // 该年不触发（如闰月生日该年无闰月）
      if (!target.isBefore(todayOnly)) {
        return BirthdayOccurrence(target, isThisYear: y == todayOnly.year);
      }
    }

    // 兜底：30 年内都找不到（闰月生日的极端情况，几乎不会发生）。
    return BirthdayOccurrence(
      DateTime(todayOnly.year + 1, 12, 31),
      isThisYear: false,
    );
  }

  /// 计算某条生日在指定年份对应的公历日期。
  /// 农历日期在该年不存在 → 返回该农历月最后一天；
  /// 闰月生日该年无对应闰月 → 返回 null（该年不触发）。
  static DateTime? _occurrenceForYear(BirthdayEntry entry, int year) {
    if (entry.type == BirthdayType.gregorian) {
      final m = entry.month;
      final d = _clampDayToMonth(year, m, entry.day);
      return DateTime(year, m, d);
    }
    return _lunarToSolar(entry, year);
  }

  /// 农历 → 公历（动态换算）。
  ///
  /// lunar_flutter（6tail lunar 系列）的闰月约定：月份用【负数】表示，
  /// 如 -4 表示闰四月；`getMonth()` 对闰月返回负数，`isLeap()` 返回 true。
  /// 这里把数据模型里的 (month + isLeap) 统一换算成该约定。
  static DateTime? _lunarToSolar(BirthdayEntry entry, int year) {
    final lm = entry.month;
    final ld = entry.day;
    final leap = entry.isLeap;

    // —— 闰月生日：仅在有对应闰月的年份触发 ——
    // lunar 1.7.8 用 LunarYear.getLeapMonth() 判断该年是否有闰月。
    if (leap) {
      if (LunarYear.fromYear(year).getLeapMonth() != lm) {
        return null; // 该年没有「闰X月」，当年不触发
      }
    }

    // 构造目标农历日期（闰月传负月）。
    var lunar = Lunar.fromYmd(year, leap ? -lm : lm, ld);

    // —— 不存在日期的处理：自动落到该月最后一天 ——
    // 若请求的农历月/日在该年不存在（如腊月三十当年只有廿九），
    // lunar 会向内修正到实际存在的日期，这里据此判断并改取当月最后一天。
    // lunar 1.7.8 中 Lunar 无 isLeap()，用 getMonth() < 0 判断是否为闰月。
    final isLeapMatch = (lunar.getMonth() < 0) == leap;
    if (lunar.getMonth().abs() != lm || lunar.getDay() != ld || !isLeapMatch) {
      final lastDay = _lunarMonthLastDay(year, lm, leap);
      lunar = Lunar.fromYmd(year, leap ? -lm : lm, lastDay);
    }

    final solar = lunar.getSolar();
    return DateTime(solar.getYear(), solar.getMonth(), solar.getDay());
  }

  /// 农历某年某月（含闰月标记）的实际天数（30 或 29）。
  /// lunar 1.7.8 用 LunarMonth.fromYm 直接取该月天数，负数表示闰月。
  static int _lunarMonthLastDay(int year, int month, bool leap) {
    final m = LunarMonth.fromYm(year, leap ? -month : month);
    return m?.getDayCount() ?? 29; // 兜底，农历月不会少于 29 天。
  }

  /// 计算「距离下一次生日」的剩余天数（今天生日为 0）。
  static int daysUntil(DateTime occurrenceDate, DateTime today) {
    final a = DateTime(occurrenceDate.year, occurrenceDate.month, occurrenceDate.day);
    final b = DateTime(today.year, today.month, today.day);
    return a.difference(b).inDays;
  }

  /// 公历某月最后一天（2 月会正确处理平/闰年）。
  static int _lastDayOfMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  /// 把 day 限制在当月有效范围内（例如非闰年 2 月没有 29 日 → 落到 28 日）。
  static int _clampDayToMonth(int year, int month, int day) {
    final last = _lastDayOfMonth(year, month);
    return day > last ? last : day;
  }

  /// 农历某年是否存在某月（含闰月）——用于农历选择器的月份列表。
  static bool lunarMonthExists(int year, int month, bool leap) =>
      LunarMonth.fromYm(year, leap ? -month : month) != null;

  /// 农历某年某月的天数——用于农历选择器的日期列表。
  static int lunarMonthDays(int year, int month, bool leap) =>
      _lunarMonthLastDay(year, month, leap);

  /// 取这条生日的生肖（按出生农历年，春节附近也基本准确）。
  static String shengXiaoOf(BirthdayEntry entry) {
    if (entry.type == BirthdayType.lunar) {
      return Lunar.fromYmd(entry.year, entry.month, entry.day)
          .getYearShengXiao();
    }
    return Solar.fromYmd(entry.year, entry.month, entry.day)
        .getLunar()
        .getYearShengXiao();
  }

  /// 计算周岁：当前年份 - 出生年份。
  static int ageOf(BirthdayEntry entry, DateTime today) {
    final age = today.year - entry.year;
    return age < 0 ? 0 : age;
  }
}
