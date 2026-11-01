import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/scope.dart';
import '../state/app_controller.dart';
import '../state/updater.dart';
import 'background.dart';
import 'glass.dart';
import 'sync_page.dart' show SubPageHeader;
import 'theme.dart';

/// Developer details shown under Settings → About.
class Developer {
  static const name = 'Seif Alsayed Ali';
  static const alias = 'SUDOSOC';
  static const title = 'Cybersecurity Engineer · SOC & Cloud Detection';
  static const email = 'ceo@sudosoc.com';
  static const portfolio = 'https://seif.sudosoc.com';
  static const github = 'https://github.com/sudosoc';

  /// Drop a square photo here (jpg) and rebuild; a monogram is shown until then.
  static const photo = 'assets/developer/photo.jpg';
}

class DeveloperPage extends StatelessWidget {
  const DeveloperPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgTop,
      body: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackground()),
          SafeArea(
            child: Column(
              children: [
                SubPageHeader(title: context.tr('dev_title')),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                        children: [
                          Glass(
                            glow: AppColors.cyan,
                            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                            child: Column(
                              children: [
                                const _Avatar(size: 132),
                                const SizedBox(height: 18),
                                const Text(Developer.name,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                                const SizedBox(height: 6),
                                ShaderMask(
                                  shaderCallback: (r) => kAccentGradient.createShader(r),
                                  child: const Text(Developer.alias,
                                      style: TextStyle(
                                          fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 4, color: Colors.white)),
                                ),
                                const SizedBox(height: 8),
                                const Text(Developer.title,
                                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13.5)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          _LinkTile(
                            icon: Icons.alternate_email_rounded,
                            color: AppColors.pink,
                            label: context.tr('dev_email'),
                            value: Developer.email,
                            onTap: () => _copy(context, Developer.email),
                            trailing: Icons.copy_rounded,
                          ),
                          _LinkTile(
                            icon: Icons.language_rounded,
                            color: AppColors.cyan,
                            label: context.tr('dev_portfolio'),
                            value: 'seif.sudosoc.com',
                            onTap: () => controller.openUrl(Developer.portfolio),
                            onLongPress: () => _copy(context, Developer.portfolio),
                          ),
                          _LinkTile(
                            icon: Icons.code_rounded,
                            color: AppColors.mint,
                            label: 'GitHub',
                            value: 'github.com/sudosoc',
                            onTap: () => controller.openUrl(Developer.github),
                            onLongPress: () => _copy(context, Developer.github),
                          ),
                          const SizedBox(height: 10),
                          Text(context.tr('dev_note'),
                              textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                        ],
                      ),
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

  static void _copy(BuildContext context, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('copied'))));
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    final monogram = Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: kAccentGradient),
      child: Text('S', style: TextStyle(fontSize: size * 0.45, fontWeight: FontWeight.w900, color: AppColors.ink)),
    );
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: kAccentGradient,
        boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.4), blurRadius: 30, spreadRadius: -6)],
      ),
      child: ClipOval(
        child: Image.asset(
          Developer.photo,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => monogram,
        ),
      ),
    );
  }
}

