import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../models/diary_entry.dart';

/// 一句话日记导出服务。
///
/// 把指定年份的日记生成 `.docx`，版式严格对齐用户提供的 `2026.docx`：
/// - 按「YYYY年M月」分月，月内按时间倒序（最新在上）
/// - 每条日记依次输出：日期(M/D)、星期X、天气(可选)、心情(可选)、日记内容、图片(可选)
/// - 无天气 / 无心情时不输出对应行（参考文档括号内写明「无则不显示字段」）
/// - 图片跟在「日记：内容」之后，宽度固定 14.65cm、按原始比例缩放
class DiaryExportService {
  DiaryExportService._();

  static const _weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];

  /// 导出后图片的显示宽度（EMU，1440000 = 4cm），缩略展示而非原尺寸
  static const int _imageWidthEmu = 1440000;

  /// 图片重压缩参数：缩略到长边 320px、JPEG 质量 70，进一步压体积
  static const int _imageMaxEdge = 320;
  static const int _imageQuality = 70;

  static const _w =
      'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  static const _r =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  static const _wp =
      'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing';
  static const _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
  static const _pic =
      'http://schemas.openxmlformats.org/drawingml/2006/picture';

  /// 生成并保存到应用文档目录，返回 docx 文件绝对路径。
  static Future<String> exportYear(int year, List<DiaryEntry> entries) async {
    final bytes = buildDocxBytes(year, entries);

    final dir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}'
      '${Platform.pathSeparator}exports',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(
      '${dir.path}${Platform.pathSeparator}'
      'LittleButler-$year年日记.docx',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 纯 Dart 构建 docx 字节（不写盘，便于单元测试直接验证内容）。
  static Uint8List buildDocxBytes(int year, List<DiaryEntry> entries) {
    final sorted = [...entries]
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    final media = <_MediaItem>[];
    final documentXml = _buildDocumentXml(year, sorted, media);

    final relsXml = _buildDocumentRels(media);
    final contentTypesXml = _buildContentTypes(media);

    final archive = Archive();
    archive.addFile(
      ArchiveFile.bytes('[Content_Types].xml', utf8.encode(contentTypesXml)),
    );
    archive.addFile(
      ArchiveFile.bytes('_rels/.rels', utf8.encode(_buildRootRels())),
    );
    archive.addFile(
      ArchiveFile.bytes('word/document.xml', utf8.encode(documentXml)),
    );
    archive.addFile(
      ArchiveFile.bytes('word/_rels/document.xml.rels', utf8.encode(relsXml)),
    );
    archive.addFile(
      ArchiveFile.bytes('word/styles.xml', utf8.encode(_stylesXml)),
    );
    for (final m in media) {
      archive.addFile(ArchiveFile.bytes('word/${m.partName}', m.bytes));
    }

    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  // ============ OOXML ============

  static String _buildDocumentXml(
    int year,
    List<DiaryEntry> entries,
    List<_MediaItem> media,
  ) {
    final body = StringBuffer();
    int? currentMonth;
    for (final e in entries) {
      if (e.dateTime.year != year) continue;
      if (currentMonth != e.dateTime.month) {
        currentMonth = e.dateTime.month;
        body.write(_p('$year年${e.dateTime.month}月'));
      }
      body.write(_p('${e.dateTime.month}/${e.dateTime.day}'));
      body.write(_p(_weekdays[e.dateTime.weekday - 1]));

      final weather = _weatherText(e);
      if (weather != null) body.write(_p('天气：$weather'));

      final mood = _moodText(e);
      if (mood != null) body.write(_p('心情：$mood'));

      body.write(_p('日记：${e.content}'));

      // 图片跟在日记内容之后
      final imgPart = _tryBuildImage(e.imagePath, media);
      if (imgPart != null) body.write(imgPart);

      body.write('<w:p/>'); // 与下一条之间空一行
    }

    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="$_w" xmlns:r="$_r" '
        'xmlns:wp="$_wp" xmlns:a="$_a" xmlns:pic="$_pic">'
        '<w:body>${body.toString()}'
        '<w:sectPr>'
        '<w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1440" w:right="1800" w:bottom="1440" w:left="1800"/>'
        '</w:sectPr>'
        '</w:body></w:document>';
  }

  /// 单个段落（run 不显式设字体字号，继承 Word 默认样式，与参考文档一致）。
  static String _p(String text) {
    return '<w:p><w:r><w:t xml:space="preserve">'
        '${_escape(text)}</w:t></w:r></w:p>';
  }

  static String? _weatherText(DiaryEntry e) {
    final desc = e.weatherDesc?.trim();
    if (desc != null && desc.isNotEmpty) return desc;
    final emoji = e.weatherEmoji?.trim();
    if (emoji != null && emoji.isNotEmpty) return emoji;
    return null;
  }

  static String? _moodText(DiaryEntry e) {
    final desc = e.moodDesc?.trim();
    if (desc != null && desc.isNotEmpty) return desc;
    final emoji = e.moodEmoji?.trim();
    if (emoji != null && emoji.isNotEmpty) return emoji;
    return null;
  }

  /// 尝试把日记图片编入文档，返回图片段落的 XML；图片读不到 / 解码失败则返回 null。
  ///
  /// 导出前会把图片缩到长边 640px 并用 JPEG 重编码：既做缩略显示，也把体积压到几百 KB。
  static String? _tryBuildImage(String? imagePath, List<_MediaItem> media) {
    if (imagePath == null || imagePath.isEmpty) return null;
    final file = File(imagePath);
    try {
      if (!file.existsSync()) return null;
      var decoded = img.decodeImage(file.readAsBytesSync());
      if (decoded == null) return null;

      // JPEG 不支持透明通道，先合成到白底，避免出现黑边/黑块
      decoded = _flattenAlpha(decoded);
      // 缩略：长边超过 640 时等比缩小
      final longSide = decoded.width >= decoded.height
          ? decoded.width
          : decoded.height;
      if (longSide > _imageMaxEdge) {
        decoded = decoded.width >= decoded.height
            ? img.copyResize(
                decoded,
                width: _imageMaxEdge,
                interpolation: img.Interpolation.average,
              )
            : img.copyResize(
                decoded,
                height: _imageMaxEdge,
                interpolation: img.Interpolation.average,
              );
      }

      final outBytes = Uint8List.fromList(
        img.encodeJpg(decoded, quality: _imageQuality),
      );

      final id = media.length + 1;
      final relId = 'rId${id + 1}'; // rId1 留给 styles.xml
      final partName = 'media/image$id.jpg';
      media.add(
        _MediaItem(
          relId: relId,
          partName: partName,
          bytes: outBytes,
          contentType: 'image/jpeg',
          widthPx: decoded.width,
          heightPx: decoded.height,
        ),
      );

      final cyEmu = (_imageWidthEmu * decoded.height / decoded.width).round();
      return _imageParagraph(relId, partName, id, _imageWidthEmu, cyEmu);
    } catch (_) {
      return null;
    }
  }

  /// JPEG 不支持透明通道，先把透明像素合成到白底
  static img.Image _flattenAlpha(img.Image image) {
    if (image.numChannels < 4) return image;
    final canvas = img.Image(width: image.width, height: image.height);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(canvas, image);
    return canvas;
  }

  static String _imageParagraph(
    String relId,
    String partName,
    int id,
    int cxEmu,
    int cyEmu,
  ) {
    final docId = 100 + id;
    final picId = id;
    return '<w:p><w:r><w:drawing>'
        '<wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cxEmu" cy="$cyEmu"/>'
        '<wp:docPr id="$docId" name="图片 $id"/>'
        '<a:graphic>'
        '<a:graphicData uri="$_pic/picture">'
        '<pic:pic>'
        '<pic:nvPicPr>'
        '<pic:cNvPr id="$picId" name="图片 $id"/>'
        '<pic:cNvPicPr/>'
        '</pic:nvPicPr>'
        '<pic:blipFill>'
        '<a:blip r:embed="$relId"/>'
        '<a:stretch><a:fillRect/></a:stretch>'
        '</pic:blipFill>'
        '<pic:spPr>'
        '<a:xfrm><a:off x="0" y="0"/>'
        '<a:ext cx="$cxEmu" cy="$cyEmu"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
        '</pic:spPr>'
        '</pic:pic>'
        '</a:graphicData>'
        '</a:graphic>'
        '</wp:inline>'
        '</w:drawing></w:r></w:p>';
  }

  static String _buildDocumentRels(List<_MediaItem> media) {
    final b = StringBuffer();
    b.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    b.write(
      '<Relationships xmlns="http://schemas.openxmlformats.org/'
      'package/2006/relationships">',
    );
    b.write(
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
      'relationships/styles" Target="styles.xml"/>',
    );
    for (final m in media) {
      b.write(
        '<Relationship Id="${m.relId}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
        'relationships/image" Target="${m.partName}"/>',
      );
    }
    b.write('</Relationships>');
    return b.toString();
  }

  static String _buildRootRels() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/'
        'package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
        'relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>';
  }

  static String _buildContentTypes(List<_MediaItem> media) {
    final b = StringBuffer();
    b.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    b.write(
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
      'content-types">',
    );
    b.write(
      '<Default Extension="rels" ContentType="application/vnd.'
      'openxmlformats-package.relationships+xml"/>',
    );
    b.write('<Default Extension="xml" ContentType="application/xml"/>');
    // 图片统一重编码为 jpg，只需声明 jpeg 类型
    if (media.isNotEmpty) {
      b.write('<Default Extension="jpg" ContentType="image/jpeg"/>');
    }
    b.write(
      '<Override PartName="/word/document.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.'
      'wordprocessingml.document.main+xml"/>',
    );
    b.write(
      '<Override PartName="/word/styles.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.'
      'wordprocessingml.styles+xml"/>',
    );
    b.write('</Types>');
    return b.toString();
  }

  static String get _stylesXml {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="$_w">'
        '<w:docDefaults>'
        '<w:rPrDefault><w:rPr>'
        '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="等线"/>'
        // 24 half-points = 12pt（小四），比参考文档的五号（21）加大一号
        '<w:sz w:val="24"/><w:szCs w:val="24"/>'
        '</w:rPr></w:rPrDefault>'
        '<w:pPrDefault><w:pPr/></w:pPrDefault>'
        '</w:docDefaults>'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
        '<w:name w:val="Normal"/>'
        '</w:style>'
        '</w:styles>';
  }

  static String _escape(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

class _MediaItem {
  final String relId;
  final String partName;
  final Uint8List bytes;
  final String contentType;
  final int widthPx;
  final int heightPx;

  _MediaItem({
    required this.relId,
    required this.partName,
    required this.bytes,
    required this.contentType,
    required this.widthPx,
    required this.heightPx,
  });
}
