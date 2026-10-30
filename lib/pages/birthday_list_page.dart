import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../data/birthday_repository.dart';
import '../models/birthday_entry.dart';
import '../models/birthday_type.dart';
import '../services/birthday_calculator.dart';
import '../services/notification_service.dart';
import '../widgets/birthday_edit_dialog.dart';

/// 生日列表页：展示全部生日，按「距离下一次生日剩余天数」升序排序。
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
    _bootstrap();
  }

  /// 启动时：申请通知权限 + 重新调度全部通知（打开即刷新，补偿农历跨年/重启丢失）。
  Future<void> _bootstrap() async {
    try {
      await widget.notification.requestPermissions();
      await widget.notification.rescheduleAll(widget.repo, DateTime.now());
      _maybeShowAndroidHint();
    } catch (e) {
      debugPrint('启动初始化通知失败: $e');
    }
  }

  /// 安卓端：引导用户授予精确闹钟、允许后台活动、关闭电池优化。
  void _maybeShowAndroidHint() {
    if (Platform.isAndroid && !_permissionHintShown) {
      _permissionHintShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('为确保提醒准时送达'),
            content: const Text(
              '部分安卓系统（小米/华为/OPPO/vivo 等）会限制后台闹钟，'
              '请手动完成以下设置，否则提醒可能被系统清理：\n\n'
              '① 关闭「电池优化 / 后台冻结」\n'
              '② 允许「自启动 / 后台活动」\n'
              '③ 授予「精确闹钟」权限\n\n'
              '设置路径通常在：系统设置 → 应用管理 → 本应用 → 电池/权限。',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
      });
    }
  }

  Future<void> _testNotification() async {
    try {
      await widget.notification.requestPermissions();
      await widget.notification.testShowNow();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已发送测试通知，下拉通知栏查看')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('测试通知失败：$e')),
        );
      }
    }
  }

  Future<void> _testScheduledNotification() async {
    try {
      await widget.notification.testScheduleLater(0);
      if (mounted) {
        // 带倒计时的 SnackBar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 11),
            content: _CountdownTimer(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('定时通知失败：$e')),
        );
      }
    }
  }

  Future<void> _openEditor([BirthdayEntry? existing]) async {
    final entry = await showDialog<BirthdayEntry>(
      context: context,
      builder: (_) => BirthdayEditDialog(existing: existing),
    );
    if (entry == null) return;

    // 修改时：先删除旧的日历事件，再把 calendarEventId 清空，让 rescheduleAll 创建新的
    if (existing != null) {
      await widget.notification.cancelForEntry(existing);
      entry.calendarEventId = null; // 清空，触发 rescheduleAll 创建新事件
    }

    await widget.repo.save(entry);
    // 新增 / 修改后：立刻重新调度通知。
    await widget.notification.rescheduleAll(widget.repo, DateTime.now());

    // 检查日历事件是否创建成功
    final updated = widget.repo.box.get(entry.id);
    final calendarOk = updated?.calendarEventId != null;

    // 操作成功提示
    if (mounted) {
      final baseText = existing == null ? '新增成功' : '修改成功';
      final String fullText;
      if (calendarOk) {
        fullText = baseText;
      } else {
        final err = widget.notification.calendarLastError ?? '日历权限未开启';
        fullText = '$baseText（日历同步失败：$err）';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(fullText)),
      );
    }
  }

  Future<void> _confirmDelete(BirthdayEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除生日'),
        content: Text('确定删除「${entry.name}」的生日记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    // 删除后：取消其已排定通知 + 移除记录 + 全量重排。
    await widget.notification.cancelForEntry(entry);
    await widget.repo.delete(entry.id);
    await widget.notification.rescheduleAll(widget.repo, DateTime.now());

    // 删除成功提示
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除成功')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('生日提醒'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active_outlined),
            tooltip: '测试即时通知',
            onPressed: _testNotification,
          ),
          IconButton(
            icon: const Icon(Icons.timer_outlined),
            tooltip: '测试定时通知(2分钟后)',
            onPressed: _testScheduledNotification,
          ),
        ],
      ),
      // Hive 2.2.3 没有 listenable()，用 box.watch() 监听数据变化。
      body: StreamBuilder<BoxEvent>(
        stream: widget.repo.box.watch(),
        builder: (context, snapshot) {
          final rows = _buildRows(widget.repo.box.values.toList(), DateTime.now());
          if (rows.isEmpty) {
            return const _EmptyView();
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final row = rows[index];
              return ListTile(
                title: Text(row.entry.name),
                subtitle: row.entry.remark == null
                    ? Text(row.subtitle)
                    : Text('${row.entry.remark}  ·  ${row.subtitle}'),
                leading: _buildLeading(row.entry),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      row.daysText,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: row.days == 0
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmDelete(row.entry),
                    ),
                  ],
                ),
                onTap: () => _openEditor(row.entry),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('新增生日'),
      ),
    );
  }

  /// 列表左侧头像：有上传头像显示图片，否则显示姓名首字母。
  Widget _buildLeading(BirthdayEntry entry) {
    final p = entry.avatarPath;
    if (p != null && File(p).existsSync()) {
      return CircleAvatar(backgroundImage: FileImage(File(p)));
    }
    return CircleAvatar(
      child: Text(entry.name.isNotEmpty ? entry.name[0] : '?'),
    );
  }

  /// 计算每一条生日的展示行，并按剩余天数升序排序。
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
  _BirthdayRow({required this.entry, required this.occurrence, required this.days});

  String get subtitle {
    final typeText = entry.type == BirthdayType.gregorian ? '公历' : '农历';
    final sx = BirthdayCalculator.shengXiaoOf(entry);
    final age = BirthdayCalculator.ageOf(entry, DateTime.now());
    return '$typeText · ${occurrence.date.year}年'
        '${occurrence.date.month}月${occurrence.date.day}日'
        ' · 属$sx · $age岁';
  }

  String get daysText {
    if (days == 0) return '今天';
    if (days == 1) return '明天';
    return '还有 $days 天';
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cake_outlined, size: 72, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            '还没有生日记录\n点右下角「新增生日」开始添加',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

/// 10秒倒计时显示组件
class _CountdownTimer extends StatefulWidget {
  @override
  State<_CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<_CountdownTimer> {
  int _seconds = 10;
  late Stream<int> _stream;

  @override
  void initState() {
    super.initState();
    _stream = Stream.periodic(const Duration(seconds: 1), (i) => 10 - i - 1).take(10);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _stream,
      builder: (context, snapshot) {
        final sec = snapshot.data ?? _seconds;
        return Text('已排定，${sec}秒后提醒...');
      },
    );
  }
}
