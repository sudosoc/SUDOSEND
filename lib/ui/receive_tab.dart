import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/util.dart';
import '../state/app_controller.dart';
import 'glass.dart';
import 'radar.dart';
import 'theme.dart';

class ReceiveTab extends StatelessWidget {
  const ReceiveTab({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final id = controller.identity;
    final trusted = controller.trust.all;
    return LayoutBuilder(builder: (context, constraints) {
      final radarSize = min(constraints.maxWidth - 48, 300.0);
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Center(
            child: Radar(
              size: radarSize,
              blips: [for (final p in controller.peers) p.id],
              center: Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: kAccentGradient,
                  boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.55), blurRadius: 40, spreadRadius: -4)],
                ),
                child: Icon(platformIcon(platformName()), color: AppColors.ink, size: 38),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text('Visible as ${id.name}',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              controller.localAddresses.isEmpty
                  ? 'Ready to receive · port ${controller.port}'
                  : 'Ready to receive · ${controller.localAddresses.join(' · ')}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
          const SizedBox(height: 22),
          Glass(
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.fingerprint_rounded,
                  color: AppColors.cyan,
                  label: 'Device fingerprint',
                  value: groupFingerprint(id.fingerprint),
                  mono: true,
                  copyValue: id.fingerprint,
                ),
                _divider(),
                _InfoRow(
                  icon: Icons.folder_rounded,
                  color: AppColors.amber,
                  label: 'Saving to',
                  value: controller.saveDir?.path ?? '—',
                ),
                _divider(),
                const _InfoRow(
                  icon: Icons.lock_rounded,
                  color: AppColors.mint,
                  label: 'Encryption',
                  value: 'X25519 · ChaCha20-Poly1305 · Ed25519 · SHA-256',
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionTitle('Trusted devices'),
          if (trusted.isEmpty)
            const Glass(
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, color: AppColors.muted),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Devices you trust skip the verification code next time. You can revoke them here.',
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ),
                ],
              ),
            )
          else
            Glass(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(
                children: [
                  for (var i = 0; i < trusted.length; i++) ...[
                    if (i > 0) _divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.verified_user_rounded, color: AppColors.mint, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(trusted[i].name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text(groupFingerprint(trusted[i].fingerprint, groups: 4),
                                    style: kMono.copyWith(color: AppColors.muted, fontSize: 11)),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Revoke trust',
                            onPressed: () => controller.untrust(trusted[i].fingerprint),
                            icon: const Icon(Icons.remove_moderator_outlined, color: AppColors.danger, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      );
    });
  }

  static Widget _divider() => Divider(height: 18, color: Colors.white.withValues(alpha: 0.07));
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.mono = false,
    this.copyValue,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final bool mono;
  final String? copyValue;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconBadge(icon: icon, color: color, size: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              const SizedBox(height: 2),
              Text(
                value,
                style: mono
                    ? kMono.copyWith(fontSize: 12.5, letterSpacing: 0.6)
                    : const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        if (copyValue != null)
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.muted),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: copyValue!));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fingerprint copied')));
            },
          ),
      ],
    );
  }
}
