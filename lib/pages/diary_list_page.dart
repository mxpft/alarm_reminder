import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/diary_repository.dart';
import '../models/diary_entry.dart';
import '../services/diary_export_service.dart';
import '../services/diary_image_service.dart';
import '../theme/app_colors.dart';
import '../widgets/diary_status_sheet.dart';

/// 一句话日记页面（含今日记录卡片 + 往昔回忆时间线）。
class DiaryListPage extends StatefulWidget {
  final DiaryRepository repo;

  const DiaryListPage({super.key, required this.repo});

  @override
  State<DiaryListPage> createState() => _DiaryListPageState();
}

class _DiaryListPageState extends State<DiaryListPage> {
  final TextEditingController _textCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  /// 今日状态（点击右上角「+」填写，记录时随日记一起保存）
  DiaryStatus? _todayStatus;

  /// 当前查看的年份
  int _year = DateTime.now().year;

  /// 用户手动展开/收起的月份
  final Set<String> _touchedKeys = {};
  final Set<String> _expandedKeys = {};

  /// 本月刚选过的颜色缓存（key 为 `年-月`，value 为 ARGB；null 表示恢复默认），
  /// 让界面在落库前就能立即换色
  final Map<String, int?> _monthColorOverrides = {};

  /// 正在编辑的日记（null 表示当前是「记录」新日记）
  DiaryEntry? _editingEntry;

  /// 编辑态下是否已把该条日记的图片标记删除（保存时才真正落库/删文件）
  bool _editingImageRemoved = false;

  /// 输入卡片的锚点，双击某条日记后据此把输入区滚回可视范围
  final GlobalKey _composeAnchor = GlobalKey();

  // 设计稿设计色（M3 token）
  static const Color _surfaceContainerLow = Color(0xFFEFF4FF);
  static const Color _surfaceContainer = Color(0xFFE5EEFF);
  static const Color _outlineVariant = Color(0xFFC2C6D6);
  static const Color _outline = Color(0xFF727785);
  static const Color _onSurfaceVariant = Color(0xFF424754);
  static const Color _onSurface = Color(0xFF0B1C30);
  static const Color _primaryFixed = Color(0xFFD8E2FF);
  static const Color _onPrimaryFixedVariant = Color(0xFF004395);
  static const Color _tertiary = Color(0xFFB10E6B);

  /// 浅色胶囊底：年度切换按钮 / 月份篇数 badge
  static const Color _chipBg = Color(0xFFE9EFFF);

  /// 浅色心情胶囊底（比 primaryFixed 更淡）
  static const Color _moodPillBg = Color(0xFFEEF3FF);

  /// 12 个月对应的时间线默认色（1 月 → 12 月，整体偏柔和不刺眼）
  static const List<Color> _monthColors = [
    Color(0xFF6B8ADA), // 1 月 雾蓝紫
    Color(0xFF5E9FDE), // 2 月 天蓝
    Color(0xFF56B295), // 3 月 青绿
    Color(0xFFE08DB2), // 4 月 玫粉
    Color(0xFFE4AE62), // 5 月 琥珀
    Color(0xFFE28B7D), // 6 月 珊瑚
    Color(0xFFD67171), // 7 月 暖红
    Color(0xFFC8839B), // 8 月 豆沙
    Color(0xFFDF9464), // 9 月 橙
    Color(0xFFCE9E58), // 10 月 金
    Color(0xFFCB6B80), // 11 月 莓红
    Color(0xFF7881D4), // 12 月 靛蓝
  ];

  /// 颜色选择器候选色板（16 色，覆盖冷暖/深浅）
  static const List<Color> _paletteColors = [
    Color(0xFF6B8ADA),
    Color(0xFF5E9FDE),
    Color(0xFF56B295),
    Color(0xFF4AA8BC),
    Color(0xFFE08DB2),
    Color(0xFFE4AE62),
    Color(0xFFE28B7D),
    Color(0xFFD67171),
    Color(0xFFC8839B),
    Color(0xFFDF9464),
    Color(0xFFCE9E58),
    Color(0xFFCB6B80),
    Color(0xFF7881D4),
    Color(0xFF8B9AAA),
    Color(0xFF7FA876),
    Color(0xFF9E86C9),
  ];

