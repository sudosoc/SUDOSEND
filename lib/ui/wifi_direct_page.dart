import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../platform/native_bridge.dart';
import '../state/app_controller.dart';
import 'background.dart';
import 'glass.dart';
import 'settings_page.dart' show InfoButton;
import 'sync_page.dart' show SubPageHeader;
import 'theme.dart';

/// Phone-to-phone Wi-Fi Direct: find nearby phones, invite one, and the
/// normal SUDOSEND device list takes over once the link is up.
class WifiDirectPage extends StatefulWidget {
  const WifiDirectPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<WifiDirectPage> createState() => _WifiDirectPageState();
}

class _WifiDirectPageState extends State<WifiDirectPage> {
  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void dispose() {
    // Scanning keeps the radio busy; stop when the screen closes.
    c.stopP2pScan();
    super.dispose();
  }

  Future<void> _scan() async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await c.startP2pScan();
    if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _connect(P2pPeer peer) async {
    final messenger = ScaffoldMessenger.of(context);
    final sent = context.tr('p2p_invite_sent', {'name': peer.label});
    final error = await c.p2pConnect(peer);
    messenger.showSnackBar(SnackBar(content: Text(error ?? sent)));
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
                final link = c.p2pLink;
                final apps = c.p2pPeers.where((p) => p.runsSudosend).toList();
                final others = c.p2pPeers.where((p) => !p.runsSudosend).toList();
                return Column(
                  children: [
                    SubPageHeader(title: context.tr('p2p_title')),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                            children: [
                              Glass(
                                child: Row(
                                  children: [
                                    const IconBadge(icon: Icons.wifi_tethering_rounded, color: AppColors.cyan, size: 42),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(context.tr('p2p_explain'),
                                          style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4)),
                                    ),
                                    InfoButton(title: context.tr('p2p_title'), body: context.tr('i_wifi_direct')),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              if (!c.p2pEnabled) _Notice(icon: Icons.wifi_off_rounded, text: context.tr('p2p_wifi_off')),
                              if (c.p2pError != null)
                                _Notice(icon: Icons.error_outline_rounded, text: context.tr('p2p_err_${c.p2pError}')),
                              if (link != null) ...[
                                Glass(
                                  borderColor: AppColors.mint.withValues(alpha: 0.5),
                                  glow: AppColors.mint,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const IconBadge(icon: Icons.link_rounded, color: AppColors.mint, size: 42),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(context.tr('p2p_connected_to', {'name': link.peerName ?? '?'}),
                                                    style: const TextStyle(fontWeight: FontWeight.w800)),
                                                Text(context.tr(link.owner ? 'p2p_role_owner' : 'p2p_role_client'),
                                                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(context.tr('p2p_next'), style: const TextStyle(fontSize: 13)),
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          GlowButton(
                                            label: context.tr('p2p_go_send'),
                                            icon: Icons.send_rounded,
                                            onPressed: () {
                                              c.setTab(0);
                                              Navigator.of(context).pop();
                                            },
                                          ),
                                          GhostButton(
                                            label: context.tr('p2p_disconnect'),
                                            icon: Icons.link_off_rounded,
                                            color: AppColors.danger,
                                            onPressed: c.p2pDisconnect,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 18),
                              ],
                              Row(
                                children: [
                                  Expanded(child: SectionTitle(context.tr('p2p_nearby'))),
                                  if (c.p2pScanning)
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyan),
                                    )
                                  else
                                    TextButton.icon(
                                      onPressed: _scan,
                                      icon: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.cyan),
                                      label: Text(context.tr('p2p_scan'), style: const TextStyle(color: AppColors.cyan)),
                                    ),
                                ],
                              ),
                              if (c.p2pPeers.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Text(context.tr(c.p2pScanning ? 'p2p_searching' : 'p2p_none'),
                                      style: const TextStyle(color: AppColors.muted)),
                                ),
                              for (final p in apps) _PeerRow(peer: p, inviting: c.p2pInviting == p.address, onTap: () => _connect(p)),
                              if (others.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(context.tr('p2p_others'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                                const SizedBox(height: 6),
                                for (final p in others)
                                  _PeerRow(peer: p, inviting: c.p2pInviting == p.address, onTap: () => _connect(p)),
                              ],
                              const SizedBox(height: 16),
                              Text(context.tr('p2p_hint'),
                                  style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45)),
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

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Glass(
        borderColor: AppColors.amber.withValues(alpha: 0.45),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.amber),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          ],
        ),
      ),
    );
  }
}

class _PeerRow extends StatelessWidget {
  const _PeerRow({required this.peer, required this.inviting, required this.onTap});
  final P2pPeer peer;
  final bool inviting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (statusKey, color) = switch (peer.status) {
      0 => ('p2p_st_connected', AppColors.mint),
      1 => ('p2p_st_invited', AppColors.amber),
      2 => ('p2p_st_failed', AppColors.danger),
      3 => ('p2p_st_available', AppColors.cyan),
      _ => ('p2p_st_unavailable', AppColors.muted),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Glass(
        padding: const EdgeInsets.all(14),
        onTap: peer.status == 0 || inviting ? null : onTap,
        child: Row(
          children: [
            IconBadge(
              icon: peer.runsSudosend ? Icons.bolt_rounded : Icons.smartphone_rounded,
              color: peer.runsSudosend ? AppColors.cyan : AppColors.muted,
              size: 42,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(peer.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (peer.runsSudosend && peer.name.isNotEmpty && peer.name != peer.label)
                        Text(peer.name, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                      Text(context.tr(statusKey), style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ),
            ),
            if (inviting)
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.amber))
            else if (peer.status != 0)
              const Icon(Icons.add_link_rounded, color: AppColors.cyan),
          ],
        ),
      ),
    );
  }
}
