import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:wraith_core/models.dart';
import 'package:wraith_core/util.dart';
import '../state/app_controller.dart';
import 'glass.dart';
import 'radar.dart';
import 'theme.dart';

class SendTab extends StatelessWidget {
  const SendTab({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 820;
      final picker = _FilesCard(controller: controller);
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
  }
}

class _FilesCard extends StatelessWidget {
  const _FilesCard({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final files = controller.selected;
    if (files.isEmpty) {
      return Glass(
        glow: AppColors.cyan,
        onTap: controller.pickFiles,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
        child: Column(
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: kAccentGradient,
                boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.5), blurRadius: 36, spreadRadius: -6)],
              ),
              child: const Icon(Icons.upload_rounded, size: 38, color: AppColors.ink),
            ),
            const SizedBox(height: 18),
            const Text('Choose files to send', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text(
              'Any size · encrypted in transit · SHA-256 verified on arrival',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                GlowButton(label: 'Files', icon: Icons.add_rounded, onPressed: controller.pickFiles),
                GhostButton(label: 'Folder', icon: Icons.folder_rounded, onPressed: () => _pickFolder(context)),
                GhostButton(label: 'Text', icon: Icons.notes_rounded, onPressed: () => _editText(context)),
              ],
            ),
          ],
        ),
      );
    }

    final text = controller.selectedText;
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
                  child: Text('Text ready · ${text.length} chars',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                TextButton(
                  onPressed: controller.clearSelected,
                  child: const Text('Clear', style: TextStyle(color: AppColors.muted)),
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
                GhostButton(label: 'Edit', icon: Icons.edit_rounded, onPressed: () => _editText(context)),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Tap a device below to send',
                    textAlign: TextAlign.end,
                    style: TextStyle(color: AppColors.cyan, fontSize: 12.5, fontWeight: FontWeight.w600),
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
                    Text('${files.length} ${files.length == 1 ? 'file' : 'files'} ready',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(formatBytes(controller.selectedBytes),
                        style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  ],
                ),
              ),
              TextButton(
                onPressed: controller.clearSelected,
                child: const Text('Clear', style: TextStyle(color: AppColors.muted)),
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
              itemBuilder: (context, i) => _FileRow(file: files[i], onRemove: () => controller.removeSelected(files[i])),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              GhostButton(label: 'Add', icon: Icons.add_rounded, onPressed: controller.pickFiles),
              const SizedBox(width: 8),
              GhostButton(label: 'Folder', icon: Icons.folder_rounded, onPressed: () => _pickFolder(context)),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Tap a device below to send',
                  textAlign: TextAlign.end,
                  style: TextStyle(color: AppColors.cyan, fontSize: 12.5, fontWeight: FontWeight.w600),
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
            const Text('Send text', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Links, notes, passwords, code — encrypted end to end. Prefilled from your clipboard.',
                style: TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: field,
              autofocus: true,
              minLines: 4,
              maxLines: 10,
              maxLength: 65536,
              decoration: const InputDecoration(hintText: 'Type or paste…', counterText: ''),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx), expand: true)),
                const SizedBox(width: 12),
                Expanded(
                  child: GlowButton(label: 'Done', expand: true, onPressed: () => Navigator.pop(ctx, field.text)),
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
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _DevicesSection extends StatelessWidget {
  const _DevicesSection({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final peers = controller.peers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Nearby devices',
          trailing: TextButton.icon(
            onPressed: () => _connectByIp(context),
            icon: const Icon(Icons.lan_rounded, size: 17, color: AppColors.cyan),
            label: const Text('By IP', style: TextStyle(color: AppColors.cyan)),
          ),
        ),
        if (peers.isEmpty)
          Glass(
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
            child: Column(
              children: [
                Radar(
                  size: 170,
                  center: const Icon(Icons.wifi_tethering_rounded, color: AppColors.cyan, size: 30),
                ),
                const SizedBox(height: 14),
                const Text('Scanning your network…', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 6),
                const Text(
                  'Open SUDOSEND on another device connected to the same Wi-Fi or hotspot.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ],
            ),
          )
        else
          for (final peer in peers)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PeerTile(
                peer: peer,
                trusted: controller.trust.isTrusted(peer.id),
                onTap: () => _send(context, peer),
              ),
            ),
      ],
    );
  }

  void _send(BuildContext context, Peer peer) {
    if (!controller.hasSelection) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick files, a folder or some text first, then tap a device.')),
      );
      return;
    }
    controller.sendTo(peer);
  }

  Future<void> _connectByIp(BuildContext context) async {
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
              const Text('Send by IP address', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text(
                'For networks that block discovery. The receiver shows its IP on the Receive tab.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: text,
                autofocus: true,
                keyboardType: TextInputType.url,
                style: kMono,
                decoration: InputDecoration(hintText: '192.168.1.20', errorText: error),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx), expand: true)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlowButton(
                      label: 'Send',
                      icon: Icons.north_east_rounded,
                      expand: true,
                      onPressed: () async {
                        final result = await controller.sendToAddress(text.text);
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
  const _PeerTile({required this.peer, required this.trusted, required this.onTap});

  final Peer peer;
  final bool trusted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = platformColor(peer.platform);
    return Glass(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          IconBadge(icon: platformIcon(peer.platform), color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(peer.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(peer.manual ? 'manual' : groupFingerprint(peer.id, groups: 2),
                        style: kMono.copyWith(color: AppColors.muted, fontSize: 11.5)),
                    Text(peer.address.address, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                    if (trusted)
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_user_rounded, size: 14, color: AppColors.mint),
                          SizedBox(width: 3),
                          Text('Trusted',
                              style: TextStyle(color: AppColors.mint, fontSize: 11.5, fontWeight: FontWeight.w700)),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
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
