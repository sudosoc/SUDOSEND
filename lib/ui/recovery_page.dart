import 'dart:io';

import 'package:flutter/material.dart';
import 'package:wraith_core/organize.dart' show dateFolder;
import 'package:wraith_core/util.dart';

import '../app/scope.dart';
import '../state/app_controller.dart';
import '../state/safe_file.dart';
import 'background.dart';
import 'glass.dart';
import 'settings_page.dart' show InfoButton;
import 'sync_page.dart' show SubPageHeader;
import 'theme.dart';

/// Smart Recovery: trash, leftovers of interrupted transfers, and what was
/// repaired after a crash.
class RecoveryPage extends StatefulWidget {
  const RecoveryPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<RecoveryPage> createState() => _RecoveryPageState();
}

class _RecoveryPageState extends State<RecoveryPage> {
  List<File>? _partials;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _loadPartials();
  }

  Future<void> _loadPartials() async {
    final found = await c.findPartials();
    if (mounted) setState(() => _partials = found);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgTop,
      body: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackground()),
          SafeArea(
            child: ListenableBuilder(
              listenable: Listenable.merge([c, c.settings]),
              builder: (context, _) {
                final s = c.settings;
                final rec = c.lastRecovery;
                final partialBytes = (_partials ?? const <File>[]).fold<int>(0, (a, f) {
                  try {
                    return a + f.lengthSync();
                  } catch (_) {
                    return a;
                  }
                });
                return Column(
                  children: [
                    SubPageHeader(title: context.tr('rec_title')),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                            children: [
                              // ── Health ──
                              Glass(
                                child: Row(
                                  children: [
                                    const IconBadge(icon: Icons.health_and_safety_rounded, color: AppColors.mint, size: 44),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            (rec?.repaired.isEmpty ?? true) && SafeFile.restored.isEmpty
                                                ? context.tr('rec_healthy')
                                                : context.tr('rec_repaired', {'n': (rec?.repaired.length ?? 0) + SafeFile.restored.length}),
                                            style: const TextStyle(fontWeight: FontWeight.w800),
                                          ),
                                          Text(context.tr('rec_healthy_sub'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                                          for (final r in [...?rec?.repaired, ...SafeFile.restored.map((f) => 'backup → $f')])
                                            Text('• $r', textDirection: TextDirection.ltr, style: const TextStyle(color: AppColors.mint, fontSize: 11.5)),
                                          for (final r in rec?.needsAttention ?? const <String>[])
                                            Text('• $r', textDirection: TextDirection.ltr, style: const TextStyle(color: AppColors.amber, fontSize: 11.5)),
                                        ],
                                      ),
                                    ),
                                    InfoButton(title: context.tr('rec_title'), body: context.tr('i_recovery')),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              // ── Trash ──
                              SectionTitle(context.tr('trash_title', {'n': c.trash.items.length, 'size': formatBytes(c.trash.totalBytes)})),
                              Glass(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(context.tr('trash_keep'), style: const TextStyle(fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        for (final d in const [0, 7, 30, 90])
                                          ChoiceChip(
                                            label: Text(d == 0 ? context.tr('trash_off') : context.tr('trash_days', {'n': d})),
                                            selected: s.trashDays == d,
                                            onSelected: (_) => s.update((x) => x.trashDays = d),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(context.tr(s.trashDays == 0 ? 'trash_off_sub' : 'trash_on_sub'),
                                        style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                    if (c.trash.items.isNotEmpty) ...[
                                      Divider(height: 20, color: Colors.white.withValues(alpha: 0.07)),
                                      for (final t in c.trash.items.take(100))
                                        Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 3),
                                          child: Row(
                                            children: [
                                              Icon(fileIcon(t.name), size: 18, color: AppColors.muted),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(t.name, overflow: TextOverflow.ellipsis),
                                                    Text('${formatBytes(t.size)} · ${dateFolder(t.at)}',
                                                        style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: context.tr('trash_restore'),
                                                icon: const Icon(Icons.restore_from_trash_rounded, color: AppColors.mint),
                                                onPressed: () async {
                                                  final messenger = ScaffoldMessenger.of(context);
                                                  final ok = context.tr('trash_restored', {'name': t.name});
                                                  final error = await c.restoreFromTrash(t);
                                                  messenger.showSnackBar(SnackBar(content: Text(error ?? ok)));
                                                },
                                              ),
                                              IconButton(
                                                tooltip: context.tr('delete'),
                                                icon: const Icon(Icons.delete_forever_rounded, color: AppColors.danger),
                                                onPressed: () => c.deleteFromTrash(t),
                                              ),
                                            ],
                                          ),
                                        ),
                                      const SizedBox(height: 8),
                                      Align(
                                        alignment: AlignmentDirectional.centerEnd,
                                        child: GhostButton(
                                          label: context.tr('trash_empty'),
                                          icon: Icons.delete_sweep_rounded,
                                          color: AppColors.danger,
                                          onPressed: () async {
                                            final ok = await _confirm(context, context.tr('trash_empty_confirm'));
                                            if (ok) await c.emptyTrash();
                                          },
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              // ── Interrupted transfers ──
                              SectionTitle(context.tr('rec_partials')),
                              Glass(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _partials == null
                                          ? context.tr('rec_scanning')
                                          : context.tr('rec_partials_found', {'n': _partials!.length, 'size': formatBytes(partialBytes)}),
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(context.tr('rec_partials_sub'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                                    if (_partials?.isNotEmpty ?? false) ...[
                                      const SizedBox(height: 10),
                                      GhostButton(
                                        label: context.tr('rec_partials_clean'),
                                        icon: Icons.cleaning_services_rounded,
                                        color: AppColors.amber,
                                        onPressed: () async {
                                          final ok = await _confirm(context, context.tr('rec_partials_confirm'));
                                          if (!ok) return;
                                          await c.cleanPartials();
                                          await _loadPartials();
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm(BuildContext context, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => GlassDialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: GhostButton(label: ctx.tr('cancel'), expand: true, onPressed: () => Navigator.pop(ctx, false))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GhostButton(
                      label: ctx.tr('delete'),
                      color: AppColors.danger,
                      expand: true,
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ) ??
      false;
}
