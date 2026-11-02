import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 自定义时间选择器（滚轮式，24小时制）。
///
/// 返回选中的 [TimeOfDay]，取消返回 null。
class CustomTimePicker extends StatefulWidget {
  final TimeOfDay initialTime;

  const CustomTimePicker({
    super.key,
    required this.initialTime,
  });

  /// 便捷方法：弹出时间选择器。
  static Future<TimeOfDay?> show(
    BuildContext context, {
    required TimeOfDay initialTime,
  }) {
    return showDialog<TimeOfDay>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => CustomTimePicker(initialTime: initialTime),
    );
  }

  @override
  State<CustomTimePicker> createState() => _CustomTimePickerState();
}

class _CustomTimePickerState extends State<CustomTimePicker> {
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;

  @override
  void initState() {
    super.initState();
    _hourController = FixedExtentScrollController(initialItem: widget.initialTime.hour);
    _minuteController = FixedExtentScrollController(initialItem: widget.initialTime.minute);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  TimeOfDay get _selectedTime {
    final hour = _hourController.selectedItem;
    final minute = _minuteController.selectedItem;
    return TimeOfDay(hour: hour, minute: minute);
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
              '选择时间',
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
                  // 小时
                  Expanded(
                    child: ListWheelScrollView.useDelegate(
                      controller: _hourController,
                      itemExtent: 48,
                      physics: const FixedExtentScrollPhysics(),
                      overAndUnderCenterOpacity: 0.4,
                      childDelegate: ListWheelChildBuilderDelegate(
                        builder: (context, index) {
                          return Center(
                            child: Text(
                              index.toString().padLeft(2, '0'),
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textBody,
                              ),
                            ),
                          );
                        },
                        childCount: 24,
                      ),
                    ),
                  ),
                  const Text(
                    ':',
                    style: TextStyle(
                      fontSize: 28,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  // 分钟
                  Expanded(
                    child: ListWheelScrollView.useDelegate(
                      controller: _minuteController,
                      itemExtent: 48,
                      physics: const FixedExtentScrollPhysics(),
                      overAndUnderCenterOpacity: 0.4,
                      childDelegate: ListWheelChildBuilderDelegate(
                        builder: (context, index) {
                          return Center(
                            child: Text(
                              index.toString().padLeft(2, '0'),
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textBody,
                              ),
                            ),
                          );
                        },
                        childCount: 60,
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
                  onPressed: () => Navigator.of(context).pop(_selectedTime),
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
