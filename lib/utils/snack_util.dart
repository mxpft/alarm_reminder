import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 全局消息提示的统一视觉规范。
///
/// 全 App 不再各自 new `SnackBar`，统一走这里：
/// 悬浮圆角、四周留边、左侧语义图标 + 单行文案。
/// 以后要改提示样式，只改本文件即可。
enum SnackKind { info, success, error }

/// 提示配色：按页面所属模块切换主色
///
/// - [app]：全 App 默认，普通/成功用主题蓝，错误用 danger 红
/// - [birthday]：生日页，沿用生日列表的时间线配色（靛蓝 / 今日红）
enum SnackPalette { app, birthday }

/// 生日页时间线配色：平时靛蓝
const Color _birthdayIndigo = Color(0xFF4F46E5);

/// 生日页时间线配色：今天红
const Color _birthdayToday = Color(0xFFE11D48);

/// 圆角、留边、阴影统一参数
const double _radius = 12;
const EdgeInsets _margin = EdgeInsets.fromLTRB(16, 0, 16, 16);

/// 按语义 + 页面配色，解析出背景色
Color _backgroundOf(SnackKind kind, SnackPalette palette) {
  switch (palette) {
    case SnackPalette.birthday:
      return kind == SnackKind.error ? _birthdayToday : _birthdayIndigo;
    case SnackPalette.app:
      return kind == SnackKind.error ? AppColors.danger : AppColors.primary;
  }
}

/// 统一入口：按语义类型弹一条悬浮提示。
///
/// [message] 为要展示的文案；同一时刻只保留一条，新的会顶掉旧的。
void showSnack(
  BuildContext context,
  String message, {
  SnackKind kind = SnackKind.info,
  SnackPalette palette = SnackPalette.app,
  Duration duration = const Duration(milliseconds: 2400),
}) {
  _show(
    context,
    kind: kind,
    palette: palette,
    duration: duration,
    content: Text(
      message,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

/// 自定义内容入口（如倒计时提示），外壳仍是统一的悬浮圆角 + 语义图标。
void showChildSnack(
  BuildContext context,
  Widget child, {
  SnackKind kind = SnackKind.info,
  SnackPalette palette = SnackPalette.app,
  Duration duration = const Duration(milliseconds: 2400),
}) {
  _show(
    context,
    kind: kind,
    palette: palette,
    duration: duration,
    content: child,
  );
}

void _show(
  BuildContext context, {
  required SnackKind kind,
  required SnackPalette palette,
  required Duration duration,
  required Widget content,
}) {
  final IconData icon = switch (kind) {
    SnackKind.info => Icons.info_outline,
    SnackKind.success => Icons.check_circle_outline,
    SnackKind.error => Icons.error_outline,
  };

  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: _margin,
        elevation: 4,
        backgroundColor: _backgroundOf(kind, palette),
        duration: duration,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
        ),
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: content),
          ],
        ),
      ),
    );
}

/// 普通信息提示
void showInfoSnack(
  BuildContext context,
  String message, {
  SnackPalette palette = SnackPalette.app,
  Duration duration = const Duration(milliseconds: 2400),
}) => showSnack(
  context,
  message,
  kind: SnackKind.info,
  palette: palette,
  duration: duration,
);

/// 操作成功提示
void showSuccessSnack(
  BuildContext context,
  String message, {
  SnackPalette palette = SnackPalette.app,
  Duration duration = const Duration(milliseconds: 2400),
}) => showSnack(
  context,
  message,
  kind: SnackKind.success,
  palette: palette,
  duration: duration,
);

/// 错误 / 校验拦截提示
void showErrorSnack(
  BuildContext context,
  String message, {
  SnackPalette palette = SnackPalette.app,
  Duration duration = const Duration(seconds: 3),
}) => showSnack(
  context,
  message,
  kind: SnackKind.error,
  palette: palette,
  duration: duration,
);
