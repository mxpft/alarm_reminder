import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/foundation.dart';

import '../models/birthday_entry.dart';
import 'birthday_calculator.dart';

/// 日历同步服务：把生日写入系统日历，杀后台也能提醒。
///
/// 规则：
/// - 新增生日 → 创建单次日历事件
/// - 删除生日 → 删除对应日历事件
/// - 修改生日 → 删除旧日历事件 + 新建日历事件
class CalendarService {
  final DeviceCalendar _plugin = DeviceCalendar.instance;
  String? lastError;

  /// 确保日历权限已授予。返回 true 表示已授权。
  Future<bool> ensurePermission() async {
    lastError = null;

    var status = await _plugin.hasPermissions();
    if (status == CalendarPermissionStatus.granted) {
      return true;
    }

    // 请求完整权限（不传 calendarId 用默认日历时，Android 需要 full access）
    try {
      status = await _plugin.requestPermissions(
        level: CalendarAccessLevel.full,
      );
    } catch (e) {
      lastError = '请求权限失败: $e';
      return false;
    }

    if (status == CalendarPermissionStatus.granted) {
      return true;
    }

    lastError = '用户拒绝了日历权限';
    return false;
  }

  /// 检查日历权限。
  Future<bool> hasPermission() async {
    final status = await _plugin.hasPermissions();
    return status == CalendarPermissionStatus.granted ||
        status == CalendarPermissionStatus.writeOnly;
  }

  /// 为一条生日创建日历事件。
  /// 返回事件ID，失败返回 null。
  Future<String?> createBirthdayEvent(
    BirthdayEntry entry,
    DateTime triggerDate,
  ) async {
    lastError = null;

    // 先确保权限
    final hasPerm = await ensurePermission();
    if (!hasPerm) {
      return null;
    }

    // 提醒时间：当天 entry.remindHour:entry.remindMinute
    final startDateTime = DateTime(
      triggerDate.year,
      triggerDate.month,
      triggerDate.day,
      entry.remindHour,
      entry.remindMinute,
    );
    final endDateTime = startDateTime.add(const Duration(hours: 1));

    try {
      final eventId = await _plugin.createEvent(
        title: '🎂 ${entry.name} 生日',
        description:
            '来自生日提醒App${entry.remark != null ? '\n备注：${entry.remark}' : ''}',
        startDate: startDateTime,
        endDate: endDateTime,
        isAllDay: false,
        reminders: [Duration.zero], // 到点提醒
      );
      return eventId;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  /// 删除一条生日的日历事件。
  Future<void> deleteBirthdayEvent(String? eventId) async {
    if (eventId == null) return;

    try {
      await _plugin.deleteEvent(instanceId: eventId);
    } catch (e) {
      // 事件可能已经被用户手动删了，忽略错误
      debugPrint('删除日历事件失败（可能已被用户删除）：$e');
    }
  }

  /// 刷新一条生日的日历事件：删旧 + 建新。
  Future<String?> refreshBirthdayEvent(
    BirthdayEntry entry,
    DateTime today,
  ) async {
    // 先删旧的
    if (entry.calendarEventId != null) {
      await deleteBirthdayEvent(entry.calendarEventId);
    }

    // 算下一次生日日期
    final occurrence = BirthdayCalculator.nextOccurrence(entry, today);
    final nextDate = occurrence.date;

    // 创建新的
    final newEventId = await createBirthdayEvent(entry, nextDate);
    return newEventId;
  }
}
