import 'package:flutter/material.dart';
import 'package:wraith_core/organize.dart' show dateFolder;

import '../app/scope.dart';
import '../state/app_controller.dart';
import '../state/audit.dart';
import 'background.dart';
import 'glass.dart';
import 'settings_page.dart' show InfoButton;
import 'sync_page.dart' show SubPageHeader;
import 'theme.dart';

(IconData, Color) auditStyle(AuditKind k) => switch (k) {
      AuditKind.connectionRejected => (Icons.shield_rounded, AppColors.danger),
      AuditKind.requestAccepted => (Icons.download_done_rounded, AppColors.mint),
      AuditKind.requestDeclined => (Icons.do_not_disturb_on_rounded, AppColors.muted),
      AuditKind.transferDone => (Icons.check_circle_rounded, AppColors.mint),
      AuditKind.transferFailed => (Icons.error_rounded, AppColors.danger),
      AuditKind.deviceTrusted => (Icons.verified_user_rounded, AppColors.mint),
      AuditKind.deviceUntrusted => (Icons.remove_moderator_rounded, AppColors.amber),
      AuditKind.deviceBlocked => (Icons.block_rounded, AppColors.danger),
      AuditKind.deviceUnblocked => (Icons.lock_open_rounded, AppColors.amber),
      AuditKind.trustExpired => (Icons.timer_off_rounded, AppColors.amber),
      AuditKind.permissionDenied => (Icons.gpp_bad_rounded, AppColors.danger),
      AuditKind.fileDeleted => (Icons.delete_rounded, AppColors.muted),
      AuditKind.duplicateFound => (Icons.copy_all_rounded, AppColors.amber),
      AuditKind.riskyFile => (Icons.gpp_maybe_rounded, AppColors.danger),
      AuditKind.storageLow => (Icons.sd_card_alert_rounded, AppColors.danger),
      AuditKind.settingsChanged => (Icons.tune_rounded, AppColors.cyan),
    };

/// Security log: connections, transfers, trust changes, deletions.
class AuditPage extends StatefulWidget {
  const AuditPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  String _filter = 'all'; // all | security | transfers | files

  static const _security = {
    AuditKind.connectionRejected,
    AuditKind.deviceTrusted,
    AuditKind.deviceUntrusted,
    AuditKind.deviceBlocked,
    AuditKind.deviceUnblocked,
    AuditKind.trustExpired,
    AuditKind.permissionDenied,
    AuditKind.riskyFile,
  };
  static const _transfers = {
    AuditKind.requestAccepted,
    AuditKind.requestDeclined,
    AuditKind.transferDone,
    AuditKind.transferFailed,
  };

  bool _match(AuditEvent e) => switch (_filter) {
        'security' => _security.contains(e.kind),
        'transfers' => _transfers.contains(e.kind),
        'files' => !_security.contains(e.kind) && !_transfers.contains(e.kind),
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      backgroundColor: AppColors.bgTop,
      body: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackground()),
          SafeArea(
            child: ListenableBuilder(
              listenable: c,
              builder: (context, _) {
                final events = c.audit.events.where(_match).take(1000).toList();
                return Column(
                  children: [
                    SubPageHeader(title: context.tr('audit_title')),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final f in const ['all', 'security', 'transfers', 'files'])
                                    Padding(
                                      padding: const EdgeInsetsDirectional.only(end: 6),
                                      child: ChoiceChip(
                                        label: Text(context.tr('audit_f_$f')),
                                        selected: _filter == f,
                                        onSelected: (_) => setState(() => _filter = f),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          InfoButton(title: context.tr('audit_title'), body: context.tr('i_audit_log')),
                          PopupMenuButton<String>(
                            tooltip: context.tr('s_export'),
                            icon: const Icon(Icons.download_rounded),
                            onSelected: (v) async {
                              final messenger = ScaffoldMessenger.of(context);
                              final saved = context.tr('history_exported');
                              final day = dateFolder(DateTime.now());
                              final path = v == 'csv'
                                  ? await c.exportText('sudosend-audit-$day.csv', c.audit.exportCsv())
                                  : await c.exportText('sudosend-audit-$day.jsonl', c.audit.exportJsonl());
                              if (path != null) messenger.showSnackBar(SnackBar(content: Text('$saved · $path')));
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'csv', child: Text('CSV')),
                              PopupMenuItem(value: 'jsonl', child: Text('JSON Lines (SIEM)')),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: events.isEmpty
                          ? Center(child: Text(context.tr('audit_empty'), style: const TextStyle(color: AppColors.muted)))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              itemCount: events.length,
                              itemBuilder: (context, i) {
                                final e = events[i];
                                final (icon, color) = auditStyle(e.kind);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Glass(
                                    padding: const EdgeInsets.all(10),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(icon, color: color, size: 20),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${context.tr('ae_${e.kind.name}')}${e.device == null ? '' : ' · ${e.device}'}',
                                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                              ),
                                              if (e.detail != null)
                                                Text(e.detail!,
                                                    textDirection: TextDirection.ltr,
                                                    style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          '${dateFolder(e.at)}\n${TimeOfDay.fromDateTime(e.at).format(context)}',
                                          textAlign: TextAlign.end,
                                          style: const TextStyle(color: AppColors.muted, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
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
