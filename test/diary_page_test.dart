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
    final dir = Directory.systemTemp.createTempSync('hive_diary_test');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(DiaryEntryAdapter());
    }
    repo = DiaryRepository();
    await repo.open();
    await repo.box.clear();
    await _seed(repo, now);
  });

  test('数据层：写入 / 按年查询 / 倒序 / 年份列表', () async {
    expect(repo.count, 4);
    final all = repo.getAll();
    expect(all.length, 4);
    // 倒序
    for (var i = 0; i < all.length - 1; i++) {
      expect(
        all[i].dateTime.isAfter(all[i + 1].dateTime) ||
            all[i].dateTime.isAtSameMomentAs(all[i + 1].dateTime),
        isTrue,
      );
    }
    expect(repo.getByYear(now.year).length, 3);
    expect(repo.getByYear(now.year - 1).length, 1);
    final years = repo.availableYears();
    expect(years.first, now.year);
    expect(years.contains(now.year - 1), isTrue);
  });

  testWidgets('有内容态：无溢出、月份可收起、年份可切换', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: DiaryListPage(repo: repo)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('往昔回忆'), findsOneWidget);
    expect(find.text('共 3 篇'), findsOneWidget);
    expect(find.text('${now.year}·${now.month}'), findsOneWidget);
    // 当月最新一条默认展开
    expect(find.textContaining('今天天气很好'), findsOneWidget);

    // 上个月默认收起 → 点击月份头展开
    final prevMonth = now.month - 1 > 0 ? now.month - 1 : 1;
    expect(find.text('上个月的记录'), findsNothing);
    await _scrollTo(tester, find.text('${now.year}·$prevMonth'), 160);
    await tester.tap(find.text('${now.year}·$prevMonth'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('上个月的记录'), findsOneWidget);

    // 再次点击收起
    await tester.tap(find.text('${now.year}·$prevMonth'));
    await tester.pumpAndSettle();
    expect(find.text('上个月的记录'), findsNothing);

    // 年份切换弹窗 → 切换到上一年
    await _scrollTo(tester, find.text('${now.year}年度'), 160);
    await tester.tap(find.text('${now.year}年度'));
    await tester.pumpAndSettle();
    expect(find.text('切换年份'), findsOneWidget);
    expect(find.text('${now.year - 1}'), findsOneWidget);
    await tester.tap(find.text('${now.year - 1}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('共 1 篇'), findsOneWidget);
    expect(find.text('${now.year - 1}年度'), findsOneWidget);
    expect(find.text('去年的记录'), findsOneWidget);

    // 切换到空年份则显示空状态
    await tester.tap(find.text('${now.year - 1}年度'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('输入框右下角字数统计：随输入更新且不与正文重叠', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: DiaryListPage(repo: repo)));
    await tester.pumpAndSettle();

    final countFinder = find.byKey(const ValueKey('diary-compose-count'));
    expect(countFinder, findsOneWidget);
    expect(tester.widget<Text>(countFinder).data, '0');

    await tester.enterText(find.byType(TextField).first, '今天天气很好');
    await tester.pump();
    expect(tester.widget<Text>(countFinder).data, '6');

    final fieldRect = tester.getRect(find.byType(TextField).first);
    final countRect = tester.getRect(countFinder);
    // 计数位于正文下方，两者不重叠
    expect(countRect.top, greaterThanOrEqualTo(fieldRect.bottom));
    // 右对齐：贴输入框右边缘
    expect(countRect.right, closeTo(fieldRect.right, 4));

    // 正文写满 5 行上限，计数仍在下方不重叠
    await tester.enterText(find.byType(TextField).first, '一二三四五六七八九十' * 5);
    await tester.pump();
    expect(tester.widget<Text>(countFinder).data, '50');
    final longField = tester.getRect(find.byType(TextField).first);
    final longCount = tester.getRect(countFinder);
    expect(longCount.top, greaterThanOrEqualTo(longField.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('月份头部内边距加大：块高与四周留白', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: DiaryListPage(repo: repo)));
    await tester.pumpAndSettle();

    final headerFinder = find.byKey(
      ValueKey('diary-month-header-${now.month}'),
    );
    expect(headerFinder, findsOneWidget);
    final headerRect = tester.getRect(headerFinder);
    final titleRect = tester.getRect(find.text('${now.year}·${now.month}'));

    // 垂直 12 + 12、水平 16
    expect(headerRect.height, greaterThanOrEqualTo(42));
    expect(titleRect.left - headerRect.left, greaterThanOrEqualTo(15));
    expect(titleRect.top - headerRect.top, greaterThanOrEqualTo(11));
    expect(headerRect.bottom - titleRect.bottom, greaterThanOrEqualTo(11));
    expect(tester.takeException(), isNull);
  });

  testWidgets('记录按钮写入 Hive 并进入时间线', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final before = repo.getAll().length;

    await tester.pumpWidget(MaterialApp(home: DiaryListPage(repo: repo)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '测试写入一条日记');
    await tester.pump();

    // Hive 写入是真实异步 I/O，需在 runAsync 中执行
    await tester.runAsync(() async {
      await tester.tap(find.text('记录'));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repo.getAll().length, before + 1);
    final saved = repo.getAll().firstWhere((e) => e.content == '测试写入一条日记');
    expect(saved.dateTime.year, now.year);
    expect(find.text('已记录'), findsOneWidget);
    // 记录后输入框已清空，内容出现在时间线卡片中
    expect(find.text('测试写入一条日记'), findsOneWidget);
  });

  testWidgets('记录后「+」面板（心情/天气/图片/位置）一并清空', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: DiaryListPage(repo: repo)));
    await tester.pumpAndSettle();

    // 打开「+」面板填写心情、天气、气温、位置
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    final sheetFields = find.byType(TextField);
    // 页面本身的输入框仍在树中，弹层内有 4 个
    expect(sheetFields, findsNWidgets(5));
    await tester.enterText(sheetFields.at(1), '平静');
    await tester.enterText(sheetFields.at(2), '晴朗');
    await tester.enterText(sheetFields.at(3), '21');
    await tester.enterText(sheetFields.at(4), '天水市秦州区');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    // 面板确认后，状态 pill 与位置 tag 出现在记录卡片中
    expect(find.byKey(const ValueKey('diary-status-pills')), findsOneWidget);
    expect(find.byKey(const ValueKey('diary-status-location')), findsOneWidget);

    // 写内容并记录
    await tester.enterText(find.byType(TextField), '记录后应清空状态');
    await tester.runAsync(() async {
      await tester.tap(find.text('记录'));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 输入框已清空
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
    // 记录卡片上的心情/天气 pill 已消失（照片缩略、位置 tag 同源清除）
    expect(find.byKey(const ValueKey('diary-status-pills')), findsNothing);
    expect(find.byKey(const ValueKey('diary-status-thumb')), findsNothing);
    expect(find.byKey(const ValueKey('diary-status-location')), findsNothing);
    // 但内容已进入下方时间线卡片
    expect(find.text('记录后应清空状态'), findsOneWidget);
    expect(find.text('天水市秦州区'), findsOneWidget);
  });

  testWidgets('长按日记卡片弹出二次确认并删除', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: DiaryListPage(repo: repo)));
    await tester.pumpAndSettle();

    final target = find.textContaining('今天天气很好').first;
    final before = repo.getAll().length;

    // 长按 → 二次确认弹框
    await tester.longPress(target);
    await tester.pumpAndSettle();
    expect(find.textContaining('此操作不可恢复'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    // 取消不删除
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repo.getAll().length, before);
    expect(find.textContaining('今天天气很好'), findsOneWidget);

    // 再次长按 → 确认删除
    await tester.longPress(find.textContaining('今天天气很好').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    // Hive 写入是真实异步 I/O：在 runAsync 中等待其落盘，再回到测试帧刷新界面
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repo.getAll().length, before - 1);
    expect(find.textContaining('今天天气很好'), findsNothing);
    expect(find.text('删除成功'), findsOneWidget);
  });

  testWidgets('只选天气不写描述：卡片出天气图标，不误显示成心情标签', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: DiaryListPage(repo: repo)));
    await tester.pumpAndSettle();

    // 打开「+」面板 → 只挑天气图标「雨」，描述与气温留空、心情完全不选
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('diary-weather-emoji-btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('雨'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    // 只有天气一类 pill，不存在空白心情 pill
    expect(
      find.byKey(const ValueKey('diary-status-weather-pill')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('diary-status-mood-pill')), findsNothing);

    await tester.enterText(find.byType(TextField).first, '只选天气不写描述');
    await tester.runAsync(() async {
      await tester.tap(find.text('记录'));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final saved = repo.getAll().firstWhere((e) => e.content == '只选天气不写描述');
    // 心情没有被默认值污染；天气只存了图标
    expect(saved.moodEmoji, isNull);
    expect(saved.moodDesc, isNull);
    expect(saved.weatherEmoji, '🌧️');
    expect(saved.weatherDesc, isNull);
    expect(saved.temp, isNull);

    // 时间线卡片上出现的是天气图标胶囊，没有心情胶囊
    expect(
      find.byKey(ValueKey('diary-weather-pill-${saved.id}')),
      findsOneWidget,
    );
    expect(find.byKey(ValueKey('diary-mood-pill-${saved.id}')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(ValueKey('diary-weather-pill-${saved.id}')),
        matching: find.text('🌧️'),
      ),
      findsOneWidget,
    );
    expect(find.text('😊'), findsNothing);
  });

  testWidgets('三处标签底色已调浅：年度切换 / 月份篇数 / 心情 tag', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: DiaryListPage(repo: repo)));
    await tester.pumpAndSettle();

    double luminOf(Finder finder) {
      final box = tester.widget<Container>(finder);
      final color = (box.decoration as BoxDecoration).color!;
      return color.computeLuminance();
    }

    // 旧值：#D3E4FE（≈0.75）、#D8E2FF（≈0.77）都偏深，新值需更亮
    expect(
      luminOf(find.byKey(const ValueKey('diary-year-chip'))),
      greaterThan(0.82),
    );
    expect(
      luminOf(find.byKey(ValueKey('diary-month-count-${now.month}'))),
      greaterThan(0.82),
    );

    // 面板里选一个心情，确认后的心情 tag 也应是浅底
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('diary-mood-emoji-btn')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(Dialog), matching: find.text('平静')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(
      luminOf(find.byKey(const ValueKey('diary-status-mood-pill'))),
      greaterThan(0.85),
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _scrollTo(WidgetTester tester, Finder finder, double delta) async {
  final scrollable = find.byType(Scrollable).first;
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: scrollable,
    maxScrolls: 60,
  );
  await tester.pumpAndSettle();
}

