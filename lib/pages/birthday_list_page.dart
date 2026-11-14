import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../data/birthday_repository.dart';
import '../models/birthday_entry.dart';
import '../models/birthday_type.dart';
import '../services/birthday_calculator.dart';
import '../services/notification_service.dart';
import '../theme/app_colors.dart';
import '../utils/snack_util.dart';
import '../widgets/birthday_edit_dialog.dart';

/// 生日列表页。
class BirthdayListPage extends StatefulWidget {
  final BirthdayRepository repo;
  final NotificationService notification;

  const BirthdayListPage({
    super.key,
    required this.repo,
    required this.notification,
  });

  @override
  State<BirthdayListPage> createState() => _BirthdayListPageState();
}

class _BirthdayListPageState extends State<BirthdayListPage> {
  bool _permissionHintShown = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// 串起「读已显示标记 → 申请权限 / 重排通知」，
  /// 必须先读到标记，否则每次冷启动都会重复弹权限引导
  Future<void> _init() async {
    await _loadPermissionHintShown();
    await _bootstrap();
  }

  /// 从 Hive 读取是否已经显示过权限引导弹窗
  Future<void> _loadPermissionHintShown() async {
    final box = await Hive.openBox('settings');
    _permissionHintShown = box.get(
      'permission_hint_shown',
      defaultValue: false,
    );
  }

  /// 启动时：申请通知权限 + 重新调度全部通知。
  Future<void> _bootstrap() async {
    try {
      await widget.notification.requestPermissions();
      await widget.notification.rescheduleAll(widget.repo, DateTime.now());
      _maybeShowAndroidHint();
    } catch (e) {
      debugPrint('启动初始化通知失败: $e');
    }
  }

