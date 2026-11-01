import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:wraith_core/models.dart';
import 'package:wraith_core/util.dart';

import '../app/scope.dart';
import '../platform/desktop.dart';
import '../state/app_controller.dart';
import '../state/history.dart';
import 'glass.dart';
import 'theme.dart';

class TransfersTab extends StatelessWidget {
  const TransfersTab({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final jobs = controller.jobs;
    final earlier = controller.earlierHistory;
    if (jobs.isEmpty && earlier.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Glass(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const IconBadge(icon: Icons.swap_vert_rounded, color: AppColors.violet, size: 58),
                const SizedBox(height: 14),
                Text(context.tr('no_transfers'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                const SizedBox(height: 6),
                Text(context.tr('no_transfers_sub'),
                    textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
              ],
            ),
          ),
        ),
      );
    }
    final hasFinished = jobs.any((j) => !j.isActive);
    final items = <Widget>[
      if (jobs.isNotEmpty)
        SectionTitle(
          context.tr('activity'),
          trailing: hasFinished
              ? TextButton(
                  onPressed: controller.clearFinished,
                  child: Text(context.tr('clear_finished'), style: const TextStyle(color: AppColors.muted)),
                )
              : null,
        ),
      for (final job in jobs)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: StreamBuilder<void>(
            stream: job.changes,
            builder: (context, _) => _JobCard(job: job, controller: controller),
          ),
        ),
      if (earlier.isNotEmpty) ...[
        const SizedBox(height: 8),
        SectionTitle(
          context.tr('earlier'),
          trailing: TextButton(
            onPressed: controller.clearHistory,
            child: Text(context.tr('clear_history'), style: const TextStyle(color: AppColors.muted)),
          ),
        ),
        for (final entry in earlier)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _HistoryTile(entry: entry, controller: controller),
          ),
      ],
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: items);
  }
}

String _summary(BuildContext context, int files, int bytes) => files == 1
    ? context.tr('one_file_size', {'size': formatBytes(bytes)})
    : context.tr('n_files_size', {'n': files, 'size': formatBytes(bytes)});

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job, required this.controller});
  final TransferJob job;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final outgoing = job.direction == TransferDirection.outgoing;
    final accent = outgoing ? AppColors.cyan : AppColors.mint;
    final showSas = outgoing && job.status == TransferStatus.awaitingApproval && job.sas != null;
    final showProgress = !job.isText &&
        (job.status == TransferStatus.transferring ||
            job.status == TransferStatus.verifying ||
            job.status == TransferStatus.done);

    return Glass(
      glow: job.isActive ? accent : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: job.isText ? Icons.notes_rounded : (outgoing ? Icons.north_east_rounded : Icons.south_west_rounded),
                color: accent,
                size: 42,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr(outgoing ? 'to_name' : 'from_name', {'name': job.peerName}),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    Text(
                      job.isText
                          ? context.tr('text_message', {'n': job.text!.length})
                          : '${_summary(context, job.files.length, job.totalBytes)}'
                              '${job.resumedBytes > 0 ? ' · ${context.tr('resumed')}' : ''}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              StatusChip(status: job.status, outgoing: outgoing),
            ],
          ),
          if (showSas) ...[
            const SizedBox(height: 16),
            job.peerTrusted ? const _TrustedNotice() : _SasPanel(sas: job.sas!),
          ],
          if (showProgress) ...[
            const SizedBox(height: 16),
            _ProgressBar(value: job.progress, color: accent),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('${(job.progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const Spacer(),
                Text(
                  '${formatBytes(job.doneBytes)} / ${formatBytes(job.totalBytes)}'
                  '${job.status == TransferStatus.transferring ? ' · ${formatSpeed(job.speed)}' : ''}',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                ),
              ],
            ),
          ],
          if (job.isText && (job.status == TransferStatus.done || outgoing)) ...[
            const SizedBox(height: 14),
            _TextPanel(text: job.text!, showCopy: !outgoing && job.status == TransferStatus.done),
          ],
          if (job.status == TransferStatus.done && !job.isText) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.verified_rounded, size: 16, color: AppColors.mint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.tr(outgoing ? 'delivered' : 'verified_saved'),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.mint, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (!outgoing && job.savedPaths.isNotEmpty) ...[
              const SizedBox(height: 10),
              _SavedFiles(paths: job.savedPaths, controller: controller),
            ],
          ],
          if (job.error != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 17, color: AppColors.danger),
                const SizedBox(width: 6),
                Expanded(child: Text(job.error!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5))),
              ],
            ),
          ],
          if (job.isActive) ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: job.cancelRequested ? null : job.cancel,
                icon: const Icon(Icons.close_rounded, size: 17, color: AppColors.danger),
                label: Text(context.tr(job.cancelRequested ? 'cancelling' : 'cancel'),
                    style: const TextStyle(color: AppColors.danger)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tappable list of received files with Open / Show in folder.
class _SavedFiles extends StatelessWidget {
  const _SavedFiles({required this.paths, required this.controller});
  final List<String> paths;
  final AppController controller;

  Future<void> _open(BuildContext context, String path) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = context.tr('cant_open');
    if (!await controller.openFile(path)) messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final shown = paths.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final path in shown)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _open(context, path),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
              child: Row(
                children: [
                  Icon(fileIcon(path), size: 18, color: AppColors.muted),
                  const SizedBox(width: 10),
                  Expanded(child: Text(p.basename(path), overflow: TextOverflow.ellipsis)),
                  const Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.cyan),
                ],
              ),
            ),
          ),
        if (paths.length > shown.length)
          Text(context.tr('n_more', {'n': paths.length - shown.length}),
              style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
        if (isDesktop) ...[
          const SizedBox(height: 8),
          GhostButton(
            label: context.tr('show_folder'),
            icon: Icons.folder_open_rounded,
            color: AppColors.cyan,
            onPressed: () => controller.reveal(paths.first),
          ),
        ],
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry, required this.controller});
  final HistoryEntry entry;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final outgoing = entry.direction == TransferDirection.outgoing;
    final existing = entry.savedPaths.where((s) => File(s).existsSync()).toList();
    final when = MaterialLocalizations.of(context);
    final date = '${when.formatShortDate(entry.at)} · ${when.formatTimeOfDay(TimeOfDay.fromDateTime(entry.at))}';
    return Glass(
      padding: const EdgeInsets.all(14),
      onTap: existing.isEmpty
          ? null
          : () async {
              final messenger = ScaffoldMessenger.of(context);
              final message = context.tr('cant_open');
              final ok = existing.length == 1 || !isDesktop
                  ? await controller.openFile(existing.first)
                  : await controller.reveal(existing.first);
              if (!ok) messenger.showSnackBar(SnackBar(content: Text(message)));
            },
      child: Row(
        children: [
          IconBadge(
            icon: entry.isText ? Icons.notes_rounded : (outgoing ? Icons.north_east_rounded : Icons.south_west_rounded),
            color: outgoing ? AppColors.cyan : AppColors.mint,
            size: 38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr(outgoing ? 'to_name' : 'from_name', {'name': entry.peerName}),
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text(
                  entry.isText
                      ? context.tr('text_message_short')
                      : (entry.fileCount == 1 && entry.firstName != null
                          ? '${p.basename(entry.firstName!)} · ${formatBytes(entry.totalBytes)}'
                          : _summary(context, entry.fileCount, entry.totalBytes)),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                Text(date, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              ],
            ),
          ),
          StatusChip(status: entry.status, outgoing: outgoing),
        ],
      ),
    );
  }
}

