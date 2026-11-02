import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../pages/birthday_list_page.dart';
import '../pages/password_list_page.dart';
import '../theme/app_colors.dart';
import '../data/birthday_repository.dart';
import '../data/password_repository.dart';
import '../services/notification_service.dart';
import '../services/birthday_calculator.dart';
import '../models/birthday_entry.dart';

/// 应用主页（功能入口卡片）。
class HomePage extends StatefulWidget {
  final BirthdayRepository repo;
  final NotificationService notification;
  final PasswordRepository passwordRepo;

  const HomePage({
    super.key,
    required this.repo,
    required this.notification,
    required this.passwordRepo,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _hasBirthdayToday = false;

  @override
  void initState() {
    super.initState();
    _checkTodayBirthday();
  }

  /// 检查今天是否有人过生日
  void _checkTodayBirthday() {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final entries = widget.repo.box.values.toList();

    for (final entry in entries) {
      final occurrence = BirthdayCalculator.nextOccurrence(entry, today);
      final occDate = DateTime(
        occurrence.date.year,
        occurrence.date.month,
        occurrence.date.day,
      );
      if (occDate == todayOnly) {
        _hasBirthdayToday = true;
        return;
      }
    }
    _hasBirthdayToday = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPage,
      body: SafeArea(
        child: StreamBuilder<BoxEvent>(
          stream: widget.repo.box.watch(),
          builder: (context, snapshot) {
            // 数据变化时重新计算
            if (snapshot.hasData) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _checkTodayBirthday();
                  });
                }
              });
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 顶部问候区
                  _buildGreetingHeader(context),
                  const SizedBox(height: 24),
                  // 三个卡片垂直居中
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.55,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 卡片1：生日提醒
                        _buildBirthdayCard(context),
                        const SizedBox(height: 16),
                        // 卡片2：密码管理
                        _buildPasswordCard(context),
                        const SizedBox(height: 16),
                        // 卡片3：一句话日记
                        _buildDiaryCard(context),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildGreetingHeader(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '你好\nLittleButler',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '不错过重要的日子，不遗失值得珍藏的记忆',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // 头像
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primaryLight.withValues(alpha: 0.3),
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/little-butter-2.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBirthdayCard(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BirthdayListPage(repo: widget.repo, notification: widget.notification),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 图标
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.pinkLight,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.cake_rounded,
                    color: AppColors.pink,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '生日提醒',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          // 今天tag：只有今天有人过生日才显示
                          if (_hasBirthdayToday) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.pinkLight,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                '今天',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.pink,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '记录亲友生辰、公农历与生肖提醒',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textPlaceholder,
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordCard(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PasswordListPage(repo: widget.passwordRepo),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // 图标
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.lock_rounded,
                color: AppColors.primary,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '密码管理',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ValueListenableBuilder(
                    valueListenable: widget.passwordRepo.box.listenable(),
                    builder: (context, box, _) {
                      return Text(
                        '已安全托管 ${widget.passwordRepo.count} 个账号密码',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textPlaceholder,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiaryCard(BuildContext context) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('功能暂未开通')),
        );
      },
      child: Opacity(
        opacity: 0.5,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        child: Row(
          children: [
            // 图标
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFE3DFFF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.edit_note_rounded,
                color: Color(0xFF4E45D5),
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '一句话日记',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '来说说今天发生了什么',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textPlaceholder,
              size: 20,
            ),
          ],
        ),
        ),
      ),
    );
  }
}
