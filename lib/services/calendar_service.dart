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
  final DeviceCalendar _plugin = DeviceCalendar();
  String? lastError;

  /// 确保日历权限已授予。返回 true 表示已授权。
  Future<bool> ensurePermission() async {
    lastError = null;

    try {
      var status = await _plugin.hasPermissions();
      debugPrint('日历权限检查: $status');

      if (status == CalendarPermissionStatus.granted ||
          status == CalendarPermissionStatus.writeOnly) {
        return true;
      }

      status = await _plugin.requestPermissions();
      debugPrint('日历权限请求: $status');

      if (status == CalendarPermissionStatus.granted ||
          status == CalendarPermissionStatus.writeOnly) {
        return true;
      }

      lastError = '用户拒绝了日历权限';
      return false;
    } catch (e) {
      lastError = '请求权限失败: $e';
      debugPrint('日历权限异常: $e');
      return false;
    }
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
      debugPrint('开始创建日历事件: title=🎂 ${entry.name} 生日, start=$startDateTime');
      // 不传 calendarId，自动写到默认日历（支持静默写入本地日历）
      final eventId = await _plugin.createEvent(
        title: '🎂 ${entry.name} 生日',
        startDate: startDateTime,
        endDate: endDateTime,
        description:
            '来自生日提醒App${entry.remark != null ? '\n备注：${entry.remark}' : ''}',
        reminders: [Duration.zero], // 到点提醒
      );
      debugPrint('创建日历事件成功: eventId=$eventId');
      return eventId;
    } on DeviceCalendarException catch (e) {
      lastError = e.message;
      debugPrint('创建日历事件失败: $e');
      return null;
    } catch (e) {
      lastError = e.toString();
      debugPrint('创建日历事件异常: $e');
      return null;
    }
  }

  /// 删除一条生日的日历事件。
  Future<void> deleteBirthdayEvent(String? eventId) async {
    if (eventId == null) return;

    try {
      await _plugin.deleteEvent(instanceId: eventId);
      debugPrint('删除日历事件成功: $eventId');
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
