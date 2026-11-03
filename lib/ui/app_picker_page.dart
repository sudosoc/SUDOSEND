import 'package:flutter/material.dart';
import 'package:wraith_core/util.dart';

import '../app/scope.dart';
import '../platform/native_bridge.dart';
import '../state/app_controller.dart';
import 'background.dart';
import 'glass.dart';
import 'settings_page.dart' show InfoButton;
import 'sync_page.dart' show SubPageHeader;
import 'theme.dart';

Future<void> openAppPicker(BuildContext context, AppController c) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AppPickerPage(controller: c)));

/// Pick installed apps to send (their APKs; split apps as a set).
class AppPickerPage extends StatefulWidget {
  const AppPickerPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<AppPickerPage> createState() => _AppPickerPageState();
}

class _AppPickerPageState extends State<AppPickerPage> {
  List<InstalledApp>? _apps;
  final Set<String> _chosen = {};
  String _q = '';
  String _sort = 'name'; // name | size | recent

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.installedApps().then((a) {
      if (mounted) setState(() => _apps = a);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = c.settings;
    final all = _apps;
    final shown = (all ?? const <InstalledApp>[])
        .where((a) => s.showSystemApps || !a.system)
        .where((a) => _q.isEmpty || a.label.toLowerCase().contains(_q) || a.package.toLowerCase().contains(_q))
        .toList();
    switch (_sort) {
      case 'size':
        shown.sort((a, b) => b.size.compareTo(a.size));
      case 'recent':
        shown.sort((a, b) => b.updated.compareTo(a.updated));
    }
    final picked = (all ?? const <InstalledApp>[]).where((a) => _chosen.contains(a.package)).toList();
    final total = picked.fold<int>(0, (t, a) => t + a.size);
    return Scaffold(
      backgroundColor: AppColors.bgTop,
      body: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackground()),
          SafeArea(
            child: Column(
              children: [
                SubPageHeader(title: context.tr('apps_title')),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Glass(
                          radius: 18,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: TextField(
                            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                            decoration: InputDecoration(
                              hintText: context.tr('apps_search'),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              icon: const Icon(Icons.search_rounded, color: AppColors.muted),
                            ),
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: context.tr('lib_sort'),
                        icon: const Icon(Icons.sort_rounded),
                        initialValue: _sort,
                        onSelected: (v) => setState(() => _sort = v),
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'name', child: Text(context.tr('sort_name'))),
                          PopupMenuItem(value: 'size', child: Text(context.tr('sort_largest'))),
                          PopupMenuItem(value: 'recent', child: Text(context.tr('apps_recent'))),
                        ],
                      ),
                      InfoButton(title: context.tr('f_share_apps'), body: context.tr('i_share_apps')),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          all == null ? context.tr('apps_loading') : context.tr('apps_count', {'n': shown.length}),
                          style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                        ),
                      ),
                      Text(context.tr('apps_system'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      Switch(
                        value: s.showSystemApps,
                        onChanged: (v) => s.update((x) => x.showSystemApps = v).then((_) {
                          if (mounted) setState(() {});
                        }),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: all == null
                      ? const Center(child: CircularProgressIndicator())
                      : LayoutBuilder(builder: (context, box) {
                          final cols = (box.maxWidth / 120).floor().clamp(3, 8);
                          return GridView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 100),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: cols,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio: 0.78,
                            ),
                            itemCount: shown.length,
                            itemBuilder: (context, i) {
                              final a = shown[i];
                              final on = _chosen.contains(a.package);
                              return _AppTile(
                                app: a,
                                selected: on,
                                onTap: () => setState(() => on ? _chosen.remove(a.package) : _chosen.add(a.package)),
                              );
                            },
                          );
                        }),
                ),
              ],
            ),
          ),
          if (picked.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SafeArea(
                child: GlowButton(
                  expand: true,
                  icon: Icons.add_rounded,
                  label: context.tr('apps_add', {'n': picked.length, 'size': formatBytes(total)}),
                  onPressed: () {
                    c.addApps(picked);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({required this.app, required this.selected, required this.onTap});
  final InstalledApp app;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 18,
      padding: const EdgeInsets.all(8),
      borderColor: selected ? AppColors.mint : null,
      glow: selected ? AppColors.mint : null,
      onTap: onTap,
      child: Stack(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (app.icon != null)
                Image.memory(app.icon!, width: 48, height: 48, gaplessPlayback: true)
              else
                const Icon(Icons.android_rounded, size: 48, color: AppColors.mint),
              const SizedBox(height: 6),
              Text(app.label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(formatBytes(app.size), style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
            ],
          ),
          if (selected)
            const PositionedDirectional(
              top: 0,
              end: 0,
              child: Icon(Icons.check_circle_rounded, color: AppColors.mint, size: 20),
            ),
          if (app.isSplit)
            PositionedDirectional(
              top: 0,
              start: 0,
              child: Tooltip(
                message: context.tr('apps_split', {'n': app.paths.length}),
                child: const Icon(Icons.layers_rounded, color: AppColors.amber, size: 16),
              ),
            ),
        ],
      ),
    );
  }
}
