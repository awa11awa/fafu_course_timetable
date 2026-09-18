import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 蓝白纯色设计规范
class AppColors {
  static const Color primary = Color(0xFF1565C0); // 主蓝
  static const Color primaryDark = Color(0xFF0D47A1); // 深蓝
  static const Color primaryMid = Color(0xFF1E7BE0); // 中蓝
  static const Color primaryLight = Color(0xFFE8F1FC); // 浅蓝底
  static const Color primaryFaint = Color(0xFFF3F8FF); // 极浅蓝

  static const Color bg = Color(0xFFF6F9FD); // 页面底
  static const Color surface = Colors.white; // 卡片
  static const Color text = Color(0xFF16202C); // 主文字
  static const Color textSub = Color(0xFF6B7C90); // 次要文字
  static const Color textFaint = Color(0xFF9AA9BB); // 弱文字
  static const Color divider = Color(0xFFE7EEF7); // 分割线
  static const Color success = Color(0xFF2E9E6B);
  static const Color warn = Color(0xFFE08A2E);
}

/// 上课节次对应的默认作息时间（可在“设置”里改）
class PeriodTime {
  static const Map<int, String> start = {
    1: '08:00', 2: '08:55', 3: '10:05', 4: '11:00', 5: '11:55',
    6: '14:00', 7: '14:55', 8: '16:05', 9: '17:00',
    10: '19:00', 11: '19:55', 12: '20:50',
  };
  static const Map<int, String> end = {
    1: '08:45', 2: '09:40', 3: '10:50', 4: '11:45', 5: '12:40',
    6: '14:45', 7: '15:40', 8: '16:50', 9: '17:45',
    10: '19:45', 11: '20:40', 12: '21:35',
  };
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.surface,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: 'Roboto',
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: .5,
      ),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.primaryFaint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
      hintStyle: const TextStyle(color: AppColors.textFaint, fontSize: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : Colors.white,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.primary
            : const Color(0xFFCBD6E2),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.primaryDark,
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
