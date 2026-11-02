import 'package:flutter/material.dart';
import 'package:wraith_core/models.dart';
import 'package:wraith_core/organize.dart' show dateFolder;
import 'package:wraith_core/util.dart';

import '../app/scope.dart';
import '../state/app_controller.dart';
import '../state/settings.dart';
import 'background.dart';
import 'devices_page.dart' show groupLabel, sinceLabel;
import 'glass.dart';
import 'settings_page.dart' show InfoButton;
import 'sync_page.dart' show SubPageHeader;
import 'theme.dart';

/// Device profile: identity, nickname, group, permissions, archiving rules,
/// transfer history and connection history for one device.
class DevicePage extends StatefulWidget {
  const DevicePage({super.key, required this.controller, required this.fingerprint, required this.name});
  final AppController controller;
  final String fingerprint;

  /// The name the device announces.
  final String name;

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  late final TextEditingController _nickname =
      TextEditingController(text: widget.controller.settings.prefsFor(widget.fingerprint).nickname ?? '');
  late final TextEditingController _folder =
      TextEditingController(text: widget.controller.settings.prefsFor(widget.fingerprint).folder ?? '');

  AppController get c => widget.controller;
  String get fp => widget.fingerprint;

  @override
  void dispose() {
    _nickname.dispose();
    _folder.dispose();
    super.dispose();
  }

  Future<void> _set(void Function(DevicePrefs d) change) => c.updateDevicePrefs(fp, change);