/// Small round photo for the About list.
class DeveloperAvatar extends StatelessWidget {
  const DeveloperAvatar({super.key, this.size = 38});
  final double size;
  @override
  Widget build(BuildContext context) => _Avatar(size: size);
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.onTap,
    this.onLongPress,
    this.trailing = Icons.open_in_new_rounded,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final IconData trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Glass(
          padding: const EdgeInsets.all(14),
          onTap: onTap,
          child: Row(
            children: [
              IconBadge(icon: icon, color: color, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    Text(value,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ],
                ),
              ),
              Icon(trailing, size: 18, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Check → show what's new → download (with progress) → install.
Future<void> showUpdateDialog(BuildContext context, AppController controller) async {
  var checking = true;
  var started = false;
  UpdateInfo? info;
  String? error;
  String? message;
  double? progress; // null = not downloading
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      if (!started) {
        started = true;
        unawaited(controller.checkForUpdates().then((r) {
          if (!ctx.mounted) return;
          setState(() {
            checking = false;
            info = r.$1;
            error = r.$2;
          });
        }));
      }
      final linux = Updater.method == UpdateMethod.linuxCommand;
      final current = info;
      return GlassDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: IconBadge(icon: Icons.system_update_rounded, color: AppColors.cyan, size: 56)),
            const SizedBox(height: 12),
            Text(ctx.tr('update_title'),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(ctx.tr('update_current', {'v': kAppVersion}),
                textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            const SizedBox(height: 16),
            if (checking)
              const Center(child: SizedBox(width: 200, child: LinearProgressIndicator(color: AppColors.cyan)))
            else if (error != null)
              Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger))
            else if (current == null)
              Text(ctx.tr('update_latest'),
                  textAlign: TextAlign.center, style: const TextStyle(color: AppColors.mint, fontWeight: FontWeight.w700))
            else ...[
              Text(ctx.tr('update_new', {'v': current.version}),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.mint, fontWeight: FontWeight.w900, fontSize: 16)),
              if (current.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  constraints: const BoxConstraints(maxHeight: 160),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.black.withValues(alpha: 0.2),
                  ),
                  child: SingleChildScrollView(
                    child: Text(_cleanNotes(current.notes), style: const TextStyle(fontSize: 12.5, height: 1.4)),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (linux) ...[
                Text(ctx.tr('update_linux'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                const SizedBox(height: 8),
                SelectableText(kLinuxInstallCommand, textDirection: TextDirection.ltr, style: kMono.copyWith(fontSize: 12)),
                const SizedBox(height: 10),
                GlowButton(
                  label: ctx.tr('update_copy_cmd'),
                  icon: Icons.copy_rounded,
                  expand: true,
                  onPressed: () {
                    Clipboard.setData(const ClipboardData(text: kLinuxInstallCommand));
                    setState(() => message = ctx.tr('copied'));
                  },
                ),
              ] else if (progress != null) ...[
                LinearProgressIndicator(value: progress! > 0 ? progress : null, color: AppColors.cyan),
                const SizedBox(height: 6),
                Text('${((progress ?? 0) * 100).toStringAsFixed(0)}%', textAlign: TextAlign.center),
              ] else
                GlowButton(
                  label: ctx.tr(Platform.isIOS ? 'update_open_page' : 'update_install'),
                  icon: Icons.download_rounded,
                  expand: true,
                  onPressed: () async {
                    setState(() {
                      progress = 0;
                      message = null;
                    });
                    final result = await controller.installUpdate(current, onProgress: (v) {
                      if (ctx.mounted) setState(() => progress = v);
                    });
                    if (!ctx.mounted) return;
                    setState(() {
                      progress = null;
                      message = result;
                    });
                  },
                ),
            ],
            if (message != null) ...[
              const SizedBox(height: 10),
              Text(message!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.amber, fontSize: 12.5)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (current != null)
                  Expanded(
                    child: GhostButton(
                      label: ctx.tr('update_page'),
                      expand: true,
                      onPressed: () => controller.openUrl(current.page),
                    ),
                  ),
                if (current != null) const SizedBox(width: 10),
                Expanded(child: GhostButton(label: ctx.tr('close'), expand: true, onPressed: () => Navigator.pop(ctx))),
              ],
            ),
          ],
        ),
      );
    }),
  );
}

/// Release notes are Markdown with a downloads table; keep only readable lines.
String _cleanNotes(String md) {
  final lines = md
      .split('\n')
      .where((l) => !l.trim().startsWith('|') && !l.contains('One-line Linux install') && !l.startsWith('Full guide'))
      .map((l) => l.replaceAll(RegExp(r'[*`#]'), '').trimRight())
      .toList();
  return lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}
