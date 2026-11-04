import 'package:flutter/material.dart';

/// "Obsidian": one calm dark surface family and a single signal accent.
/// (Names are kept from the old palette so every screen picks the new look up;
/// [cyan] is now the signal accent, [violet]/[pink] are quiet secondaries.)
class AppColors {
  AppColors._();
  static const Color bgTop = Color(0xFF0A0B0F);
  static const Color bgBottom = Color(0xFF0A0B0F);
  static const Color surface = Color(0xFF12151B);
  static const Color surfaceHi = Color(0xFF1A1E27);
  static const Color line = Color(0xFF262B38);
  static const Color accent = Color(0xFF5BF0C0);
  static const Color cyan = accent;
  static const Color violet = Color(0xFFA394FF);
  static const Color pink = Color(0xFFFF8FA8);
  static const Color mint = Color(0xFF4ADE80);
  static const Color amber = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFFB7185);
  static const Color text = Color(0xFFECEFF4);
  static const Color muted = Color(0xFF8B94A7);
  static const Color ink = Color(0xFF04140E);
}

const LinearGradient kAccentGradient = LinearGradient(
  colors: [Color(0xFF6DF5C9), Color(0xFF3FD3A3)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const TextStyle kMono = TextStyle(
  fontFamily: 'IBMPlexMono',
  fontFamilyFallback: [
    'JetBrains Mono',
    'Consolas',
    'DejaVu Sans Mono',
    'Courier New'
  ],
);

const String kArabicFont = 'IBMPlexSansArabic';
const String kLatinFont = 'IBMPlexSans';

ThemeData buildTheme({bool arabic = false}) {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: arabic ? kArabicFont : kLatinFont,
    fontFamilyFallback: const [kArabicFont],
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.cyan,
      brightness: Brightness.dark,
      surface: AppColors.bgTop,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bgTop,
    focusColor: AppColors.cyan.withValues(alpha: 0.22),
    textTheme: base.textTheme
        .apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    iconTheme: const IconThemeData(color: AppColors.text),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surfaceHi,
      contentTextStyle: base.textTheme.bodyMedium?.copyWith(color: AppColors.text),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.line),
      ),
    ),
    dividerColor: AppColors.line,
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surfaceHi,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.line),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.line)),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.muted,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.accent.withValues(alpha: 0.14)
              : Colors.transparent,
        ),
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      side: const BorderSide(color: AppColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: base.textTheme.labelLarge?.copyWith(color: AppColors.text, fontSize: 13),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected) ? AppColors.ink : AppColors.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.accent
            : AppColors.surfaceHi,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.accent
            : AppColors.line,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.cyan
            : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(AppColors.ink),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: const TextStyle(color: AppColors.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.accent),
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
  const code = {
    'py',
    'dart',
    'js',
    'ts',
    'c',
    'cpp',
    'rs',
    'go',
    'sh',
    'json',
    'yaml',
    'yml'
  };
  if (images.contains(ext)) return Icons.image_rounded;
  if (videos.contains(ext)) return Icons.movie_rounded;
  if (audio.contains(ext)) return Icons.audiotrack_rounded;
  if (archives.contains(ext)) return Icons.folder_zip_rounded;
  if (code.contains(ext)) return Icons.code_rounded;
  if (ext == 'apk') return Icons.android;
  if (ext == 'pdf') return Icons.picture_as_pdf_rounded;
  return Icons.insert_drive_file_rounded;
}
