import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/util.dart';
import '../state/app_controller.dart';
import 'glass.dart';
import 'theme.dart';

class TransfersTab extends StatelessWidget {
  const TransfersTab({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final jobs = controller.jobs;
    if (jobs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Glass(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconBadge(icon: Icons.swap_vert_rounded, color: AppColors.violet, size: 58),
                SizedBox(height: 14),
                Text('No transfers yet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                SizedBox(height: 6),
                Text('Everything you send or receive shows up here.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
              ],
            ),
          ),
        ),
      );
    }
    final hasFinished = jobs.any((j) => !j.isActive);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: jobs.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return SectionTitle(
            'Activity',
            trailing: hasFinished
                ? TextButton(
                    onPressed: controller.clearFinished,
                    child: const Text('Clear finished', style: TextStyle(color: AppColors.muted)),
                  )
                : null,
          );
        }
        final job = jobs[i - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ListenableBuilder(listenable: job, builder: (context, _) => _JobCard(job: job)),
        );
      },
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});
  final TransferJob job;

  @override
  Widget build(BuildContext context) {
    final outgoing = job.direction == TransferDirection.outgoing;
    final accent = outgoing ? AppColors.cyan : AppColors.mint;
    final showSas = outgoing && job.status == TransferStatus.awaitingApproval && job.sas != null;
    final showProgress = job.status == TransferStatus.transferring ||
        job.status == TransferStatus.verifying ||
        job.status == TransferStatus.done;

    return Glass(
      glow: job.isActive ? accent : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: outgoing ? Icons.north_east_rounded : Icons.south_west_rounded,
                color: accent,
                size: 42,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${outgoing ? 'To' : 'From'} ${job.peerName}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    Text(
                      '${job.files.length} ${job.files.length == 1 ? 'file' : 'files'} · ${formatBytes(job.totalBytes)}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              _StatusChip(status: job.status, outgoing: outgoing),
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
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                ),
              ],
            ),
          ],
          if (job.status == TransferStatus.done) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.verified_rounded, size: 16, color: AppColors.mint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    outgoing
                        ? 'Delivered · SHA-256 verified by receiver'
                        : 'SHA-256 verified · saved to ${job.savedPaths.isEmpty ? '—' : _dirOf(job.savedPaths.first)}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.mint, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
          if (job.error != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 17, color: AppColors.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(job.error!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
                ),
              ],
            ),
          ],
          if (job.isActive) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: job.cancelRequested ? null : job.cancel,
                icon: const Icon(Icons.close_rounded, size: 17, color: AppColors.danger),
                label: Text(job.cancelRequested ? 'Cancelling…' : 'Cancel',
                    style: const TextStyle(color: AppColors.danger)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _dirOf(String path) {
    final sep = path.contains('\\') ? '\\' : '/';
    final i = path.lastIndexOf(sep);
    return i > 0 ? path.substring(0, i) : path;
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
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shield_rounded, size: 16, color: AppColors.amber),
              SizedBox(width: 6),
              Text('VERIFICATION CODE',
                  style: TextStyle(color: AppColors.amber, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
            ],
          ),
          const SizedBox(height: 8),
          Text(formatSas(sas),
              style: kMono.copyWith(fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 6)),
          const SizedBox(height: 6),
          const Text(
            'The receiver must see this exact code before accepting.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12.5),
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
    return const Row(
      children: [
        Icon(Icons.verified_user_rounded, size: 18, color: AppColors.mint),
        SizedBox(width: 8),
        Expanded(
          child: Text('Trusted device · waiting for the receiver to accept…',
              style: TextStyle(color: AppColors.mint, fontSize: 13, fontWeight: FontWeight.w600)),
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
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: value),
          duration: const Duration(milliseconds: 220),
          builder: (context, v, _) => FractionallySizedBox(
            widthFactor: v.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(colors: [color, AppColors.violet]),
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 12, spreadRadius: -2)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.outgoing});
  final TransferStatus status;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      TransferStatus.connecting => ('Connecting', AppColors.muted),
      TransferStatus.awaitingApproval => ('Waiting', AppColors.amber),
      TransferStatus.transferring => (outgoing ? 'Sending' : 'Receiving', AppColors.cyan),
      TransferStatus.verifying => ('Verifying', AppColors.violet),
      TransferStatus.done => ('Done', AppColors.mint),
      TransferStatus.declined => ('Declined', AppColors.danger),
      TransferStatus.failed => ('Failed', AppColors.danger),
      TransferStatus.cancelled => ('Cancelled', AppColors.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800)),
    );
  }
}
