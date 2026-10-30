/// 生日类型：公历 / 农历（二选一）。
enum BirthdayType {
  gregorian('公历'),
  lunar('农历');

  /// 界面展示文案。
  final String label;

  const BirthdayType(this.label);
}
