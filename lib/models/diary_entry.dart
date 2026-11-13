/// 一条一句话日记。
class DiaryEntry {
  /// 唯一 ID。
  final String id;

  /// 正文内容。
  String content;

  /// 记录时间（精确到分钟）。
  DateTime dateTime;

  /// 心情 emoji（可空）。
  String? moodEmoji;

  /// 心情描述（可空）。
  String? moodDesc;

  /// 天气 emoji（可空）。
  String? weatherEmoji;

  /// 天气描述（可空）。
  String? weatherDesc;

  /// 气温（可空，仅数字）。
  String? temp;

  /// 地理位置（可空）。
  String? location;

  /// 图片本地路径（可空）。
  String? imagePath;

  DiaryEntry({
    required this.id,
    required this.content,
    required this.dateTime,
    this.moodEmoji,
    this.moodDesc,
    this.weatherEmoji,
    this.weatherDesc,
    this.temp,
    this.location,
    this.imagePath,
  });
}
