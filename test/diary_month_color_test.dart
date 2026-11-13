import 'dart:io';

import 'package:birthday_reminder/data/diary_repository.dart';
import 'package:birthday_reminder/models/diary_entry.dart';
import 'package:birthday_reminder/models/diary_entry_adapter.dart';
import 'package:birthday_reminder/pages/diary_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late DiaryRepository repo;
  final now = DateTime.now();
  final prevMonth = now.month == 1 ? 12 : now.month - 1;
  final prevMonthYear = now.month == 1 ? now.year - 1 : now.year;

  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('hive_diary_color_test');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(DiaryEntryAdapter());
    }
    repo = DiaryRepository();
    await repo.open();
    await repo.box.clear();
    await repo.colorBox.clear();
    await repo.save(
      DiaryEntry(
        id: 'm1',
        content: '本月第一条，双击它换配色。',
        dateTime: DateTime(now.year, now.month, 12, 16, 54),
      ),
    );
    await repo.save(
      DiaryEntry(
        id: 'm2',
        content: '本月第二条，颜色要跟着一起变。',
        dateTime: DateTime(now.year, now.month, 12, 15, 24),
      ),
    );
    await repo.save(
      DiaryEntry(
        id: 'p1',
        content: '上个月的记录，不应被本月的配色影响。',
        dateTime: DateTime(prevMonthYear, prevMonth, 20, 10, 0),
      ),
    );
  });

  Color dotColor(WidgetTester tester, String id) {
    final box = tester.widget<Container>(
      find.byKey(ValueKey('diary-entry-dot-$id')),
    );
    return (box.decoration as BoxDecoration).color!;
  }

  Color dateColor(WidgetTester tester, String id) {
    final text = tester.widget<Text>(
      find.byKey(ValueKey('diary-entry-date-$id')),
    );
    return text.style!.color!;
  }

  /// 弹窗开合走完路由动画（不用 pumpAndSettle：真 Hive I/O 下可能等不到静止）
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  // WidgetTester 没有内置 doubleTap：两次点击需落在 40~300ms 之间
  Future<void> doubleTap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// 染色入口：双击左侧日期列（双击卡片是「编辑日记」，两者分区）
  Future<void> openPalette(WidgetTester tester, String id) async {
    await doubleTap(tester, find.byKey(ValueKey('diary-entry-datecol-$id')));
    await settle(tester);
  }

  Color dayLabelColor(WidgetTester tester, String id) {
    final text = tester.widget<Text>(
      find.byKey(ValueKey('diary-entry-daylabel-$id')),
    );
    return text.style!.color!;
  }

  Color lineColor(WidgetTester tester, String id) {
    final line = tester.widget<Container>(
      find.byKey(ValueKey('diary-entry-line-$id')),
    );
    return line.color!;
  }

  /// 把页面里 fire-and-forget 的 Hive 写推完：runAsync 推进真实 I/O，pump flush microtask
  Future<void> drainWrites(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  testWidgets('双击时间轴换月配色：圆点 / 日期 / 月份头同步，且恢复默认可用', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: DiaryListPage(repo: repo)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 1. 默认色整体柔和：不再是原先那套深蓝 / 深红，圆点与日期 / 「今天」同色
    final defaultColor = dotColor(tester, 'm1');
    expect(defaultColor, isNot(const Color(0xFF1E3A8A)));
    expect(defaultColor, isNot(const Color(0xFFB91C1C)));
    expect(defaultColor.computeLuminance(), greaterThan(0.15));
    expect(dateColor(tester, 'm1'), defaultColor);
    expect(dayLabelColor(tester, 'm1'), defaultColor);

    // 2. 双击左侧日期列 → 弹出色板
    await openPalette(tester, 'm1');
    expect(find.byKey(const ValueKey('diary-color-picker')), findsOneWidget);
    expect(find.textContaining('时间轴配色'), findsOneWidget);
    // 双击日期列只换色，不应误进「编辑」态
    expect(find.byKey(const ValueKey('diary-editing-banner')), findsNothing);

    const chosen = Color(0xFF56B295);
    await tester.tap(find.byKey(const ValueKey('diary-color-56b295')));
    await settle(tester);
    expect(find.byKey(const ValueKey('diary-color-picker')), findsNothing);

    // 3. 本月全部日记的圆点、日期、日期下方「今天」、连线一起换色
    expect(dotColor(tester, 'm1'), chosen);
    expect(dotColor(tester, 'm2'), chosen);
    expect(dateColor(tester, 'm1'), chosen);
    expect(dateColor(tester, 'm2'), chosen);
    expect(dayLabelColor(tester, 'm1'), chosen);
    expect(dayLabelColor(tester, 'm2'), chosen);
    // 连线用同色但更淡
    expect(
      lineColor(tester, 'm1').toARGB32(),
      chosen.withValues(alpha: 0.38).toARGB32(),
    );

    // 4. 月份头用同色 10% 极淡底
    final header = tester.widget<Container>(
      find.byKey(ValueKey('diary-month-header-${now.month}')),
    );
    expect(
      (header.decoration as BoxDecoration).color!.toARGB32(),
      chosen.withValues(alpha: 0.10).toARGB32(),
    );

    // 5. 上月分组默认收起，展开后它的圆点仍是默认色（本月配色不外溢）
    final prevHeader = find.byKey(ValueKey('diary-month-header-$prevMonth'));
    await tester.ensureVisible(prevHeader);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(prevHeader);
    await settle(tester);
    expect(dotColor(tester, 'p1'), isNot(chosen));

    // 6. 颜色已落库，且只写了当月
    await drainWrites(tester);
    expect(repo.monthColorValue(now.year, now.month), 0xFF56B295);
    expect(repo.monthColorValue(prevMonthYear, prevMonth), isNull);

    // 7. 再双击日期列选「恢复默认」，回到内置月度色且落库值清空
    await tester.ensureVisible(find.byKey(ValueKey('diary-entry-datecol-m1')));
    await tester.pump(const Duration(milliseconds: 200));
    await openPalette(tester, 'm1');
    await tester.tap(find.byKey(const ValueKey('diary-color-reset')));
    await settle(tester);

    expect(dotColor(tester, 'm1'), defaultColor);
    expect(dateColor(tester, 'm1'), defaultColor);
    expect(dayLabelColor(tester, 'm1'), defaultColor);
    await drainWrites(tester);
    expect(repo.monthColorValue(now.year, now.month), isNull);
    expect(tester.takeException(), isNull);
  });
}
