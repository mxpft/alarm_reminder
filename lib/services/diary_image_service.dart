import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'image_compress_service.dart';

/// 日记图片的存储与压缩。
///
/// 相册原图动辄 3–10MB，直接落盘会把本地库撑大；
/// 统一在写入数据库前压成「最长边 640、JPEG 质量 70」的图片，
/// 体积通常只有几十到几百 KB，用于时间轴/编辑表单的缩略显示足够清晰。
class DiaryImageService {
  /// 长边上限（同时限宽高），640 已足够覆盖卡片缩略与全屏预览。
  static const int maxDimension = 640;

  /// JPEG 质量，70 在体积与清晰度之间取平衡。
  static const int jpegQuality = 70;

  /// 相册选中后先落一份临时工作副本，压缩完成后删除。
  static const String pendingPrefix = 'pending_';

  /// 是否是选中后尚未压缩的临时副本。
  static bool isPending(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    return name.startsWith(pendingPrefix);
  }

  /// 压缩到 App 文档目录下的 diary_images，返回新文件路径。
  static Future<String> compressToDiaryDir(String sourcePath) async {
    final dir = await _diaryImageDir();
    return compressToDirectory(sourcePath, dir);
  }

  /// 可测试版本：压缩到指定目录，输出 `diary_<ms>.jpg`。
  @visibleForTesting
  static Future<String> compressToDirectory(
    String sourcePath,
    Directory outDir,
  ) {
    return ImageCompressService.compressFile(
      sourcePath,
      dir: outDir,
      prefix: 'diary_',
      maxDimension: maxDimension,
      quality: jpegQuality,
    );
  }

  static Future<Directory> _diaryImageDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/diary_images');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
