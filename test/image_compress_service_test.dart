import 'dart:io';
import 'dart:typed_data';

import 'package:birthday_reminder/services/image_compress_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('头像：800×800 压到 512 长边，体积变小', () async {
    final tmp = Directory.systemTemp.createTempSync('avatar_compress');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final source = img.Image(width: 800, height: 800);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
      }
    }
    final bytes = img.encodeJpg(source, quality: 95);
    final file = File('${tmp.path}/raw.jpg');
    await file.writeAsBytes(bytes);

    final outPath = await ImageCompressService.compressFile(
      file.path,
      dir: Directory('${tmp.path}/avatars'),
      prefix: 'avatar_',
      maxDimension: 512,
      quality: 80,
    );
    final outBytes = await File(outPath).readAsBytes();
    expect(outPath.split(RegExp(r'[/\\]')).last, startsWith('avatar_'));
    expect(outBytes.length, lessThan(bytes.length));

    final decoded = img.decodeImage(outBytes)!;
    expect(decoded.width, 512);
    expect(decoded.height, 512);
  });

  test('透明 PNG 压缩后合成白底，不出现黑块', () async {
    final source = img.Image(width: 200, height: 200, numChannels: 4);
    // 默认全透明，直接编码为 PNG
    final pngBytes = Uint8List.fromList(img.encodePng(source));

    final out = await ImageCompressService.compressBytes(
      pngBytes,
      maxDimension: 512,
      quality: 80,
    );
    final decoded = img.decodeImage(out)!;
    final pixel = decoded.getPixel(40, 40);
    expect(pixel.r, greaterThan(240));
    expect(pixel.g, greaterThan(240));
    expect(pixel.b, greaterThan(240));
  });

  test('无法解码的字节原样返回', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    final out = await ImageCompressService.compressBytes(
      bytes,
      maxDimension: 512,
      quality: 80,
    );
    expect(out, bytes);
  });
}
