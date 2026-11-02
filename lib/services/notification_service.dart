import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../data/birthday_repository.dart';
import '../models/birthday_entry.dart';
import '../models/birthday_entry_adapter.dart';
import 'birthday_calculator.dart';
import 'calendar_service.dart';

/// 通知调度服务（用 AlarmManager 替代 zonedSchedule，避开序列化bug）。
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final CalendarService _calendar = CalendarService();

  /// 日历同步的最后错误信息（供 UI 显示）。
  String? get calendarLastError => _calendar.lastError;

  static const String _channelId = 'birthday_channel';
  static const String _channelName = '生日提醒';
  static const String _channelDesc = '生日提醒通知';

  bool _initialized = false;

  /// 初始化通知插件。
  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings);
    _initialized = true;
  }

  /// 申请通知权限 + 精确闹钟权限。
  Future<bool> requestPermissions() async {
    await init();
    var ok = true;

    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final notif = await android.requestNotificationsPermission();
      ok = ok && (notif ?? true);
    }

    return ok;
  }

  /// 立刻弹一条测试通知。
  Future<void> testShowNow() async {
    await init();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
      ),
      iOS: DarwinNotificationDetails(),
    );

    await _plugin.show(
      9999,
      '生日提醒测试',
      '通知功能正常！这条是立即测试消息。',
      details,
    );
  }

  /// 排10秒后的定时通知（用 AlarmManager）。
  Future<void> testScheduleLater() async {
    await init();

    final ok = await AndroidAlarmManager.oneShot(
      const Duration(seconds: 10),
      9998,
      alarmCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: false,
    );

    if (!ok) {
      throw Exception('闹钟设置失败！请检查「闹钟和提醒」权限是否打开');
    }
  }

  /// 全量重排：先取消旧通知，再按最新数据重新调度。
  Future<void> rescheduleAll(BirthdayRepository repo, DateTime now) async {
    await init();

    // 取消所有旧闹钟
    await AndroidAlarmManager.cancel(9998);

    final today = DateTime(now.year, now.month, now.day);
    var calendarPermissionDenied = false; // 权限被拒绝后，跳过后续日历创建

    for (final entry in repo.getAll()) {
      await _scheduleOne(entry, today);
      // 同步日历：如果还没有日历事件，且权限没有被拒绝，创建一个
      if (entry.calendarEventId == null && !calendarPermissionDenied) {
        final occurrence = BirthdayCalculator.nextOccurrence(entry, today);
        final eventId = await _calendar.createBirthdayEvent(entry, occurrence.date);
        if (eventId != null) {
          entry.calendarEventId = eventId;
          await repo.save(entry);
        } else {
          // 日历创建失败，可能是权限被拒绝，标记一下，后面不再弹
          calendarPermissionDenied = true;
        }
      }
    }
  }

  /// 调度单条生日的通知（当天 + 可选提前3天）。
  Future<void> _scheduleOne(BirthdayEntry entry, DateTime today) async {
    final occurrence = BirthdayCalculator.nextOccurrence(entry, today);
    final date = occurrence.date;

    // 当天提醒
    if (!date.isBefore(today)) {
      final triggerTime = DateTime(
        date.year,
        date.month,
        date.day,
        entry.remindHour,
        entry.remindMinute,
      );
      if (triggerTime.isAfter(DateTime.now())) {
        await AndroidAlarmManager.oneShotAt(
          triggerTime,
          _notifyId(entry, 1),
          alarmCallback,
          exact: true,
          wakeup: true,
          rescheduleOnReboot: true,
        );
      }
    }

    // 提前 3 天提醒
    if (entry.notify3DaysBefore) {
      final before = date.subtract(const Duration(days: 3));
      if (!before.isBefore(today)) {
        final triggerTime = DateTime(
          before.year,
          before.month,
          before.day,
          entry.remindHour,
          entry.remindMinute,
        );
        if (triggerTime.isAfter(DateTime.now())) {
          await AndroidAlarmManager.oneShotAt(
            triggerTime,
            _notifyId(entry, 0),
            alarmCallback,
            exact: true,
            wakeup: true,
            rescheduleOnReboot: true,
          );
        }
      }
    }
  }

  /// 删除单条生日后，取消它已排定的闹钟 + 删除日历事件。
  Future<void> cancelForEntry(BirthdayEntry entry) async {
    await AndroidAlarmManager.cancel(_notifyId(entry, 0));
    await AndroidAlarmManager.cancel(_notifyId(entry, 1));
    // 同步删除日历事件
    await _calendar.deleteBirthdayEvent(entry.calendarEventId);
  }

  /// 修改生日后：刷新闹钟 + 刷新日历事件（删旧+建新）。
  Future<void> refreshAfterEdit(BirthdayEntry entry, DateTime now) async {
    // 先取消旧闹钟
    await AndroidAlarmManager.cancel(_notifyId(entry, 0));
    await AndroidAlarmManager.cancel(_notifyId(entry, 1));

    // 重新调度闹钟
    final today = DateTime(now.year, now.month, now.day);
    await _scheduleOne(entry, today);

    // 刷新日历事件：删旧 + 建新
    final newEventId = await _calendar.refreshBirthdayEvent(entry, today);
    if (newEventId != null) {
      entry.calendarEventId = newEventId;
    }
  }

  /// 生成稳定的闹钟 ID。
  int _notifyId(BirthdayEntry entry, int slot) {
    final base = 5000 + (entry.id.hashCode & 0x3fffffff);
    return base + slot;
  }
}

