import 'package:flutter/material.dart';

import '../core/transfer.dart';
import '../core/util.dart';
import 'glass.dart';
import 'theme.dart';

/// Shows the accept/decline dialog. Closes by itself if the request times out.
Future<void> showIncomingDialog(BuildContext context, IncomingRequest request) async {
  final navigator = Navigator.of(context);
  var open = true;
  request.decision.then((_) {
    if (open && navigator.mounted) {
      open = false;
      navigator.pop();
    }
  });
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => _IncomingDialog(
      request: request,
      onDecide: (accept, trust) {
        if (!open) return;
        open = false;
        navigator.pop();
        request.respond(accept, trust: trust);
      },
    ),
  );
  open = false;
  request.respond(false); // no-op if already answered
}

class _IncomingDialog extends StatefulWidget {
  const _IncomingDialog({required this.request, required this.onDecide});

  final IncomingRequest request;
  final void Function(bool accept, bool trust) onDecide;

  @override
  State<_IncomingDialog> createState() => _IncomingDialogState();
}

class _IncomingDialogState extends State<_IncomingDialog> {
  bool _trust = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final shown = r.files.take(4).toList();
    final more = r.files.length - shown.length;
    return GlassDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon: platformIcon(r.peerPlatform), color: platformColor(r.peerPlatform), size: 50),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('INCOMING TRANSFER',
                        style: TextStyle(color: AppColors.muted, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                    const SizedBox(height: 2),
                    Text(r.peerName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(groupFingerprint(r.fingerprint), style: kMono.copyWith(color: AppColors.muted, fontSize: 11.5)),
          const SizedBox(height: 16),
          if (r.trusted)
            const Row(
              children: [
                Icon(Icons.verified_user_rounded, color: AppColors.mint, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Trusted device — identity proven by its key',
                      style: TextStyle(color: AppColors.mint, fontWeight: FontWeight.w700)),
                ),
              ],
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: AppColors.amber.withValues(alpha: 0.07),
                border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
              ),
              child: Column(
                children: [
                  Text(formatSas(r.sas),
                      style: kMono.copyWith(fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: 6)),
                  const SizedBox(height: 4),
                  const Text(
                    'Accept only if the sender shows the same code.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.amber, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          for (final f in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(fileIcon(f.name), size: 18, color: AppColors.muted),
                  const SizedBox(width: 10),
                  Expanded(child: Text(f.name, overflow: TextOverflow.ellipsis)),
                  Text(formatBytes(f.size), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ],
              ),
            ),
          if (more > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('+ $more more', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ),
          const SizedBox(height: 6),
          Text('Total ${formatBytes(r.totalBytes)}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          if (!r.trusted) ...[
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _trust = !_trust),
              child: Row(
                children: [
                  Checkbox(value: _trust, onChanged: (v) => setState(() => _trust = v ?? false)),
                  const Expanded(
                    child: Text('Trust this device (skip the code next time)',
                        style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GhostButton(
                  label: 'Decline',
                  color: AppColors.danger,
                  expand: true,
                  onPressed: () => widget.onDecide(false, false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GlowButton(
                  label: 'Accept',
                  icon: Icons.download_rounded,
                  expand: true,
                  onPressed: () => widget.onDecide(true, _trust),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
