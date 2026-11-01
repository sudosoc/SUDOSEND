import 'dart:async';

import 'package:flutter/material.dart';

import 'package:wraith_core/transfer.dart';
import 'package:wraith_core/util.dart';
import '../app/scope.dart';
import '../state/app_controller.dart';
import 'background.dart';
import 'glass.dart';
import 'incoming_dialog.dart';
import 'radar.dart';
import 'receive_tab.dart';
import 'send_tab.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'transfers_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _NavItem {
  const _NavItem(this.icon, this.labelKey);
  final IconData icon;
  final String labelKey;
}

const _navItems = [
  _NavItem(Icons.send_rounded, 'tab_send'),
  _NavItem(Icons.wifi_tethering_rounded, 'tab_receive'),
  _NavItem(Icons.swap_vert_rounded, 'tab_transfers'),
];

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<IncomingRequest>? _incomingSub;
  StreamSubscription<String>? _messageSub;
  StreamSubscription<String>? _ringSub;
  bool _ringOpen = false;
  final List<IncomingRequest> _queue = [];
  bool _dialogOpen = false;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _incomingSub = c.incoming.listen((r) {
      _queue.add(r);
      _drainQueue();
    });
    _ringSub = c.rings.listen((from) {
      if (!mounted) return;
      if (from.isEmpty) {
        if (_ringOpen) Navigator.of(context).pop();
        return;
      }
      if (_ringOpen) return;
      _ringOpen = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => GlassDialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const IconBadge(icon: Icons.notifications_active_rounded, color: AppColors.amber, size: 64),
              const SizedBox(height: 14),
              Text(context.tr('ring_title'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(context.tr('ring_from', {'name': from}), textAlign: TextAlign.center),
              const SizedBox(height: 18),
              GlowButton(
                label: context.tr('ring_stop'),
                icon: Icons.stop_rounded,
                expand: true,
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ).whenComplete(() {
        _ringOpen = false;
        c.stopRinging();
      });
    });
    _messageSub = c.messages.listen((m) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    });
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    _messageSub?.cancel();
    _ringSub?.cancel();
    super.dispose();
  }

  /// Shows incoming requests one at a time.
  Future<void> _drainQueue() async {
    if (_dialogOpen || !mounted) return;
    while (_queue.isNotEmpty && mounted) {
      final request = _queue.removeAt(0);
      if (!request.isPending) continue;
      _dialogOpen = true;
      await showIncomingDialog(context, request);
      _dialogOpen = false;
    }
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
              listenable: c,
              builder: (context, _) {
                if (!c.ready) return _Boot(error: c.startupError);
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    final content = Column(
                      children: [
                        _Header(controller: c, compact: constraints.maxWidth < 420),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: context.reducedEffects ? Duration.zero : const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOutCubic,
                            transitionBuilder: (child, anim) => FadeTransition(
                              opacity: anim,
                              child: SlideTransition(
                                position: Tween(begin: const Offset(0, 0.02), end: Offset.zero)
                                    .animate(anim),
                                child: child,
                              ),
                            ),
                            child: KeyedSubtree(key: ValueKey(c.tab), child: _tabBody()),
                          ),
                        ),
                        if (!wide) _BottomNav(controller: c),
                      ],
                    );
                    if (!wide) return content;
                    return Row(
                      children: [
                        _SideNav(controller: c),
                        Expanded(child: content),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBody() => switch (c.tab) {
        0 => SendTab(controller: c),
        1 => ReceiveTab(controller: c),
        _ => TransfersTab(controller: c),
      };
}

class _Boot extends StatelessWidget {
  const _Boot({this.error});
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Radar(
              size: 200,
              center: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: kAccentGradient),
                child: const Icon(Icons.bolt_rounded, color: AppColors.ink, size: 34),
              ),
            ),
            const SizedBox(height: 24),
            if (error == null)
              Text(context.tr('booting'), style: const TextStyle(color: AppColors.muted, letterSpacing: 1.2))
            else
              Glass(
                borderColor: AppColors.danger.withValues(alpha: 0.4),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 32),
                    const SizedBox(height: 8),
                    Text(context.tr('cant_start'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                    const SizedBox(height: 6),
                    Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.compact});

  final AppController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final id = controller.identity;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: kAccentGradient,
              boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.45), blurRadius: 22, spreadRadius: -4)],
            ),
            child: const Icon(Icons.bolt_rounded, color: AppColors.ink, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (r) => const LinearGradient(colors: [Colors.white, Color(0xFFBFD8FF)])
                      .createShader(r),
                  child: const Text(
                    'SUDOSEND',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 3.5, color: Colors.white),
                  ),
                ),
                if (!compact)
                  Text(
                    context.tr('tagline'),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Glass(
              radius: 40,
              blur: 16,
              padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
              onTap: () => showRenameDialog(context, controller),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(platformIcon(platformName()), size: 18, color: platformColor(platformName())),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(id.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        Text(id.shortId,
                            style: kMono.copyWith(color: AppColors.muted, fontSize: 10.5, letterSpacing: 1)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Glass(
            radius: 40,
            blur: 16,
            padding: const EdgeInsets.all(10),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => SettingsPage(controller: controller)),
            ),
            child: Tooltip(
              message: context.tr('settings'),
              child: const Icon(Icons.tune_rounded, size: 20, color: AppColors.text),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showRenameDialog(BuildContext context, AppController controller) async {
  {
    final text = TextEditingController(text: controller.identity.name);
    final result = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => GlassDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('device_name'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(context.tr('device_name_sub'), style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            TextField(
              controller: text,
              autofocus: true,
              maxLength: 40,
              onSubmitted: (v) => Navigator.pop(ctx, v),
              decoration: const InputDecoration(hintText: 'e.g. Seif-Laptop', counterText: ''),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: GhostButton(label: context.tr('cancel'), onPressed: () => Navigator.pop(ctx), expand: true)),
                const SizedBox(width: 12),
                Expanded(
                  child: GlowButton(label: context.tr('save'), onPressed: () => Navigator.pop(ctx, text.text), expand: true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (result != null && result.trim().isNotEmpty) await controller.rename(result);
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Glass(
        radius: 26,
        blur: 26,
        tint: 0.08,
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            for (var i = 0; i < _navItems.length; i++)
              Expanded(
                child: _NavButton(
                  item: _navItems[i],
                  selected: controller.tab == i,
                  badge: i == 2 ? controller.activeJobs : 0,
                  onTap: () => controller.setTab(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
      child: Glass(
        radius: 28,
        blur: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: SizedBox(
          width: 84,
          child: Column(
            children: [
              for (var i = 0; i < _navItems.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _NavButton(
                    item: _navItems[i],
                    selected: controller.tab == i,
                    badge: i == 2 ? controller.activeJobs : 0,
                    vertical: true,
                    onTap: () => controller.setTab(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
    this.badge = 0,
    this.vertical = false,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;
  final int badge;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.ink : AppColors.muted;
    final icon = Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(item.icon, color: color, size: 22),
        if (badge > 0)
          Positioned(
            right: -8,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: AppColors.pink, borderRadius: BorderRadius.circular(10)),
              child: Text('$badge',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
            ),
          ),
      ],
    );
    final label = Text(
      context.tr(item.labelKey),
      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: vertical ? 11.5 : 13),
    );
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(vertical: vertical ? 12 : 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: selected ? kAccentGradient : null,
          boxShadow: selected
              ? [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.35), blurRadius: 18, spreadRadius: -6)]
              : const [],
        ),
        child: vertical
            ? Column(children: [icon, const SizedBox(height: 6), label])
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [icon, const SizedBox(width: 8), Flexible(child: label)],
              ),
      ),
    );
  }
}
