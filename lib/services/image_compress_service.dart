import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 通用图片压缩：解码 → 校正 EXIF 方向 → 透明底转白 → 等比缩放到长边上限 → JPEG 重编码。
///
/// 解码/缩放/重编码放在后台 isolate 执行，避免压大图时卡住 UI。
/// 日记图片、生日头像都走这一套，只是长边与质量参数不同。
class ImageCompressService {
  /// 压缩字节，返回 JPEG 字节；无法解码（如 HEIC）时原样返回入参，由调用方兜底。
  static Future<Uint8List> compressBytes(
    Uint8List bytes, {
    required int maxDimension,
    required int quality,
  }) {
    return compute(_compressInIsolate, <String, dynamic>{
      'bytes': bytes,
      'maxDimension': maxDimension,
      'quality': quality,
    });
  }

  /// 压缩文件并写入 [dir]，文件名 `<prefix><ms>.jpg`，返回新文件路径。
  static Future<String> compressFile(
    String sourcePath, {
    required Directory dir,
    required String prefix,
    int maxDimension = 1280,
    int quality = 80,
  }) async {
    final compressed = await compressBytes(
      await File(sourcePath).readAsBytes(),
      maxDimension: maxDimension,
      quality: quality,
    );
    return writeBytes(compressed, dir: dir, prefix: prefix);
  }

  /// 把已压缩好的字节落盘（头像裁剪后只有内存字节时用这个）。
  static Future<String> writeBytes(
    Uint8List bytes, {
    required Directory dir,
    required String prefix,
  }) async {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final dest = File(
      '${dir.path}/$prefix${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await dest.writeAsBytes(bytes, flush: true);
    return dest.path;
  }

  /// JPEG 不支持透明通道，先把半透明/透明像素合成到白底，避免出现黑边或黑块。
  /// 导出 docx 等场景也复用这一份，避免各写一套。
  static img.Image flattenOnWhite(img.Image image) {
    if (image.numChannels < 4) return image;
    final canvas = img.Image(width: image.width, height: image.height);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(canvas, image);
    return canvas;
  }

  /// 长边超过 [maxDimension] 时等比缩小，否则原样返回。
  static img.Image resizeToMax(img.Image image, int maxDimension) {
    final longSide = image.width >= image.height ? image.width : image.height;
    if (longSide <= maxDimension) return image;
    return image.width >= image.height
        ? img.copyResize(
            image,
            width: maxDimension,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: maxDimension,
            interpolation: img.Interpolation.average,
          );
  }
}

Uint8List _compressInIsolate(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final maxDimension = args['maxDimension'] as int;
  final quality = args['quality'] as int;

  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return bytes;
  }
  final oriented = img.bakeOrientation(decoded);
  final flattened = ImageCompressService.flattenOnWhite(oriented);
  final resized = ImageCompressService.resizeToMax(flattened, maxDimension);
  return img.encodeJpg(resized, quality: quality);
}
