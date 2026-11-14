import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart'
    show Crop, CropController, CropSuccess;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lunar/lunar.dart';
import 'package:path_provider/path_provider.dart';

import '../data/birthday_repository.dart';
import '../models/birthday_entry.dart';
import '../models/birthday_type.dart';
import '../services/image_compress_service.dart';
import '../theme/app_colors.dart';
import '../utils/file_util.dart';
import 'custom_date_picker.dart';
import 'custom_time_picker.dart';
import 'lunar_date_picker.dart';

/// 新增 / 编辑生日页面。
class BirthdayEditDialog extends StatefulWidget {
  /// 头像长边上限：头像最大显示约 96dp，512 已足够清晰
  static const int avatarMaxDimension = 512;

  /// 头像 JPEG 质量
  static const int avatarJpegQuality = 80;

  final BirthdayEntry? existing;

  const BirthdayEditDialog({super.key, this.existing});

  @override
  State<BirthdayEditDialog> createState() => _BirthdayEditDialogState();
}

class _BirthdayEditDialogState extends State<BirthdayEditDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _remarkCtrl;

  late BirthdayType _type;

  late int _remindHour;
  late int _remindMinute;
  late bool _notify3DaysBefore;

  String? _avatarPath;
  final _picker = ImagePicker();

  /// 打开页面时已有的头像（取消编辑时不能误删）
  String? _initialAvatarPath;

  /// 是否点了「保存」把结果交出去；没交出去时本次新裁的头像要清理
  bool _submitted = false;

  late int _gYear, _gMonth, _gDay;
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

    _gYear = e?.year ?? now.year;
    _gMonth = e?.month ?? now.month;
    _gDay = e?.day ?? now.day;

    final lunar = Solar.fromYmd(now.year, now.month, now.day).getLunar();
    _lYear = e?.year ?? lunar.getYear();
    _lMonth = e?.month ?? lunar.getMonth().abs();
    _lDay = e?.day ?? lunar.getDay();
    _lLeap = e?.isLeap ?? lunar.getMonth() < 0;

    _type = e?.type ?? BirthdayType.gregorian;

    _remindHour = e?.remindHour ?? 9;
    _remindMinute = e?.remindMinute ?? 0;
    _notify3DaysBefore = e?.notify3DaysBefore ?? false;
    _avatarPath = e?.avatarPath;
    _initialAvatarPath = e?.avatarPath;

    // 页面打开后主动收起键盘，避免自动弹出
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).unfocus();
      }
    });
  }

  @override
  void dispose() {
    // 没保存就退出：本次新裁的头像没人接手，删掉避免成为孤儿文件
    final path = _avatarPath;
    if (!_submitted &&
        path != null &&
        path.isNotEmpty &&
        path != _initialAvatarPath) {
      unawaited(deleteFileQuietly(path));
    }
    _nameCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _isEdit ? '编辑生日' : '新增生日',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 头像
                Center(child: _buildAvatarField()),
                const SizedBox(height: 28),
                // 姓名
                _FieldLabel(text: '姓名', required: true),
                const SizedBox(height: 10),
                _buildNameField(),
                const SizedBox(height: 24),
                // 类型切换
                _buildTypeSwitch(),
                const SizedBox(height: 24),
                // 出生日期
                _FieldLabel(text: '出生日期', required: true),
                const SizedBox(height: 10),
                _buildDateField(),
                const SizedBox(height: 20),
                // 提醒时间
                _FieldLabel(text: '提醒时间', required: true),
                const SizedBox(height: 10),
                _buildRemindTimeField(),
                const SizedBox(height: 20),
                // 备注
                _FieldLabel(text: '备注（选填）'),
                const SizedBox(height: 10),
                _buildRemarkField(),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ========== 头像 ==========
  Widget _buildAvatarField() {
    final path = _avatarPath;
    final hasAvatar = path != null && path.isNotEmpty;
    return GestureDetector(
      onTap: _pickAvatar,
      // 长按清空头像；文件读不到时同样按「无头像」处理
      onLongPress: hasAvatar ? () => setState(() => _avatarPath = null) : null,
      child: Container(
        width: 110,
        height: 110,
        decoration: const BoxDecoration(
          color: AppColors.bgLight,
          shape: BoxShape.circle,
        ),
        child: hasAvatar
            ? ClipOval(
                child: Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.add_a_photo,
                    size: 40,
                    color: AppColors.textPlaceholder,
                  ),
                ),
              )
            : const Icon(
                Icons.add_a_photo,
                size: 40,
                color: AppColors.textPlaceholder,
              ),
      ),
    );
  }

  /// 彻底收起键盘（防止 Dialog 关闭后焦点恢复）
  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  Future<void> _pickAvatar() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null) return;

    final croppedPath = await _showCropDialog(picked.path);
    if (croppedPath != null) {
      setState(() => _avatarPath = croppedPath);
    }
    // 彻底收起键盘
    _dismissKeyboard();
  }

  Future<String?> _showCropDialog(String imagePath) async {
    final data = await File(imagePath).readAsBytes();
    if (!mounted) return null;
    final controller = CropController();
    Uint8List? result;

    await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '裁剪头像',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(
              height: 320,
              child: Crop(
                image: data,
                controller: controller,
                aspectRatio: 1,
                onCropped: (cropped) {
                  if (cropped is CropSuccess) {
                    result = cropped.croppedImage;
                  }
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => controller.crop(),
                    child: const Text('确定'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (result == null) return null;

    // 保存到 App 私有文档目录，系统不会清理
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final avatarDir = Directory('${appDir.path}/avatars');
      if (!await avatarDir.exists()) {
        await avatarDir.create(recursive: true);
      }
      // 裁剪结果是内存字节，先压缩再落盘（头像最大显示不到 100dp，512 足够）
      Uint8List bytes = result!;
      try {
        bytes = await ImageCompressService.compressBytes(
          bytes,
          maxDimension: BirthdayEditDialog.avatarMaxDimension,
          quality: BirthdayEditDialog.avatarJpegQuality,
        );
      } catch (e) {
        debugPrint('头像压缩失败，保留裁剪原图: $e');
      }
      final avatarFile = await ImageCompressService.writeBytes(
        bytes,
        dir: avatarDir,
        prefix: 'avatar_',
      );
      debugPrint('头像已保存到: $avatarFile');
      return avatarFile;
    } catch (e) {
      debugPrint('头像保存失败: $e');
      return null;
    }
  }

  // ========== 输入框 ==========
  Widget _buildNameField() {
    return TextFormField(
      controller: _nameCtrl,
      style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
      decoration: _inputDecoration('请输入姓名'),
      validator: (v) => (v == null || v.trim().isEmpty) ? '请输入姓名' : null,
    );
  }

  Widget _buildRemarkField() {
    return TextFormField(
      controller: _remarkCtrl,
      style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
      decoration: _inputDecoration('请输入备注（选填）').copyWith(counterText: ''),
      maxLines: 3,
      minLines: 2,
      maxLength: 200,
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: AppColors.textPlaceholder,
        fontSize: 16,
      ),
      filled: true,
      fillColor: AppColors.bgCard,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 1),
      ),
    );
  }

  // ========== 类型切换 ==========
  Widget _buildTypeSwitch() {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.bgLight,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _type = BirthdayType.gregorian),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: _type == BirthdayType.gregorian
                      ? AppColors.primaryLight
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(26),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check,
                      size: 20,
                      color: _type == BirthdayType.gregorian
                          ? AppColors.primary
                          : Colors.transparent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '公历生日',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _type == BirthdayType.gregorian
                            ? AppColors.primary
                            : AppColors.textBody,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _type = BirthdayType.lunar),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: _type == BirthdayType.lunar
                      ? AppColors.primaryLight
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(26),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle_outlined,
                      size: 20,
                      color: _type == BirthdayType.lunar
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '农历生日',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _type == BirthdayType.lunar
                            ? AppColors.primary
                            : AppColors.textBody,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========== 日期选择 ==========
  Widget _buildDateField() {
    final text = _type == BirthdayType.gregorian
        ? '$_gYear 年 $_gMonth 月 $_gDay 日'
        : '$_lYear 年 ${_lLeap ? '闰' : ''}${lunarMonthNameOf(_lMonth)}'
              '${lunarDayNameOf(_lDay)}';

    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        ),
        child: Row(
          children: [
            Icon(
              _type == BirthdayType.gregorian
                  ? Icons.calendar_today
                  : Icons.circle,
              size: 22,
              color: AppColors.iconGray,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 16, color: AppColors.textBody),
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: AppColors.iconGray),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    if (_type == BirthdayType.gregorian) {
      final picked = await CustomDatePicker.show(
        context,
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
    // 收起键盘
    _dismissKeyboard();
  }

  Future<void> _pickLunarDate() async {
    var selection = LunarSelection(_lYear, _lMonth, _lDay, isLeap: _lLeap);
    final picked = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: StatefulBuilder(
          builder: (ctx, setDialogState) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题
                const Text(
                  '选择农历日期',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                // 当前选中日期
                Center(
                  child: Text(
                    '${selection.year} 年 ${selection.monthName}${selection.dayName}',
                    style: const TextStyle(
                      fontSize: 22,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // 滚轮
                LunarDatePicker(
                  initialYear: selection.year,
                  initialMonth: selection.month,
                  initialDay: selection.day,
                  initialIsLeap: selection.isLeap,
                  onChanged: (s) => setDialogState(() => selection = s),
                ),
                const SizedBox(height: 20),
                // 底部按钮
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: const Text(
                        '取消',
                        style: TextStyle(
                          fontSize: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      child: const Text(
                        '确定',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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

  // ========== 提醒时间 ==========
  Widget _buildRemindTimeField() {
    final hh = _remindHour.toString().padLeft(2, '0');
    final mm = _remindMinute.toString().padLeft(2, '0');

    return InkWell(
      onTap: _pickRemindTime,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.access_time_filled,
              size: 22,
              color: AppColors.iconGray,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$hh:$mm',
                style: const TextStyle(fontSize: 16, color: AppColors.textBody),
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: AppColors.iconGray),
          ],
        ),
      ),
    );
  }

  Future<void> _pickRemindTime() async {
    final picked = await CustomTimePicker.show(
      context,
      initialTime: TimeOfDay(hour: _remindHour, minute: _remindMinute),
    );
    if (picked != null) {
      setState(() {
        _remindHour = picked.hour;
        _remindMinute = picked.minute;
      });
    }
    // 收起键盘
    _dismissKeyboard();
  }

  // ========== 底部按钮 ==========
  Widget _buildBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.bgLight, width: 1)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Text(
                '取消',
                style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Text(
                '保存',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========== 保存 ==========
  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    _submitted = true;
    final entry = _buildEntry();
    // 换了头像或清掉了头像：旧文件没人引用了，后台删掉，避免越攒越多
    final oldAvatar = widget.existing?.avatarPath;
    if (oldAvatar != null && oldAvatar.isNotEmpty && oldAvatar != _avatarPath) {
      unawaited(deleteFileQuietly(oldAvatar));
    }
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

/// 表单字段标签。
class _FieldLabel extends StatelessWidget {
  final String text;
  final bool required;

  const _FieldLabel({required this.text, this.required = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textBody,
          ),
        ),
        if (required)
          const Text(
            ' *',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}
