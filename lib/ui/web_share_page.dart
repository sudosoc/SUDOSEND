import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wraith_core/util.dart';

import '../app/scope.dart';
import '../state/app_controller.dart';
import 'background.dart';
import 'glass.dart';
import 'theme.dart';

/// Live page for an active browser share: QR + links, activity, stop.
class WebSharePage extends StatelessWidget {
  const WebSharePage({super.key, required this.controller});

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
              listenable: controller,
              builder: (context, _) {
                final share = controller.webShare;
                final urls = controller.webUrls;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const BackButtonIcon(),
                              color: AppColors.text,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(context.tr('web_title'),
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (share == null)
                          Glass(
                            child: Text(context.tr('web_stopped'), textAlign: TextAlign.center),
                          )
                        else ...[
                          Glass(
                            glow: AppColors.cyan,
                            child: Column(
                              children: [
                                if (urls.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                        color: Colors.white, borderRadius: BorderRadius.circular(22)),
                                    child: QrImageView(
                                      data: urls.first,
                                      size: 220,
                                      backgroundColor: Colors.white,
                                      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.ink),
                                      dataModuleStyle: const QrDataModuleStyle(
                                          dataModuleShape: QrDataModuleShape.square, color: AppColors.ink),
                                    ),
                                  ),
                                const SizedBox(height: 14),
                                Text(context.tr(share.allowUpload ? 'web_sub_upload' : 'web_sub'),
                                    textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
                                const SizedBox(height: 12),
                                for (final u in urls)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 3),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: SelectableText(u,
                                              textDirection: TextDirection.ltr,
                                              style: kMono.copyWith(fontSize: 12, color: AppColors.cyan)),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.muted),
                                          onPressed: () {
                                            Clipboard.setData(ClipboardData(text: u));
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(content: Text(context.tr('copied'))));
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    _Pill(Icons.inventory_2_rounded,
                                        context.tr('web_files', {'n': share.files.length})),
                                    if (share.allowUpload) _Pill(Icons.upload_rounded, context.tr('web_upload_on')),
                                    if (share.expiresAt != null)
                                      _Pill(Icons.timer_outlined,
                                          context.tr('web_expires', {'time': TimeOfDay.fromDateTime(share.expiresAt!).format(context)})),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Glass(
                            borderColor: AppColors.amber.withValues(alpha: 0.35),
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline_rounded, color: AppColors.amber, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Text(context.tr('web_warning'), style: const TextStyle(fontSize: 12.5))),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          SectionTitle(context.tr('activity')),
                          if (controller.webEvents.isEmpty)
                            Text(context.tr('web_waiting'), style: const TextStyle(color: AppColors.muted))
                          else
                            for (final e in controller.webEvents.take(50))
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Icon(
                                      switch (e.kind) {
                                        'download' => Icons.north_east_rounded,
                                        'upload' => Icons.south_west_rounded,
                                        _ => Icons.visibility_rounded,
                                      },
                                      size: 18,
                                      color: e.kind == 'visit' ? AppColors.muted : AppColors.mint,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        switch (e.kind) {
                                          'download' => context.tr('web_ev_download', {'ip': e.address, 'name': e.name}),
                                          'upload' => context.tr('web_ev_upload',
                                              {'ip': e.address, 'name': e.name, 'size': formatBytes(e.size)}),
                                          _ => context.tr('web_ev_visit', {'ip': e.address}),
                                        },
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          const SizedBox(height: 20),
                          GhostButton(
                            label: context.tr('web_stop'),
                            icon: Icons.stop_circle_outlined,
                            color: AppColors.danger,
                            expand: true,
                            onPressed: controller.stopWebShare,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.muted),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

/// Opens the browser-share page after starting a share.
Future<void> openWebShare(BuildContext context, AppController controller,
    {required bool upload, required bool withSelection}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final error = await controller.startWebShare(upload: upload, withSelection: withSelection);
  if (error != null) {
    messenger.showSnackBar(SnackBar(content: Text(error)));
    return;
  }
  await navigator.push(MaterialPageRoute<void>(builder: (_) => WebSharePage(controller: controller)));
}