class _SasPanel extends StatelessWidget {
  const _SasPanel({required this.sas});
  final String sas;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: AppColors.amber.withValues(alpha: 0.07),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield_rounded, size: 16, color: AppColors.amber),
              const SizedBox(width: 6),
              Text(context.tr('verification_code'),
                  style: const TextStyle(
                      color: AppColors.amber, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
            ],
          ),
          const SizedBox(height: 8),
          Text(formatSas(sas),
              textDirection: TextDirection.ltr,
              style: kMono.copyWith(fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 6)),
          const SizedBox(height: 6),
          Text(
            context.tr('sas_hint_sender'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _TrustedNotice extends StatelessWidget {
  const _TrustedNotice();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.verified_user_rounded, size: 18, color: AppColors.mint),
        const SizedBox(width: 8),
        Expanded(
          child: Text(context.tr('trusted_waiting'),
              style: const TextStyle(color: AppColors.mint, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, required this.color});
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 9,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: value),
          duration: const Duration(milliseconds: 220),
          builder: (context, v, _) => FractionallySizedBox(
            widthFactor: v.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(colors: [color, AppColors.violet]),
                boxShadow: context.reducedEffects
                    ? const []
                    : [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 12, spreadRadius: -2)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, required this.outgoing});
  final TransferStatus status;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    final (key, color) = switch (status) {
      TransferStatus.connecting => ('st_connecting', AppColors.muted),
      TransferStatus.awaitingApproval => ('st_waiting', AppColors.amber),
      TransferStatus.transferring => (outgoing ? 'st_sending' : 'st_receiving', AppColors.cyan),
      TransferStatus.verifying => ('st_verifying', AppColors.violet),
      TransferStatus.done => ('st_done', AppColors.mint),
      TransferStatus.declined => ('st_declined', AppColors.danger),
      TransferStatus.failed => ('st_failed', AppColors.danger),
      TransferStatus.cancelled => ('st_cancelled', AppColors.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(context.tr(key), style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800)),
    );
  }
}

class _TextPanel extends StatelessWidget {
  const _TextPanel({required this.text, required this.showCopy});
  final String text;
  final bool showCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.black.withValues(alpha: 0.18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            text.length > 600 ? '${text.substring(0, 600)}…' : text,
            style: const TextStyle(fontSize: 13.5, height: 1.4),
          ),
          if (showCopy) ...[
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: GhostButton(
                label: context.tr('copy'),
                icon: Icons.copy_rounded,
                color: AppColors.cyan,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('copied'))));
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
