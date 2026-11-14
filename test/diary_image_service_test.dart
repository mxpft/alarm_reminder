import 'dart:io';

import 'package:birthday_reminder/services/diary_image_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('压缩：长边缩到 640，体积显著变小，产物可解码', () async {
    final tmp = Directory.systemTemp.createTempSync('diary_img');
    addTearDown(() => tmp.deleteSync(recursive: true));

    // 造一张 2400×1600 的渐变图，模拟相册原图
    final source = img.Image(width: 2400, height: 1600);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
      }
    }
    final originBytes = img.encodeJpg(source, quality: 95);
    final sourceFile = File('${tmp.path}/raw.jpg');
    await sourceFile.writeAsBytes(originBytes);
    final originalSize = await sourceFile.length();

    final outDir = Directory('${tmp.path}/diary_images');
    final outPath = await DiaryImageService.compressToDirectory(
      sourceFile.path,
      outDir,
    );
    final outFile = File(outPath);

    expect(await outFile.exists(), isTrue);
    expect(outPath.endsWith('.jpg'), isTrue);
    expect(outPath.split(RegExp(r'[/\\]')).last, startsWith('diary_'));

    final outBytes = await outFile.readAsBytes();
    final outSize = outBytes.length;
    // 压缩后必须明显小于原图
    expect(outSize, lessThan(originalSize / 2));
    expect(outSize, lessThan(600 * 1024));

    final decoded = img.decodeImage(outBytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, DiaryImageService.maxDimension);
    // 等比缩放：2400×1600 → 640×427
    expect(
      decoded.height,
      (1600 * DiaryImageService.maxDimension / 2400).round(),
    );
  });

  test('小图不放大，仅重编码', () async {
    final tmp = Directory.systemTemp.createTempSync('diary_img_small');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final source = img.Image(width: 600, height: 400);
    img.fill(source, color: img.ColorRgb8(74, 108, 247));
    final file = File('${tmp.path}/small.jpg');
    await file.writeAsBytes(img.encodeJpg(source, quality: 95));

    final outPath = await DiaryImageService.compressToDirectory(
      file.path,
      Directory('${tmp.path}/out'),
    );
    final decoded = img.decodeImage(await File(outPath).readAsBytes());
    expect(decoded!.width, 600);
    expect(decoded.height, 400);
  });

  test('无法解码的文件原样保留（不丢用户图片）', () async {
    final tmp = Directory.systemTemp.createTempSync('diary_img_bad');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final file = File('${tmp.path}/broken.jpg');
    await file.writeAsString('not-an-image');
    final before = await file.readAsBytes();

    final outPath = await DiaryImageService.compressToDirectory(
      file.path,
      Directory('${tmp.path}/out'),
    );
    expect(await File(outPath).readAsBytes(), before);
  });

  test('isPending 识别待压缩临时副本', () {
    expect(DiaryImageService.isPending('/data/pending_123.jpg'), isTrue);
    expect(DiaryImageService.isPending(r'C:\data\pending_1.jpg'), isTrue);
    expect(DiaryImageService.isPending('/data/diary_123.jpg'), isFalse);
  });
}