  /// 安卓端：引导用户授予精确闹钟、允许后台活动。
  void _maybeShowAndroidHint() {
    if (Platform.isAndroid && !_permissionHintShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          barrierColor: Colors.black.withValues(alpha: 0.5),
          builder: (ctx) => const _PermissionGuideDialog(),
        );
        // 用户点击"知道了"后，永久记录不再弹出
        _permissionHintShown = true;
        final box = await Hive.openBox('settings');
        await box.put('permission_hint_shown', true);
      });
    }
  }

  Future<void> _testNotification() async {
    try {
      await widget.notification.requestPermissions();
      await widget.notification.testShowNow();
      if (mounted) {
        showSuccessSnack(
          context,
          '已发送测试通知，下拉通知栏查看',
          palette: SnackPalette.birthday,
        );
      }
    } catch (e) {
      if (mounted) {
        showErrorSnack(context, '测试通知失败：$e', palette: SnackPalette.birthday);
      }
    }
  }

  Future<void> _testScheduledNotification() async {
    try {
      await widget.notification.testScheduleLater();
      if (mounted) {
        showChildSnack(
          context,
          _CountdownTimer(),
          palette: SnackPalette.birthday,
          duration: const Duration(seconds: 11),
        );
      }
    } catch (e) {
      if (mounted) {
        showErrorSnack(context, '定时通知失败：$e', palette: SnackPalette.birthday);
      }
    }
  }

  Future<void> _openEditor([BirthdayEntry? existing]) async {
    final entry = await showDialog<BirthdayEntry>(
      context: context,
      builder: (_) => BirthdayEditDialog(existing: existing),
    );
    if (entry == null) return;

    if (existing != null) {
      await widget.notification.cancelForEntry(existing);
      entry.calendarEventId = null;
    }

    await widget.repo.save(entry);
    await widget.notification.rescheduleAll(widget.repo, DateTime.now());

    final updated = widget.repo.box.get(entry.id);
    final calendarOk = updated?.calendarEventId != null;

    if (mounted) {
      final baseText = existing == null ? '新增成功' : '修改成功';
      final String fullText;
      if (calendarOk) {
        fullText = baseText;
      } else {
        fullText = '$baseText（本地提醒已设置）';
      }
      showSuccessSnack(
        context,
        fullText,
        palette: SnackPalette.birthday,
        duration: const Duration(seconds: 3),
      );
    }
  }

  Future<void> _confirmDelete(BirthdayEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '确定删除「${entry.name}」的生日记录吗？此操作不可恢复。',
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.6,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text(
                      '删除',
                      style: TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;

    await widget.notification.cancelForEntry(entry);
    await widget.repo.delete(entry.id);
    await widget.notification.rescheduleAll(widget.repo, DateTime.now());

    if (mounted) {
      showSuccessSnack(context, '删除成功', palette: SnackPalette.birthday);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPage,
      body: SafeArea(
        child: Column(
          children: [
            // 固定头部：返回按钮 + 测试按钮（不随列表滚动）
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _buildGreetingHeader(),
            ),
            // 可滚动的列表区域
            Expanded(
              child: StreamBuilder<BoxEvent>(
                stream: widget.repo.box.watch(),
                builder: (context, snapshot) {
                  final rows = _buildRows(
                    widget.repo.box.values.toList(),
                    DateTime.now(),
                  );
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                    physics: const ClampingScrollPhysics(),
                    children: [
                      // 生日列表或空状态
                      if (rows.isEmpty)
                        const _EmptyView()
                      else
                        for (var i = 0; i < rows.length; i++) ...[
                          _BirthdayListTile(
                            row: rows[i],
                            onTap: () => _openEditor(rows[i].entry),
                            onDelete: () => _confirmDelete(rows[i].entry),
                          ),
                          if (i < rows.length - 1) const SizedBox(height: 16),
                        ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        backgroundColor: AppColors.primary,
        elevation: 4,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }

  /// 顶部问候区
  Widget _buildGreetingHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 返回按钮
        IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        // 标题文案已隐藏，用 Spacer 把测试按钮推到右侧
        const Spacer(),
        const SizedBox(width: 12),
        // 测试按钮
        IconButton(
          icon: const Icon(
            Icons.notifications_none_rounded,
            color: AppColors.textSecondary,
          ),
          tooltip: '测试即时通知',
          onPressed: _testNotification,
        ),
        IconButton(
          icon: const Icon(
            Icons.timer_outlined,
            color: AppColors.textSecondary,
          ),
          tooltip: '测试定时通知',
          onPressed: _testScheduledNotification,
        ),
      ],
    );
  }

  List<_BirthdayRow> _buildRows(List<BirthdayEntry> entries, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final rows = <_BirthdayRow>[];
    for (final e in entries) {
      final occ = BirthdayCalculator.nextOccurrence(e, today);
      final days = BirthdayCalculator.daysUntil(occ.date, today);
      rows.add(_BirthdayRow(entry: e, occurrence: occ, days: days));
    }
    rows.sort((a, b) => a.days.compareTo(b.days));
    return rows;
  }
}

class _BirthdayRow {
  final BirthdayEntry entry;
  final BirthdayOccurrence occurrence;
  final int days;
  _BirthdayRow({
    required this.entry,
    required this.occurrence,
    required this.days,
  });

  String get daysText {
    if (days == 0) return '今天';
    if (days == 1) return '明天';
    return '还有 $days 天';
  }
}

/// 列表项卡片。
class _BirthdayListTile extends StatelessWidget {
  final _BirthdayRow row;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _BirthdayListTile({
    required this.row,
    required this.onTap,
    required this.onDelete,
  });

  /// 判断这个生日是否在本月
  bool _isBirthdayThisMonth(_BirthdayRow row) {
    final now = DateTime.now();
    final occ = row.occurrence.date;
    return occ.year == now.year && occ.month == now.month;
  }

  /// 判断今天是否过生日
  bool _isToday(_BirthdayRow row) {
    return row.days == 0;
  }

  /// 生肖 emoji 映射
  String _shengXiaoEmoji(String shengXiao) {
    switch (shengXiao) {
      case '鼠':
        return '🐭';
      case '牛':
        return '🐮';
      case '虎':
        return '🐯';
      case '兔':
        return '🐰';
      case '龙':
        return '🐲';
      case '蛇':
        return '🐍';
      case '马':
        return '🐴';
      case '羊':
        return '🐑';
      case '猴':
        return '🐵';
      case '鸡':
        return '🐔';
      case '狗':
        return '🐶';
      case '猪':
        return '🐷';
      default:
        return '✨';
    }
  }

  @override
  Widget build(BuildContext context) {
    final shengXiao = BirthdayCalculator.shengXiaoOf(row.entry);
    final age = BirthdayCalculator.ageOf(row.entry, DateTime.now());
    final hasNote = row.entry.remark != null && row.entry.remark!.isNotEmpty;

    return Container(
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onDelete,
          borderRadius: BorderRadius.circular(24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                // 左侧渐变竖线（今天过生日才显示）
                if (_isToday(row))
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 6,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFEF4444), Color(0xFFF59E0B)],
                        ),
                        borderRadius: BorderRadius.only(
                          topRight: Radius.circular(6),
                          bottomRight: Radius.circular(6),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 头像
                      _LeadingAvatar(entry: row.entry),
                      const SizedBox(width: 14),
                      // 中间信息
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 第一行：左边 姓名+年龄+生肖，右边 状态标签
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Text(
                                        row.entry.name,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF1E293B),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // 生肖徽章（只显示 emoji）
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFE2E8F0),
                                            width: 1,
                                          ),
                                        ),
                                        child: Text(
                                          _shengXiaoEmoji(shengXiao),
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      // 年龄徽章
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFFBEB),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFFDE68A),
                                            width: 1,
                                          ),
                                        ),
                                        child: Text(
                                          '$age岁',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFFB45309),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // 状态标签（今天/还有X天）
                                if (_isBirthdayThisMonth(row))
                                  _DaysBadge(
                                    days: row.days,
                                    text: row.daysText,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // 第二行：日历图标 + 公历/农历 · 录入的生日日期
                            Row(
                              children: [
                                const Icon(
                                  Icons.calendar_month_outlined,
                                  size: 14,
                                  color: Color(0xFF94A3B8),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  row.entry.type == BirthdayType.gregorian
                                      ? '公历 · ${row.entry.year}年${row.entry.month}月${row.entry.day}日'
                                      : '农历 · ${row.entry.year}年${lunarMonthNameOf(row.entry.month)}${lunarDayNameOf(row.entry.day)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                            // 第三行：备注（上面有分隔线）
                            if (hasNote) ...[
                              const SizedBox(height: 10),
                              Container(
                                height: 1,
                                color: const Color(0xFFF1F5F9),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                row.entry.remark!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF64748B),
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 天数标签（"今天"红色，其他蓝色）。
class _DaysBadge extends StatelessWidget {
  final int days;
  final String text;

  const _DaysBadge({required this.days, required this.text});

  @override
  Widget build(BuildContext context) {
    final isToday = days == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isToday ? const Color(0xFFFEF2F2) : const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isToday ? const Color(0xFFFECACA) : const Color(0xFFE0E7FF),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isToday) ...[
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFFEF4444),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isToday
                  ? const Color(0xFFE11D48)
                  : const Color(0xFF4F46E5),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeadingAvatar extends StatelessWidget {
  final BirthdayEntry entry;
  const _LeadingAvatar({required this.entry});

  @override
  Widget build(BuildContext context) {
    final p = entry.avatarPath;
    // 用 Image.file + errorBuilder，而不是 existsSync()：
    // 列表每次重建都做一次同步文件检测会阻塞主线程，文件丢失时也能自动兜底
    if (p != null && p.isNotEmpty) {
      return ClipOval(
        child: Image.file(
          File(p),
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _initialAvatar(),
        ),
      );
    }
    return _initialAvatar();
  }

  Widget _initialAvatar() {
    return CircleAvatar(
      radius: 26,
      backgroundColor: AppColors.primaryLight,
      child: Text(
        entry.name.isNotEmpty ? entry.name[0] : '?',
        style: const TextStyle(
          fontSize: 20,
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 空状态视图。
class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 蛋糕图标
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cake_outlined,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '还没有生日记录',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textBody,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '点击右下角按钮，开始添加第一个生日',
              style: TextStyle(fontSize: 14, color: AppColors.textPlaceholder),
            ),
          ],
        ),
      ),
    );
  }
}

/// 10秒倒计时组件。
class _CountdownTimer extends StatefulWidget {
  @override
  State<_CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<_CountdownTimer> {
  final int _seconds = 10;
  late Stream<int> _stream;

  @override
  void initState() {
    super.initState();
    _stream = Stream.periodic(
      const Duration(seconds: 1),
      (i) => 10 - i - 1,
    ).take(10);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _stream,
      builder: (context, snapshot) {
        final sec = snapshot.data ?? _seconds;
        return Text(
          '已排定，$sec秒后提醒...',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1.4,
            fontWeight: FontWeight.w500,
          ),
        );
      },
    );
  }
}

/// 权限引导弹窗。
class _PermissionGuideDialog extends StatelessWidget {
  const _PermissionGuideDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            const Text(
              '为确保提醒准时送达',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            // 说明文字
            const Text(
              '部分安卓系统（小米/华为/OPPO/vivo 等）会限制后台闹钟，'
              '请手动完成以下设置，否则影响可能被系统清理：',
              style: TextStyle(
                fontSize: 16,
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            // 三个步骤
            _StepItem(number: 1, text: '关闭「电池优化 / 后台冻结」'),
            const SizedBox(height: 16),
            _StepItem(number: 2, text: '允许「自启动 / 后台活动」'),
            const SizedBox(height: 16),
            _StepItem(number: 3, text: '授予「精确闹钟」权限'),
            const SizedBox(height: 24),
            // 分隔线
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 20),
            // 设置路径
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.settings,
                  size: 20,
                  color: AppColors.textPlaceholder,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: const Text(
                    '设置路径通常在：系统设置 → 应用管理 → 本应用 → 电池/权限。',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // 按钮（右对齐）
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                child: const Text(
                  '知道了',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 弹窗步骤项。
class _StepItem extends StatelessWidget {
  final int number;
  final String text;

  const _StepItem({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 数字圆圈
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$number',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(width: 14),
        // 步骤文字
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textBody,
            ),
          ),
        ),
      ],
    );
  }
}
