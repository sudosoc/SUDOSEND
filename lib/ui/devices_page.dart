import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../state/app_controller.dart';
import '../state/devices.dart';
import 'background.dart';
import 'device_page.dart';
import 'glass.dart';
import 'sync_page.dart' show SubPageHeader;
import 'theme.dart';

String sinceLabel(BuildContext context, DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return context.tr('ago_now');
  if (d.inHours < 1) return context.tr('ago_min', {'n': d.inMinutes});
  if (d.inDays < 1) return context.tr('ago_hour', {'n': d.inHours});
  return context.tr('ago_day', {'n': d.inDays});
}

/// Every device SUDOSEND has met, grouped, with status at a glance.
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  String? _group; // null = all

  AppController get c => widget.controller;

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
                // Known profiles plus trusted devices never seen since profiles existed.
                final all = <DeviceProfile>[
                  ...c.devices.sorted,
                  for (final t in c.trust.all)
                    if (c.devices[t.fingerprint] == null)
                      DeviceProfile(
                        fingerprint: t.fingerprint,
                        name: t.name,
                        platform: 'unknown',
                        firstSeen: t.addedAt,
                        lastSeen: t.addedAt,
                      ),
                ];
                final shown = all.where((d) => _group == null || s.devicePrefs[d.fingerprint]?.group == _group).toList();
                return Column(
                  children: [
                    SubPageHeader(title: context.tr('devices_title')),
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 6),
                            child: ChoiceChip(
                              label: Text(context.tr('devices_all', {'n': all.length})),
                              selected: _group == null,
                              onSelected: (_) => setState(() => _group = null),
                            ),
                          ),
                          for (final g in s.deviceGroups)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 6),
                              child: ChoiceChip(
                                label: Text(groupLabel(context, g)),
                                selected: _group == g,
                                onSelected: (_) => setState(() => _group = g),
                              ),
                            ),
                          ActionChip(
                            avatar: const Icon(Icons.add_rounded, size: 16),
                            label: Text(context.tr('group_new')),
                            onPressed: () => _newGroup(context),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: shown.isEmpty
                          ? Center(child: Text(context.tr('devices_none'), style: const TextStyle(color: AppColors.muted)))
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              children: [for (final d in shown) _DeviceTile(controller: c, profile: d)],
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

  Future<void> _newGroup(BuildContext context) async {
    final text = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => GlassDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ctx.tr('group_new'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(controller: text, autofocus: true, maxLength: 24, onSubmitted: (v) => Navigator.pop(ctx, v)),
            const SizedBox(height: 12),
            GlowButton(label: ctx.tr('save'), expand: true, onPressed: () => Navigator.pop(ctx, text.text)),
          ],
        ),
      ),
    );
    final n = name?.trim() ?? '';
    if (n.isEmpty || c.settings.deviceGroups.contains(n)) return;
    await c.settings.update((s) => s.deviceGroups = [...s.deviceGroups, n]);
  }
}

/// Built-in group names are translated; custom ones are shown as typed.
String groupLabel(BuildContext context, String g) => switch (g) {
      'Personal' => context.tr('group_personal'),
      'Work' => context.tr('group_work'),
      _ => g,
    };

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.controller, required this.profile});
  final AppController controller;
  final DeviceProfile profile;

  @override
  Widget build(BuildContext context) {
    final fp = profile.fingerprint;
    final online = controller.isOnline(fp);
    final trusted = controller.trust.isTrusted(fp);
    final blocked = controller.trust.isBlocked(fp);
    final prefs = controller.settings.devicePrefs[fp];
    final name = controller.displayName(fp, profile.name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Glass(
        padding: const EdgeInsets.all(14),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => DevicePage(controller: controller, fingerprint: fp, name: profile.name),
        )),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconBadge(icon: platformIcon(profile.platform), color: platformColor(profile.platform), size: 44),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: online ? AppColors.mint : AppColors.muted,
                      border: Border.all(color: AppColors.bgTop, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (name != profile.name)
                        Text(profile.name, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                      Text(online ? context.tr('online') : sinceLabel(context, profile.lastSeen),
                          style: TextStyle(color: online ? AppColors.mint : AppColors.muted, fontSize: 11.5)),
                      if (prefs?.group != null)
                        Text(groupLabel(context, prefs!.group!), style: const TextStyle(color: AppColors.violet, fontSize: 11.5)),
                    ],
                  ),
                ],
              ),
            ),
            if (blocked)
              const Icon(Icons.block_rounded, color: AppColors.danger, size: 20)
            else if (trusted)
              const Icon(Icons.verified_user_rounded, color: AppColors.mint, size: 20),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
