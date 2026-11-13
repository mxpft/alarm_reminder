import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../services/diary_image_service.dart';
import '../theme/app_colors.dart';

/// 今日状态（心情 / 天气 / 气温 / 位置 / 图片）。
class DiaryStatus {
  final String moodEmoji;
  final String moodDesc;
  final String weatherEmoji;
  final String weatherDesc;
  final String temp;
  final String location;
  final String? imagePath;

  const DiaryStatus({
    required this.moodEmoji,
    required this.moodDesc,
    required this.weatherEmoji,
    required this.weatherDesc,
    required this.temp,
    required this.location,
    this.imagePath,
  });
}

/// 点击日记页右上角「+」弹出的状态填写面板（从下往上弹，与密码管理表单一致）。
class DiaryStatusSheet extends StatefulWidget {
  const DiaryStatusSheet({super.key, this.initial});

  final DiaryStatus? initial;

  @override
  State<DiaryStatusSheet> createState() => _DiaryStatusSheetState();
}

class _DiaryStatusSheetState extends State<DiaryStatusSheet> {
  // 设计稿设计色（M3 token）
  static const Color _fieldBg = Color(0xFFEFF4FF);
  static const Color _outline = Color(0xFF727785);
  static const Color _onSurface = Color(0xFF0B1C30);
  static const Color _onSurfaceVariant = Color(0xFF424754);
  static const Color _surfaceContainer = Color(0xFFE5EEFF);

  final TextEditingController _moodDescCtrl = TextEditingController();
  final TextEditingController _weatherDescCtrl = TextEditingController();
  final TextEditingController _tempCtrl = TextEditingController();
  final TextEditingController _locationCtrl = TextEditingController();

  // 默认不预选：用户不点就是「未选」，避免没填状态时被塞进默认表情
  String _moodEmoji = '';
  String _weatherEmoji = '';
  String? _imagePath;

  /// 打开面板时就已经带着的图片（来自上一次选择），关闭时不能误删
  String? _initialImagePath;

  /// 是否点了「保存」把结果交出去；没交出去时本次新选的图片要清理掉
  bool _submitted = false;

  /// 心情可选 emoji（再点一次已选的即取消，回到占位图标）
  static const List<Map<String, String>> _moods = [
    {'emoji': '😊', 'label': '开心'},
    {'emoji': '😄', 'label': '愉快'},
    {'emoji': '🥳', 'label': '兴奋'},
    {'emoji': '🥰', 'label': '幸福'},
    {'emoji': '😌', 'label': '平静'},
    {'emoji': '🤔', 'label': '沉思'},
    {'emoji': '😐', 'label': '一般'},
    {'emoji': '🥱', 'label': '无聊'},
    {'emoji': '😴', 'label': '疲惫'},
    {'emoji': '😢', 'label': '难过'},
    {'emoji': '😭', 'label': '委屈'},
    {'emoji': '😤', 'label': '生气'},
    {'emoji': '😱', 'label': '焦虑'},
    {'emoji': '🤩', 'label': '惊喜'},
    {'emoji': '😎', 'label': '得意'},
    {'emoji': '🥲', 'label': '心酸'},
  ];

