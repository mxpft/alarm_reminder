import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:birthday_reminder/models/diary_entry.dart';
import 'package:birthday_reminder/services/diary_export_service.dart';

void main() {
  test('导出 docx 严格对齐 2026.docx 的字段规则', () {
    final tmp = Directory.systemTemp.createTempSync('diary_export_test');
    addTearDown(() => tmp.deleteSync(recursive: true));

    // 一张 2x2 的测试图片
    final pngBytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 2, height: 2)),
    );
    final imageFile = File('${tmp.path}${Platform.pathSeparator}pic.png');
    imageFile.writeAsBytesSync(pngBytes);

    final entries = <DiaryEntry>[
      DiaryEntry(
        id: 'a',
        content: '平常的一天，今天啥也没干，但是感觉很累。',
        dateTime: DateTime(2026, 11, 13, 18, 14),
        weatherDesc: '冷飕飕',
        moodDesc: '有点无语',
        imagePath: imageFile.path,
      ),
      DiaryEntry(
        id: 'b',
        content: '好久没运动了，今天稍微跑了下步，心肺更要爆炸了似的。',
        dateTime: DateTime(2026, 11, 12, 0, 0),
      ),
    ];

    final bytes = DiaryExportService.buildDocxBytes(2026, entries);
    final archive = ZipDecoder().decodeBytes(bytes);

    String contentOf(String name) {
      final f = archive.findFile(name);
      expect(f, isNotNull, reason: 'docx 缺少 $name');
      return utf8.decode(f!.content as List<int>);
    }

    final document = contentOf('word/document.xml');
    final rels = contentOf('word/_rels/document.xml.rels');

    // 月份头与日期、星期
    expect(document, contains('2026年11月'));
    expect(document, contains('11/13'));
    expect(document, contains('星期五')); // 2026-11-13 是周五
    expect(document, contains('11/12'));
    expect(document, contains('星期四')); // 2026-11-12 是周四

    // 天气/心情：有则输出，无则整行不出现
    expect(document, contains('天气：冷飕飕'));
    expect(document, contains('心情：有点无语'));
    // 第二条没有天气/心情，因此全文「天气：」「心情：」各只出现一次
    expect('天气：'.allMatches(document).length, 1);
    expect('心情：'.allMatches(document).length, 1);

    // 日记内容
    expect(document, contains('日记：平常的一天，今天啥也没干，但是感觉很累。'));
    expect(document, contains('日记：好久没运动了，今天稍微跑了下步，心肺更要爆炸了似的。'));

    // 图片：有 drawing 与 media 关系（统一重编码为 jpg）
    expect(document, contains('<w:drawing'));
    expect(rels, contains('relationships/image'));
    expect(rels, contains('media/image1.jpg'));
    expect(archive.findFile('word/media/image1.jpg'), isNotNull);

    // 月份头只出现一次（两条同属 11 月）
    expect('2026年11月'.allMatches(document).length, 1);
  });

  test('导出图片会缩略到长边 320 并重压缩为 JPEG', () {
    final tmp = Directory.systemTemp.createTempSync('diary_export_shrink');
    addTearDown(() => tmp.deleteSync(recursive: true));

    // 一张 1600x1200 的随机噪点图，原始 PNG 体积会明显大于压缩后的 JPEG
    final rnd = Random(42);
    final rng = img.Image(width: 1600, height: 1200);
    for (var y = 0; y < rng.height; y++) {
      for (var x = 0; x < rng.width; x++) {
        rng.setPixelRgb(
          x,
          y,
          rnd.nextInt(256),
          rnd.nextInt(256),
          rnd.nextInt(256),
        );
      }
    }
    final srcBytes = Uint8List.fromList(img.encodePng(rng));
    final imageFile = File('${tmp.path}${Platform.pathSeparator}big.png');
    imageFile.writeAsBytesSync(srcBytes);

    final entries = <DiaryEntry>[
      DiaryEntry(
        id: 'a',
        content: '带图的一条。',
        dateTime: DateTime(2026, 11, 13),
        imagePath: imageFile.path,
      ),
    ];

    final bytes = DiaryExportService.buildDocxBytes(2026, entries);
    final archive = ZipDecoder().decodeBytes(bytes);
    final media = archive.findFile('word/media/image1.jpg');
    expect(media, isNotNull);

    final jpgBytes = Uint8List.fromList(media!.content as List<int>);
    final decoded = img.decodeImage(jpgBytes);
    expect(decoded, isNotNull);
    // 长边 1600 -> 320，短边等比 1200*320/1600 = 240
    expect(decoded!.width, 320);
    expect(decoded.height, 240);
    // 重压缩后体积应远小于原始 PNG
    expect(jpgBytes.length, lessThan(srcBytes.length));
  });
}
