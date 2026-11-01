import 'package:flutter/material.dart';
import 'package:wraith_core/util.dart';

import '../app/scope.dart';
import '../state/app_controller.dart';
import '../state/settings.dart';
import 'background.dart';
import 'glass.dart';
import 'settings_page.dart' show InfoButton;
import 'sync_page.dart' show SubPageHeader;
import 'theme.dart';

/// Per-device permissions for one trusted device.
class DevicePage extends StatefulWidget {
  const DevicePage({super.key, required this.controller, required this.fingerprint, required this.name});
  final AppController controller;
  final String fingerprint;
  final String name;

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  late final TextEditingController _folder =
      TextEditingController(text: widget.controller.settings.prefsFor(widget.fingerprint).folder ?? '');

  AppController get c => widget.controller;

  @override
  void dispose() {
    _folder.dispose();
    super.dispose();
  }

  Future<void> _set(void Function(DevicePrefs d) change) => c.updateDevicePrefs(widget.fingerprint, change);

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
                final d = s.prefsFor(widget.fingerprint);
                final trusted = c.trust.isTrusted(widget.fingerprint);
                final divider = Divider(height: 18, color: Colors.white.withValues(alpha: 0.07));
                return Column(
                  children: [
                    SubPageHeader(title: widget.name),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                            children: [
                              Text(groupFingerprint(widget.fingerprint),
                                  textDirection: TextDirection.ltr,
                                  style: kMono.copyWith(color: AppColors.muted, fontSize: 11.5)),
                              const SizedBox(height: 10),
                              Text(context.tr('dp_intro'), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                              const SizedBox(height: 16),
                              SectionTitle(context.tr('dp_folder')),
                              Glass(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _folder,
                                        maxLength: 40,
                                        decoration: InputDecoration(
                                          hintText: widget.name,
                                          counterText: '',
                                          helperText: context.tr('dp_folder_help'),
                                          helperMaxLines: 3,
                                        ),
                                        onSubmitted: (v) => _set((x) => x.folder = v.trim().isEmpty ? null : sanitizeFileName(v.trim())),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: context.tr('save'),
                                      icon: const Icon(Icons.check_rounded, color: AppColors.cyan),
                                      onPressed: () {
                                        final v = _folder.text.trim();
                                        _set((x) => x.folder = v.isEmpty ? null : sanitizeFileName(v));
                                        FocusScope.of(context).unfocus();
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(content: Text(context.tr('dp_saved'))));
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              SectionTitle(context.tr('dp_allow')),
                              Glass(
                                child: Column(
                                  children: [
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
                                      icon: Icons.speed_rounded,
                                      color: AppColors.mint,
                                      title: context.tr('dp_speed'),
                                      value: d.speedTest,
                                      globalOff: !s.allowSpeedTest,
                                      onChanged: (v) => _set((x) => x.speedTest = v),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              SectionTitle(context.tr('dp_sending')),
                              Glass(
                                child: _Perm(
                                  icon: Icons.location_on_rounded,
                                  color: AppColors.pink,
                                  title: context.tr('dp_keep_metadata'),
                                  value: d.keepMetadata,
                                  note: context.tr('dp_keep_metadata_sub'),
                                  globalOff: s.metadata == 'off',
                                  info: 'i_metadata',
                                  onChanged: (v) => _set((x) => x.keepMetadata = v),
                                ),
                              ),
                              const SizedBox(height: 24),
                              if (trusted)
                                GhostButton(
                                  label: context.tr('s_revoke'),
                                  icon: Icons.remove_moderator_outlined,
                                  color: AppColors.danger,
                                  expand: true,
                                  onPressed: () async {
                                    final nav = Navigator.of(context);
                                    await c.untrust(widget.fingerprint);
                                    nav.pop();
                                  },
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
    this.info,
  });

  final IconData icon;
  final Color color;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? note;

  /// The feature is switched off for every device in Features.
  final bool globalOff;
  final String? info;

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
              if (info != null) InfoButton(title: title, body: context.tr(info!)),
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