  /// 该月的实际时间线颜色：优先用户自定义，否则用默认月度色
  Color _monthColor(int month) {
    final custom = _customMonthColor(_year, month);
    if (custom != null) return custom;
    return _monthColors[(month - 1).clamp(0, 11)];
  }

  Color? _customMonthColor(int year, int month) {
    final key = DiaryRepository.monthColorKey(year, month);
    if (_monthColorOverrides.containsKey(key)) {
      final cached = _monthColorOverrides[key];
      return cached == null ? null : Color(cached);
    }
    final value = widget.repo.monthColorValue(year, month);
    return value == null ? null : Color(value);
  }

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  /// 只用于输入框边框高亮，字数统计走 ValueListenableBuilder 局部刷新，
  /// 避免每敲一个字都重建整页日记卡片（图片会被反复解码）
  void _onFocusChanged() => setState(() {});

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  /// 日期与星期根据系统自动带出：今天 · 10月24日 星期二
  String get _todayLabel {
    final now = DateTime.now();
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return '今天 · ${now.month}月${now.day}日 星期${weekdays[now.weekday - 1]}';
  }

  /// 编辑目标的时间描述：「11月13日 00:05」
  String _editTargetLabel(DiaryEntry e) {
    final dt = e.dateTime;
    final hm =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '${dt.month}月${dt.day}日 $hm';
  }

  /// 顶部输入卡里展示的图片路径：编辑态取被编辑条目，记录态取今日状态
  String? _composeImagePath(DiaryEntry? editing) {
    if (editing != null) {
      if (_editingImageRemoved) return null;
      final p = editing.imagePath;
      if (p != null && p.isNotEmpty) return p;
      return null;
    }
    return _todayStatus?.imagePath;
  }

  /// 顶部输入卡里展示的位置：编辑态取被编辑条目，记录态取今日状态
  String _composeLocation(DiaryEntry? editing) {
    final l = editing?.location;
    if (l != null && l.isNotEmpty) return l;
    return _todayStatus?.location ?? '';
  }

