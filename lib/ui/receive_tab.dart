import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wraith_core/util.dart';

import '../app/scope.dart';
import '../state/app_controller.dart';
import 'glass.dart';
import 'radar.dart';
import 'theme.dart';
import 'web_share_page.dart';

class ReceiveTab extends StatefulWidget {
  const ReceiveTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<ReceiveTab> createState() => _ReceiveTabState();
}

class _ReceiveTabState extends State<ReceiveTab> {
  Timer? _tick;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    // Re-check the pairing code so an expired or used one is replaced.
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = controller.identity;
    final stealth = controller.settings.stealth;
    final ips = controller.localAddresses.map((a) => a.address).join(' · ');
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 820;
      final radarSize = min(constraints.maxWidth - 48, wide ? 260.0 : 300.0);
      final header = Column(
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
                child: Icon(stealth ? Icons.visibility_off_rounded : platformIcon(platformName()),
                    color: AppColors.ink, size: 38),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(context.tr(stealth ? 'hidden_as' : 'visible_as', {'name': id.name}),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            ips.isEmpty
                ? context.tr('ready_port', {'port': controller.port})
                : context.tr('ready_ips', {'ips': ips}),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          if (stealth) ...[
            const SizedBox(height: 14),
            Glass(
              borderColor: AppColors.violet.withValues(alpha: 0.4),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.visibility_off_rounded, color: AppColors.violet, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(context.tr('stealth_on'), style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),
          ],
        ],
      );
      final qr = _PairingCard(controller: controller);
      final info = _InfoCard(controller: controller);
      final noApp = _NoAppCard(controller: controller);
      final showNoApp = controller.settings.webShare || controller.webShare != null || Platform.isAndroid;
      if (wide) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Column(children: [header, const SizedBox(height: 22), info])),
              const SizedBox(width: 18),
              SizedBox(width: 340, child: Column(children: [qr, if (showNoApp) ...[const SizedBox(height: 16), noApp]])),
            ],
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          header,
          const SizedBox(height: 22),
          qr,
          if (showNoApp) ...[
            const SizedBox(height: 16),
            noApp,
          ],
          const SizedBox(height: 16),
          info,
        ],
      );
    });
  }
}

class _PairingCard extends StatelessWidget {
  const _PairingCard({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final pairing = controller.pairing;
    return Glass(
      glow: AppColors.cyan,
      child: Column(
        children: [
          Row(
            children: [
              const IconBadge(icon: Icons.qr_code_2_rounded, color: AppColors.cyan, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Text(context.tr('pair_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (pairing == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(context.tr('no_network'),
                  textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.35), blurRadius: 30, spreadRadius: -8)],
              ),
              child: QrImageView(
                data: pairing.toUri(),
                size: 220,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.ink),
                dataModuleStyle:
                    const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: AppColors.ink),
              ),
            ),
            const SizedBox(height: 14),
            Text(context.tr('pair_sub'),
                textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                GhostButton(
                  label: context.tr('copy_link'),
                  icon: Icons.link_rounded,
                  color: AppColors.cyan,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: pairing.toUri()));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('link_copied'))));
                  },
                ),
                GhostButton(label: context.tr('new_code'), icon: Icons.refresh_rounded, onPressed: controller.refreshPairing),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Browser receive + hotspot: for when the other side has no app or there is no Wi-Fi.
class _NoAppCard extends StatelessWidget {
  const _NoAppCard({required this.controller});
  final AppController controller;

  static String _wifiEscape(String v) => v.replaceAllMapped(RegExp(r'([\\;,:"])'), (m) => '\\${m[1]}');

  @override
  Widget build(BuildContext context) {
    final hotspot = controller.hotspot;
    return Glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconBadge(icon: Icons.language_rounded, color: AppColors.violet, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('noapp_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                    Text(context.tr('noapp_sub'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (controller.settings.webShare || controller.webShare != null)
          GhostButton(
            label: context.tr(controller.webShare != null ? 'web_open' : 'web_receive'),
            icon: Icons.public_rounded,
            color: AppColors.violet,
            expand: true,
            onPressed: () => controller.webShare != null
                ? Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WebSharePage(controller: controller)))
                : openWebShare(context, controller, upload: true, withSelection: false),
          ),
          if (Platform.isAndroid) ...[
            const SizedBox(height: 10),
            if (hotspot == null)
              GhostButton(
                label: context.tr('hotspot_start'),
                icon: Icons.wifi_tethering_rounded,
                color: AppColors.amber,
                expand: true,
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final error = await controller.startHotspot();
                  if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
                },
              )
            else ...[
              const SizedBox(height: 4),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                  child: QrImageView(
                    data: 'WIFI:T:WPA;S:${_wifiEscape(hotspot.ssid)};P:${_wifiEscape(hotspot.password)};;',
                    size: 180,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(context.tr('hotspot_sub'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              const SizedBox(height: 6),
              SelectableText('Wi-Fi: ${hotspot.ssid}\n${context.tr('hotspot_password')}: ${hotspot.password}',
                  textAlign: TextAlign.center, textDirection: TextDirection.ltr, style: kMono.copyWith(fontSize: 13)),
              const SizedBox(height: 10),
              GhostButton(
                label: context.tr('hotspot_stop'),
                icon: Icons.portable_wifi_off_rounded,
                color: AppColors.danger,
                expand: true,
                onPressed: controller.stopHotspot,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final id = controller.identity;
    return Glass(
      child: Column(
        children: [
          InfoRow(
            icon: Icons.fingerprint_rounded,
            color: AppColors.cyan,
            label: context.tr('fingerprint'),
            value: groupFingerprint(id.fingerprint),
            mono: true,
            copyValue: id.fingerprint,
            copiedMessage: context.tr('fingerprint_copied'),
          ),
          Divider(height: 18, color: Colors.white.withValues(alpha: 0.07)),
          InfoRow(
            icon: Icons.folder_rounded,
            color: AppColors.amber,
            label: context.tr('saving_to'),
            value: controller.saveDir?.path ?? '—',
            ltr: true,
          ),
          Divider(height: 18, color: Colors.white.withValues(alpha: 0.07)),
          InfoRow(
            icon: Icons.lock_rounded,
            color: AppColors.mint,
            label: context.tr('encryption'),
            value: 'X25519 · ChaCha20-Poly1305 · Ed25519 · SHA-256',
            ltr: true,
          ),
        ],
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.mono = false,
    this.ltr = false,
    this.copyValue,
    this.copiedMessage,
    this.trailing,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final bool mono;
  final bool ltr;
  final String? copyValue;
  final String? copiedMessage;
  final Widget? trailing;

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
                textDirection: mono || ltr ? TextDirection.ltr : null,
                style: mono
                    ? kMono.copyWith(fontSize: 12.5, letterSpacing: 0.6)
                    : const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
        if (copyValue != null)
          IconButton(
            tooltip: context.tr('copy'),
            icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.muted),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: copyValue!));
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(copiedMessage ?? context.tr('copied'))));
            },
          ),
      ],
    );
  }
}
