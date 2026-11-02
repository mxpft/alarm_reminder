/// 一条密码记录。
class PasswordEntry {
  /// 唯一 ID。
  final String id;

  /// 平台或网站名称（如 GitHub、Google）。
  String title;

  /// 账号或用户名。
  String username;

  /// 登录密码。
  String password;

  /// 备注信息（可选）。
  String? note;

  PasswordEntry({
    required this.id,
    required this.title,
    required this.username,
    required this.password,
    this.note,
  });
}
