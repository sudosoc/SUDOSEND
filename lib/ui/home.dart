import 'dart:async';

import 'package:flutter/material.dart';

import 'package:wraith_core/transfer.dart';
import '../app/scope.dart';
import '../state/app_controller.dart';
import 'background.dart';
import 'chat_page.dart';
import 'glass.dart';
import 'incoming_dialog.dart';
import 'library_page.dart';
import 'radar.dart';
import 'receive_tab.dart';
import 'send_tab.dart';
import 'settings_page.dart';
import 'sync_page.dart' show SubPageHeader;
import 'theme.dart';
import 'transfers_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _NavItem {
  const _NavItem(this.id, this.icon, this.labelKey);

  /// The tab index this item opens (AppController.tab).
  final int id;
  final IconData icon;
  final String labelKey;
}

const _navItems = [
  _NavItem(0, Icons.radar_rounded, 'tab_nearby'),
  _NavItem(4, Icons.folder_copy_rounded, 'tab_files'),
  _NavItem(2, Icons.swap_vert_rounded, 'tab_transfers'),
  _NavItem(3, Icons.forum_rounded, 'tab_messages'),
];

/// Tabs on screen: Messages only while that feature is on.
List<_NavItem> _visibleNav(AppController c) => [
      for (final i in _navItems)
        if (i.id != 3 || c.settings.chat) i,
    ];

int _badgeFor(AppController c, int id) => switch (id) {
      2 => c.activeJobs,
      3 => c.chat.unread,
      4 => c.storageLow ? 1 : 0,
      _ => 0,
    };

