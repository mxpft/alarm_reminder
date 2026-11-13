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
  final firstDt = DateTime(now.year, now.month, now.day, 17, 10);
  final secondDt = DateTime(
    now.year,
    now.month,
    now.day == 1 ? 2 : now.day - 1,
    9,
    30,
  );
  const firstContent = '第一条：晚上下班路上看到晚霞。';
  const secondContent = '第二条：上午开会开了两小时。';
  const editedContent = '改一下：晚霞特别好看，拍了三张。';

  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('hive_diary_edit_test');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(DiaryEntryAdapter());
    }
    repo = DiaryRepository();
    await repo.open();
    await repo.box.clear();
    await repo.save(
      DiaryEntry(
        id: 'e1',
        content: firstContent,
        dateTime: firstDt,
        moodEmoji: '😊',
        moodDesc: '有点累但满足',
        location: '天水新天坛医院',
      ),
    );
    await repo.save(
      DiaryEntry(id: 'e2', content: secondContent, dateTime: secondDt),
    );
  });

  // WidgetTester 没有内置 doubleTap：两次点击需落在 40~300ms 之间
  Future<void> doubleTap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// 真实 Hive 写：runAsync 推进 I/O，pump flush microtask
  Future<void> drainWrites(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  String? fieldText(WidgetTester tester) {
    final tf = tester.widget<TextField>(find.byType(TextField).first);
    return tf.controller?.text;
  }

  Future<void> doubleTapCard(WidgetTester tester, String id) async {
    final card = find.byKey(ValueKey('diary-entry-card-$id'));
    await tester.ensureVisible(card);
    await tester.pump(const Duration(milliseconds: 200));
    await doubleTap(tester, card);
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('双击日记进入编辑：回填 / 保存更新 / 取消 / 切换编辑对象', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: DiaryListPage(repo: repo)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 未编辑：按钮「记录」，输入框为空
    expect(find.text('记录'), findsOneWidget);
    expect(fieldText(tester), isEmpty);

    // 1. 双击第一条 → 内容回填、按钮变「编辑」、出现编辑提示
    await doubleTapCard(tester, 'e1');
    expect(find.byKey(const ValueKey('diary-editing-banner')), findsOneWidget);
    // 双击卡片是编辑，不应弹出配色板（配色只在双击左侧日期列时触发）
    expect(find.byKey(const ValueKey('diary-color-picker')), findsNothing);
    expect(find.textContaining('正在编辑'), findsOneWidget);
    expect(fieldText(tester), firstContent);
    expect(find.text('编辑'), findsOneWidget);
    // 字数统计跟着回填内容同步
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('diary-compose-count')))
          .data,
      '${firstContent.runes.length}',
    );

    // 2. 改写后点「编辑」保存：只动正文，时间 / 心情 / 位置原样保留
    await tester.enterText(find.byType(TextField).first, editedContent);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('diary-save-btn')));
    await drainWrites(tester);

    final updated = repo.box.get('e1')!;
    expect(updated.content, editedContent);
    expect(updated.dateTime, firstDt);
    expect(updated.moodEmoji, '😊');
    expect(updated.location, '天水新天坛医院');
    expect(fieldText(tester), isEmpty);
    expect(find.byKey(const ValueKey('diary-editing-banner')), findsNothing);
    expect(find.text('记录'), findsOneWidget);

    // 3. 双击第二条 → 再点「取消」，数据不变、输入框清空
    await doubleTapCard(tester, 'e2');
    expect(fieldText(tester), secondContent);
    await tester.enterText(find.byType(TextField).first, '随便写点什么然后取消');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('diary-edit-cancel')));
    await tester.pump();
    expect(fieldText(tester), isEmpty);
    expect(find.text('记录'), findsOneWidget);
    expect(repo.box.get('e2')!.content, secondContent);

    // 4. 编辑一条时再双击另一条 → 输入框切到新的这条
    await doubleTapCard(tester, 'e1');
    expect(fieldText(tester), editedContent);
    await doubleTapCard(tester, 'e2');
    expect(fieldText(tester), secondContent);
    expect(tester.takeException(), isNull);
  });
}
