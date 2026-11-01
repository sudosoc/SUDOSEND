import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wraith_core/identity.dart';
import 'package:wraith_core/util.dart';
import 'package:wraith_core/wraith.dart' show kProtocol;

import '../app/scope.dart';
import '../state/app_controller.dart';
import 'background.dart';
import 'glass.dart';
import 'home.dart' show showRenameDialog;
import 'receive_tab.dart' show InfoRow;
import 'theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgTop,
      body: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackground()),
          SafeArea(
            child: ListenableBuilder(
              listenable: Listenable.merge([controller, controller.settings]),
              builder: (context, _) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 16, 6),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const BackButtonIcon(),
                          color: AppColors.text,
                        ),
                        const SizedBox(width: 4),
                        Text(context.tr('settings'),
                            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                          children: _sections(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _sections(BuildContext context) {
    final s = controller.settings;
    final id = controller.identity;
    final keyStorage = switch (id.protection) {
      'dpapi' => context.tr('ks_dpapi'),
      'android-keystore' => context.tr('ks_android'),
      _ => context.tr('ks_file'),
    };
    final divider = Divider(height: 18, color: Colors.white.withValues(alpha: 0.07));
    return [
      // ── This device ──
      SectionTitle(context.tr('s_device')),
      Glass(
        child: Column(
          children: [
            InfoRow(
              icon: platformIcon(platformName()),
              color: platformColor(platformName()),
              label: context.tr('s_name'),
              value: id.name,
              trailing: IconButton(
                icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.muted),
                onPressed: () => showRenameDialog(context, controller),
              ),
            ),
            divider,
            InfoRow(
              icon: Icons.fingerprint_rounded,
              color: AppColors.cyan,
              label: context.tr('fingerprint'),
              value: groupFingerprint(id.fingerprint),
              mono: true,
              copyValue: id.fingerprint,
              copiedMessage: context.tr('fingerprint_copied'),
            ),
            divider,
            InfoRow(icon: Icons.key_rounded, color: AppColors.amber, label: context.tr('s_key_storage'), value: keyStorage),
          ],
        ),
      ),
      const SizedBox(height: 22),

      // ── Receiving ──
      SectionTitle(context.tr('s_receiving')),
      Glass(
        child: Column(
          children: [
            InfoRow(
              icon: Icons.folder_rounded,
              color: AppColors.amber,
              label: context.tr('s_save_dir'),
              value: controller.saveDir?.path ?? '—',
              ltr: true,
            ),
            if (!Platform.isIOS) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  GhostButton(
                    label: context.tr('s_change'),
                    icon: Icons.drive_folder_upload_rounded,
                    color: AppColors.cyan,
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final error = await controller.chooseSaveDir();
                      if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
                    },
                  ),
                  if (s.saveDir != null)
                    GhostButton(label: context.tr('s_reset'), icon: Icons.restart_alt_rounded, onPressed: controller.resetSaveDir),
                ],
              ),
            ],
            divider,
            _Switch(
              icon: Icons.verified_user_rounded,
              color: AppColors.mint,
              title: context.tr('s_auto_accept'),
              subtitle: context.tr('s_auto_accept_sub'),
              value: s.autoAcceptTrusted,
              onChanged: (v) => s.update((x) => x.autoAcceptTrusted = v),
            ),
            if (Platform.isAndroid) ...[
              divider,
              _Switch(
                icon: Icons.nights_stay_rounded,
                color: AppColors.violet,
                title: context.tr('s_background'),
                subtitle: context.tr('s_background_sub'),
                value: s.backgroundReceive,
                onChanged: controller.setBackgroundReceive,
              ),
            ],
            divider,
            _Switch(
              icon: Icons.notifications_rounded,
              color: AppColors.pink,
              title: context.tr('s_notifications'),
              subtitle: context.tr('s_notifications_sub'),
              value: s.notifications,
              onChanged: controller.setNotifications,
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),

      // ── Privacy & security ──
      SectionTitle(context.tr('s_privacy')),
      Glass(
        child: Column(
          children: [
            _Switch(
              icon: Icons.visibility_off_rounded,
              color: AppColors.violet,
              title: context.tr('s_stealth'),
              subtitle: context.tr('s_stealth_sub'),
              value: s.stealth,
              onChanged: controller.setStealth,
            ),
            divider,
            _DeviceList(
              title: context.tr('s_trusted'),
              empty: context.tr('s_trusted_none'),
              icon: Icons.verified_user_rounded,
              color: AppColors.mint,
              devices: controller.trust.all,
              actionLabel: context.tr('s_revoke'),
              actionIcon: Icons.remove_moderator_outlined,
              onAction: controller.untrust,
            ),
            divider,
            _DeviceList(
              title: context.tr('s_blocked'),
              empty: context.tr('s_blocked_none'),
              icon: Icons.block_rounded,
              color: AppColors.danger,
              devices: controller.trust.blocked,
              actionLabel: context.tr('s_unblock'),
              actionIcon: Icons.lock_open_rounded,
              onAction: controller.unblock,
            ),
            divider,
            Row(
              children: [
                const IconBadge(icon: Icons.shield_rounded, color: AppColors.cyan, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('s_rejected', {'n': controller.rejectedConnections}),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(context.tr('s_rejected_sub'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),

      // ── Appearance ──
      SectionTitle(context.tr('s_appearance')),
      Glass(
        child: Column(
          children: [
            Row(
              children: [
                const IconBadge(icon: Icons.translate_rounded, color: AppColors.cyan, size: 38),
                const SizedBox(width: 12),
                Expanded(child: Text(context.tr('s_language'), style: const TextStyle(fontWeight: FontWeight.w700))),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              showSelectedIcon: false,
              style: ButtonStyle(
                foregroundColor: WidgetStateProperty.resolveWith(
                    (st) => st.contains(WidgetState.selected) ? AppColors.ink : AppColors.text),
                backgroundColor: WidgetStateProperty.resolveWith(
                    (st) => st.contains(WidgetState.selected) ? AppColors.cyan : Colors.white.withValues(alpha: 0.04)),
                side: WidgetStatePropertyAll(BorderSide(color: Colors.white.withValues(alpha: 0.14))),
              ),
              segments: [
                ButtonSegment(value: 'system', label: Text(context.tr('lang_system'))),
                const ButtonSegment(value: 'en', label: Text('English')),
                const ButtonSegment(value: 'ar', label: Text('العربية')),
              ],
              selected: {s.language},
              onSelectionChanged: (v) => s.update((x) => x.language = v.first),
            ),
            divider,
            _Switch(
              icon: Icons.blur_off_rounded,
              color: AppColors.amber,
              title: context.tr('s_effects'),
              subtitle: context.tr('s_effects_sub'),
              value: s.reduceEffects,
              onChanged: (v) => s.update((x) => x.reduceEffects = v),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),

      // ── About ──
      SectionTitle(context.tr('s_about')),
      Glass(
        child: Column(
          children: [
            InfoRow(icon: Icons.bolt_rounded, color: AppColors.cyan, label: context.tr('s_version'), value: 'SUDOSEND $kAppVersion', ltr: true),
            divider,
            InfoRow(
                icon: Icons.hub_rounded,
                color: AppColors.violet,
                label: context.tr('s_protocol'),
                value: '$kProtocol · X25519 · Ed25519 · ChaCha20-Poly1305',
                ltr: true),
            divider,
            InfoRow(
              icon: Icons.code_rounded,
              color: AppColors.mint,
              label: context.tr('s_source'),
              value: 'github.com/sudosoc/SUDOSEND',
              ltr: true,
              copyValue: 'https://github.com/sudosoc/SUDOSEND',
            ),
            divider,
            InfoRow(
              icon: Icons.person_rounded,
              color: AppColors.pink,
              label: context.tr('s_developer'),
              value: 'SUDOSOC · ceo@sudosoc.com',
              ltr: true,
              copyValue: 'ceo@sudosoc.com',
            ),
            divider,
            InfoRow(icon: Icons.gavel_rounded, color: AppColors.amber, label: context.tr('s_license'), value: 'MIT', ltr: true),
          ],
        ),
      ),
    ];
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            IconBadge(icon: icon, color: color, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: value,
              onChanged: onChanged,
              thumbColor: WidgetStateProperty.resolveWith(
                  (st) => st.contains(WidgetState.selected) ? AppColors.ink : AppColors.muted),
              trackColor: WidgetStateProperty.resolveWith(
                  (st) => st.contains(WidgetState.selected) ? AppColors.cyan : Colors.white.withValues(alpha: 0.08)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({
    required this.title,
    required this.empty,
    required this.icon,
    required this.color,
    required this.devices,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
  });

  final String title;
  final String empty;
  final IconData icon;
  final Color color;
  final List<KnownDevice> devices;
  final String actionLabel;
  final IconData actionIcon;
  final Future<void> Function(String fingerprint) onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconBadge(icon: icon, color: color, size: 38),
            const SizedBox(width: 12),
            Expanded(child: Text('$title (${devices.length})', style: const TextStyle(fontWeight: FontWeight.w700))),
          ],
        ),
        const SizedBox(height: 6),
        if (devices.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 50, top: 2, bottom: 4),
            child: Text(empty, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          )
        else
          for (final d in devices)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 50),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(groupFingerprint(d.fingerprint, groups: 4),
                            textDirection: TextDirection.ltr, style: kMono.copyWith(color: AppColors.muted, fontSize: 11)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: actionLabel,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      onAction(d.fingerprint);
                    },
                    icon: Icon(actionIcon, color: color, size: 20),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
