// Smart file organization for received files:
//
//   SUDOSEND/<device>/<category>/<yyyy-mm-dd>/<file>
//
// e.g. SUDOSEND/Galaxy A52/Pictures/2026-11-02/photo.jpg. A sent *folder* is
// kept whole (its own structure matters) under <device>/Folders/<date>/.
// Unknown extensions go to "Other Files" so nothing is lost. Each level can
// be switched off.

import 'util.dart';

enum FileCategory { documents, pictures, videos, audio, archives, applications, code, other }

extension FileCategoryFolder on FileCategory {
  /// Folder name on disk (English on purpose: stable across UI languages).
  String get folder => switch (this) {
        FileCategory.documents => 'Documents',
        FileCategory.pictures => 'Pictures',
        FileCategory.videos => 'Videos',
        FileCategory.audio => 'Audio',
        FileCategory.archives => 'Archives',
        FileCategory.applications => 'Applications',
        FileCategory.code => 'Code',
        FileCategory.other => 'Other Files',
      };
}

/// Folder for whole-folder transfers.
const String kFoldersFolder = 'Folders';

const Map<FileCategory, Set<String>> _extensions = {
  FileCategory.documents: {
    'pdf', 'doc', 'docx', 'odt', 'rtf', 'txt', 'md', 'tex', 'pages', //
    'xls', 'xlsx', 'xlsm', 'ods', 'csv', 'tsv', 'numbers',
    'ppt', 'pptx', 'odp', 'key', 'epub', 'mobi', 'azw3', 'djvu', 'xps', 'oxps', 'one', 'vsdx', 'log',
  },
  FileCategory.pictures: {
    'jpg', 'jpeg', 'jfif', 'png', 'gif', 'webp', 'heic', 'heif', 'avif', 'bmp', 'tif', 'tiff', //
    'svg', 'ico', 'psd', 'xcf', 'ai', 'eps', 'raw', 'dng', 'cr2', 'cr3', 'nef', 'arw', 'orf', 'rw2', 'raf',
  },
  FileCategory.videos: {
    'mp4', 'm4v', 'mkv', 'mov', 'avi', 'webm', 'wmv', 'flv', '3gp', '3g2', 'ts', 'mts', 'm2ts', 'mpg', 'mpeg', 'vob', 'ogv',
  },
  FileCategory.audio: {
    'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'oga', 'opus', 'wma', 'amr', 'aiff', 'aif', 'mid', 'midi', 'm4b', 'ape', 'alac',
  },
  FileCategory.archives: {
    'zip', 'rar', '7z', 'tar', 'gz', 'tgz', 'bz2', 'tbz2', 'xz', 'txz', 'zst', 'lz', 'lzma', 'cab', 'iso', 'img', 'dmg',
  },
  FileCategory.applications: {
    'apk', 'apks', 'xapk', 'aab', 'exe', 'msi', 'msix', 'appx', 'deb', 'rpm', 'appimage', 'flatpak', 'snap', 'ipa', 'pkg', 'jar',
  },
  FileCategory.code: {
    'py', 'js', 'jsx', 'tsx', 'dart', 'java', 'kt', 'kts', 'c', 'h', 'cpp', 'hpp', 'cc', 'cs', 'go', 'rs', 'rb', 'php', //
    'swift', 'm', 'sh', 'bash', 'zsh', 'ps1', 'bat', 'cmd', 'lua', 'pl', 'r', 'sql', 'html', 'htm', 'css', 'scss', 'json',
    'yaml', 'yml', 'toml', 'xml', 'ini', 'conf', 'cfg', 'ipynb', 'gradle', 'cmake', 'dockerfile', 'tf',
  },
};

/// Files whose whole name identifies them (no useful extension).
const Map<String, FileCategory> _names = {
  'dockerfile': FileCategory.code,
  'makefile': FileCategory.code,
  'cmakelists.txt': FileCategory.code,
};

FileCategory categorize(String fileName) {
  final lower = fileName.toLowerCase();
  final byName = _names[lower];
  if (byName != null) return byName;
  if (lower.endsWith('.tar.gz') || lower.endsWith('.tar.xz') || lower.endsWith('.tar.bz2') || lower.endsWith('.tar.zst')) {
    return FileCategory.archives;
  }
  final dot = lower.lastIndexOf('.');
  if (dot <= 0 || dot == lower.length - 1) return FileCategory.other;
  final ext = lower.substring(dot + 1);
  for (final e in _extensions.entries) {
    if (e.value.contains(ext)) return e.key;
  }
  return FileCategory.other;
}

String dateFolder(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

/// Which levels to create.
class OrganizeRules {
  const OrganizeRules({this.byDevice = true, this.byType = true, this.byDate = true});
  final bool byDevice;
  final bool byType;
  final bool byDate;

  bool get any => byDevice || byType || byDate;

  /// Maps the sender's relative path ([segments], already sanitized) to the
  /// path under the inbox. Every returned segment is a safe single name.
  List<String> place(String device, List<String> segments, DateTime when) {
    final deviceDir = sanitizeFileName(device.trim().isEmpty ? 'Unknown device' : device);
    final isFolder = segments.length > 1;
    return [
      if (byDevice) deviceDir,
      if (byType) isFolder ? kFoldersFolder : categorize(segments.last).folder,
      if (byDate) dateFolder(when),
      ...segments,
    ];
  }
}
