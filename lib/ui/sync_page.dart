import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../platform/desktop.dart' show isDesktop;
import '../state/app_controller.dart';
import '../state/settings.dart';
import 'background.dart';
import 'glass.dart';
import 'theme.dart';

/// Lists folder-sync pairs and lets the user pause, run or remove them.
class SyncPage extends StatelessWidget {
  const SyncPage({super.key, required this.controller});
  final AppController controller;

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
              builder: (context, _) {
                final pairs = controller.settings.syncPairs;
                final trustedOnline = controller.trustedOnline;
                return Column(
                  children: [
                    SubPageHeader(title: context.tr('sync_title')),
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
                                    const IconBadge(icon: Icons.sync_alt_rounded, color: AppColors.violet, size: 40),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(context.tr('sync_explain'),
                                          style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4)),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              if (!controller.syncSupported)
                                Text(context.tr(controller.settings.folderSync ? 'sync_unsupported' : 'sync_off'),
                                    style: const TextStyle(color: AppColors.amber)),
                              if (pairs.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: Text(context.tr('sync_none'), style: const TextStyle(color: AppColors.muted)),
                                ),
                              for (final pair in pairs)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _PairCard(controller: controller, pair: pair),
                                ),
                              if (controller.syncSupported) ...[
                                const SizedBox(height: 12),
                                SectionTitle(context.tr('sync_new')),
                                if (trustedOnline.isEmpty)
                                  Text(context.tr('sync_need_device'), style: const TextStyle(color: AppColors.muted, fontSize: 13))
                                else
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final peer in trustedOnline)
                                        GhostButton(
                                          label: peer.name,
                                          icon: Icons.add_rounded,
                                          color: AppColors.violet,
                                          onPressed: () async {
                                            final messenger = ScaffoldMessenger.of(context);
                                            final error = await controller.createSync(peer);
                                            if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
                                          },
                                        ),
                                    ],
                                  ),
                              ],
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

class _PairCard extends StatelessWidget {
  const _PairCard({required this.controller, required this.pair});
  final AppController controller;
  final SyncPair pair;

  @override
  Widget build(BuildContext context) {
    final online = controller.isOnline(pair.fingerprint) || controller.isRecent(pair.fingerprint);
    final busy = controller.isSyncing(pair.id);
    final last = pair.lastSync == null
        ? context.tr('sync_never')
        : TimeOfDay.fromDateTime(pair.lastSync!).format(context);
    return Glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon: Icons.folder_copy_rounded, color: pair.enabled ? AppColors.violet : AppColors.muted, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pair.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('⇄ ${pair.peerName}${online ? '' : ' · ${context.tr('chat_offline')}'}',
                        style: TextStyle(color: online ? AppColors.mint : AppColors.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              Switch(
                value: pair.enabled,
                onChanged: (v) => controller.setSyncEnabled(pair.id, v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(pair.path, textDirection: TextDirection.ltr, style: kMono.copyWith(color: AppColors.muted, fontSize: 11)),
          const SizedBox(height: 6),
          Text(context.tr('sync_status', {'time': last, 'n': pair.pushed}),
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          if (pair.lastError != null)
            Text(pair.lastError!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              GhostButton(
                label: context.tr(busy ? 'sync_running' : 'sync_now'),
                icon: Icons.sync_rounded,
                color: AppColors.cyan,
                onPressed: busy || !online || !pair.enabled ? null : controller.syncNow,
              ),
              if (isDesktop)
              GhostButton(
                label: context.tr('s_hot_open'),
                icon: Icons.folder_open_rounded,
                onPressed: () => controller.reveal(pair.path),
              ),
              GhostButton(
                label: context.tr('sync_remove'),
                icon: Icons.link_off_rounded,
                color: AppColors.danger,
                onPressed: () => controller.removeSync(pair.id),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Back button + title, shared by the settings sub-pages.
class SubPageHeader extends StatelessWidget {
  const SubPageHeader({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 6),
      child: Row(
        children: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
            icon: const BackButtonIcon(),
            color: AppColors.text,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ),
        ],
      ),
    );
  }
}
