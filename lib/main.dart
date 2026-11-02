import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'data/birthday_repository.dart';
import 'data/password_repository.dart';
import 'models/birthday_entry_adapter.dart';
import 'models/password_entry_adapter.dart';
import 'pages/birthday_list_page.dart';
import 'pages/home_page.dart';
import 'services/notification_service.dart';
import 'theme/app_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 先挂一个加载页，避免白屏时毫无反馈。
  runApp(const _BootApp(message: '正在初始化…'));

  try {
    // —— Hive 本地数据库初始化（数据只存在本机）——
    await Hive.initFlutter();
    Hive.registerAdapter(BirthdayEntryAdapter());
    Hive.registerAdapter(PasswordEntryAdapter());
    final repo = BirthdayRepository();
    await repo.open();
    final passwordRepo = PasswordRepository();
    await passwordRepo.open();

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

    runApp(BirthdayApp(repo: repo, notification: notification, passwordRepo: passwordRepo));
  } catch (e, st) {
    // 任何初始化错误都不会再静默白屏，直接在屏幕上显示出来。
    debugPrint('初始化失败: $e\n$st');
    runApp(_BootApp(message: '启动失败：$e\n\n$st'));
  }
}

class BirthdayApp extends StatelessWidget {
  final BirthdayRepository repo;
  final NotificationService notification;
  final PasswordRepository passwordRepo;

  const BirthdayApp({
    super.key,
    required this.repo,
    required this.notification,
    required this.passwordRepo,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LittleButler',
      debugShowCheckedModeBanner: false,
      theme: _buildAppTheme(),
      home: HomePage(repo: repo, notification: notification, passwordRepo: passwordRepo),
    );
  }

  ThemeData _buildAppTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.white,
      // AppBar 主题
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      // 对话框主题
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      // 按钮主题
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      // 输入框主题
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgCard,
        hintStyle: const TextStyle(
          color: AppColors.textPlaceholder,
          fontSize: 16,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.primary,
            width: 1.5,
          ),
        ),
      ),
      // 分割线主题
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      // 开关主题
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return AppColors.trackGray;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      // SnackBar 主题
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
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
