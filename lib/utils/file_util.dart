import 'dart:io';

import 'package:flutter/foundation.dart';

/// 静默删除本地文件。
///
/// 用于清理临时副本 / 已废弃的图片：文件不存在、被占用或删除失败都不应影响
/// 业务结果，只打一条日志，避免调用方到处写重复的 try/catch。
Future<void> deleteFileQuietly(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } catch (e) {
    debugPrint('删除文件失败($path): $e');
  }
}
