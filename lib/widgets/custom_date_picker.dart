import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 自定义公历日期选择器（滚轮式，年/月/日）。
///
/// 返回选中的 [DateTime]，取消返回 null。
class CustomDatePicker extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  const CustomDatePicker({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  /// 便捷方法：弹出日期选择器。
  static Future<DateTime?> show(
    BuildContext context, {
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) {
    return showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => CustomDatePicker(
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
      ),
    );
  }

  @override
  State<CustomDatePicker> createState() => _CustomDatePickerState();
}

class _CustomDatePickerState extends State<CustomDatePicker> {
  late int _year;
  late int _month;
  late int _day;

  late FixedExtentScrollController _yearCtrl;
  late FixedExtentScrollController _monthCtrl;
  late FixedExtentScrollController _dayCtrl;

  int get _firstYear => widget.firstDate.year;
  int get _lastYear => widget.lastDate.year;

  int get _daysInMonth {
    return DateTime(_year, _month + 1, 0).day;
  }

  @override
  void initState() {
    super.initState();
    _year = widget.initialDate.year;
    _month = widget.initialDate.month;
    _day = widget.initialDate.day;

    _yearCtrl = FixedExtentScrollController(initialItem: _year - _firstYear);
    _monthCtrl = FixedExtentScrollController(initialItem: _month - 1);
    _dayCtrl = FixedExtentScrollController(initialItem: _day - 1);
  }

  @override
  void dispose() {
    _yearCtrl.dispose();
    _monthCtrl.dispose();
    _dayCtrl.dispose();
    super.dispose();
  }

  DateTime get _selectedDate {
    return DateTime(_year, _month, _day);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            const Text(
              '选择日期',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w500,
                color: AppColors.textBody,
              ),
            ),
            const SizedBox(height: 20),
            // 滚轮选择
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  // 年
                  Expanded(
                    child: ListWheelScrollView.useDelegate(
                      controller: _yearCtrl,
                      itemExtent: 48,
                      physics: const FixedExtentScrollPhysics(),
                      overAndUnderCenterOpacity: 0.4,
                      onSelectedItemChanged: (index) {
                        setState(() {
                          _year = _firstYear + index;
                          // 自动调整日
                          final maxDay = _daysInMonth;
                          if (_day > maxDay) {
                            _day = maxDay;
                            _dayCtrl.jumpToItem(_day - 1);
                          }
                        });
                      },
                      childDelegate: ListWheelChildBuilderDelegate(
                        builder: (context, index) {
                          final year = _firstYear + index;
                          return Center(
                            child: Text(
                              '$year年',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textBody,
                              ),
                            ),
                          );
                        },
                        childCount: _lastYear - _firstYear + 1,
                      ),
                    ),
                  ),
                  // 月
                  Expanded(
                    child: ListWheelScrollView.useDelegate(
                      controller: _monthCtrl,
                      itemExtent: 48,
                      physics: const FixedExtentScrollPhysics(),
                      overAndUnderCenterOpacity: 0.4,
                      onSelectedItemChanged: (index) {
                        setState(() {
                          _month = index + 1;
                          // 自动调整日
                          final maxDay = _daysInMonth;
                          if (_day > maxDay) {
                            _day = maxDay;
                            _dayCtrl.jumpToItem(_day - 1);
                          }
                        });
                      },
                      childDelegate: ListWheelChildBuilderDelegate(
                        builder: (context, index) {
                          return Center(
                            child: Text(
                              '${index + 1}月',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textBody,
                              ),
                            ),
                          );
                        },
                        childCount: 12,
                      ),
                    ),
                  ),
                  // 日
                  Expanded(
                    child: ListWheelScrollView.useDelegate(
                      controller: _dayCtrl,
                      itemExtent: 48,
                      physics: const FixedExtentScrollPhysics(),
                      overAndUnderCenterOpacity: 0.4,
                      onSelectedItemChanged: (index) {
                        setState(() {
                          _day = index + 1;
                        });
                      },
                      childDelegate: ListWheelChildBuilderDelegate(
                        builder: (context, index) {
                          return Center(
                            child: Text(
                              '${index + 1}日',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textBody,
                              ),
                            ),
                          );
                        },
                        childCount: _daysInMonth,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 底部按钮
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  child: const Text(
                    '取消',
                    style: TextStyle(
                      fontSize: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_selectedDate),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: const Text(
                    '确定',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
