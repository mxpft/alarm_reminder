import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/birthday_entry.dart';
import '../services/birthday_calculator.dart';
import '../theme/app_colors.dart';

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

  // 跟踪当前选中的 index，用于动态设置文字颜色。
  int _selectedYearIndex = 0;
  int _selectedMonthIndex = 0;
  int _selectedDayIndex = 0;

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

    _selectedYearIndex = _year - 1900;
    _selectedMonthIndex = _monthIndex;
    _selectedDayIndex = _day - 1;

    _yearCtrl = FixedExtentScrollController(initialItem: _selectedYearIndex);
    _monthCtrl = FixedExtentScrollController(initialItem: _selectedMonthIndex);
    _dayCtrl = FixedExtentScrollController(initialItem: _selectedDayIndex);
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
      height: 240,
      child: Stack(
        children: [
          // 选中项背景块（三列各一个）
          Positioned(
            left: 0,
            right: 0,
            top: 240 / 2 - 24,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 48,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 48,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 48,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 三列滚轮
          Row(
            children: [
              Expanded(
                child: _wheel(
                  _yearCtrl,
                  _years,
                  _onYearChange,
                  _selectedYearIndex,
                ),
              ),
              Expanded(
                child: _wheel(
                  _monthCtrl,
                  _months,
                  _onMonthChange,
                  _selectedMonthIndex,
                ),
              ),
              Expanded(
                child: _wheel(_dayCtrl, days, _onDayChange, _selectedDayIndex),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<int> get _years => List.generate(201, (i) => 1900 + i); // 1900 - 2100

  Widget _wheel<T>(
    FixedExtentScrollController controller,
    List<T> items,
    ValueChanged<int> onChanged,
    int selectedIndex,
  ) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: 48,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: items.length,
        builder: (context, index) {
          final isSelected = index == selectedIndex;
          return Center(
            child: Text(
              items[index] is int
                  ? '${items[index]}'
                  : (items[index] as _LunarMonthOption).label,
              style: TextStyle(
                fontSize: 20,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? AppColors.primary
                    : AppColors.textPlaceholder,
              ),
            ),
          );
        },
      ),
    );
  }

  void _onYearChange(int index) {
    setState(() {
      _selectedYearIndex = index;
      _year = _years[index];
      final oldMonth = _month;
      final oldLeap = _isLeap;
      _months = _monthsForYear(_year);
      _monthIndex = _indexOf(_months, oldMonth, oldLeap);
      if (_monthIndex < 0) _monthIndex = 0;
      _selectedMonthIndex = _monthIndex;
      _day = _clampDay(_month, _isLeap, _day);
      _selectedDayIndex = _day - 1;
    });
    _syncSecondaryControllers();
    _emit();
  }

  void _onMonthChange(int index) {
    setState(() {
      _selectedMonthIndex = index;
      _monthIndex = index;
      _day = _clampDay(_month, _isLeap, _day);
      _selectedDayIndex = _day - 1;
    });
    _syncDayController();
    _emit();
  }

  void _onDayChange(int index) {
    setState(() {
      _selectedDayIndex = index;
      _day = index + 1;
    });
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

  String get label => '${isLeap ? '闰' : ''}${lunarMonthNameOf(month)}';

  @override
  String toString() => label;
}