  void _saveText(BuildContext context) {
    final nick = _nickname.text.trim();
    final folder = _folder.text.trim();
    _set((x) {
      x.nickname = nick.isEmpty ? null : nick;
      x.folder = folder.isEmpty ? null : sanitizeFileName(folder);
    });
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('dp_saved'))));
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
                final d = s.prefsFor(fp);
                final profile = c.devices[fp];
                final trusted = c.trust.isTrusted(fp);
                final blocked = c.trust.isBlocked(fp);
                final online = c.isOnline(fp);
                final shown = c.displayName(fp, widget.name);
                final divider = Divider(height: 18, color: Colors.white.withValues(alpha: 0.07));
                final history = c.history.entries
                    .where((e) => e.fingerprint == fp || (e.fingerprint == null && e.peerName == widget.name))
                    .take(50)
                    .toList();
                final sessions = profile?.sessions.reversed.take(30).toList() ?? const [];
                final sentBytes = history
                    .where((e) => e.direction == TransferDirection.outgoing && e.status == TransferStatus.done)
                    .fold<int>(0, (a, e) => a + e.totalBytes);
                final gotBytes = history
                    .where((e) => e.direction == TransferDirection.incoming && e.status == TransferStatus.done)
                    .fold<int>(0, (a, e) => a + e.totalBytes);
                return Column(
                  children: [
                    SubPageHeader(title: shown),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                            children: [
                              // ── Profile ──
                              Glass(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        IconBadge(
                                          icon: platformIcon(profile?.platform ?? 'unknown'),
                                          color: platformColor(profile?.platform ?? 'unknown'),
                                          size: 52,
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(shown, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                                              if (shown != widget.name)
                                                Text(context.tr('dp_real_name', {'name': widget.name}),
                                                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                              const SizedBox(height: 4),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 4,
                                                children: [
                                                  _Chip(
                                                    online ? context.tr('online') : context.tr('chat_offline'),
                                                    online ? AppColors.mint : AppColors.muted,
                                                  ),
                                                  if (blocked)
                                                    _Chip(context.tr('dp_blocked'), AppColors.danger)
                                                  else if (trusted)
                                                    _Chip(context.tr('trusted'), AppColors.mint)
                                                  else
                                                    _Chip(context.tr('dp_not_trusted'), AppColors.amber),
                                                  if (d.group != null) _Chip(groupLabel(context, d.group!), AppColors.violet),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    divider,
                                    _Kv(context.tr('dp_os'), _os(profile?.platform)),
                                    if (profile != null) ...[
                                      _Kv(context.tr('dp_first_seen'), _when(context, profile.firstSeen)),
                                      _Kv(context.tr('dp_last_seen'),
                                          online ? context.tr('online') : '${_when(context, profile.lastSeen)} (${sinceLabel(context, profile.lastSeen)})'),
                                      if (profile.lastAddress != null) _Kv(context.tr('dp_address'), profile.lastAddress!),
                                    ],
                                    _Kv(context.tr('fingerprint'), groupFingerprint(fp, groups: 4), mono: true),
                                    _Kv(context.tr('dp_traffic'), '↑ ${formatBytes(sentBytes)}   ↓ ${formatBytes(gotBytes)}'),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              // ── Name, group, folder ──
                              SectionTitle(context.tr('dp_identity')),
                              Glass(
                                child: Column(
                                  children: [
                                    TextField(
                                      controller: _nickname,
                                      maxLength: 40,
                                      decoration: InputDecoration(
                                        labelText: context.tr('dp_nickname'),
                                        hintText: widget.name,
                                        counterText: '',
                                        helperText: context.tr('dp_nickname_help'),
                                        helperMaxLines: 2,
                                      ),
                                      onSubmitted: (_) => _saveText(context),
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: _folder,
                                      maxLength: 40,
                                      decoration: InputDecoration(
                                        labelText: context.tr('dp_folder'),
                                        hintText: _nickname.text.trim().isEmpty ? widget.name : _nickname.text.trim(),
                                        counterText: '',
                                        helperText: context.tr('dp_folder_help'),
                                        helperMaxLines: 3,
                                      ),
                                      onSubmitted: (_) => _saveText(context),
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: AlignmentDirectional.centerEnd,
                                      child: GhostButton(
                                        label: context.tr('save'),
                                        icon: Icons.check_rounded,
                                        color: AppColors.cyan,
                                        onPressed: () => _saveText(context),
                                      ),
                                    ),
                                    divider,
                                    Row(
                                      children: [
                                        const Icon(Icons.workspaces_rounded, color: AppColors.violet),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(context.tr('dp_group'), style: const TextStyle(fontWeight: FontWeight.w700)),
                                        ),
                                        DropdownButton<String?>(
                                          value: s.deviceGroups.contains(d.group) ? d.group : null,
                                          items: [
                                            DropdownMenuItem<String?>(value: null, child: Text(context.tr('dp_no_group'))),
                                            for (final g in s.deviceGroups)
                                              DropdownMenuItem<String?>(value: g, child: Text(groupLabel(context, g))),
                                          ],
                                          onChanged: (v) => _set((x) => x.group = v),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              // ── Permission profile ──
                              SectionTitle(
                                context.tr('dp_permissions'),
                                trailing: InfoButton(title: context.tr('dp_permissions'), body: context.tr('i_permissions')),
                              ),
                              Glass(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(context.tr('dp_direction'), style: const TextStyle(fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 8),
                                    SegmentedButton<String>(
                                      showSelectedIcon: false,
                                      segments: [
                                        ButtonSegment(value: 'both', label: Text(context.tr('dir_both'))),
                                        ButtonSegment(value: 'receiveOnly', label: Text(context.tr('dir_receive_only'))),
                                        ButtonSegment(value: 'sendOnly', label: Text(context.tr('dir_send_only'))),
                                      ],
                                      selected: {d.direction},
                                      onSelectionChanged: (v) => _set((x) => x.direction = v.first),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(context.tr('dir_${d.direction}_sub'),
                                        style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                    divider,
                                    _Perm(
                                      icon: Icons.download_done_rounded,
                                      color: AppColors.mint,
                                      title: context.tr('dp_auto_accept'),
                                      value: d.autoAccept ?? s.autoAcceptTrusted,
                                      note: d.autoAccept == null ? context.tr('dp_follows_global') : null,
                                      onChanged: (v) => _set((x) => x.autoAccept = v),
                                    ),
                                    divider,
                                    _Perm(
                                      icon: Icons.forum_rounded,
                                      color: AppColors.cyan,
                                      title: context.tr('dp_chat'),
                                      value: d.chat,
                                      globalOff: !s.chat,
                                      onChanged: (v) => _set((x) => x.chat = v),
                                    ),
                                    divider,
                                    _Perm(
                                      icon: Icons.content_paste_rounded,
                                      color: AppColors.violet,
                                      title: context.tr('dp_clipboard'),
                                      value: d.clipboard,
                                      globalOff: !s.clipboardSync,
                                      onChanged: (v) => _set((x) => x.clipboard = v),
                                    ),
                                    divider,
                                    _Perm(
                                      icon: Icons.notifications_active_rounded,
                                      color: AppColors.amber,
                                      title: context.tr('dp_ring'),
                                      value: d.ring,
                                      globalOff: !s.allowRing,
                                      onChanged: (v) => _set((x) => x.ring = v),
                                    ),
                                    divider,
                                    _Perm(
                                      icon: Icons.sync_alt_rounded,
                                      color: AppColors.violet,
                                      title: context.tr('dp_sync'),
                                      value: d.sync,
                                      globalOff: !s.folderSync,
                                      onChanged: (v) => _set((x) => x.sync = v),
                                    ),
                                    divider,
                                    _Perm(
                                      icon: Icons.travel_explore_rounded,
                                      color: AppColors.violet,
                                      title: context.tr('dp_search'),
                                      value: d.search,
                                      globalOff: !s.remoteSearch,
                                      onChanged: (v) => _set((x) => x.search = v),
                                    ),
                                    divider,
                                    _Perm(
                                      icon: Icons.speed_rounded,
                                      color: AppColors.mint,
                                      title: context.tr('dp_speed'),
                                      value: d.speedTest,
                                      globalOff: !s.allowSpeedTest,
                                      onChanged: (v) => _set((x) => x.speedTest = v),
                                    ),
                                    divider,
                                    _Perm(
                                      icon: Icons.location_on_rounded,
                                      color: AppColors.pink,
                                      title: context.tr('dp_keep_metadata'),
                                      value: d.keepMetadata,
                                      note: context.tr('dp_keep_metadata_sub'),
                                      globalOff: s.metadata == 'off',
                                      onChanged: (v) => _set((x) => x.keepMetadata = v),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              // ── Trust & session expiry ──
                              SectionTitle(context.tr('dp_trust')),
                              Glass(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (trusted) ...[
                                      Text(context.tr('dp_trust_expiry'), style: const TextStyle(fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 4),
                                      Text(
                                        d.trustExpires == null
                                            ? context.tr('dp_trust_forever')
                                            : context.tr('dp_trust_until', {'when': _when(context, d.trustExpires!)}),
                                        style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          for (final (key, len) in const <(String, Duration?)>[
                                            ('exp_never', null),
                                            ('exp_1h', Duration(hours: 1)),
                                            ('exp_1d', Duration(days: 1)),
                                            ('exp_7d', Duration(days: 7)),
                                            ('exp_30d', Duration(days: 30)),
                                          ])
                                            ActionChip(label: Text(context.tr(key)), onPressed: () => c.setTrustExpiry(fp, len)),
                                        ],
                                      ),
                                      divider,
                                    ],
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (!trusted && !blocked)
                                          GhostButton(
                                            label: context.tr('dp_trust_now'),
                                            icon: Icons.verified_user_rounded,
                                            color: AppColors.mint,
                                            onPressed: () => c.trustDevice(fp, widget.name),
                                          ),
                                        if (trusted)
                                          GhostButton(
                                            label: context.tr('s_revoke'),
                                            icon: Icons.remove_moderator_outlined,
                                            color: AppColors.amber,
                                            onPressed: () => c.untrust(fp),
                                          ),
                                        if (blocked)
                                          GhostButton(
                                            label: context.tr('s_unblock'),
                                            icon: Icons.lock_open_rounded,
                                            color: AppColors.amber,
                                            onPressed: () => c.unblock(fp),
                                          )
                                        else
                                          GhostButton(
                                            label: context.tr('block'),
                                            icon: Icons.block_rounded,
                                            color: AppColors.danger,
                                            onPressed: () => c.block(fp, widget.name),
                                          ),
                                      ],
                                    ),
                                    if (!trusted && !blocked) ...[
                                      const SizedBox(height: 6),
                                      Text(context.tr('dp_trust_now_sub'), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              // ── Archiving rules ──
                              SectionTitle(context.tr('dp_rules')),
                              Glass(
                                child: Column(
                                  children: [
                                    _TriRule(
                                      label: context.tr('org_by_type'),
                                      value: d.byType,
                                      global: s.organizeByType,
                                      onChanged: (v) => _set((x) => x.byType = v),
                                    ),
                                    divider,
                                    _TriRule(
                                      label: context.tr('org_by_date'),
                                      value: d.byDate,
                                      global: s.organizeByDate,
                                      onChanged: (v) => _set((x) => x.byDate = v),
                                    ),
                                    if (!s.organize) ...[
                                      divider,
                                      Text(context.tr('dp_rules_off'), style: const TextStyle(color: AppColors.amber, fontSize: 12)),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              // ── Transfer history ──
                              SectionTitle(context.tr('dp_history', {'n': history.length})),
                              Glass(
                                child: history.isEmpty
                                    ? Text(context.tr('dp_history_none'), style: const TextStyle(color: AppColors.muted))
                                    : Column(
                                        children: [
                                          for (final e in history)
                                            Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 4),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    e.direction == TransferDirection.incoming
                                                        ? Icons.south_west_rounded
                                                        : Icons.north_east_rounded,
                                                    size: 18,
                                                    color: e.status == TransferStatus.done ? AppColors.mint : AppColors.danger,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      e.isText
                                                          ? context.tr('text')
                                                          : '${e.firstName ?? ''}${e.fileCount > 1 ? ' +${e.fileCount - 1}' : ''}',
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  Text('${formatBytes(e.totalBytes)} · ${dateFolder(e.at)}',
                                                      style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                              ),
                              const SizedBox(height: 20),

                              // ── Connection history ──
                              SectionTitle(context.tr('dp_sessions')),
                              Glass(
                                child: sessions.isEmpty
                                    ? Text(context.tr('dp_sessions_none'), style: const TextStyle(color: AppColors.muted))
                                    : Column(
                                        children: [
                                          for (final ses in sessions)
                                            Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 4),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.wifi_rounded, size: 17, color: AppColors.cyan),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      '${_when(context, ses.start)} → ${TimeOfDay.fromDateTime(ses.end).format(context)}',
                                                      style: const TextStyle(fontSize: 13),
                                                    ),
                                                  ),
                                                  Text('${_duration(ses.length)} · ${ses.address}',
                                                      textDirection: TextDirection.ltr,
                                                      style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                                ],
                                              ),
                                            ),
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

  static String _os(String? p) => switch (p) {
        'android' => 'Android',
        'ios' => 'iOS',
        'windows' => 'Windows',
        'linux' => 'Linux',
        'macos' => 'macOS',
        _ => '—',
      };

  static String _when(BuildContext context, DateTime t) =>
      '${dateFolder(t)} ${TimeOfDay.fromDateTime(t).format(context)}';

  static String _duration(Duration d) {
    if (d.inMinutes < 1) return '<1m';
    if (d.inHours < 1) return '${d.inMinutes}m';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );
}

class _Kv extends StatelessWidget {
  const _Kv(this.k, this.v, {this.mono = false});
  final String k;
  final String v;
  final bool mono;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 12.5))),
            Expanded(
              child: Text(v,
                  textDirection: mono ? TextDirection.ltr : null,
                  style: (mono ? kMono : const TextStyle()).copyWith(fontSize: 12.5)),
            ),
          ],
        ),
      );
}

/// Follow general / on / off.
class _TriRule extends StatelessWidget {
  const _TriRule({required this.label, required this.value, required this.global, required this.onChanged});
  final String label;
  final bool? value;
  final bool global;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final key = value == null ? 'default' : (value! ? 'on' : 'off');
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
        SegmentedButton<String>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            ButtonSegment(
                value: 'default', label: Text(context.tr('rule_default', {'v': context.tr(global ? 'rule_on' : 'rule_off')}))),
            ButtonSegment(value: 'on', label: Text(context.tr('rule_on'))),
            ButtonSegment(value: 'off', label: Text(context.tr('rule_off'))),
          ],
          selected: {key},
          onSelectionChanged: (v) => onChanged(switch (v.first) {
            'on' => true,
            'off' => false,
            _ => null,
          }),
        ),
      ],
    );
  }
}

class _Perm extends StatelessWidget {
  const _Perm({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.onChanged,
    this.note,
    this.globalOff = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? note;

  /// The feature is switched off for every device in Features.
  final bool globalOff;

  @override
  Widget build(BuildContext context) {
    final sub = globalOff ? context.tr('dp_global_off') : note;
    return Opacity(
      opacity: globalOff ? 0.5 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: globalOff ? null : () => onChanged(!value),
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
                    if (sub != null) Text(sub, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                ),
              ),
              Switch(
                value: value && !globalOff,
                onChanged: globalOff ? null : onChanged,
                thumbColor: WidgetStateProperty.resolveWith(
                    (st) => st.contains(WidgetState.selected) ? AppColors.ink : AppColors.muted),
                trackColor: WidgetStateProperty.resolveWith(
                    (st) => st.contains(WidgetState.selected) ? AppColors.cyan : Colors.white.withValues(alpha: 0.08)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
