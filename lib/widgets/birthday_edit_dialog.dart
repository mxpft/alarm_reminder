import 'dart:io';
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart' show Crop, CropController, CropSuccess;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
// import 'package:lunar_flutter/lunar.dart';
import 'package:lunar/lunar.dart';
import '../data/birthday_repository.dart';
import '../models/birthday_entry.dart';
import '../models/birthday_type.dart';
import 'lunar_date_picker.dart';

/// 新增 / 编辑生日的弹窗。
///
/// 表单：姓名（必填）、备注（选填）、生日类型（公历/农历单选）、日期选择器
/// （公历用系统日历，农历用 [LunarDatePicker] 滚轮）。
/// 保存后通过 Navigator.pop 返回一条 [BirthdayEntry]。
class BirthdayEditDialog extends StatefulWidget {
  /// 传入则为编辑模式，否则为新增。
  final BirthdayEntry? existing;

  const BirthdayEditDialog({super.key, this.existing});

  @override
  State<BirthdayEditDialog> createState() => _BirthdayEditDialogState();
}

class _BirthdayEditDialogState extends State<BirthdayEditDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _remarkCtrl;

  late BirthdayType _type;

  // 提醒配置
  late int _remindHour;
  late int _remindMinute;
  late bool _notify3DaysBefore;

  // 头像
  String? _avatarPath;
  final _picker = ImagePicker();

  // 公历选择
  late int _gYear, _gMonth, _gDay;
  // 农历选择
  late int _lYear, _lMonth, _lDay;
  late bool _lLeap;

  final _formKey = GlobalKey<FormState>();

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final now = DateTime.now();

    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _remarkCtrl = TextEditingController(text: e?.remark ?? '');

    // 当前公历日期（新增默认值）。
    _gYear = e?.year ?? now.year;
    _gMonth = e?.month ?? now.month;
    _gDay = e?.day ?? now.day;

    // 当前农历日期（新增默认值）。
    // lunar 1.7.8：闰月时 getMonth() 返回负数，故取绝对值存正数月，用 <0 判断闰月。
    final lunar = Solar.fromYmd(now.year, now.month, now.day).getLunar();
    _lYear = e?.year ?? lunar.getYear();
    _lMonth = e?.month ?? lunar.getMonth().abs();
    _lDay = e?.day ?? lunar.getDay();
    _lLeap = e?.isLeap ?? lunar.getMonth() < 0;

    _type = e?.type ?? BirthdayType.gregorian;

    // 提醒配置：编辑时读已有值，新增默认 9:00 + 提前3天提醒。
    _remindHour = e?.remindHour ?? 9;
    _remindMinute = e?.remindMinute ?? 0;
    _notify3DaysBefore = e?.notify3DaysBefore ?? true;
    _avatarPath = e?.avatarPath;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? '编辑生日' : '新增生日'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: _buildAvatarField()),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                autofocus: !_isEdit,
                decoration: const InputDecoration(
                  labelText: '姓名 *',
                  hintText: '例如：妈妈',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请输入姓名' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _remarkCtrl,
                decoration: const InputDecoration(
                  labelText: '备注（选填）',
                  hintText: '例如：老家习俗按农历过',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // 生日类型：公历 / 农历 单选
              SegmentedButton<BirthdayType>(
                segments: const [
                  ButtonSegment(
                    value: BirthdayType.gregorian,
                    label: Text('公历生日'),
                    icon: Icon(Icons.calendar_today),
                  ),
                  ButtonSegment(
                    value: BirthdayType.lunar,
                    label: Text('农历生日'),
                    icon: Icon(Icons.circle_outlined),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 16),
              _buildDateField(),
              const SizedBox(height: 16),
              _buildRemindTimeField(),
              const SizedBox(height: 8),
              _buildRemind3DaysSwitch(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }

  /// 日期选择入口：展示当前所选日期，点击弹出对应日历。
  Widget _buildDateField() {
    final text = _type == BirthdayType.gregorian
        ? '$_gYear 年 $_gMonth 月 $_gDay 日'
        : '$_lYear 年 ${_lLeap ? '闰' : ''}${lunarMonthNameOf(_lMonth)}'
            '${lunarDayNameOf(_lDay)}';

    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: '生日日期 *',
          border: OutlineInputBorder(),
        ),
        child: Row(
          children: [
            Icon(
              _type == BirthdayType.gregorian
                  ? Icons.calendar_today
                  : Icons.circle_outlined,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(text, style: const TextStyle(fontSize: 16)),
            const Spacer(),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    if (_type == BirthdayType.gregorian) {
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime(_gYear, _gMonth, _gDay),
        firstDate: DateTime(1900),
        lastDate: DateTime(2100),
      );
      if (picked != null) {
        setState(() {
          _gYear = picked.year;
          _gMonth = picked.month;
          _gDay = picked.day;
        });
      }
    } else {
      await _pickLunarDate();
    }
  }

  /// 头像选择：圆形头像，点击从相册选图；有头像时长按删除。
  Widget _buildAvatarField() {
    final hasAvatar = _avatarPath != null && File(_avatarPath!).existsSync();
    return GestureDetector(
      onTap: _pickAvatar,
      onLongPress: hasAvatar
          ? () => setState(() => _avatarPath = null)
          : null,
      child: CircleAvatar(
        radius: 40,
        backgroundColor: Colors.grey.shade200,
        backgroundImage: hasAvatar ? FileImage(File(_avatarPath!)) : null,
        child: hasAvatar
            ? null
            : const Icon(Icons.add_a_photo, size: 32, color: Colors.grey),
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null) return;

    // 选完图后弹出裁剪界面
    final croppedPath = await _showCropDialog(picked.path);
    if (croppedPath != null) {
      setState(() => _avatarPath = croppedPath);
    }
  }

  /// 弹出裁剪界面，返回裁剪后的文件路径。
  Future<String?> _showCropDialog(String imagePath) async {
    final data = await File(imagePath).readAsBytes();
    final controller = CropController();
    Uint8List? result;

    await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('裁剪头像', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            SizedBox(
              height: 300,
              child: Crop(
                image: data,
                controller: controller,
                aspectRatio: 1, // 1:1 方形
                onCropped: (cropped) {
                  if (cropped is CropSuccess) {
                    result = cropped.croppedImage;
                  }
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
              ),
            ),
            OverflowBar(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => controller.crop(),
                  child: const Text('确定'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (result == null) return null;

    // 保存裁剪后的图片到临时文件
    final tempDir = Directory.systemTemp;
    final tempFile = File('${tempDir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await tempFile.writeAsBytes(result!);
    return tempFile.path;
  }

  /// 提醒时间选择入口：展示当前 HH:MM，点击弹出系统时间选择器。
  Widget _buildRemindTimeField() {
    final hh = _remindHour.toString().padLeft(2, '0');
    final mm = _remindMinute.toString().padLeft(2, '0');
    return InkWell(
      onTap: _pickRemindTime,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: '当天提醒时间',
          border: OutlineInputBorder(),
        ),
        child: Row(
          children: [
            const Icon(Icons.access_time, size: 20),
            const SizedBox(width: 8),
            Text('$hh:$mm', style: const TextStyle(fontSize: 16)),
            const Spacer(),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  Future<void> _pickRemindTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _remindHour, minute: _remindMinute),
    );
    if (picked != null) {
      setState(() {
        _remindHour = picked.hour;
        _remindMinute = picked.minute;
      });
    }
  }

  /// 是否提前 3 天提醒的开关。
  Widget _buildRemind3DaysSwitch() {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('提前 3 天也提醒'),
      subtitle: const Text('生日前 3 天的同一时间再提醒一次'),
      value: _notify3DaysBefore,
      onChanged: (v) => setState(() => _notify3DaysBefore = v),
    );
  }

  Future<void> _pickLunarDate() async {
    var selection = LunarSelection(_lYear, _lMonth, _lDay, isLeap: _lLeap);
    final picked = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择农历日期'),
        content: StatefulBuilder(
          builder: (ctx, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${selection.year} 年 ${selection.monthName}${selection.dayName}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              LunarDatePicker(
                initialYear: selection.year,
                initialMonth: selection.month,
                initialDay: selection.day,
                initialIsLeap: selection.isLeap,
                onChanged: (s) => setDialogState(() => selection = s),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (picked == true) {
      setState(() {
        _lYear = selection.year;
        _lMonth = selection.month;
        _lDay = selection.day;
        _lLeap = selection.isLeap;
      });
    }
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final entry = _buildEntry();
    Navigator.of(context).pop(entry);
  }

  BirthdayEntry _buildEntry() {
    final name = _nameCtrl.text.trim();
    final remark = _remarkCtrl.text.trim();
    final isGregorian = _type == BirthdayType.gregorian;
    return BirthdayEntry(
      id: widget.existing?.id ?? BirthdayRepository.generateId(),
      name: name,
      remark: remark.isEmpty ? null : remark,
      type: _type,
      year: isGregorian ? _gYear : _lYear,
      month: isGregorian ? _gMonth : _lMonth,
      day: isGregorian ? _gDay : _lDay,
      isLeap: isGregorian ? false : _lLeap,
      remindHour: _remindHour,
      remindMinute: _remindMinute,
      notify3DaysBefore: _notify3DaysBefore,
      avatarPath: _avatarPath,
    );
  }
}
