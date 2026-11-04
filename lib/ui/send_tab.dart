import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wraith_core/models.dart';
import 'package:wraith_core/util.dart';

import '../app/scope.dart';
import '../platform/desktop.dart';
import '../state/app_controller.dart';
import 'app_picker_page.dart';
import 'device_actions.dart';
import 'devices_page.dart' show groupLabel;
import 'glass.dart';
import 'radar.dart';
import 'scan_page.dart';
import 'theme.dart';
import 'web_share_page.dart';
import 'wifi_direct_page.dart';

class SendTab extends StatefulWidget {
  const SendTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<SendTab> createState() => _SendTabState();
}

/// Tile keys of the visible devices, so a drop can be matched to a device.
final Map<String, GlobalKey> _peerKeys = {};

/// Device under the pointer while dragging files (highlighted).
final ValueNotifier<String?> _dropPeer = ValueNotifier<String?>(null);

Peer? _peerAt(AppController c, Offset global) {
  for (final p in c.peers) {
    final box = _peerKeys[p.id]?.currentContext?.findRenderObject();
    if (box is RenderBox && box.attached) {
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(global)) return p;
    }
  }
  return null;
}

class _SendTabState extends State<SendTab> {
  bool _dragging = false;

  AppController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final body = LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 820;
      final picker = _FilesCard(controller: controller, dragging: _dragging);
      final devices = _DevicesSection(controller: controller);
      if (wide) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SingleChildScrollView(child: picker)),
              const SizedBox(width: 18),
              Expanded(child: SingleChildScrollView(child: devices)),
            ],
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: controller.rescan,
        color: AppColors.cyan,
        backgroundColor: const Color(0xFF151B36),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [picker, const SizedBox(height: 22), devices],
        ),
      );
    });
    if (!isDesktop) return body;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) {
        _dropPeer.value = null;
        setState(() => _dragging = false);
      },
      onDragUpdated: (d) => _dropPeer.value = _peerAt(controller, d.globalPosition)?.id,
      onDragDone: (detail) async {
        _dropPeer.value = null;
        setState(() => _dragging = false);
        final messenger = ScaffoldMessenger.of(context);
        final paths = [for (final f in detail.files) f.path];
        // Dropped onto a device: send straight to it. Elsewhere: add to the selection.
        final target = _peerAt(controller, detail.globalPosition);
        final String? error;
        if (target != null) {
          final sending = context.tr('drop_sending', {'name': controller.displayName(target.id, target.name)});
          messenger.showSnackBar(SnackBar(content: Text(sending)));
          error = await controller.sendPathsTo(target, paths);
        } else {
          error = await controller.addPaths(paths);
        }
        if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
      },
      child: body,
    );
  }
}