/// 闹钟回调函数（必须是顶层函数 + @pragma）。
@pragma('vm:entry-point')
Future<void> alarmCallback(int id) async {
  final plugin = FlutterLocalNotificationsPlugin();

  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings();
  const settings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );
  await plugin.initialize(settings);

  // 必须先创建通知通道，否则通知不显示
  final androidPlugin = plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  if (androidPlugin != null) {
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'birthday_channel',
        '生日提醒',
        description: '生日提醒通知',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'birthday_channel',
      '生日提醒',
      channelDescription: '生日提醒通知',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
    ),
    iOS: DarwinNotificationDetails(),
  );

  String title = '生日提醒';
  String body = '今天有人生日！';

  if (id == 9998) {
    // 10秒测试通知
    title = '定时测试通知';
    body = '10秒倒计时到了！如果看到这条说明定时闹钟正常';
  } else {
    // 真实生日通知：从 Hive 找到对应的 entry
    try {
      await Hive.initFlutter();
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(BirthdayEntryAdapter());
      }
      final box = await Hive.openBox<BirthdayEntry>(
        BirthdayRepository.boxName,
      );

      BirthdayEntry? matched;
      var isEarlyReminder = false;

      for (final entry in box.values) {
        final earlyId = _alarmIdForEntry(entry, 0);
        final todayId = _alarmIdForEntry(entry, 1);
        if (id == earlyId) {
          matched = entry;
          isEarlyReminder = true;
          break;
        }
        if (id == todayId) {
          matched = entry;
          break;
        }
      }

      if (matched != null) {
        if (isEarlyReminder) {
          title = '生日提醒';
          body = '3天后是「${matched.name}」的生日，别忘了准备祝福';
        } else {
          title = '生日提醒';
          body = '今天是「${matched.name}」的生日，祝 TA 生日快乐';
        }
      }
    } catch (e) {
      // Hive 读取失败时，用通用文案兜底
      debugPrint('闹钟回调读取数据失败: $e');
    }
  }

  await plugin.show(id, title, body, details);
}

/// 供顶层回调使用的 ID 计算（与类内方法保持一致）。
int _alarmIdForEntry(BirthdayEntry entry, int slot) {
  final base = 5000 + (entry.id.hashCode & 0x3fffffff);
  return base + slot;
}
