import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wraith_core/identity.dart';
import 'package:wraith_core/models.dart';
import 'package:wraith_core/util.dart';
import 'package:wraith_core/wraith.dart' show kProtocol;

import '../app/scope.dart';
import '../platform/desktop.dart';
import '../state/app_controller.dart';
import '../state/updater.dart' show kReleaseRepo;
import 'about_pages.dart';
import 'audit_page.dart';
import 'background.dart';
import 'dashboard_page.dart';
import 'device_page.dart';
import 'devices_page.dart';
import 'glass.dart';
import 'home.dart' show showRenameDialog;
import 'receive_tab.dart' show InfoRow;
import 'recovery_page.dart';
import 'sync_page.dart';
import 'theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    // Each entry opens either a settings section or a full page.
    Widget Function() section(List<Widget> Function(BuildContext) b, String title) =>
        () => _SettingsScaffold(controller: controller, title: context.tr(title), children: b);
    final cats = <(IconData, Color, String, String, Widget Function())>[
      (Icons.smartphone_rounded, AppColors.cyan, 's_device', 'cat_device_sub', section(_device, 's_device')),
      (Icons.devices_other_rounded, AppColors.violet, 'devices_title', 'cat_devices_sub', () => DevicesPage(controller: controller)),
      (Icons.download_rounded, AppColors.amber, 's_receiving', 'cat_receiving_sub', section(_receiving, 's_receiving')),
      (Icons.extension_rounded, AppColors.violet, 's_features', 's_features_sub', section(_features, 's_features')),
      (Icons.shield_rounded, AppColors.mint, 's_privacy', 'cat_privacy_sub', section(_privacy, 's_privacy')),
      (Icons.insights_rounded, AppColors.pink, 'dash_title', 'cat_dash_sub', () => DashboardPage(controller: controller)),
      (Icons.policy_rounded, AppColors.amber, 'audit_title', 'cat_audit_sub', () => AuditPage(controller: controller)),
      (Icons.healing_rounded, AppColors.mint, 'rec_title', 'cat_rec_sub', () => RecoveryPage(controller: controller)),
      (Icons.data_usage_rounded, AppColors.pink, 's_usage', 'cat_usage_sub', section(_usage, 's_usage')),
      (Icons.palette_rounded, AppColors.amber, 's_appearance', 'cat_appearance_sub', section(_appearance, 's_appearance')),
      (Icons.info_rounded, AppColors.cyan, 's_about', 'cat_about_sub', section(_about, 's_about')),
    ];
    return _SettingsScaffold(
      controller: controller,
      title: context.tr('settings'),
      children: (context) => [
        for (final c in cats)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Glass(
              padding: const EdgeInsets.all(14),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => c.$5())),
              child: Row(
                children: [
                  IconBadge(icon: c.$1, color: c.$2, size: 42),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.tr(c.$3), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                        const SizedBox(height: 2),
                        Text(context.tr(c.$4), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget get _divider => Divider(height: 18, color: Colors.white.withValues(alpha: 0.07));

  List<Widget> _device(BuildContext context) {
    final id = controller.identity;
    final keyStorage = switch (id.protection) {
      'dpapi' => context.tr('ks_dpapi'),
      'android-keystore' => context.tr('ks_android'),
      _ => context.tr('ks_file'),
    };
    return [
      Glass(
        child: Column(
          children: [
            InfoRow(
              icon: platformIcon(platformName()),
              color: platformColor(platformName()),
              label: context.tr('s_name'),
              value: id.name,
              trailing: IconButton(
                tooltip: context.tr('edit'),
                icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.muted),
                onPressed: () => showRenameDialog(context, controller),
              ),
            ),
            _divider,
            InfoRow(
              icon: Icons.fingerprint_rounded,
              color: AppColors.cyan,
              label: context.tr('fingerprint'),
              value: groupFingerprint(id.fingerprint),
              mono: true,
              copyValue: id.fingerprint,
              copiedMessage: context.tr('fingerprint_copied'),
            ),
            _divider,
            InfoRow(
              icon: Icons.key_rounded,
              color: AppColors.amber,
              label: context.tr('s_key_storage'),
              value: keyStorage,
              trailing: InfoButton(title: context.tr('s_key_storage'), body: context.tr('i_key_storage')),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _receiving(BuildContext context) {
    final s = controller.settings;
    return [
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
            _divider,
            _Switch(
              icon: Icons.account_tree_rounded,
              color: AppColors.amber,
              title: context.tr('org_title'),
              subtitle: context.tr('org_sub'),
              info: 'i_organize',
              value: s.organize,
              onChanged: (v) => s.update((x) => x.organize = v),
            ),
            if (s.organize) ...[
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 50),
                child: Column(
                  children: [
                    _SubSwitch(
                      label: context.tr('org_by_device'),
                      value: s.organizeByDevice,
                      onChanged: (v) => s.update((x) => x.organizeByDevice = v),
                    ),
                    _SubSwitch(
                      label: context.tr('org_by_type'),
                      value: s.organizeByType,
                      onChanged: (v) => s.update((x) => x.organizeByType = v),
                    ),
                    _SubSwitch(
                      label: context.tr('org_by_date'),
                      value: s.organizeByDate,
                      onChanged: (v) => s.update((x) => x.organizeByDate = v),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.black.withValues(alpha: 0.2),
                      ),
                      child: Text(controller.organizeExample(),
                          textDirection: TextDirection.ltr, style: kMono.copyWith(fontSize: 11.5, color: AppColors.cyan)),
                    ),
                  ],
                ),
              ),
            ] else ...[
              _divider,
              _Switch(
                icon: Icons.create_new_folder_rounded,
                color: AppColors.amber,
                title: context.tr('s_sender_folders'),
                subtitle: context.tr('s_sender_folders_sub'),
                info: 'i_sender_folders',
                value: s.senderFolders,
                onChanged: (v) => s.update((x) => x.senderFolders = v),
              ),
            ],
            _divider,
            _Switch(
              icon: Icons.verified_user_rounded,
              color: AppColors.mint,
              title: context.tr('s_auto_accept'),
              subtitle: context.tr('s_auto_accept_sub'),
              info: 'i_auto_accept',
              value: s.autoAcceptTrusted,
              onChanged: (v) => s.update((x) => x.autoAcceptTrusted = v),
            ),
            _divider,
            _Switch(
              icon: Icons.content_paste_go_rounded,
              color: AppColors.cyan,
              title: context.tr('s_auto_copy'),
              subtitle: context.tr('s_auto_copy_sub'),
              info: 'i_auto_copy',
              value: s.autoCopyText,
              onChanged: (v) => s.update((x) => x.autoCopyText = v),
            ),
            if (Platform.isAndroid) ...[
              _divider,
              _Switch(
                icon: Icons.nights_stay_rounded,
                color: AppColors.violet,
                title: context.tr('s_background'),
                subtitle: context.tr('s_background_sub'),
                info: 'i_background',
                value: s.backgroundReceive,
                onChanged: controller.setBackgroundReceive,
              ),
            ],
            _divider,
            _Switch(
              icon: Icons.notifications_rounded,
              color: AppColors.pink,
              title: context.tr('s_notifications'),
              subtitle: context.tr('s_notifications_sub'),
              info: 'i_notifications',
              value: s.notifications,
              onChanged: controller.setNotifications,
            ),
            if (s.notifications)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 50),
                child: Column(
                  children: [
                    _SubSwitch(
                      label: context.tr('nt_done'),
                      value: s.notifyDone,
                      onChanged: (v) => s.update((x) => x.notifyDone = v),
                    ),
                    _SubSwitch(
                      label: context.tr('nt_failed'),
                      value: s.notifyFailed,
                      onChanged: (v) => s.update((x) => x.notifyFailed = v),
                    ),
                    _SubSwitch(
                      label: context.tr('nt_duplicates'),
                      value: s.notifyDuplicates,
                      onChanged: (v) => s.update((x) => x.notifyDuplicates = v),
                    ),
                    _SubSwitch(
                      label: context.tr('nt_storage'),
                      value: s.notifyStorage,
                      onChanged: (v) => s.update((x) => x.notifyStorage = v),
                    ),
                  ],
                ),
              ),
            _divider,
            _Header(
              icon: Icons.copy_all_rounded,
              color: AppColors.amber,
              title: context.tr('dup_setting'),
              subtitle: context.tr('dup_setting_sub'),
              info: 'i_duplicates',
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'keep', label: Text(context.tr('dup_keep'))),
                ButtonSegment(value: 'remove', label: Text(context.tr('dup_remove'))),
              ],
              selected: {s.duplicates},
              onSelectionChanged: (v) => s.update((x) => x.duplicates = v.first),
            ),
            _divider,
            _Switch(
              icon: Icons.sd_storage_rounded,
              color: AppColors.mint,
              title: context.tr('sg_title'),
              subtitle: context.tr('sg_sub'),
              info: 'i_storage',
              value: s.storageGuard,
              onChanged: (v) => s.update((x) => x.storageGuard = v),
            ),
            _divider,
            _Header(
              icon: Icons.speed_rounded,
              color: AppColors.cyan,
              title: context.tr('s_speed'),
              subtitle: context.tr('s_speed_sub'),
              info: 'i_speed_limit',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final v in const [0, 1, 5, 10, 50])
                  ChoiceChip(
                    label: Text(v == 0 ? context.tr('s_speed_unlimited') : '$v MB/s'),
                    selected: s.uploadLimit == v,
                    onSelected: (_) => s.update((x) => x.uploadLimit = v),
                  ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _features(BuildContext context) {
    final s = controller.settings;
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(context.tr('s_features_sub'), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
      ),
      SectionTitle(context.tr('fg_transfer')),
      Glass(
        child: Column(
          children: [
            _Switch(
              icon: Icons.compress_rounded,
              color: AppColors.cyan,
              title: context.tr('f_compression'),
              subtitle: context.tr('f_compression_sub'),
              info: 'i_compression',
              value: s.compression,
              onChanged: (v) => s.update((x) => x.compression = v),
            ),
            _divider,
            _Switch(
              icon: Icons.image_rounded,
              color: AppColors.pink,
              title: context.tr('f_previews_send'),
              subtitle: context.tr('f_previews_send_sub'),
              info: 'i_previews_send',
              value: s.previewsSend,
              onChanged: (v) => s.update((x) => x.previewsSend = v),
            ),
            _divider,
            _Switch(
              icon: Icons.photo_library_rounded,
              color: AppColors.pink,
              title: context.tr('f_previews_show'),
              subtitle: context.tr('f_previews_show_sub'),
              info: 'i_previews_show',
              value: s.previewsShow,
              onChanged: (v) => s.update((x) => x.previewsShow = v),
            ),
            _divider,
            _Switch(
              icon: Icons.schedule_send_rounded,
              color: AppColors.violet,
              title: context.tr('f_queue'),
              subtitle: context.tr('f_queue_sub'),
              info: 'i_queue',
              value: s.offlineQueue,
              onChanged: (v) => s.update((x) => x.offlineQueue = v),
            ),
            if (isDesktop) ...[
              _divider,
              _Switch(
                icon: Icons.drive_folder_upload_rounded,
                color: AppColors.amber,
                title: context.tr('s_hot'),
                subtitle: context.tr('s_hot_sub'),
                info: 'i_hot',
                value: s.hotFolders,
                onChanged: (v) => s.update((x) => x.hotFolders = v),
              ),
              if (s.hotFolders)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    onPressed: () => controller.reveal(controller.hotRoot),
                    icon: const Icon(Icons.folder_open_rounded, size: 18, color: AppColors.cyan),
                    label: Text(context.tr('s_hot_open'), style: const TextStyle(color: AppColors.cyan)),
                  ),
                ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 22),
      SectionTitle(context.tr('fg_files')),
      Glass(
        child: Column(
          children: [
            if (Platform.isAndroid) ...[
              _Switch(
                icon: Icons.apps_rounded,
                color: AppColors.mint,
                title: context.tr('f_share_apps'),
                subtitle: context.tr('f_share_apps_sub'),
                info: 'i_share_apps',
                value: s.shareApps,
                onChanged: (v) => s.update((x) => x.shareApps = v),
              ),
              if (s.shareApps)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 50),
                  child: _SubSwitch(
                    label: context.tr('apps_system'),
                    value: s.showSystemApps,
                    onChanged: (v) => s.update((x) => x.showSystemApps = v),
                  ),
                ),
              _divider,
            ],
            _Switch(
              icon: Icons.manage_search_rounded,
              color: AppColors.cyan,
              title: context.tr('f_metadata'),
              subtitle: context.tr('f_metadata_sub'),
              info: 'i_metadata_explorer',
              value: s.showMetadata,
              onChanged: (v) => s.update((x) => x.showMetadata = v),
            ),
            if (s.showMetadata)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 50),
                child: _SubSwitch(
                  label: context.tr('f_metadata_gps'),
                  value: s.showGps,
                  onChanged: (v) => s.update((x) => x.showGps = v),
                ),
              ),
            _divider,
            _Switch(
              icon: Icons.travel_explore_rounded,
              color: AppColors.violet,
              title: context.tr('f_remote_search'),
              subtitle: context.tr('f_remote_search_sub'),
              info: 'i_remote_search',
              value: s.remoteSearch,
              onChanged: (v) => s.update((x) => x.remoteSearch = v),
            ),
            if (s.remoteSearch)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 50, top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(context.tr('f_remote_limit'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                    for (final n in const [20, 50, 100, 200])
                      ChoiceChip(
                        label: Text('$n'),
                        selected: s.remoteSearchLimit == n,
                        onSelected: (_) => s.update((x) => x.remoteSearchLimit = n),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      SectionTitle(context.tr('fg_devices')),
      Glass(
        child: Column(
          children: [
            _Switch(
              icon: Icons.forum_rounded,
              color: AppColors.cyan,
              title: context.tr('f_chat'),
              subtitle: context.tr('f_chat_sub'),
              info: 'i_chat',
              value: s.chat,
              onChanged: (v) => s.update((x) => x.chat = v),
            ),
            _divider,
            _Switch(
              icon: Icons.sync_alt_rounded,
              color: AppColors.violet,
              title: context.tr('f_sync'),
              subtitle: context.tr(Platform.isIOS ? 'sync_unsupported' : 'f_sync_sub'),
              info: 'i_sync',
              value: s.folderSync,
              onChanged: Platform.isIOS ? null : (v) => s.update((x) => x.folderSync = v),
            ),
            if (controller.syncSupported)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => SyncPage(controller: controller))),
                  icon: const Icon(Icons.folder_copy_rounded, size: 18, color: AppColors.violet),
                  label: Text(context.tr('sync_manage', {'n': s.syncPairs.length}),
                      style: const TextStyle(color: AppColors.violet)),
                ),
              ),
            if (Platform.isAndroid) ...[
              _divider,
              _Switch(
                icon: Icons.wifi_tethering_rounded,
                color: AppColors.cyan,
                title: context.tr('f_wifi_direct'),
                subtitle: context.tr('f_wifi_direct_sub'),
                info: 'i_wifi_direct',
                value: s.wifiDirect,
                onChanged: (v) => s.update((x) => x.wifiDirect = v),
              ),
            ],
            _divider,
            _Switch(
              icon: Icons.speed_rounded,
              color: AppColors.mint,
              title: context.tr('f_speed'),
              subtitle: context.tr('f_speed_sub'),
              info: 'i_speed',
              value: s.allowSpeedTest,
              onChanged: (v) => s.update((x) => x.allowSpeedTest = v),
            ),
            _divider,
            _Switch(
              icon: Icons.sync_rounded,
              color: AppColors.violet,
              title: context.tr('s_clip_sync'),
              subtitle: context.tr(isDesktop ? 's_clip_sync_sub' : 's_clip_sync_sub_mobile'),
              info: 'i_clip_sync',
              value: s.clipboardSync,
              onChanged: (v) => s.update((x) => x.clipboardSync = v),
            ),
            _divider,
            _Switch(
              icon: Icons.notifications_active_rounded,
              color: AppColors.amber,
              title: context.tr('s_ring'),
              subtitle: context.tr('s_ring_sub'),
              info: 'i_ring',
              value: s.allowRing,
              onChanged: (v) => s.update((x) => x.allowRing = v),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      SectionTitle(context.tr('fg_app')),
      Glass(
        child: _Switch(
          icon: Icons.system_update_rounded,
          color: AppColors.mint,
          title: context.tr('f_update'),
          subtitle: context.tr('f_update_sub'),
          info: 'i_update',
          value: s.autoUpdateCheck,
          onChanged: (v) => s.update((x) => x.autoUpdateCheck = v),
        ),
      ),
      const SizedBox(height: 22),
      SectionTitle(context.tr('fg_noapp')),
      Glass(
        child: Column(
          children: [
            _Switch(
              icon: Icons.public_rounded,
              color: AppColors.violet,
              title: context.tr('f_web'),
              subtitle: context.tr('f_web_sub'),
              info: 'i_web',
              value: s.webShare,
              onChanged: (v) => s.update((x) => x.webShare = v),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _privacy(BuildContext context) {
    final s = controller.settings;
    return [
      Glass(
        child: Column(
          children: [
            _Switch(
              icon: Icons.visibility_off_rounded,
              color: AppColors.violet,
              title: context.tr('s_stealth'),
              subtitle: context.tr('s_stealth_sub'),
              info: 'i_stealth',
              value: s.stealth,
              onChanged: controller.setStealth,
            ),
            _divider,
            _Header(
              icon: Icons.location_off_rounded,
              color: AppColors.pink,
              title: context.tr('md_title'),
              subtitle: context.tr('md_sub'),
              info: 'i_metadata',
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              showSelectedIcon: false,
              style: ButtonStyle(
                foregroundColor: WidgetStateProperty.resolveWith(
                    (st) => st.contains(WidgetState.selected) ? AppColors.ink : AppColors.text),
                backgroundColor: WidgetStateProperty.resolveWith(
                    (st) => st.contains(WidgetState.selected) ? AppColors.pink : Colors.white.withValues(alpha: 0.04)),
                side: WidgetStatePropertyAll(BorderSide(color: Colors.white.withValues(alpha: 0.14))),
              ),
              segments: [
                ButtonSegment(value: 'off', label: Text(context.tr('md_off'))),
                ButtonSegment(value: 'location', label: Text(context.tr('md_location'))),
                ButtonSegment(value: 'all', label: Text(context.tr('md_all'))),
              ],
              selected: {s.metadata},
              onSelectionChanged: (v) => s.update((x) => x.metadata = v.first),
            ),
            const SizedBox(height: 6),
            Text(context.tr('md_${s.metadata}_sub'), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            _divider,
            _DeviceList(
              title: context.tr('s_trusted'),
              empty: context.tr('s_trusted_none'),
              icon: Icons.verified_user_rounded,
              color: AppColors.mint,
              info: 'i_trusted',
              devices: controller.trust.all,
              onOpen: (d) => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => DevicePage(controller: controller, fingerprint: d.fingerprint, name: d.name),
              )),
              actionLabel: context.tr('s_revoke'),
              actionIcon: Icons.remove_moderator_outlined,
              onAction: controller.untrust,
            ),
            _divider,
            _DeviceList(
              title: context.tr('s_blocked'),
              empty: context.tr('s_blocked_none'),
              icon: Icons.block_rounded,
              color: AppColors.danger,
              info: 'i_blocked',
              devices: controller.trust.blocked,
              actionLabel: context.tr('s_unblock'),
              actionIcon: Icons.lock_open_rounded,
              onAction: controller.unblock,
            ),
            _divider,
            _Header(
              icon: Icons.receipt_long_rounded,
              color: AppColors.mint,
              title: context.tr('s_audit'),
              subtitle: context.tr('s_audit_sub'),
              info: 'i_audit',
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: GhostButton(
                label: context.tr('s_export'),
                icon: Icons.download_rounded,
                color: AppColors.mint,
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final saved = context.tr('history_exported');
                  final path = await controller.exportHistory();
                  if (path != null) messenger.showSnackBar(SnackBar(content: Text('$saved · $path')));
                },
              ),
            ),
            _divider,
            _Header(
              icon: Icons.shield_rounded,
              color: AppColors.cyan,
              title: context.tr('s_rejected', {'n': controller.rejectedConnections}),
              subtitle: context.tr('s_rejected_sub'),
              info: 'i_rejected',
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _usage(BuildContext context) => [Glass(child: _UsageCard(controller: controller))];

  List<Widget> _appearance(BuildContext context) {
    final s = controller.settings;
    ButtonStyle segStyle(Color accent) => ButtonStyle(
          foregroundColor:
              WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? AppColors.ink : AppColors.text),
          backgroundColor: WidgetStateProperty.resolveWith(
              (st) => st.contains(WidgetState.selected) ? accent : Colors.white.withValues(alpha: 0.04)),
          side: WidgetStatePropertyAll(BorderSide(color: Colors.white.withValues(alpha: 0.14))),
        );
    return [
      Glass(
        child: Column(
          children: [
            _Header(icon: Icons.translate_rounded, color: AppColors.cyan, title: context.tr('s_language')),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              showSelectedIcon: false,
              style: segStyle(AppColors.cyan),
              segments: [
                ButtonSegment(value: 'system', label: Text(context.tr('lang_system'))),
                const ButtonSegment(value: 'en', label: Text('English')),
                const ButtonSegment(value: 'ar', label: Text('العربية')),
              ],
              selected: {s.language},
              onSelectionChanged: (v) => s.update((x) => x.language = v.first),
            ),
            _divider,
            _Header(
              icon: Icons.auto_awesome_rounded,
              color: AppColors.amber,
              title: context.tr('s_effects'),
              subtitle: context.tr('s_effects_sub'),
              info: 'i_effects',
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              showSelectedIcon: false,
              style: segStyle(AppColors.amber),
              segments: [
                ButtonSegment(value: 'lite', label: Text(context.tr('fx_lite'))),
                ButtonSegment(value: 'balanced', label: Text(context.tr('fx_balanced'))),
                ButtonSegment(value: 'full', label: Text(context.tr('fx_full'))),
              ],
              selected: {s.effects},
              onSelectionChanged: (v) => s.update((x) => x.effects = v.first),
            ),
            const SizedBox(height: 6),
            Text(context.tr('fx_${s.effects}_sub'), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ),
      ),
    ];
  }

  List<Widget> _about(BuildContext context) => [
        Glass(
          padding: const EdgeInsets.all(14),
          onTap: () => showUpdateDialog(context, controller),
          borderColor: controller.updateAvailable != null ? AppColors.mint.withValues(alpha: 0.6) : null,
          child: Row(
            children: [
              const IconBadge(icon: Icons.system_update_rounded, color: AppColors.mint, size: 42),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('update_check'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                    Text(
                      controller.updateAvailable != null
                          ? context.tr('update_new', {'v': controller.updateAvailable!.version})
                          : context.tr('update_current', {'v': kAppVersion}),
                      style: TextStyle(
                          color: controller.updateAvailable != null ? AppColors.mint : AppColors.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Glass(
          padding: const EdgeInsets.all(14),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => DeveloperPage(controller: controller))),
          child: Row(
            children: [
              const DeveloperAvatar(size: 42),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('dev_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                    const Text('${Developer.name} · ${Developer.alias}',
                        style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Glass(
          child: Column(
            children: [
              InfoRow(icon: Icons.bolt_rounded, color: AppColors.cyan, label: context.tr('s_version'), value: 'SUDOSEND $kAppVersion', ltr: true),
              _divider,
              InfoRow(
                  icon: Icons.hub_rounded,
                  color: AppColors.violet,
                  label: context.tr('s_protocol'),
                  value: '$kProtocol · X25519 · Ed25519 · ChaCha20-Poly1305',
                  ltr: true),
              _divider,
              InfoRow(
                icon: Icons.download_rounded,
                color: AppColors.mint,
                label: context.tr('s_downloads'),
                value: 'github.com/$kReleaseRepo',
                ltr: true,
                copyValue: 'https://github.com/$kReleaseRepo',
              ),
              _divider,
              InfoRow(icon: Icons.gavel_rounded, color: AppColors.amber, label: context.tr('s_license'), value: 'MIT', ltr: true),
            ],
          ),
        ),
      ];
}

/// Background + header + centred list; rebuilds when settings change.
class _SettingsScaffold extends StatelessWidget {
  const _SettingsScaffold({required this.controller, required this.title, required this.children});
  final AppController controller;
  final String title;
  final List<Widget> Function(BuildContext context) children;

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
                  SubPageHeader(title: title),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                          children: children(context),
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
}

/// The (i) button: opens a short explanation of a feature.
class InfoButton extends StatelessWidget {
  const InfoButton({super.key, required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.tr('more_info'),
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.info_outline_rounded, size: 20, color: AppColors.muted),
      onPressed: () => showInfo(context, title, body),
    );
  }
}

Future<void> showInfo(BuildContext context, String title, String body) => showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => GlassDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_rounded, color: AppColors.cyan),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 14),
            Text(body, style: const TextStyle(height: 1.5, fontSize: 14)),
            const SizedBox(height: 18),
            GlowButton(label: ctx.tr('got_it'), expand: true, onPressed: () => Navigator.pop(ctx)),
          ],
        ),
      ),
    );

/// Icon + title (+ subtitle) row with an optional (i) button.
class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.color, required this.title, this.subtitle, this.info});
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final String? info;

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
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (subtitle != null) Text(subtitle!, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ],
          ),
        ),
        if (info != null) InfoButton(title: title, body: context.tr(info!)),
      ],
    );
  }
}

/// Compact indented switch for sub-options.
class _SubSwitch extends StatelessWidget {
  const _SubSwitch({required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5))),
          Switch(
            value: value,
            onChanged: onChanged,
            thumbColor: WidgetStateProperty.resolveWith(
                (st) => st.contains(WidgetState.selected) ? AppColors.ink : AppColors.muted),
            trackColor: WidgetStateProperty.resolveWith(
                (st) => st.contains(WidgetState.selected) ? AppColors.amber : Colors.white.withValues(alpha: 0.08)),
          ),
        ],
      ),
    );
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
    this.info,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// String key of the (i) explanation.
  final String? info;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: change == null ? null : () => change(!value),
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
            if (info != null) InfoButton(title: title, body: context.tr(info!)),
            Switch(
              value: value,
              onChanged: change,
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
    this.info,
    required this.devices,
    this.onOpen,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
  });

  final String title;
  final String empty;
  final IconData icon;
  final Color color;
  final String? info;
  final List<KnownDevice> devices;

  /// Opens per-device settings (trusted list only).
  final void Function(KnownDevice d)? onOpen;
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
            if (info != null) InfoButton(title: title, body: context.tr(info!)),
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
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onOpen == null ? null : () => onOpen!(d),
              child: Padding(
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
                  if (onOpen != null) const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 20),
                ],
              ),
            ),
            ),
      ],
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final perPeer = <String, (int sent, int received, int count)>{};
    var sent = 0, received = 0;
    for (final e in controller.history.entries) {
      if (e.status != TransferStatus.done) continue;
      final cur = perPeer[e.peerName] ?? (0, 0, 0);
      if (e.direction == TransferDirection.outgoing) {
        sent += e.totalBytes;
        perPeer[e.peerName] = (cur.$1 + e.totalBytes, cur.$2, cur.$3 + 1);
      } else {
        received += e.totalBytes;
        perPeer[e.peerName] = (cur.$1, cur.$2 + e.totalBytes, cur.$3 + 1);
      }
    }
    final top = perPeer.entries.toList()..sort((a, b) => (b.value.$1 + b.value.$2).compareTo(a.value.$1 + a.value.$2));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _Stat(icon: Icons.north_east_rounded, color: AppColors.cyan, label: context.tr('s_usage_sent'), value: formatBytes(sent))),
            const SizedBox(width: 10),
            Expanded(child: _Stat(icon: Icons.south_west_rounded, color: AppColors.mint, label: context.tr('s_usage_received'), value: formatBytes(received))),
          ],
        ),
        if (top.isNotEmpty) const SizedBox(height: 12),
        for (final e in top.take(6))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text(e.key, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                Text('↑ ${formatBytes(e.value.$1)}  ↓ ${formatBytes(e.value.$2)}  · ${e.value.$3}',
                    textDirection: TextDirection.ltr, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ],
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.color, required this.label, required this.value});
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                Text(value, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