Future<void> _seed(DiaryRepository repo, DateTime now) async {
  final entries = [
    DiaryEntry(
      id: 'a',
      content:
          '今天天气很好，去公园散步，看到了很久没见的晚霞，心情特别好。'
          '写一段比较长的文字，用来验证正文换行、卡片高度自适应以及整体布局不会溢出。',
      dateTime: DateTime(now.year, now.month, 12, 21, 15),
      moodEmoji: '😊',
      moodDesc: '心情非常复杂但总体还挺不错的一天',
      weatherEmoji: '☀️',
      weatherDesc: '上午阴下午晴间多云转晴',
      temp: '21',
      location: '天水市秦州区人民公园东门附近',
      imagePath: '/no/such/file.jpg',
    ),
    DiaryEntry(
      id: 'b',
      content: '只有正文，没有心情/天气/图片/位置。',
      dateTime: DateTime(now.year, now.month, 3, 8, 30),
    ),
    DiaryEntry(
      id: 'c',
      content: '上个月的记录',
      dateTime: DateTime(
        now.year,
        now.month - 1 > 0 ? now.month - 1 : 1,
        20,
        19,
        0,
      ),
      weatherEmoji: '🌧️',
      weatherDesc: '小雨',
      temp: '15',
    ),
    DiaryEntry(
      id: 'd',
      content: '去年的记录',
      dateTime: DateTime(now.year - 1, 10, 24, 18, 45),
    ),
  ];
  for (final e in entries) {
    await repo.save(e);
  }
}