/// Watches and other tiny screens.
bool _tiny(BoxConstraints c) => c.maxWidth < 300 || c.maxHeight < 300;

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
              const IconBadge(
                  icon: Icons.notifications_active_rounded,
                  color: AppColors.amber,
                  size: 64),
              const SizedBox(height: 14),
              Text(context.tr('ring_title'),
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(context.tr('ring_from', {'name': from}),
                  textAlign: TextAlign.center),
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
      await showIncomingDialog(context, request,
          onAcceptSync: c.acceptSyncInvite);
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
              listenable: Listenable.merge([c, c.settings]),
              builder: (context, _) {
                if (!c.ready) return _Boot(error: c.startupError);
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    final tiny = _tiny(constraints);
                    final content = Column(
                      children: [
                        if (!tiny)
                          _Header(
                              controller: c,
                              compact: constraints.maxWidth < 420),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: context.reducedEffects
                                ? Duration.zero
                                : const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOutCubic,
                            // Tabs fill the area and start at the top (the default centres them).
                            layoutBuilder: (current, previous) => Stack(
                              fit: StackFit.expand,
                              alignment: Alignment.topCenter,
                              children: [
                                ...previous,
                                if (current != null) current
                              ],
                            ),
                            transitionBuilder: (child, anim) => FadeTransition(
                              opacity: anim,
                              child: SlideTransition(
                                position: Tween(
                                        begin: const Offset(0, 0.02),
                                        end: Offset.zero)
                                    .animate(anim),
                                child: child,
                              ),
                            ),
                            child: KeyedSubtree(
                                key: ValueKey(c.tab), child: _tabBody()),
                          ),
                        ),
                        if (!wide)
                          _BottomNav(
                              controller: c,
                              iconsOnly: constraints.maxWidth < 620),
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
        0 || 1 => SendTab(controller: c),
        3 when c.settings.chat => MessagesTab(controller: c),
        4 => LibraryTab(controller: c),
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
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, gradient: kAccentGradient),
                child: const Icon(Icons.bolt_rounded,
                    color: AppColors.ink, size: 34),
              ),
            ),
            const SizedBox(height: 24),
            if (error == null)
              Text(context.tr('booting'),
                  style: const TextStyle(
                      color: AppColors.muted, letterSpacing: 1.2))
            else
              Glass(
                borderColor: AppColors.danger.withValues(alpha: 0.4),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppColors.danger, size: 32),
                    const SizedBox(height: 8),
                    Text(context.tr('cant_start'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 17)),
                    const SizedBox(height: 6),
                    Text(error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.muted)),
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
    final online = controller.peers.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                gradient: kAccentGradient),
            child:
                const Icon(Icons.bolt_rounded, color: AppColors.ink, size: 22),
          ),
          const SizedBox(width: 10),
          const Text(
            'SUDOSEND',
            maxLines: 1,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 2.2),
          ),
          // Tap: "My device" — QR, address, how others can reach this device.
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: Glass(
                  radius: 14,
                  padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
                  onTap: () => openMyDevice(context, controller),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: controller.settings.stealth
                              ? AppColors.violet
                              : AppColors.mint,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(id.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                            Text(
                              controller.settings.stealth
                                  ? context.tr('hidden')
                                  : online == 0
                                      ? context.tr('visible')
                                      : context.tr('n_nearby', {'n': online}),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.muted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Glass(
            radius: 14,
            padding: const EdgeInsets.all(9),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => SettingsPage(controller: controller)),
            ),
            child: Tooltip(
              message: context.tr('settings'),
              child: Badge(
                isLabelVisible: controller.updateAvailable != null,
                backgroundColor: AppColors.accent,
                smallSize: 9,
                child: const Icon(Icons.tune_rounded,
                    size: 20, color: AppColors.text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "My device": the old Receive tab, one tap from the header chip.
void openMyDevice(BuildContext context, AppController controller) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      backgroundColor: AppColors.bgTop,
      body: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackground()),
          SafeArea(
            child: ListenableBuilder(
              listenable: Listenable.merge([controller, controller.settings]),
              builder: (context, _) => Column(
                children: [
                  SubPageHeader(
                    title: context.tr('my_device'),
                    actions: [
                      IconButton(
                        tooltip: context.tr('edit'),
                        onPressed: () => showRenameDialog(context, controller),
                        icon: const Icon(Icons.edit_rounded,
                            size: 20, color: AppColors.muted),
                      ),
                    ],
                  ),
                  Expanded(child: ReceiveTab(controller: controller)),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  ));
}

Future<void> showRenameDialog(
    BuildContext context, AppController controller) async {
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
            Text(context.tr('device_name'),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(context.tr('device_name_sub'),
                style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            TextField(
              controller: text,
              autofocus: true,
              maxLength: 40,
              onSubmitted: (v) => Navigator.pop(ctx, v),
              decoration: InputDecoration(
                  hintText: context.tr('device_name_hint'), counterText: ''),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                    child: GhostButton(
                        label: context.tr('cancel'),
                        onPressed: () => Navigator.pop(ctx),
                        expand: true)),
                const SizedBox(width: 12),
                Expanded(
                  child: GlowButton(
                      label: context.tr('save'),
                      onPressed: () => Navigator.pop(ctx, text.text),
                      expand: true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (result != null && result.trim().isNotEmpty)
      await controller.rename(result);
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.controller, this.iconsOnly = false});
  final AppController controller;
  final bool iconsOnly;

  @override
  Widget build(BuildContext context) {
    final items = _visibleNav(controller);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: _NavButton(
                item: item,
                selected: controller.tab == item.id,
                badge: _badgeFor(controller, item.id),
                vertical: true,
                showLabel: !iconsOnly || items.length <= 4,
                onTap: () => controller.setTab(item.id),
              ),
            ),
        ],
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
        radius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: SizedBox(
          width: 84,
          child: Column(
            children: [
              for (final item in _visibleNav(controller))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _NavButton(
                    item: item,
                    selected: controller.tab == item.id,
                    badge: _badgeFor(controller, item.id),
                    vertical: true,
                    onTap: () => controller.setTab(item.id),
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
    this.showLabel = true,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;
  final int badge;
  final bool vertical;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.muted;
    final icon = Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(item.icon, color: color, size: 24),
        if (badge > 0)
          Positioned(
            right: -9,
            top: -5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                  color: AppColors.pink,
                  borderRadius: BorderRadius.circular(10)),
              child: Text('$badge',
                  style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 10,
                      fontWeight: FontWeight.w800)),
            ),
          ),
      ],
    );
    final label = Text(
      context.tr(item.labelKey),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          color: color,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          fontSize: 11.5),
    );
    // InkWell (not GestureDetector) so TV remotes and keyboards can focus it.
    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.symmetric(vertical: vertical ? 9 : 10, horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: selected
            ? AppColors.accent.withValues(alpha: 0.12)
            : Colors.transparent,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          if (showLabel) ...[const SizedBox(height: 4), label]
        ],
      ),
    );
    final button = Semantics(
      button: true,
      selected: selected,
      label: badge > 0
          ? '${context.tr(item.labelKey)}, $badge'
          : context.tr(item.labelKey),
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          focusColor: AppColors.accent.withValues(alpha: 0.25),
          child: body,
        ),
      ),
    );
    return showLabel
        ? button
        : Tooltip(message: context.tr(item.labelKey), child: button);
  }
}
