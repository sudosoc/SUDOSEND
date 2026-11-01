import 'package:flutter/material.dart';

class AppColors {
  AppColors._();
  static const Color bgTop = Color(0xFF060816);
  static const Color bgBottom = Color(0xFF0B1028);
  static const Color cyan = Color(0xFF38E1FF);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color pink = Color(0xFFF472B6);
  static const Color mint = Color(0xFF34D399);
  static const Color amber = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFFB7185);
  static const Color text = Color(0xFFEAF0FF);
  static const Color muted = Color(0xFF8E9BB8);
  static const Color ink = Color(0xFF070A16);
}

const LinearGradient kAccentGradient = LinearGradient(
  colors: [AppColors.cyan, AppColors.violet],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const TextStyle kMono = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['JetBrains Mono', 'Consolas', 'DejaVu Sans Mono', 'Courier New'],
);

const String kArabicFont = 'IBMPlexSansArabic';

ThemeData buildTheme({bool arabic = false}) {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: arabic ? kArabicFont : null,
    fontFamilyFallback: const [kArabicFont],
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.cyan,
      brightness: Brightness.dark,
      surface: AppColors.bgTop,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bgTop,
    textTheme: base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    iconTheme: const IconThemeData(color: AppColors.text),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF151B36),
      contentTextStyle: const TextStyle(color: AppColors.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.cyan : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(AppColors.ink),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      hintStyle: const TextStyle(color: AppColors.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.cyan),
      ),
    ),
  );
}

IconData platformIcon(String platform) => switch (platform) {
      'android' => Icons.android,
      'windows' => Icons.desktop_windows_rounded,
      'linux' => Icons.terminal_rounded,
      'macos' => Icons.laptop_mac_rounded,
      'ios' => Icons.phone_iphone_rounded,
      _ => Icons.devices_other_rounded,
    };

Color platformColor(String platform) => switch (platform) {
      'android' => AppColors.mint,
      'windows' => AppColors.cyan,
      'linux' => AppColors.amber,
      'macos' || 'ios' => AppColors.pink,
      _ => AppColors.violet,
    };

IconData fileIcon(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  const images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp', 'svg'};
  const videos = {'mp4', 'mkv', 'mov', 'avi', 'webm'};
  const audio = {'mp3', 'wav', 'flac', 'ogg', 'm4a', 'aac'};
  const archives = {'zip', 'rar', '7z', 'tar', 'gz', 'xz', 'iso'};
  const code = {'py', 'dart', 'js', 'ts', 'c', 'cpp', 'rs', 'go', 'sh', 'json', 'yaml', 'yml'};
  if (images.contains(ext)) return Icons.image_rounded;
  if (videos.contains(ext)) return Icons.movie_rounded;
  if (audio.contains(ext)) return Icons.audiotrack_rounded;
  if (archives.contains(ext)) return Icons.folder_zip_rounded;
  if (code.contains(ext)) return Icons.code_rounded;
  if (ext == 'apk') return Icons.android;
  if (ext == 'pdf') return Icons.picture_as_pdf_rounded;
  return Icons.insert_drive_file_rounded;
}
