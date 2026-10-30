import 'package:flutter/cupertino.dart';

import '../models/birthday_entry.dart';
import '../services/birthday_calculator.dart';

/// 一次农历选择的封装结果。
class LunarSelection {
  final int year;
  final int month; // 农历月：1 = 正月 … 12 = 腊月
  final int day;
  final bool isLeap;

  LunarSelection(this.year, this.month, this.day, {this.isLeap = false});

  String get monthName => '${isLeap ? '闰' : ''}${lunarMonthNameOf(month)}';

  String get dayName => lunarDayNameOf(day);
}

/// 农历日期滚轮选择器（年 / 月 / 日）。
///
/// 基于 lunar_flutter 动态计算每一年的闰月与每月实际天数，
/// 保证用户只能选到真实存在的农历日期。
/// 滚轮控制器保持为稳定实例，避免重建时跳动。
class LunarDatePicker extends StatefulWidget {
  final int initialYear;
  final int initialMonth;
  final int initialDay;
  final bool initialIsLeap;
  final ValueChanged<LunarSelection> onChanged;

  const LunarDatePicker({
    super.key,
    required this.initialYear,
    required this.initialMonth,
    required this.initialDay,
    this.initialIsLeap = false,
    required this.onChanged,
  });

  @override
  State<LunarDatePicker> createState() => _LunarDatePickerState();
}

class _LunarDatePickerState extends State<LunarDatePicker> {
  late int _year;
  late int _monthIndex; // 指向 _months 列表中的位置
  late int _day;

  late List<_LunarMonthOption> _months;

  // 三个滚轮的稳定控制器（避免 build 重建导致跳动）。
  late final FixedExtentScrollController _yearCtrl;
  late final FixedExtentScrollController _monthCtrl;
  late final FixedExtentScrollController _dayCtrl;

  int get _month => _months[_monthIndex].month;
  bool get _isLeap => _months[_monthIndex].isLeap;

  @override
  void initState() {
    super.initState();
    _year = widget.initialYear;
    _months = _monthsForYear(_year);
    _monthIndex = _indexOf(_months, widget.initialMonth, widget.initialIsLeap);
    if (_monthIndex < 0) _monthIndex = 0;
    _day = _clampDay(_month, _isLeap, widget.initialDay);

    _yearCtrl = FixedExtentScrollController(initialItem: _year - 1900);
    _monthCtrl = FixedExtentScrollController(initialItem: _monthIndex);
    _dayCtrl = FixedExtentScrollController(initialItem: _day - 1);
  }

  @override
  void dispose() {
    _yearCtrl.dispose();
    _monthCtrl.dispose();
    _dayCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final days = List.generate(
      BirthdayCalculator.lunarMonthDays(_year, _month, _isLeap),
      (i) => i + 1,
    );

    return SizedBox(
      height: 220,
      child: Row(
        children: [
          Expanded(child: _wheel(_yearCtrl, _years, _onYearChange)),
          Expanded(child: _wheel(_monthCtrl, _months, _onMonthChange)),
          Expanded(child: _wheel(_dayCtrl, days, _onDayChange)),
        ],
      ),
    );
  }

  List<int> get _years => List.generate(201, (i) => 1900 + i); // 1900 - 2100

  Widget _wheel<T>(
    FixedExtentScrollController controller,
    List<T> items,
    ValueChanged<int> onChanged,
  ) {
    return CupertinoPicker(
      scrollController: controller,
      itemExtent: 40,
      onSelectedItemChanged: onChanged,
      children: [
        for (final item in items)
          Center(
            child: Text(
              item is int ? '$item' : (item as _LunarMonthOption).label,
              style: const TextStyle(fontSize: 18),
            ),
          ),
      ],
    );
  }

  void _onYearChange(int index) {
    setState(() {
      _year = _years[index];
      final oldMonth = _month;
      final oldLeap = _isLeap;
      _months = _monthsForYear(_year);
      _monthIndex = _indexOf(_months, oldMonth, oldLeap);
      if (_monthIndex < 0) _monthIndex = 0;
      _day = _clampDay(_month, _isLeap, _day);
    });
    _syncSecondaryControllers();
    _emit();
  }

  void _onMonthChange(int index) {
    setState(() {
      _monthIndex = index;
      _day = _clampDay(_month, _isLeap, _day);
    });
    _syncDayController();
    _emit();
  }

  void _onDayChange(int index) {
    setState(() => _day = index + 1);
    _emit();
  }

  /// 年份变化后，月/日滚轮同步到新的目标位置（等重建完成后再跳转）。
  void _syncSecondaryControllers() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_monthCtrl.hasClients) _monthCtrl.jumpToItem(_monthIndex);
      if (_dayCtrl.hasClients) _dayCtrl.jumpToItem(_day - 1);
    });
  }

  void _syncDayController() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_dayCtrl.hasClients) _dayCtrl.jumpToItem(_day - 1);
    });
  }

  void _emit() {
    widget.onChanged(LunarSelection(_year, _month, _day, isLeap: _isLeap));
  }

  int _clampDay(int month, bool leap, int day) {
    final last = BirthdayCalculator.lunarMonthDays(_year, month, leap);
    return day > last ? last : day;
  }

  int _indexOf(List<_LunarMonthOption> list, int month, bool leap) {
    for (var i = 0; i < list.length; i++) {
      if (list[i].month == month && list[i].isLeap == leap) return i;
    }
    return -1;
  }

  /// 构建某农历年份的月份列表（含闰月）。
  List<_LunarMonthOption> _monthsForYear(int year) {
    int? leapMonth;
    for (var m = 1; m <= 12; m++) {
      if (BirthdayCalculator.lunarMonthExists(year, m, true)) {
        leapMonth = m;
        break;
      }
    }
    final list = <_LunarMonthOption>[];
    for (var m = 1; m <= 12; m++) {
      list.add(_LunarMonthOption(year, m, false));
      if (leapMonth == m) list.add(_LunarMonthOption(year, m, true));
    }
    return list;
  }
}

class _LunarMonthOption {
  final int year;
  final int month;
  final bool isLeap;
  _LunarMonthOption(this.year, this.month, this.isLeap);

  String get label =>
      '${isLeap ? '闰' : ''}${lunarMonthNameOf(month)}';

  @override
  String toString() => label;
}