class _FilesCard extends StatelessWidget {
  const _FilesCard({required this.controller, required this.dragging});
  final AppController controller;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final files = controller.selected;
    final text = controller.selectedText;
    if (files.isEmpty && text == null) {
      return Glass(
        glow: AppColors.cyan,
        borderColor: dragging ? AppColors.cyan : null,
        onTap: controller.pickFiles,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
        child: Column(
          children: [
            AnimatedScale(
              scale: dragging ? 1.12 : 1,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: kAccentGradient,
                  boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.5), blurRadius: 36, spreadRadius: -6)],
                ),
                child: Icon(dragging ? Icons.file_download_rounded : Icons.upload_rounded,
                    size: 38, color: AppColors.ink),
              ),
            ),
            const SizedBox(height: 18),
            Text(context.tr(dragging ? 'drop_now' : 'choose_title'),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              context.tr('choose_sub'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                GlowButton(label: context.tr('files'), icon: Icons.add_rounded, onPressed: controller.pickFiles),
                GhostButton(
                    label: context.tr('folder'), icon: Icons.folder_rounded, onPressed: () => _pickFolder(context)),
                GhostButton(label: context.tr('text'), icon: Icons.notes_rounded, onPressed: () => _editText(context)),
                if (controller.appSharing)
                  GhostButton(
                    label: context.tr('apps'),
                    icon: Icons.apps_rounded,
                    color: AppColors.mint,
                    onPressed: () => openAppPicker(context, controller),
                  ),
              ],
            ),
            if (isDesktop) ...[
              const SizedBox(height: 14),
              Text(context.tr('drop_hint'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ],
          ],
        ),
      );
    }

    if (text != null) {
      return Glass(
        glow: AppColors.violet,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconBadge(icon: Icons.notes_rounded, color: AppColors.violet, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(context.tr('text_ready', {'n': text.length}),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                TextButton(
                  onPressed: controller.clearSelected,
                  child: Text(context.tr('clear'), style: const TextStyle(color: AppColors.muted)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              text.length > 300 ? '${text.substring(0, 300)}…' : text,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(height: 1.4),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                GhostButton(label: context.tr('edit'), icon: Icons.edit_rounded, onPressed: () => _editText(context)),
                const SizedBox(width: 8),
                if (controller.settings.webShare) ...[
                  GhostButton(
                    label: context.tr('web_link'),
                    icon: Icons.public_rounded,
                    color: AppColors.violet,
                    onPressed: () => openWebShare(context, controller, upload: false, withSelection: true),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    context.tr('tap_device'),
                    textAlign: TextAlign.end,
                    style: const TextStyle(color: AppColors.cyan, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Glass(
      glow: AppColors.violet,
      borderColor: dragging ? AppColors.cyan : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(icon: Icons.inventory_2_rounded, color: AppColors.cyan, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        files.length == 1
                            ? context.tr('one_file_ready')
                            : context.tr('n_files_ready', {'n': files.length}),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(formatBytes(controller.selectedBytes),
                        style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  ],
                ),
              ),
              TextButton(
                onPressed: controller.clearSelected,
                child: Text(context.tr('clear'), style: const TextStyle(color: AppColors.muted)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: files.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
              itemBuilder: (context, i) =>
                  _FileRow(file: files[i], onRemove: () => controller.removeSelected(files[i])),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GhostButton(label: context.tr('add'), icon: Icons.add_rounded, onPressed: controller.pickFiles),
              GhostButton(label: context.tr('folder'), icon: Icons.folder_rounded, onPressed: () => _pickFolder(context)),
              if (controller.appSharing)
                GhostButton(
                  label: context.tr('apps'),
                  icon: Icons.apps_rounded,
                  color: AppColors.mint,
                  onPressed: () => openAppPicker(context, controller),
                ),
              if (controller.settings.webShare)
                GhostButton(
                  label: context.tr('web_link'),
                  icon: Icons.public_rounded,
                  color: AppColors.violet,
                  onPressed: () => openWebShare(context, controller, upload: false, withSelection: true),
                ),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4),
                child: Text(
                  context.tr('tap_device'),
                  style: const TextStyle(color: AppColors.cyan, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickFolder(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await controller.pickFolder();
    if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _editText(BuildContext context) async {
    var initial = controller.selectedText ?? '';
    if (initial.isEmpty) {
      try {
        initial = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
      } catch (_) {}
    }
    if (!context.mounted) return;
    final field = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => GlassDialog(
        maxWidth: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('send_text_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(context.tr('send_text_sub'), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: field,
              autofocus: true,
              minLines: 4,
              maxLines: 10,
              maxLength: 65536,
              decoration: InputDecoration(hintText: context.tr('type_or_paste'), counterText: ''),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: GhostButton(label: context.tr('cancel'), onPressed: () => Navigator.pop(ctx), expand: true)),
                const SizedBox(width: 12),
                Expanded(
                  child: GlowButton(
                      label: context.tr('done'), expand: true, onPressed: () => Navigator.pop(ctx, field.text)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (result != null) controller.setText(result);
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.onRemove});
  final FileEntry file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(fileIcon(file.name), size: 20, color: AppColors.muted),
          const SizedBox(width: 12),
          Expanded(child: Text(file.name, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Text(formatBytes(file.size), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          IconButton(
            tooltip: context.tr('delete'),
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _DevicesSection extends StatefulWidget {
  const _DevicesSection({required this.controller});
  final AppController controller;

  @override
  State<_DevicesSection> createState() => _DevicesSectionState();
}

class _DevicesSectionState extends State<_DevicesSection> {
  AppController get controller => widget.controller;
  bool _selecting = false;
  final Set<String> _chosen = {};

  @override
  Widget build(BuildContext context) {
    final peers = controller.peers;
    _chosen.removeWhere((id) => !peers.any((p) => p.id == id));
    if (peers.length < 2) _selecting = false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          context.tr('nearby'),
          trailing: Wrap(
            children: [
              if (peers.length >= 2)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _selecting = !_selecting;
                    _chosen.clear();
                  }),
                  icon: Icon(_selecting ? Icons.close_rounded : Icons.checklist_rounded, size: 17, color: AppColors.cyan),
                  label: Text(context.tr(_selecting ? 'cancel' : 'select'), style: const TextStyle(color: AppColors.cyan)),
                ),
              if (controller.settings.clipboardSync && !_selecting)
                TextButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final none = context.tr('clip_none');
                    final sentMsg = context.tr('clip_sent', {'n': '#'});
                    final sent = await controller.pollClipboard(force: true);
                    messenger.showSnackBar(SnackBar(content: Text(sent == 0 ? none : sentMsg.replaceAll('#', '$sent'))));
                  },
                  icon: const Icon(Icons.content_paste_go_rounded, size: 17, color: AppColors.cyan),
                  label: Text(context.tr('clipboard'), style: const TextStyle(color: AppColors.cyan)),
                ),
              if (hasCamera && !_selecting)
                TextButton.icon(
                  onPressed: () => _scan(context),
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 17, color: AppColors.cyan),
                  label: Text(context.tr('scan_qr'), style: const TextStyle(color: AppColors.cyan)),
                ),
              if (!_selecting)
                TextButton.icon(
                onPressed: () => _sendToTarget(context),
                icon: const Icon(Icons.link_rounded, size: 17, color: AppColors.cyan),
                label: Text(context.tr('by_link'), style: const TextStyle(color: AppColors.cyan)),
              ),
            ],
          ),
        ),
        if (!_selecting)
          Builder(builder: (context) {
            final groups = [
              for (final g in controller.settings.deviceGroups)
                if (controller.peersInGroup(g).isNotEmpty) (g, controller.peersInGroup(g).length),
            ];
            if (groups.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (g, n) in groups)
                    ActionChip(
                      avatar: const Icon(Icons.groups_rounded, size: 17, color: AppColors.violet),
                      label: Text(context.tr('group_send', {'group': groupLabel(context, g), 'n': n})),
                      onPressed: () {
                        if (!controller.hasSelection) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('pick_first'))));
                          return;
                        }
                        unawaited(controller.sendToGroup(g));
                      },
                    ),
                ],
              ),
            );
          }),
        if (controller.p2pLink != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Glass(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              borderColor: AppColors.mint.withValues(alpha: 0.45),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => WifiDirectPage(controller: controller))),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded, color: AppColors.mint, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr('p2p_connected_to', {'name': controller.p2pLink!.peerName ?? '?'}),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.mint, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('p2p_disconnect'),
                    onPressed: controller.p2pDisconnect,
                    icon: const Icon(Icons.link_off_rounded, size: 20, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
        if (peers.isEmpty)
          Glass(
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
            child: Column(
              children: [
                const Radar(
                  size: 170,
                  center: Icon(Icons.wifi_tethering_rounded, color: AppColors.cyan, size: 30),
                ),
                const SizedBox(height: 14),
                Text(context.tr('scanning'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 6),
                Text(
                  context.tr('scanning_sub'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                if (controller.wifiDirectAvailable) ...[
                  const SizedBox(height: 14),
                  GhostButton(
                    label: context.tr('p2p_try'),
                    icon: Icons.wifi_tethering_rounded,
                    color: AppColors.cyan,
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => WifiDirectPage(controller: controller))),
                  ),
                ],
              ],
            ),
          )
        else
        ...[
          for (final peer in peers)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PeerTile(
                key: _peerKeys.putIfAbsent(peer.id, GlobalKey.new),
                name: controller.displayName(peer.id, peer.name),
                group: controller.settings.devicePrefs[peer.id]?.group,
                peer: peer,
                trusted: controller.trust.isTrusted(peer.id),
                onMore: controller.trust.isTrusted(peer.id) ? () => showDeviceActions(context, controller, peer) : null,
                selected: _selecting ? _chosen.contains(peer.id) : null,
                onTap: _selecting
                    ? () => setState(() => _chosen.contains(peer.id) ? _chosen.remove(peer.id) : _chosen.add(peer.id))
                    : () => _send(context, peer),
              ),
            ),
          if (_selecting)
            GlowButton(
              label: context.tr('send_to_n', {'n': _chosen.length}),
              icon: Icons.call_split_rounded,
              expand: true,
              onPressed: _chosen.isEmpty
                  ? null
                  : () {
                      if (!controller.hasSelection) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('pick_first'))));
                        return;
                      }
                      final targets = peers.where((p) => _chosen.contains(p.id)).toList();
                      setState(() {
                        _selecting = false;
                        _chosen.clear();
                      });
                      unawaited(controller.sendToMany(targets));
                    },
            ),
        ],
        if (controller.settings.offlineQueue && controller.trustedOffline.isNotEmpty && !_selecting) ...[
          const SizedBox(height: 14),
          SectionTitle(context.tr('offline_trusted')),
          for (final d in controller.trustedOffline.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Glass(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                onTap: () {
                  if (!controller.hasSelection) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('pick_first'))));
                    return;
                  }
                  unawaited(controller.enqueueFor(d));
                },
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 20, color: AppColors.muted),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(context.tr('send_when_online'),
                              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                        ],
                      ),
                    ),
                    const Icon(Icons.schedule_send_rounded, color: AppColors.violet, size: 20),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  void _send(BuildContext context, Peer peer) {
    if (!controller.hasSelection) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('pick_first'))));
      return;
    }
    unawaited(controller.sendTo(peer));
  }

  Future<void> _scan(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final link = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanPage()));
    if (link == null || !context.mounted) return;
    if (!controller.hasSelection) {
      // Keep the link: let the user pick what to send, then finish.
      messenger.showSnackBar(SnackBar(content: Text(context.tr('pick_first'))));
      await controller.pickFiles();
      if (!controller.hasSelection) return;
    }
    final error = await controller.sendToTarget(link);
    if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _sendToTarget(BuildContext context) async {
    final text = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => GlassDialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('target_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(context.tr('target_sub'), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 16),
              TextField(
                controller: text,
                autofocus: true,
                keyboardType: TextInputType.url,
                textDirection: TextDirection.ltr,
                style: kMono,
                decoration: InputDecoration(
                  hintText: '192.168.1.20  ·  sudosend://pair?…',
                  errorText: error,
                  suffixIcon: IconButton(
                    tooltip: context.tr('paste'),
                    icon: const Icon(Icons.content_paste_rounded, size: 18),
                    onPressed: () async {
                      final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
                      if (clip != null) text.text = clip.trim();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: GhostButton(label: context.tr('cancel'), onPressed: () => Navigator.pop(ctx), expand: true)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlowButton(
                      label: context.tr('send'),
                      icon: Icons.north_east_rounded,
                      expand: true,
                      onPressed: () async {
                        final result = await controller.sendToTarget(text.text);
                        if (result == null) {
                          if (ctx.mounted) Navigator.pop(ctx);
                        } else {
                          setState(() => error = result);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({
    super.key,
    required this.name,
    this.group,
    required this.peer,
    required this.trusted,
    required this.onTap,
    this.selected,
    this.onMore,
  });

  /// Nickname, or the device's own name.
  final String name;
  final String? group;

  /// Trusted devices: ring, speed test, message, folder sync.
  final VoidCallback? onMore;

  final Peer peer;
  final bool trusted;
  final VoidCallback onTap;

  /// null = normal mode; true/false = multi-select mode.
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final color = platformColor(peer.platform);
    return ValueListenableBuilder<String?>(
      valueListenable: _dropPeer,
      builder: (context, hover, child) => Glass(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        borderColor: selected == true || hover == peer.id ? AppColors.cyan : null,
        glow: hover == peer.id ? AppColors.cyan : null,
        child: child!,
      ),
      child: Row(
        children: [
          IconBadge(icon: platformIcon(peer.platform), color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(peer.manual ? context.tr('manual') : groupFingerprint(peer.id, groups: 2),
                        textDirection: TextDirection.ltr, style: kMono.copyWith(color: AppColors.muted, fontSize: 11.5)),
                    Text(peer.address.address,
                        textDirection: TextDirection.ltr, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                    if (trusted)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified_user_rounded, size: 14, color: AppColors.mint),
                          const SizedBox(width: 3),
                          Text(context.tr('trusted'),
                              style: const TextStyle(color: AppColors.mint, fontSize: 11.5, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    if (group != null)
                      Text(groupLabel(context, group!),
                          style: const TextStyle(color: AppColors.violet, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
          ),
          if (onMore != null && selected == null)
            IconButton(
              tooltip: context.tr('device_actions'),
              onPressed: onMore,
              icon: const Icon(Icons.more_horiz_rounded, size: 22, color: AppColors.amber),
            ),
          if (selected != null)
            Checkbox(value: selected, onChanged: (_) => onTap())
          else
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: const Icon(Icons.north_east_rounded, size: 18, color: AppColors.cyan),
            ),
        ],
      ),
    );
  }
}
