// Risky-file detection for received files. SUDOSEND never opens or runs a
// received file by itself; this decides when to warn before the user does.

enum RiskLevel { none, caution, danger }

class FileRisk {
  const FileRisk(this.level, this.reason);
  final RiskLevel level;

  /// executable | script | macro | double-extension | disguised | shortcut
  final String? reason;

  static const safe = FileRisk(RiskLevel.none, null);
}

const _executables = {
  'exe', 'scr', 'com', 'pif', 'msi', 'msix', 'msp', 'dll', 'cpl', 'sys', 'appx', 'apk', 'xapk', 'apks', //
  'deb', 'rpm', 'appimage', 'run', 'bin', 'elf', 'app', 'dmg', 'pkg', 'jar', 'ipa', 'gadget', 'hta',
};
const _scripts = {
  'bat', 'cmd', 'ps1', 'psm1', 'vbs', 'vbe', 'js', 'jse', 'wsf', 'wsh', 'sh', 'bash', 'zsh', 'py', 'pl', 'rb', //
  'command', 'applescript', 'scpt', 'reg', 'inf',
};
const _macros = {'docm', 'dotm', 'xlsm', 'xltm', 'xlam', 'pptm', 'potm', 'ppam', 'sldm'};
const _shortcuts = {'lnk', 'url', 'desktop', 'webloc', 'library-ms', 'settingcontent-ms', 'iso', 'img', 'vhd', 'vhdx'};

/// Extensions people trust to be "just a document or picture".
const _harmlessLooking = {
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf', 'jpg', 'jpeg', 'png', 'gif', 'mp4', 'mp3', 'zip', 'csv',
};

/// Checks a file by its name and, when given, its first bytes.
FileRisk assessRisk(String name, [List<int>? head]) {
  final lower = name.toLowerCase().trim();
  final parts = lower.split('.');
  final ext = parts.length > 1 ? parts.last : '';
  final inner = parts.length > 2 ? parts[parts.length - 2] : '';

  // Content that is a program, whatever the name says.
  final magic = head == null ? null : _sniff(head);
  if (magic != null && !_executables.contains(ext) && !_scripts.contains(ext)) {
    return FileRisk(RiskLevel.danger, magic == 'script' ? 'disguised-script' : 'disguised');
  }
  // invoice.pdf.exe, photo.jpg   .scr (padding to hide the real extension)
  if ((_executables.contains(ext) || _scripts.contains(ext)) && (_harmlessLooking.contains(inner) || name.contains('   '))) {
    return const FileRisk(RiskLevel.danger, 'double-extension');
  }
  // Right-to-left override characters used to flip the visible extension.
  if (name.contains('\u202E') || name.contains('\u202D')) return const FileRisk(RiskLevel.danger, 'double-extension');
  if (_executables.contains(ext)) return const FileRisk(RiskLevel.caution, 'executable');
  if (_scripts.contains(ext)) return const FileRisk(RiskLevel.caution, 'script');
  if (_macros.contains(ext)) return const FileRisk(RiskLevel.caution, 'macro');
  if (_shortcuts.contains(ext)) return const FileRisk(RiskLevel.caution, 'shortcut');
  return FileRisk.safe;
}

/// 'exe' for native programs, 'script' for shebang scripts, else null.
String? _sniff(List<int> h) {
  bool at(int i, List<int> sig) {
    if (h.length < i + sig.length) return false;
    for (var k = 0; k < sig.length; k++) {
      if (h[i + k] != sig[k]) return false;
    }
    return true;
  }

  if (at(0, const [0x4D, 0x5A])) return 'exe'; // MZ (Windows PE)
  if (at(0, const [0x7F, 0x45, 0x4C, 0x46])) return 'exe'; // ELF
  if (at(0, const [0xCF, 0xFA, 0xED, 0xFE]) || at(0, const [0xCE, 0xFA, 0xED, 0xFE])) return 'exe'; // Mach-O
  if (at(0, const [0xCA, 0xFE, 0xBA, 0xBE])) return 'exe'; // Mach-O universal
  if (at(0, const [0x23, 0x21])) return 'script'; // #!
  return null;
}
