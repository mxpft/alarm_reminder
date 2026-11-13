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

  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('hive_diary_ui_test');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(DiaryEntryAdapter());
    }
    repo = DiaryRepository();
    await repo.open();
    await repo.box.clear();
    // 同一个月三条，验证时间线竖线在末条卡片底部收口
    await repo.save(
      DiaryEntry(
        id: 't1',
        content: 'UI 校验条目：圆点与日期间距、心情天气单行横滑。',
        dateTime: DateTime(now.year, now.month, 12, 16, 54),
        moodEmoji: '😊',
        moodDesc: '心情非常复杂但总体还挺不错的一天',
        weatherEmoji: '☀️',
        weatherDesc: '上午阴下午晴间多云转晴',
        temp: '21',
        location: '天水市秦州区人民公园东门附近',
      ),
    );
    await repo.save(
      DiaryEntry(
        id: 't2',
        content: '第二条，用来撑出卡间间距。',
        dateTime: DateTime(now.year, now.month, 12, 16, 21),
      ),
    );
    await repo.save(
      DiaryEntry(
        id: 't3',
        content: '第三条，最后一条卡片底部应收住竖线。',
        dateTime: DateTime(now.year, now.month, 12, 16, 14),
      ),
    );
  });

  testWidgets('时间线 UI：圆点不压日期、心情天气单行可横滑、定位图标中性色', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: DiaryListPage(repo: repo)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 圆点与日期文字留有间隙，不得重叠；圆点与卡片之间再留 3px 空隙
    final dateRect = tester.getRect(
      find.byKey(const ValueKey('diary-entry-date-t1')),
    );
    final dotRect = tester.getRect(
      find.byKey(const ValueKey('diary-entry-dot-t1')),
    );
    final cardRect = tester.getRect(
      find.byKey(const ValueKey('diary-entry-card-t1')),
    );
    expect(dateRect.right, lessThanOrEqualTo(dotRect.left - 2));
    expect(dotRect.width, 11, reason: '圆点直径 11，比原来小一圈');
    expect(cardRect.left - dotRect.right, 3, reason: '圆点右边缘到卡片左边缘留 3px，不贴卡片');

    // 心情 + 天气超宽时不换行，改为横向滚动
    final moodText = find.text('心情非常复杂但总体还挺不错的一天');
    expect(moodText, findsOneWidget);
    final scroller = find.ancestor(
      of: moodText,
      matching: find.byType(SingleChildScrollView),
    );
    expect(scroller, findsWidgets);
    final scrollers = tester.widgetList<SingleChildScrollView>(scroller);
    expect(
      scrollers.where((s) => s.scrollDirection == Axis.horizontal).length,
      1,
      reason: '心情/天气应在唯一的横向滚动容器内单行排列',
    );
    // 单行高度，没有被 Wrap 折成两行
    final moodRect = tester.getRect(moodText);
    expect(moodRect.height, lessThan(24));

    // 超宽内容右侧渐变淡出：滚动区外层是 dstIn 的 ShaderMask
    final shaderMasks = tester.widgetList<ShaderMask>(
      find.ancestor(of: moodText, matching: find.byType(ShaderMask)),
    );
    expect(
      shaderMasks.where((s) => s.blendMode == BlendMode.dstIn).length,
      1,
      reason: '心情/天气横向滚动区应由 ShaderMask 做右侧渐隐',
    );

    // 定位图标固定中性灰（不再跟随月份主题色）
    final locationIcon = tester.widget<Icon>(
      find.byIcon(Icons.location_on).first,
    );
    expect(locationIcon.color, const Color(0xFF727785));
    expect(tester.takeException(), isNull);
  });

  testWidgets('时间线竖线：止于末条圆点，首条不向上延伸', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: DiaryListPage(repo: repo)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 月份标题格式：2026·11
    expect(find.text('${now.year}·${now.month}'), findsOneWidget);

    final firstLine = tester.getRect(
      find.byKey(const ValueKey('diary-entry-line-t1')),
    );
    final firstDot = tester.getRect(
      find.byKey(const ValueKey('diary-entry-dot-t1')),
    );
    // 首条竖线从圆点中心开始，不向上多画
    expect(firstLine.top, closeTo(firstDot.center.dy, 1));

    // 中间条目的线要跨过 16px 间距，接到下一段
    final midCard = tester.getRect(
      find.byKey(const ValueKey('diary-entry-card-t2')),
    );
    final midLine = tester.getRect(
      find.byKey(const ValueKey('diary-entry-line-t2')),
    );
    expect(midLine.bottom, greaterThan(midCard.bottom + 8));

    // 末条竖线止于末个圆点中心，圆点下方不再拖出线
    final lastDot = tester.getRect(
      find.byKey(const ValueKey('diary-entry-dot-t3')),
    );
    final lastLine = tester.getRect(
      find.byKey(const ValueKey('diary-entry-line-t3')),
    );
    final lastCard = tester.getRect(
      find.byKey(const ValueKey('diary-entry-card-t3')),
    );
    expect(lastLine.bottom, closeTo(lastDot.center.dy, 1));
    expect(lastLine.bottom, lessThan(lastCard.bottom));
    // 与上一条的线首尾相接（末条线起点 -16，接住上一条的溢出段）
    expect(lastLine.top, closeTo(lastCard.top - 16, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('只有一条记录时完全不画竖线', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await repo.box.clear();
      await repo.save(
        DiaryEntry(
          id: 'solo',
          content: '只有一条，圆点下方不该有线。',
          dateTime: DateTime(now.year, now.month, 12, 9, 30),
        ),
      );
    });

    await tester.pumpWidget(MaterialApp(home: DiaryListPage(repo: repo)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('diary-entry-dot-solo')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('diary-entry-line-solo')),
      findsNothing,
      reason: '首末同一条时不绘制竖线',
    );
    expect(tester.takeException(), isNull);
  });
}