  /// 天气可选 emoji（再点一次已选的即取消，回到占位图标）
  static const List<Map<String, String>> _weathers = [
    {'emoji': '☀️', 'label': '晴'},
    {'emoji': '🌤️', 'label': '多云'},
    {'emoji': '⛅', 'label': '阴晴'},
    {'emoji': '☁️', 'label': '阴'},
    {'emoji': '🌧️', 'label': '雨'},
    {'emoji': '🌦️', 'label': '阵雨'},
    {'emoji': '⛈️', 'label': '雷雨'},
    {'emoji': '❄️', 'label': '雪'},
    {'emoji': '🌫️', 'label': '雾'},
    {'emoji': '🌬️', 'label': '风'},
    {'emoji': '🌈', 'label': '彩虹'},
    {'emoji': '🌪️', 'label': '大风'},
  ];

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      _moodEmoji = init.moodEmoji;
      _weatherEmoji = init.weatherEmoji;
      _moodDescCtrl.text = init.moodDesc;
      _weatherDescCtrl.text = init.weatherDesc;
      _tempCtrl.text = init.temp;
      _locationCtrl.text = init.location;
      _imagePath = init.imagePath;
      _initialImagePath = init.imagePath;
    }
  }

  @override
  void dispose() {
    // 没点保存就关掉面板：本次新选的图片没人接手，删掉避免越攒越多
    final path = _imagePath;
    if (!_submitted &&
        path != null &&
        path.isNotEmpty &&
        path != _initialImagePath &&
        DiaryImageService.isPending(path)) {
      _deleteFileQuietly(path);
    }
    _moodDescCtrl.dispose();
    _weatherDescCtrl.dispose();
    _tempCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    _submitted = true;
    Navigator.of(context).pop(
      DiaryStatus(
        moodEmoji: _moodEmoji,
        moodDesc: _moodDescCtrl.text.trim(),
        weatherEmoji: _weatherEmoji,
        weatherDesc: _weatherDescCtrl.text.trim(),
        temp: _tempCtrl.text.trim(),
        location: _locationCtrl.text.trim(),
        imagePath: _imagePath,
      ),
    );
  }

  /// 从相册选图，先落一份「待压缩」工作副本，真正记录时再压缩入库。
  Future<void> _pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${appDir.path}/diary_images');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final dest = File(
        '${dir.path}/${DiaryImageService.pendingPrefix}'
        '${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await dest.writeAsBytes(await File(picked.path).readAsBytes());
      if (!mounted) return;
      final oldPath = _imagePath;
      setState(() => _imagePath = dest.path);
      if (oldPath != null && oldPath.isNotEmpty && oldPath != dest.path) {
        _deleteFileQuietly(oldPath);
      }
    } catch (e) {
      debugPrint('日记图片保存失败: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('图片添加失败，请重试')));
    }
  }

  /// 移除图片时同步清掉工作副本，避免留下孤儿文件
  void _deleteFileQuietly(String path) {
    unawaited(() async {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint('清理待压缩图片失败: $e');
      }
    }());
  }

  /// emoji 选择面板：点一下选中并回填，再点同一个即取消（回到占位图标）
  Future<void> _pickEmoji({
    required String title,
    required List<Map<String, String>> options,
    required String current,
    required ValueChanged<String> onPick,
  }) async {
    final picked = await showDialog<String>(
      context: context,
      barrierColor: const Color(0xFF213145).withValues(alpha: 0.40),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _onSurface,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '点一下选中，再点一次取消',
                style: TextStyle(fontSize: 11, color: _outline),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                ),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final o in options) _emojiOption(ctx, o, current),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    // 点的就是当前选中的那个 → 回传空串，表示取消选中
    onPick(picked == current ? '' : picked);
  }

  /// 单个 emoji 选项：选中态描一圈主题色边框
  Widget _emojiOption(
    BuildContext ctx,
    Map<String, String> option,
    String current,
  ) {
    final emoji = option['emoji']!;
    final selected = current.isNotEmpty && emoji == current;
    return GestureDetector(
      key: ValueKey('diary-emoji-option-$emoji'),
      onTap: () => Navigator.of(ctx).pop(emoji),
      child: Container(
        width: 52,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFD8E2FF).withValues(alpha: 0.45)
              : _fieldBg,
          borderRadius: BorderRadius.circular(10),
          border: selected
              ? Border.all(color: AppColors.primary, width: 1.5)
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(option['emoji']!, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 2),
            Text(
              option['label']!,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.primary : _onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: screenHeight * 0.9),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + safeBottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 心情与感受
                _label('心情与感受'),
                const SizedBox(height: 6),
                _buildEmojiInput(
                  field: 'mood',
                  emoji: _moodEmoji,
                  controller: _moodDescCtrl,
                  hint: '此刻心情如何',
                  inputPadding: 10,
                  onTapEmoji: () => _pickEmoji(
                    title: '所有美好如约而至',
                    options: _moods,
                    current: _moodEmoji,
                    onPick: (e) => setState(() => _moodEmoji = e),
                  ),
                ),
                const SizedBox(height: 14),
                // 天气与描述 + 气温
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('天气与描述'),
                          const SizedBox(height: 6),
                          _buildEmojiInput(
                            field: 'weather',
                            emoji: _weatherEmoji,
                            controller: _weatherDescCtrl,
                            hint: '惠风和畅',
                            inputPadding: 8,
                            onTapEmoji: () => _pickEmoji(
                              title: '选择天气',
                              options: _weathers,
                              current: _weatherEmoji,
                              onPick: (e) => setState(() => _weatherEmoji = e),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('气温'),
                          const SizedBox(height: 6),
                          Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: _fieldBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _tempCtrl,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: _onSurface,
                                    ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      filled: false,
                                      fillColor: Colors.transparent,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                      hintText: '21',
                                      hintStyle: TextStyle(
                                        fontSize: 14,
                                        color: _outline,
                                      ),
                                    ),
                                  ),
                                ),
                                const Text(
                                  '°C',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // 地理位置
                _label('地理位置'),
                const SizedBox(height: 6),
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: _fieldBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      const Icon(Icons.location_on, size: 18, color: _outline),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: _locationCtrl,
                          style: const TextStyle(
                            fontSize: 14,
                            color: _onSurface,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: false,
                            fillColor: Colors.transparent,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            hintText: '当下身在何处',
                            hintStyle: const TextStyle(
                              fontSize: 14,
                              color: _outline,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // 图片（可选）
                _label('图片'),
                const SizedBox(height: 6),
                _buildImageField(),
                const SizedBox(height: 20),
                // 取消 / 确定
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _surfaceContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            '取消',
                            style: TextStyle(
                              fontSize: 14,
                              color: _onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: _submit,
                        child: Container(
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: const Text(
                            '确定',
                            style: TextStyle(fontSize: 14, color: Colors.white),
                          ),
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
  }

  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        height: 1.4,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.02,
        color: _onSurfaceVariant,
      ),
    );
  }

  /// 图片：未选时是「添加图片」按钮，已选时显示缩略图 + 删除
  Widget _buildImageField() {
    if (_imagePath == null) {
      return GestureDetector(
        onTap: _pickImage,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _fieldBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_photo_alternate_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              SizedBox(width: 6),
              Text(
                '添加图片',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF424754),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Row(
      children: [
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(_imagePath!),
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 64,
                  height: 64,
                  color: _fieldBg,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    size: 20,
                    color: _outline,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: () {
                  final removed = _imagePath;
                  if (removed != null && removed.isNotEmpty) {
                    _deleteFileQuietly(removed);
                  }
                  setState(() => _imagePath = null);
                },
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF213145).withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 12, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: _pickImage,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _fieldBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '更换图片',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// emoji 按钮 + 文本输入（整体同一底色）
  Widget _buildEmojiInput({
    required String field,
    required String emoji,
    required TextEditingController controller,
    required String hint,
    required double inputPadding,
    required VoidCallback onTapEmoji,
  }) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: _fieldBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onTapEmoji,
            child: Container(
              key: ValueKey('diary-$field-emoji-btn'),
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
              child: emoji.isEmpty
                  ? Icon(
                      // 心情用表情占位，天气用太阳占位，一眼区分两个输入项
                      field == 'weather'
                          ? Icons.wb_sunny_outlined
                          : Icons.add_reaction_outlined,
                      size: 20,
                      color: _outline,
                    )
                  : Text(emoji, style: const TextStyle(fontSize: 20)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: inputPadding),
              child: TextField(
                controller: controller,
                style: const TextStyle(fontSize: 14, color: _onSurface),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: hint,
                  hintStyle: const TextStyle(fontSize: 14, color: _outline),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
