import 'package:flutter/material.dart';
import 'package:wraith_core/receipt.dart';
import 'package:wraith_core/util.dart';

import '../app/scope.dart';
import '../state/app_controller.dart';
import 'glass.dart';
import 'theme.dart';

/// Shows a signed delivery receipt, re-verifies its signature, and offers export.
Future<void> showReceiptDialog(BuildContext context, AppController controller, DeliveryReceipt receipt) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => GlassDialog(
      maxWidth: 560,
      child: FutureBuilder<bool>(
        future: receipt.verifySignature(),
        builder: (ctx, snap) {
          final valid = snap.data;
          final d = receipt.data;
          final files = ((d['files'] as List?) ?? const []).cast<Map<String, dynamic>>();
          final sender = (d['sender'] as Map?) ?? const {};
          final receiver = (d['receiver'] as Map?) ?? const {};
          final color = valid == null ? AppColors.muted : (valid ? AppColors.mint : AppColors.danger);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconBadge(icon: valid == false ? Icons.gpp_bad_rounded : Icons.verified_rounded, color: color, size: 46),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.tr('receipt_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                        Text(
                          valid == null
                              ? '…'
                              : context.tr(valid ? 'receipt_valid' : 'receipt_invalid'),
                          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _kv(context, context.tr('receipt_from'), '${sender['name']}', '${sender['fingerprint']}'),
              _kv(context, context.tr('receipt_to'), '${receiver['name']}', receipt.signerFingerprint),
              _kv(context, context.tr('receipt_when'), '${d['completed']}', null),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final f in files)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${f['name']} · ${formatBytes(f['size'] as int)}',
                                  overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text('SHA-256 ${f['sha256']}',
                                  textDirection: TextDirection.ltr,
                                  style: kMono.copyWith(color: AppColors.muted, fontSize: 10.5)),
                            ],
                          ),
                        ),
                      if (d['text_sha256'] != null)
                        Text('text SHA-256 ${d['text_sha256']}',
                            textDirection: TextDirection.ltr, style: kMono.copyWith(color: AppColors.muted, fontSize: 10.5)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(context.tr('receipt_explain'), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: GhostButton(label: context.tr('done'), expand: true, onPressed: () => Navigator.pop(ctx))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlowButton(
                      label: context.tr('receipt_export'),
                      icon: Icons.download_rounded,
                      expand: true,
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final saved = context.tr('receipt_saved');
                        final path = await controller.exportReceipt(receipt);
                        if (path != null) messenger.showSnackBar(SnackBar(content: Text('$saved · $path')));
                      },
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );
}

Widget _kv(BuildContext context, String k, String v, String? fp) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 70, child: Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 12.5))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                if (fp != null && fp.length == 32)
                  Text(groupFingerprint(fp),
                      textDirection: TextDirection.ltr, style: kMono.copyWith(color: AppColors.muted, fontSize: 10.5)),
              ],
            ),
          ),
        ],
      ),
    );
