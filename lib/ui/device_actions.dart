import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wraith_core/models.dart';
import 'package:wraith_core/util.dart';

import '../app/scope.dart';
import '../state/app_controller.dart';
import 'chat_page.dart';
import 'glass.dart';
import 'sync_page.dart';
import 'theme.dart';

/// Actions for a trusted device: message, speed test, ring, folder sync.
Future<void> showDeviceActions(BuildContext context, AppController controller, Peer peer) async {
  final s = controller.settings;
  final action = await showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) => GlassDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(icon: platformIcon(peer.platform), color: platformColor(peer.platform), size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Text(peer.name,
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (s.chat)
            _ActionTile(icon: Icons.forum_rounded, color: AppColors.cyan, label: ctx.tr('act_message'), value: 'chat'),
          _ActionTile(icon: Icons.speed_rounded, color: AppColors.mint, label: ctx.tr('speed_test'), value: 'speed'),
          _ActionTile(icon: Icons.notifications_active_rounded, color: AppColors.amber, label: ctx.tr('ring'), value: 'ring'),
          if (controller.syncSupported)
            _ActionTile(icon: Icons.sync_alt_rounded, color: AppColors.violet, label: ctx.tr('sync_new'), value: 'sync'),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  switch (action) {
    case 'chat':
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ChatThreadPage(controller: controller, fingerprint: peer.id, name: peer.name),
      ));
    case 'speed':
      await showSpeedTest(context, controller, peer);
    case 'ring':
      final ok = context.tr('ring_sent', {'name': peer.name});
      final error = await controller.ringDevice(peer);
      messenger.showSnackBar(SnackBar(content: Text(error ?? ok)));
    case 'sync':
      final error = await controller.createSync(peer);
      if (error != null) {
        messenger.showSnackBar(SnackBar(content: Text(error)));
      } else if (context.mounted) {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SyncPage(controller: controller)));
      }
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.color, required this.label, required this.value});
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Glass(
        radius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => Navigator.pop(context, value),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// Runs a 6-second encrypted throughput test and shows the result.
Future<void> showSpeedTest(BuildContext context, AppController controller, Peer peer) async {
  double? rate;
  String? error;
  var running = true;
  var started = false;
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      if (!started) {
        started = true;
        unawaited(controller.speedTest(peer).then((r) {
          if (!ctx.mounted) return;
          setState(() {
            rate = r.$1;
            error = r.$2;
            running = false;
          });
        }));
      }
      return GlassDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IconBadge(icon: Icons.speed_rounded, color: AppColors.mint, size: 56),
            const SizedBox(height: 12),
            Text(ctx.tr('speed_test'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(peer.name, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 18),
            if (running) ...[
              const SizedBox(width: 200, child: LinearProgressIndicator(color: AppColors.mint)),
              const SizedBox(height: 10),
              Text(ctx.tr('speed_running'), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            ] else if (rate != null) ...[
              Text('${formatBytes(rate!.round())}/s',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: AppColors.mint)),
              Text('${(rate! * 8 / 1e6).toStringAsFixed(0)} Mbit/s',
                  textDirection: TextDirection.ltr, style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 10),
              Text(ctx.tr('speed_note', {'gb': formatDuration(rate!)}),
                  textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ] else
              Text(error ?? '', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
            const SizedBox(height: 18),
            GhostButton(label: ctx.tr('close'), expand: true, onPressed: () => Navigator.pop(ctx)),
          ],
        ),
      );
    }),
  );
}

/// How long 1 GB would take at [rate] bytes/s, e.g. "1 min 12 s".
String formatDuration(double rate) {
  if (rate <= 0) return '—';
  final secs = (1e9 / rate).round();
  if (secs < 60) return '$secs s';
  return '${secs ~/ 60} min ${secs % 60} s';
}
