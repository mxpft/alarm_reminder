import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../data/password_repository.dart';
import '../models/password_entry.dart';
import '../theme/app_colors.dart';

class PasswordListPage extends StatefulWidget {
  final PasswordRepository repo;

  const PasswordListPage({super.key, required this.repo});

  @override
  State<PasswordListPage> createState() => _PasswordListPageState();
}

class _PasswordListPageState extends State<PasswordListPage> {
  String _searchQuery = '';

  List<PasswordEntry> _filterEntries(List<PasswordEntry> entries) {
    if (_searchQuery.isEmpty) return entries;
    final q = _searchQuery.toLowerCase();
    return entries.where((e) {
      return e.title.toLowerCase().contains(q) ||
          e.username.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPage,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部固定区域
            _buildHeader(),
            // 搜索框（有数据时才显示）
            ValueListenableBuilder(
              valueListenable: widget.repo.box.listenable(),
              builder: (context, box, _) {
                if (widget.repo.count == 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: const InputDecoration(
                        hintText: '搜索应用、网站或用户名...',
                        hintStyle: TextStyle(fontSize: 14, color: AppColors.textPlaceholder),
                        prefixIcon: Icon(Icons.search, size: 20, color: AppColors.textPlaceholder),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                );
              },
            ),
            // 可滚动列表
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: widget.repo.box.listenable(),
                builder: (context, box, _) {
                  final all = widget.repo.getAll();
                  final filtered = _filterEntries(all);
                  if (filtered.isEmpty) {
                    return _buildEmptyView();
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      for (var i = 0; i < filtered.length; i++) ...[
                        _PasswordCard(
                          entry: filtered[i],
                          onTap: () => _openEditor(filtered[i]),
                          onDelete: () => _confirmDelete(filtered[i]),
                        ),
                        if (i < filtered.length - 1) const SizedBox(height: 12),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: AppColors.bgPage,
      child: Column(
        children: [
          // AppBar
          SizedBox(
            height: 48,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 22),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          // 密码库摘要卡片
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF4FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.lock,
                      color: AppColors.primary,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '密码库',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        ValueListenableBuilder(
                          valueListenable: widget.repo.box.listenable(),
                          builder: (context, box, _) {
                            return Text(
                              '已安全保管 ${widget.repo.count} 个账号凭证',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  // 新建按钮
                  FilledButton(
                    onPressed: () => _openEditor(null),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 18),
                        SizedBox(width: 2),
                        Text('新建', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.55,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 大圆形 lock 图标 + 右下角小圆形 vpn_key 图标
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
                        color: AppColors.primaryLight.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.lock,
                        size: 48,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.vpn_key,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '密码库还是空的',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                '点击上方"+ 新建"按钮，即可安全记录并管理您的网站与应用账号密码，支持一键复制与本地加密。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor(PasswordEntry? entry) async {
    final result = await showModalBottomSheet<PasswordEntry?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PasswordEditSheet(entry: entry),
    );
    if (result != null) {
      await widget.repo.save(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存成功')),
        );
      }
    }
  }

  Future<void> _confirmDelete(PasswordEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '确定删除「${entry.title}」的密码记录吗？此操作不可恢复。',
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
    if (ok == true) {
      await widget.repo.delete(entry.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除成功')),
        );
      }
    }
  }
}

/// 密码卡片
class _PasswordCard extends StatelessWidget {
  final PasswordEntry entry;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _PasswordCard({
    required this.entry,
    required this.onDelete,
    required this.onTap,
  });

  void _copy(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label复制成功')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            // 用户名行
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '账号 / 用户名',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textPlaceholder,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          entry.username,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.content_copy, size: 18, color: AppColors.primary),
                    onPressed: () => _copy(context, entry.username, '账号'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // 密码行
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '登录密码',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textPlaceholder,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          entry.password,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.content_copy, size: 18, color: AppColors.primary),
                    onPressed: () => _copy(context, entry.password, '密码'),
                  ),
                ],
              ),
            ),
            // 备注信息（上面有分隔线）
            if (entry.note != null && entry.note!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                height: 1,
                color: const Color(0xFFF1F5F9),
              ),
              const SizedBox(height: 12),
              Text(
                entry.note!,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 新增/编辑密码底部弹窗
class _PasswordEditSheet extends StatefulWidget {
  final PasswordEntry? entry;

  const _PasswordEditSheet({this.entry});

  @override
  State<_PasswordEditSheet> createState() => _PasswordEditSheetState();
}

class _PasswordEditSheetState extends State<_PasswordEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleCtrl;
  late TextEditingController _usernameCtrl;
  late TextEditingController _passwordCtrl;
  late TextEditingController _noteCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.entry?.title ?? '');
    _usernameCtrl = TextEditingController(text: widget.entry?.username ?? '');
    _passwordCtrl = TextEditingController(text: widget.entry?.password ?? '');
    _noteCtrl = TextEditingController(text: widget.entry?.note ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final result = PasswordEntry(
      id: widget.entry?.id ?? PasswordRepository.generateId(),
      title: _titleCtrl.text.trim(),
      username: _usernameCtrl.text.trim(),
      password: _passwordCtrl.text,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    );
    Navigator.of(context).pop(result);
  }

  void _generatePassword() {
    const lower = 'abcdefghijklmnopqrstuvwxyz';
    const upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const digits = '0123456789';
    const special = '!@#\$%^&*()_+-=[]{}|;:,.<>?';
    final all = lower + upper + digits + special;
    final rng = DateTime.now().microsecondsSinceEpoch;
    final rand = rng ^ (rng >> 16);

    String pick(String chars, int seed) {
      return chars[seed % chars.length];
    }

    // 确保包含大小写、数字、特殊字符
    final chars = <String>[
      pick(lower, rand),
      pick(upper, rand >> 1),
      pick(digits, rand >> 2),
      pick(special, rand >> 3),
    ];
    // 剩余4位随机填充
    for (var i = 4; i < 8; i++) {
      final idx = (rand >> i) & (all.length - 1);
      chars.add(all[idx]);
    }
    // 打乱顺序
    chars.shuffle();
    _passwordCtrl.text = chars.join();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Text(
                widget.entry == null ? '添加新密码' : '编辑密码',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              // 平台名称
              const Text('平台或网站名称', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              TextFormField(
                controller: _titleCtrl,
                decoration: InputDecoration(
                  hintText: '请输入应用名称',
                  prefixIcon: const Icon(Icons.language, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
                  ),
                ),
                validator: (v) => v!.trim().isEmpty ? '请输入应用名称' : null,
              ),
              const SizedBox(height: 16),
              // 账号
              const Text('账号或邮箱', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              TextFormField(
                controller: _usernameCtrl,
                decoration: InputDecoration(
                  hintText: '输入账号名称或邮箱',
                  prefixIcon: const Icon(Icons.person, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
                  ),
                ),
                validator: (v) => v!.trim().isEmpty ? '请输入账号' : null,
              ),
              const SizedBox(height: 16),
              // 密码
              const Text('安全密码', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              TextFormField(
                controller: _passwordCtrl,
                decoration: InputDecoration(
                  hintText: '输入密码',
                  prefixIcon: const Icon(Icons.key, size: 18),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.auto_fix_high, size: 20, color: AppColors.primary),
                    onPressed: _generatePassword,
                    tooltip: '随机生成密码',
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
                  ),
                ),
                validator: (v) => v!.isEmpty ? '请输入密码' : null,
              ),
              const SizedBox(height: 16),
              // 备注
              const Text('备注信息（可选）', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              TextFormField(
                controller: _noteCtrl,
                decoration: InputDecoration(
                  hintText: '如：备用验证码、绑定的二次验证',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // 按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('保存凭据'),
                    ),
                  ),
                ],
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        ),
      ),
    );
  }
}