  /// 双击日记卡片：把这条内容填回输入框，按钮切成「编辑」
  void _startEdit(DiaryEntry entry) {
    if (_editingEntry?.id == entry.id) {
      _focusNode.requestFocus();
      return;
    }
    setState(() => _editingEntry = entry);
    _editingImageRemoved = false;
    _textCtrl.text = entry.content;
    _textCtrl.selection = TextSelection.collapsed(offset: entry.content.length);
    _focusNode.requestFocus();
    // 用户可能正滚在很下面的时间线，编辑态要把它带回顶部的输入框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _composeAnchor.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0,
        );
      }
    });
  }

  /// 退出编辑，回到「记录」新日记
  void _cancelEdit() {
    setState(() => _editingEntry = null);
    _editingImageRemoved = false;
    _textCtrl.clear();
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.repo.getByYear(_year);

    return Scaffold(
      backgroundColor: AppColors.bgPage,
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildComposeCard(context),
                  const SizedBox(height: 24),
                  _buildTimeline(entries),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部返回栏（高度 56，带底部细阴影）
  Widget _buildHeader(BuildContext context) {
    return Container(
      color: AppColors.bgPage,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(
                    Icons.arrow_back,
                    size: 24,
                    color: _onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 顶部记录卡片
  Widget _buildComposeCard(BuildContext context) {
    final editing = _editingEntry;
    return Container(
      key: _composeAnchor,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 日期行 + 新建按钮
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _todayLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: _onSurface,
                  ),
                ),
              ),
              // 编辑态只改正文，右上角「+」状态面板入口隐藏
              if (editing == null)
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _openStatusSheet,
                      child: const Icon(
                        Icons.add,
                        size: 18,
                        color: _onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // 编辑提示：正在改哪一条，随时可退出
          if (editing != null) ...[
            const SizedBox(height: 10),
            Container(
              key: const ValueKey('diary-editing-banner'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _chipBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.edit_outlined,
                    size: 14,
                    color: _onPrimaryFixedVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '正在编辑 ${_editTargetLabel(editing)} 的日记',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _onPrimaryFixedVariant,
                      ),
                    ),
                  ),
                  GestureDetector(
                    key: const ValueKey('diary-edit-cancel'),
                    onTap: _cancelEdit,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        '取消',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // 心情 / 天气标签（在「+」弹窗中维护，有内容才显示）
          if (_todayStatus != null && _statusHasPills(_todayStatus!)) ...[
            const SizedBox(height: 12),
            _buildStatusPills(_todayStatus!),
          ],
          const SizedBox(height: 12),
          // 输入框（聚焦时边框变主色，右下角字数统计）
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _focusNode.hasFocus
                    ? AppColors.primary
                    : _outlineVariant.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _textCtrl,
                  focusNode: _focusNode,
                  minLines: 3,
                  maxLines: 5,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: _onSurface,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: editing == null
                        ? '用一句话记录今天的见闻或闪光时刻...'
                        : '改一句话，把这条记录补完整...',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: _outlineVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // 字数统计独立成行、右对齐，位于文本下方，不与正文重叠
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _textCtrl,
                  builder: (context, value, _) => Align(
                    alignment: Alignment.centerRight,
                    child: IgnorePointer(
                      child: Text(
                        '${value.text.runes.length}',
                        key: const ValueKey('diary-compose-count'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _outline,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 图片缩略 / 位置标签 + 记录按钮
          Row(
            children: [
              // 编辑态：展示被编辑条目的图片/位置，图片可删除；记录态：展示今日状态
              if (_composeImagePath(editing) != null) ...[
                editing != null
                    ? _buildEditingThumb(_composeImagePath(editing)!)
                    : _buildThumb(_composeImagePath(editing)!),
                const SizedBox(width: 8),
              ],
              if (_composeLocation(editing).isNotEmpty)
                Flexible(child: _buildLocationTag(_composeLocation(editing))),
              const Spacer(),
              GestureDetector(
                key: const ValueKey('diary-save-btn'),
                onTap: _saveDiary,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        editing == null ? '记录' : '编辑',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.check, size: 16, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 面板里是否填了任何状态（都没有时不占位，避免空白 12dp 间距）
  bool _statusHasPills(DiaryStatus s) {
    return s.moodEmoji.trim().isNotEmpty ||
        s.moodDesc.isNotEmpty ||
        s.weatherEmoji.trim().isNotEmpty ||
        s.weatherDesc.isNotEmpty ||
        s.temp.isNotEmpty;
  }

  /// 心情 / 天气标签（各自按「有图标或有文字」独立判断，避免串味）
  Widget _buildStatusPills(DiaryStatus status) {
    final moodEmoji = status.moodEmoji.trim();
    final weatherEmoji = status.weatherEmoji.trim();
    final weatherText = [
      if (status.weatherDesc.isNotEmpty) status.weatherDesc,
      if (status.temp.isNotEmpty) '${status.temp}°C',
    ].join(' ');
    final hasMood = moodEmoji.isNotEmpty || status.moodDesc.isNotEmpty;
    final hasWeather = weatherEmoji.isNotEmpty || weatherText.isNotEmpty;

    return Wrap(
      key: const ValueKey('diary-status-pills'),
      spacing: 6,
      runSpacing: 6,
      children: [
        if (hasMood)
          Container(
            key: const ValueKey('diary-status-mood-pill'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: _moodPillBg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (moodEmoji.isNotEmpty)
                  Text(moodEmoji, style: const TextStyle(fontSize: 13)),
                if (status.moodDesc.isNotEmpty) ...[
                  if (moodEmoji.isNotEmpty) const SizedBox(width: 4),
                  Text(
                    status.moodDesc,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _onPrimaryFixedVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (hasWeather)
          Container(
            key: const ValueKey('diary-status-weather-pill'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _surfaceContainerLow,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (weatherEmoji.isNotEmpty)
                  Text(weatherEmoji, style: const TextStyle(fontSize: 13)),
                if (weatherEmoji.isNotEmpty && weatherText.isNotEmpty)
                  const SizedBox(width: 4),
                if (weatherText.isNotEmpty)
                  Text(
                    weatherText,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// 28×28 图片缩略，右上角带删除
  Widget _buildThumb(String path) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        key: const ValueKey('diary-status-thumb'),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(path),
              width: 28,
              height: 28,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 28,
                height: 28,
                color: _surfaceContainer,
                child: const Icon(
                  Icons.broken_image_outlined,
                  size: 14,
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
                final s = _todayStatus;
                if (s == null) return;
                final droppedPath = s.imagePath;
                if (droppedPath != null && droppedPath.isNotEmpty) {
                  unawaited(_deleteImageFile(droppedPath));
                }
                setState(() {
                  _todayStatus = DiaryStatus(
                    moodEmoji: s.moodEmoji,
                    moodDesc: s.moodDesc,
                    weatherEmoji: s.weatherEmoji,
                    weatherDesc: s.weatherDesc,
                    temp: s.temp,
                    location: s.location,
                    imagePath: null,
                  );
                });
              },
              child: Container(
                width: 14,
                height: 14,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF213145).withValues(alpha: 0.7),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(8),
                    bottomLeft: Radius.circular(8),
                  ),
                ),
                child: const Icon(Icons.close, size: 10, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 编辑态图片缩略：带删除角标；删除只是标记，保存时才真正删文件
  Widget _buildEditingThumb(String path) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        key: const ValueKey('diary-edit-thumb'),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(path),
              width: 28,
              height: 28,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 28,
                height: 28,
                color: _surfaceContainer,
                child: const Icon(
                  Icons.broken_image_outlined,
                  size: 14,
                  color: _outline,
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              onTap: () => setState(() => _editingImageRemoved = true),
              child: Container(
                width: 14,
                height: 14,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF213145).withValues(alpha: 0.7),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(8),
                    bottomLeft: Radius.circular(8),
                  ),
                ),
                child: const Icon(Icons.close, size: 10, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 位置标签
  Widget _buildLocationTag(String location) {
    return Container(
      key: const ValueKey('diary-status-location'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _primaryFixed.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_on, size: 14, color: AppColors.primary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              location,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 往昔回忆时间线
  Widget _buildTimeline(List<DiaryEntry> entries) {
    if (entries.isEmpty) return _buildEmptyTimeline();

    // 按月份分组（倒序）
    final months = <int, List<DiaryEntry>>{};
    for (final e in entries) {
      months.putIfAbsent(e.dateTime.month, () => []).add(e);
    }
    final monthKeys = months.keys.toList()..sort((a, b) => b.compareTo(a));
    // 最新月份（列表按时间倒序，第一条即最新）一次算好，供各月份头判断是否默认展开
    final latestMonth = entries.first.dateTime.month;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildYearHeader(entries.length),
        const SizedBox(height: 12),
        for (final m in monthKeys) ...[
          _buildMonthGroup(
            m,
            months[m]!,
            expanded: _isMonthExpanded(m, latestMonth: latestMonth),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 8),
        _buildTimelineFooter(),
      ],
    );
  }

  /// 头部：往昔回忆 + 年份切换 + 共 X 篇（导出按钮已移到年份弹框右上角）
  Widget _buildYearHeader(int total) {
    return Row(
      children: [
        const Icon(Icons.timeline, size: 20, color: AppColors.primary),
        const SizedBox(width: 4),
        const Text(
          '往昔回忆',
          style: TextStyle(
            fontSize: 18,
            height: 1.3,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: _onSurface,
          ),
        ),
        const SizedBox(width: 6),
        // 年份胶囊（点击弹年份选择）
        GestureDetector(
          onTap: _pickYear,
          child: Container(
            key: const ValueKey('diary-year-chip'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _chipBg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _outlineVariant.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$_year年度',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _onSurface,
                  ),
                ),
                const SizedBox(width: 2),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.keyboard_arrow_up,
                      size: 12,
                      color: _onSurfaceVariant,
                    ),
                    Icon(
                      Icons.keyboard_arrow_down,
                      size: 12,
                      color: _onSurfaceVariant,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        Text(
          '共 $total 篇',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _monthKey(int month) => '$_year-$month';

  /// 默认只展开该年最新的月份。
  /// [latestMonth] 由调用方一次算好传入，避免每个月份头都重读一遍数据库。
  bool _isMonthExpanded(int month, {int? latestMonth}) {
    final key = _monthKey(month);
    if (_touchedKeys.contains(key)) return _expandedKeys.contains(key);
    return latestMonth == month;
  }

  void _toggleMonth(int month) {
    final key = _monthKey(month);
    final entries = widget.repo.getByYear(_year);
    setState(() {
      final current = _isMonthExpanded(
        month,
        latestMonth: entries.isEmpty ? null : entries.first.dateTime.month,
      );
      _touchedKeys.add(key);
      if (current) {
        _expandedKeys.remove(key);
      } else {
        _expandedKeys.add(key);
      }
    });
  }

  /// 月份分组（可收起）
  Widget _buildMonthGroup(
    int month,
    List<DiaryEntry> entries, {
    required bool expanded,
  }) {
    final color = _monthColor(month);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _toggleMonth(month),
          child: Container(
            key: ValueKey('diary-month-header-$month'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              // 月度色极淡铺底：与圆点 / 日期同色系，但不抢注意力
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text(
                  '$_year·$month',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _onSurface,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  key: ValueKey('diary-month-count-$month'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _chipBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${entries.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _onSurfaceVariant,
                    ),
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.expand_more,
                    size: 20,
                    color: _onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  _buildEntryCard(
                    entries[i],
                    color,
                    isFirst: i == 0,
                    isLast: i == entries.length - 1,
                    isEditing: _editingEntry?.id == entries[i].id,
                  ),
                  if (i < entries.length - 1) const SizedBox(height: 16),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// 单条日记（左侧日期 + 圆点 + 右侧卡片）
  Widget _buildEntryCard(
    DiaryEntry entry,
    Color color, {
    required bool isFirst,
    required bool isLast,
    bool isEditing = false,
  }) {
    final dt = entry.dateTime;
    final dateText =
        '${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
    final timeText =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    final weatherEmoji = (entry.weatherEmoji ?? '').trim();
    final weatherText = [
      if ((entry.weatherDesc ?? '').isNotEmpty) entry.weatherDesc!,
      if ((entry.temp ?? '').isNotEmpty) '${entry.temp}°C',
    ].join(' ');

    // 天气只要有图标 / 描述 / 温度任一就展示；心情同理，二者互不顶替
    final hasWeather = weatherEmoji.isNotEmpty || weatherText.isNotEmpty;
    final hasMood =
        (entry.moodDesc ?? '').isNotEmpty ||
        (entry.moodEmoji ?? '').trim().isNotEmpty;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _confirmDelete(entry),
      // 双击卡片 → 内容回填到上方输入框，进入编辑态（长按仍是删除）
      onDoubleTap: () => _startEdit(entry),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 日期列（与右侧圆点留出间距，避免圆点压住日期数字）
          // 双击这块（日期 + 「今天/昨天」）→ 换这个月的时间轴配色
          GestureDetector(
            key: ValueKey('diary-entry-datecol-${entry.id}'),
            behavior: HitTestBehavior.opaque,
            onDoubleTap: () => _pickMonthColor(year: dt.year, month: dt.month),
            child: SizedBox(
              width: 46,
              child: Padding(
                padding: const EdgeInsets.only(right: 8, top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      dateText,
                      key: ValueKey('diary-entry-date-${entry.id}'),
                      style: TextStyle(
                        fontSize: 15,
                        height: 1,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _dayLabel(dt),
                      key: ValueKey('diary-entry-daylabel-${entry.id}'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 圆点 + 内容卡片（同一 Stack，竖线随卡片高度自适应，末条下方不再多出一截）
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 时间轴竖线：从圆点中心延伸到卡片底部；
                // 中间条目向下跨 16px 间距接住下一段，首条不向上、末条不向下延伸
                // 竖线只负责连接相邻圆点：首条从圆点中心起，末条收到圆点中心，
                // 首尾同一条（只有一条记录）时不画，避免圆点下方多出一截
                if (!(isFirst && isLast))
                  Positioned(
                    left: 5,
                    top: isFirst ? 19.5 : -16,
                    bottom: isLast ? null : -16,
                    height: isLast ? 35.5 : null,
                    child: Container(
                      key: ValueKey('diary-entry-line-${entry.id}'),
                      width: 1,
                      // 连线跟着该月主题色，比圆点淡一档，保持从属感
                      color: color.withValues(alpha: 0.38),
                    ),
                  ),
                Positioned(
                  top: 14,
                  left: 0,
                  child: Container(
                    key: ValueKey('diary-entry-dot-${entry.id}'),
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.bgPage,
                          spreadRadius: 1,
                          blurRadius: 0,
                        ),
                      ],
                    ),
                  ),
                ),
                // 内容卡片
                Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Container(
                    key: ValueKey('diary-entry-card-${entry.id}'),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      // 编辑中的那条描一圈月度色，提醒正在改哪条
                      border: isEditing
                          ? Border.all(
                              color: color.withValues(alpha: 0.55),
                              width: 1.5,
                            )
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              timeText,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _onSurface,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              // 心情/天气单行排列，超宽横向滑动；右侧用渐变淡出，
                              // 让溢出内容自然隐去，而不是被硬边裁断
                              child: ShaderMask(
                                blendMode: BlendMode.dstIn,
                                shaderCallback: (rect) => const LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Colors.white,
                                    Colors.white,
                                    Colors.transparent,
                                  ],
                                  stops: [0.0, 0.84, 1.0],
                                ).createShader(rect),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  clipBehavior: Clip.hardEdge,
                                  child: Padding(
                                    // 末尾留白，滑到尽头时末个胶囊不会被渐变吃掉
                                    padding: const EdgeInsets.only(right: 20),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (hasWeather)
                                          _weatherPill(entry, weatherText),
                                        if (hasWeather && hasMood)
                                          const SizedBox(width: 6),
                                        if (hasMood) _moodPill(entry),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          entry.content,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.6,
                            color: _onSurface,
                          ),
                        ),
                        // 图片（有内容才显示）
                        if ((entry.imagePath ?? '').isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(entry.imagePath!),
                              width: double.infinity,
                              height: 176,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                width: double.infinity,
                                height: 120,
                                color: _surfaceContainer,
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.broken_image_outlined,
                                  size: 24,
                                  color: _outline,
                                ),
                              ),
                            ),
                          ),
                        ],
                        // 地理位置（有内容才显示）
                        if ((entry.location ?? '').isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 14,
                                color: _outline,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  entry.location!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 天气胶囊（图标 + 描述 + 气温）
  Widget _weatherPill(DiaryEntry entry, String weatherText) {
    final emoji = (entry.weatherEmoji ?? '').trim();
    return Container(
      key: ValueKey('diary-weather-pill-${entry.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (emoji.isNotEmpty) ...[
            Text(emoji, style: const TextStyle(fontSize: 12)),
            if (weatherText.isNotEmpty) const SizedBox(width: 4),
          ],
          if (weatherText.isNotEmpty)
            Text(
              weatherText,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  /// 心情胶囊（emoji + 描述）
  Widget _moodPill(DiaryEntry entry) {
    final emoji = (entry.moodEmoji ?? '').trim();
    final desc = entry.moodDesc ?? '';
    return Container(
      key: ValueKey('diary-mood-pill-${entry.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: _moodPillBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (emoji.isNotEmpty)
            Text(emoji, style: const TextStyle(fontSize: 12)),
          if (desc.isNotEmpty) ...[
            if (emoji.isNotEmpty) const SizedBox(width: 4),
            Text(
              desc,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _onPrimaryFixedVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _dayLabel(DateTime dt) {
    final now = DateTime.now();
    final day = DateTime(dt.year, dt.month, dt.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return weekdays[dt.weekday - 1];
  }

  /// 底部装饰分隔
  Widget _buildTimelineFooter() {
    return Opacity(
      opacity: 0.6,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 1,
            color: _outlineVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.auto_awesome, size: 14, color: _outline),
          const SizedBox(width: 4),
          const Text(
            '记录生活每一天',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: _outline,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 80,
            height: 1,
            color: _outlineVariant.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }

  /// 空状态
  Widget _buildEmptyTimeline() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: Stack(
                children: [
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: _surfaceContainerLow,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: _primaryFixed.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit_note,
                            size: 36,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.auto_awesome,
                        size: 16,
                        color: _tertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.history_edu, size: 14, color: _outline),
                SizedBox(width: 4),
                Text(
                  '岁月留香，往事飞扬',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _outline,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 打开「今日状态」填写面板（底部弹出）
  Future<void> _openStatusSheet() async {
    final result = await showModalBottomSheet<DiaryStatus>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DiaryStatusSheet(initial: _todayStatus),
    );
    if (result != null && mounted) {
      setState(() => _todayStatus = result);
    }
  }

  /// 保存今天的日记
  Future<void> _saveDiary() async {
    final text = _textCtrl.text.trim();
    final editingTarget = _editingEntry;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            editingTarget == null ? '请先写下一句值得记录的话吧...' : '内容不能为空，想删掉这条请长按卡片',
          ),
        ),
      );
      _focusNode.requestFocus();
      return;
    }

    // 编辑态：只改这条的正文，时间 / 心情 / 天气 / 图片 / 位置原样保留；
    // 图片若被用户点删除，这里才清引用并删掉本地文件
    if (editingTarget != null) {
      String? imagePath = editingTarget.imagePath;
      if (_editingImageRemoved && imagePath != null) {
        unawaited(_deleteImageFile(imagePath));
        imagePath = null;
      }
      final updated = DiaryEntry(
        id: editingTarget.id,
        content: text,
        dateTime: editingTarget.dateTime,
        moodEmoji: editingTarget.moodEmoji,
        moodDesc: editingTarget.moodDesc,
        weatherEmoji: editingTarget.weatherEmoji,
        weatherDesc: editingTarget.weatherDesc,
        temp: editingTarget.temp,
        location: editingTarget.location,
        imagePath: imagePath,
      );
      await widget.repo.save(updated);
      if (!mounted) return;
      _textCtrl.clear();
      _focusNode.unfocus();
      setState(() {
        _editingEntry = null;
        _editingImageRemoved = false;
        _year = updated.dateTime.year;
        _expandedKeys.add(_monthKey(updated.dateTime.month));
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已更新')));
      return;
    }

    final now = DateTime.now();
    final status = _todayStatus;

    // 图片在写入数据库前统一压缩：相册原图大，直接入库会把本地库撑大
    final originalImagePath = _nullIfEmpty(status?.imagePath);
    String? imagePath = originalImagePath;
    if (imagePath != null) {
      try {
        imagePath = await DiaryImageService.compressToDiaryDir(imagePath);
        if (originalImagePath != null && originalImagePath != imagePath) {
          // 未压缩的临时副本用完即删，避免留下同图两份
          unawaited(_deleteImageFile(originalImagePath));
        }
      } catch (e) {
        debugPrint('日记图片压缩失败，保留原图: $e');
        imagePath = originalImagePath;
      }
    }

    final entry = DiaryEntry(
      id: DiaryRepository.generateId(),
      content: text,
      dateTime: now,
      moodEmoji: _nullIfEmpty(status?.moodEmoji),
      moodDesc: _nullIfEmpty(status?.moodDesc),
      weatherEmoji: _nullIfEmpty(status?.weatherEmoji),
      weatherDesc: _nullIfEmpty(status?.weatherDesc),
      temp: _nullIfEmpty(status?.temp),
      location: _nullIfEmpty(status?.location),
      imagePath: imagePath,
    );

    await widget.repo.save(entry);
    if (!mounted) return;
    _textCtrl.clear();
    setState(() {
      _year = now.year;
      // 记录完成后，输入框与「+」面板（心情/天气/图片/位置）一并清空
      _todayStatus = null;
      _touchedKeys.remove(_monthKey(now.month));
      _expandedKeys.add(_monthKey(now.month));
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已记录')));
  }

  String? _nullIfEmpty(String? v) {
    if (v == null) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  /// 长按日记卡片 → 二次确认删除（样式与密码/生日模块一致）
  Future<void> _confirmDelete(DiaryEntry entry) async {
    final dt = entry.dateTime;
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '确定删除「${dt.month}月${dt.day}日」的这篇日记吗？此操作不可恢复。',
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.6,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text(
                      '删除',
                      style: TextStyle(
                        color: AppColors.danger,
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
    );
    if (ok != true) return;

    await widget.repo.delete(entry.id);

    // 图片清理放后台执行，避免界面刷新被文件 I/O 阻塞
    final imagePath = entry.imagePath;
    if (imagePath != null && imagePath.isNotEmpty) {
      unawaited(_deleteImageFile(imagePath));
    }

    if (!mounted) return;
    // 删掉的正好是正在编辑的那条：一并退出编辑态，避免输入框里留着已删内容
    final wasEditing = _editingEntry?.id == entry.id;
    if (wasEditing) _textCtrl.clear();
    setState(() {
      if (wasEditing) {
        _editingEntry = null;
        _editingImageRemoved = false;
      }
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('删除成功')));
  }

  /// 静默删除本地图片文件（失败不影响删除结果）
  Future<void> _deleteImageFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('删除日记图片失败: $e');
    }
  }

  /// 年份切换
  Future<void> _pickYear() async {
    final years = widget.repo.availableYears();
    var selected = _year;

    final result = await showDialog<int>(
      context: context,
      barrierColor: const Color(0xFF213145).withValues(alpha: 0.40),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.white,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题 + 右上角导出（导出的是当前选中的年份，功能稍后实现）
                Row(
                  children: [
                    const Text(
                      '切换年份',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: _onSurface,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      key: const ValueKey('diary-export-btn'),
                      onTap: () {
                        final year = selected;
                        Navigator.of(ctx).pop();
                        _exportYear(year);
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _surfaceContainerLow,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _outlineVariant.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: const Icon(
                          Icons.file_download_outlined,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final y in years)
                      GestureDetector(
                        onTap: () => setDialogState(() => selected = y),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: selected == y
                                ? _primaryFixed
                                : _surfaceContainerLow,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$y',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: selected == y
                                  ? _onPrimaryFixedVariant
                                  : _onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(ctx).pop(),
                        child: Container(
                          height: 44,
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
                        onTap: () => Navigator.of(ctx).pop(selected),
                        child: Container(
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(12),
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

    if (result != null && mounted) {
      setState(() {
        _year = result;
        _touchedKeys.clear();
        _expandedKeys.clear();
      });
    }
  }

  /// 导出某年日记为 docx（版式对齐用户提供的 2026.docx），完成后拉起系统分享。
  Future<void> _exportYear(int year) async {
    final entries = widget.repo.getByYear(year);
    if (entries.isEmpty) {
      _showSnack('$year 年还没有日记，无法导出');
      return;
    }
    _showSnack('正在导出 $year 年日记…');
    try {
      final path = await DiaryExportService.exportYear(year, entries);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], subject: 'LittleButler $year年日记'),
      );
    } catch (e) {
      if (mounted) _showSnack('导出失败：$e');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 双击时间轴：给这个月挑一个配色。
  /// 圆点、日期文字用满色；月份头用它 10% 的极淡底，保持视觉主次。
  Future<void> _pickMonthColor({required int year, required int month}) async {
    final current = _customMonthColor(year, month);
    final picked = await showDialog<int>(
      context: context,
      barrierColor: const Color(0xFF213145).withValues(alpha: 0.40),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            key: const ValueKey('diary-color-picker'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$year年$month月 · 时间轴配色',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _onSurface,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '选一个颜色，这个月的圆点与日期一起换色',
                style: TextStyle(fontSize: 11, color: _outline),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in _paletteColors)
                    GestureDetector(
                      key: ValueKey('diary-color-${_hex(c)}'),
                      onTap: () => Navigator.of(ctx).pop(c.toARGB32()),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: current == c ? _onSurface : Colors.white,
                            width: current == c ? 2 : 0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: c.withValues(alpha: 0.25),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: current == c
                            ? const Icon(
                                Icons.check,
                                size: 20,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  GestureDetector(
                    key: const ValueKey('diary-color-reset'),
                    onTap: () => Navigator.of(ctx).pop(-1),
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '恢复默认',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (picked == null || !mounted) return;
    final value = picked == -1 ? null : picked;
    setState(() {
      _monthColorOverrides[DiaryRepository.monthColorKey(year, month)] = value;
    });
    // 落库放后台：写的是内存 box，失败也不该卡住换色
    unawaited(() async {
      try {
        await widget.repo.setMonthColor(year, month, value);
      } catch (e) {
        debugPrint('保存月份时间轴颜色失败: $e');
      }
    }());
  }

  /// 颜色转 6 位十六进制（只用于生成稳定的测试 key）
  String _hex(Color c) =>
      c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2);
}
