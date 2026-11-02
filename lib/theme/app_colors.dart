import 'package:flutter/material.dart';

/// 全局颜色常量（统一管理，避免硬编码不一致）。
class AppColors {
  AppColors._();

  // ========== 主色 ==========
  static const Color primary = Color(0xFF4A6CF7);
  static const Color primaryLight = Color(0xFFE0E7FF); // 选中浅蓝背景

  // ========== 文字颜色 ==========
  static const Color textPrimary = Color(0xFF1F2937); // 标题/主要文字
  static const Color textBody = Color(0xFF374151); // 正文
  static const Color textSecondary = Color(0xFF6B7280); // 次要文字
  static const Color textPlaceholder = Color(0xFF9CA3AF); // 占位/图标

  // ========== 背景颜色 ==========
  static const Color bgPage = Color(0xFFF8F9FF); // 页面背景（浅蓝白）
  static const Color bgCard = Color(0xFFFFFFFF); // 卡片背景（白色）
  static const Color bgLight = Color(0xFFF3F4F6); // 更浅的灰色背景
  static const Color border = Color(0xFFE5E7EB); // 边框
  static const Color divider = Color(0xFFF3F4F6); // 分隔线

  // ========== 功能色 ==========
  static const Color danger = Color(0xFFDC2626); // 红色（今天/危险）
  static const Color dangerLight = Color(0xFFFEE2E2); // 浅红背景
  static const Color iconGray = Color(0xFF4B5563); // 深灰图标
  static const Color trackGray = Color(0xFFD1D5DB); // 开关轨道/灰色点

  // ========== 装饰色 ==========
  static const Color pink = Color(0xFFD23284); // 玫红（生日图标）
  static const Color pinkLight = Color(0xFFFFD9E4); // 浅粉背景
}
