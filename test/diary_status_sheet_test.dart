import 'package:birthday_reminder/widgets/diary_status_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('今日状态面板：四个输入框不吃全局白色填充', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          // 模拟 App 全局主题：InputDecoration 默认白色填充
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        home: Scaffold(body: Builder(builder: (ctx) => DiaryStatusSheet())),
      ),
    );
    await tester.pumpAndSettle();

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields.length, 4, reason: '心情、天气、气温、位置四个输入框');
    for (final f in fields) {
      expect(f.decoration?.filled, isFalse);
    }

    // 填入内容后不抛异常
    await tester.enterText(find.byType(TextField).first, '不喜不悲');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('emoji 选择：点一下选中回填、再点一次取消，且没有「无」项', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: (ctx) => DiaryStatusSheet())),
      ),
    );
    await tester.pumpAndSettle();

    // 默认未选：心情用表情占位、天气用太阳占位
    expect(find.byKey(const ValueKey('diary-mood-emoji-btn')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('diary-weather-emoji-btn')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.add_reaction_outlined), findsOneWidget);
    expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);

    // 打开心情选择器：emoji 项齐全，不再有「无」
    await tester.tap(find.byKey(const ValueKey('diary-mood-emoji-btn')));
    await tester.pumpAndSettle();
    // 只断言弹框存在，不锁标题文案（标题属可调的产品文案）
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('心酸'), findsOneWidget);
    expect(find.text('焦虑'), findsOneWidget);
    expect(find.text('惊喜'), findsOneWidget);
    expect(find.text('无'), findsNothing);
    expect(find.byIcon(Icons.block), findsNothing);

    // 选一个心情 → 弹框关闭，占位图标变成该 emoji
    await tester.tap(find.byKey(const ValueKey('diary-emoji-option-😊')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('😊'), findsWidgets);
    expect(find.byIcon(Icons.add_reaction_outlined), findsNothing);

    // 再点同一个 → 取消选中，回到占位图标
    await tester.tap(find.byKey(const ValueKey('diary-mood-emoji-btn')));
    await tester.pumpAndSettle();
    // 弹框里该项应为选中态（描了主题色边框）
    final selected = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(const ValueKey('diary-emoji-option-😊')),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (selected.decoration as BoxDecoration).border,
      isNotNull,
      reason: '已选中的 emoji 要有选中边框',
    );
    await tester.tap(find.byKey(const ValueKey('diary-emoji-option-😊')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add_reaction_outlined), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);

    // 天气选择器：扩充项齐全、无「无」，选晴后占位太阳消失
    await tester.tap(find.byKey(const ValueKey('diary-weather-emoji-btn')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('彩虹'), findsOneWidget);
    expect(find.text('阵雨'), findsOneWidget);
    expect(find.text('大风'), findsOneWidget);
    expect(find.text('无'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('diary-emoji-option-☀️')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add_reaction_outlined), findsOneWidget);
    expect(find.byIcon(Icons.wb_sunny_outlined), findsNothing);
    expect(find.text('☀️'), findsWidgets);

    // 取消天气 → 回到太阳占位图标
    await tester.tap(find.byKey(const ValueKey('diary-weather-emoji-btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('diary-emoji-option-☀️')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
