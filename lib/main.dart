import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'data/birthday_repository.dart';
import 'models/birthday_entry_adapter.dart';
import 'pages/birthday_list_page.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 先挂一个加载页，避免白屏时毫无反馈。
  runApp(const _BootApp(message: '正在初始化…'));

  try {
    // —— Hive 本地数据库初始化（数据只存在本机）——
    await Hive.initFlutter();
    Hive.registerAdapter(BirthdayEntryAdapter());
    final repo = BirthdayRepository();
    await repo.open();

    // —— 精确闹钟初始化 ——
    await AndroidAlarmManager.initialize();

    // —— 通知服务初始化（时区 + 插件）——
    final notification = NotificationService.instance;
    try {
      await notification.init();
      await notification.rescheduleAll(repo, DateTime.now());
    } catch (e) {
      debugPrint('初始化通知服务失败: $e');
    }

    runApp(BirthdayApp(repo: repo, notification: notification));
  } catch (e, st) {
    // 任何初始化错误都不会再静默白屏，直接在屏幕上显示出来。
    debugPrint('初始化失败: $e\n$st');
    runApp(_BootApp(message: '启动失败：$e\n\n$st'));
  }
}

class BirthdayApp extends StatelessWidget {
  final BirthdayRepository repo;
  final NotificationService notification;

  const BirthdayApp({
    super.key,
    required this.repo,
    required this.notification,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '生日提醒',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
        useMaterial3: true,
      ),
      home: BirthdayListPage(repo: repo, notification: notification),
    );
  }
}

/// 启动占位 / 错误展示页。
class _BootApp extends StatelessWidget {
  final String message;
  const _BootApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: SelectableText(
              message,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
        ),
      ),
    );
  }
}
