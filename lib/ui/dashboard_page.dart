import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:wraith_core/models.dart';
import 'package:wraith_core/organize.dart';
import 'package:wraith_core/util.dart';

import '../app/scope.dart';
import '../state/app_controller.dart';
import '../state/history.dart';
import '../state/library.dart';
import '../state/stats.dart';
import 'audit_page.dart';
import 'background.dart';
import 'devices_page.dart';
import 'glass.dart';
import 'library_page.dart' show categoryColor, categoryIcon, categoryLabel;
import 'storage_map_page.dart';
import 'sync_page.dart' show SubPageHeader;
import 'theme.dart';

/// One screen for everything SUDOSEND has done.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  StatsPeriod _period = StatsPeriod.daily;

  AppController get c => widget.controller;

  Stats _stats() => Stats(c.history.entries, c.library.items,
      nameOf: (HistoryEntry e) => c.displayName(e.fingerprint ?? '', e.peerName));

  @override
  void initState() {
    super.initState();
    c.refreshStorage();
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
                final st = _stats();
                final dups = c.library.duplicateGroups();
                final wasted = dups.fold<int>(0, (a, g) => a + g.first.size * (g.length - 1));
                return Column(
                  children: [
                    SubPageHeader(title: context.tr('dash_title')),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                            children: [
                              LayoutBuilder(builder: (context, box) {
                                final cols = box.maxWidth > 700 ? 4 : 2;
                                final w = (box.maxWidth - 10 * (cols - 1)) / cols;
                                Widget card(IconData i, Color col, String label, String value) =>
                                    SizedBox(width: w, child: _StatCard(icon: i, color: col, label: label, value: value));
                                return Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    card(Icons.south_west_rounded, AppColors.mint, context.tr('dash_received'),
                                        '${st.filesReceived} · ${formatBytes(st.bytesReceived)}'),
                                    card(Icons.north_east_rounded, AppColors.cyan, context.tr('dash_sent'),
                                        '${st.filesSent} · ${formatBytes(st.bytesSent)}'),
                                    card(Icons.swap_vert_rounded, AppColors.violet, context.tr('dash_total'),
                                        formatBytes(st.bytesReceived + st.bytesSent)),
                                    card(Icons.check_circle_rounded, AppColors.mint, context.tr('dash_transfers'),
                                        '${st.transfers} · ${context.tr('dash_failed', {'n': st.failed})}'),
                                    card(Icons.speed_rounded, AppColors.amber, context.tr('dash_avg_speed'),
                                        st.averageSpeed > 0 ? formatSpeed(st.averageSpeed) : '—'),
                                    card(Icons.rocket_launch_rounded, AppColors.pink, context.tr('dash_peak_speed'),
                                        st.peakSpeed > 0 ? formatSpeed(st.peakSpeed) : '—'),
                                    card(Icons.copy_all_rounded, AppColors.amber, context.tr('dash_duplicates'),
                                        '${dups.length} · ${formatBytes(wasted)}'),
                                    card(Icons.folder_rounded, AppColors.cyan, context.tr('dash_library'),
                                        '${c.library.items.length} · ${formatBytes(c.library.items.fold(0, (a, i) => a + i.size))}'),
                                  ],
                                );
                              }),
                              const SizedBox(height: 22),
                              SectionTitle(
                                context.tr('dash_activity'),
                                trailing: SegmentedButton<StatsPeriod>(
                                  showSelectedIcon: false,
                                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                                  segments: [
                                    ButtonSegment(value: StatsPeriod.daily, label: Text(context.tr('dash_daily'))),
                                    ButtonSegment(value: StatsPeriod.weekly, label: Text(context.tr('dash_weekly'))),
                                    ButtonSegment(value: StatsPeriod.monthly, label: Text(context.tr('dash_monthly'))),
                                  ],
                                  selected: {_period},
                                  onSelectionChanged: (v) => setState(() => _period = v.first),
                                ),
                              ),
                              Glass(child: _ActivityChart(buckets: st.activity(_period))),
                              const SizedBox(height: 22),
                              SectionTitle(context.tr('dash_top_senders')),
                              Glass(
                                child: st.topSenders().isEmpty
                                    ? Text(context.tr('dash_nothing'), style: const TextStyle(color: AppColors.muted))
                                    : Column(
                                        children: [
                                          for (final s in st.topSenders())
                                            _BarRow(
                                              icon: Icons.devices_rounded,
                                              color: AppColors.cyan,
                                              label: s.$1,
                                              value: '${s.$2} · ${formatBytes(s.$3)}',
                                              fraction: s.$3 / math.max(1, st.topSenders().first.$3),
                                            ),
                                        ],
                                      ),
                              ),
                              const SizedBox(height: 22),
                              SectionTitle(context.tr('dash_categories')),
                              Glass(
                                child: st.topCategories().isEmpty
                                    ? Text(context.tr('dash_nothing'), style: const TextStyle(color: AppColors.muted))
                                    : Column(
                                        children: [
                                          for (final s in st.topCategories())
                                            _BarRow(
                                              icon: categoryIcon(s.$1),
                                              color: categoryColor(s.$1),
                                              label: categoryLabel(context, s.$1),
                                              value: '${s.$2} · ${formatBytes(s.$3)}',
                                              fraction: s.$3 / math.max(1, st.topCategories().first.$3),
                                            ),
                                        ],
                                      ),
                              ),
                              const SizedBox(height: 22),
                              SectionTitle(
                                context.tr('dash_storage'),
                                trailing: TextButton.icon(
                                  onPressed: () => Navigator.of(context)
                                      .push(MaterialPageRoute<void>(builder: (_) => StorageMapPage(controller: c))),
                                  icon: const Icon(Icons.grid_view_rounded, size: 17, color: AppColors.cyan),
                                  label: Text(context.tr('heat_title'), style: const TextStyle(color: AppColors.cyan)),
                                ),
                              ),
                              Glass(child: _StorageCard(controller: c)),
                              const SizedBox(height: 22),
                              SectionTitle(context.tr('dash_duplicates')),
                              Glass(
                                child: dups.isEmpty
                                    ? Text(context.tr('dash_no_dups'), style: const TextStyle(color: AppColors.muted))
                                    : Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(context.tr('dash_dups_sub', {'n': dups.length, 'size': formatBytes(wasted)}),
                                              style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                                          const SizedBox(height: 8),
                                          for (final g in dups.take(30)) _DupGroup(controller: c, group: g),
                                        ],
                                      ),
                              ),
                              const SizedBox(height: 22),
                              SectionTitle(context.tr('dash_reports')),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  GhostButton(
                                    label: 'CSV',
                                    icon: Icons.table_chart_rounded,
                                    color: AppColors.mint,
                                    onPressed: () => _export(context, 'csv', st),
                                  ),
                                  GhostButton(
                                    label: 'JSON',
                                    icon: Icons.data_object_rounded,
                                    color: AppColors.cyan,
                                    onPressed: () => _export(context, 'json', st),
                                  ),
                                  GhostButton(
                                    label: 'PDF',
                                    icon: Icons.picture_as_pdf_rounded,
                                    color: AppColors.pink,
                                    onPressed: () => _export(context, 'pdf', st),
                                  ),
                                  GhostButton(
                                    label: context.tr('audit_title'),
                                    icon: Icons.policy_rounded,
                                    color: AppColors.amber,
                                    onPressed: () => Navigator.of(context)
                                        .push(MaterialPageRoute<void>(builder: (_) => AuditPage(controller: c))),
                                  ),
                                  GhostButton(
                                    label: context.tr('devices_title'),
                                    icon: Icons.devices_other_rounded,
                                    color: AppColors.violet,
                                    onPressed: () => Navigator.of(context)
                                        .push(MaterialPageRoute<void>(builder: (_) => DevicesPage(controller: c))),
                                  ),
                                ],
                              ),
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

  Future<void> _export(BuildContext context, String kind, Stats st) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = context.tr('history_exported');
    final day = dateFolder(DateTime.now());
    String? path;
    switch (kind) {
      case 'csv':
        path = await c.exportText('sudosend-report-$day.csv', st.toCsv());
      case 'json':
        path = await c.exportText('sudosend-report-$day.json', st.toPrettyJson(c.history.entries));
      default:
        path = await c.exportBytes('sudosend-report-$day.pdf', await _pdf(st));
    }
    if (path != null) messenger.showSnackBar(SnackBar(content: Text('$saved · $path')));
  }

  Future<Uint8List> _pdf(Stats st) async {
    pw.Font? font;
    pw.Font? bold;
    try {
      font = pw.Font.ttf(await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf'));
      bold = pw.Font.ttf(await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf'));
    } catch (_) {}
    final theme = font == null ? null : pw.ThemeData.withFont(base: font, bold: bold ?? font);
    final doc = pw.Document(title: 'SUDOSEND report', author: c.identity.name);
    pw.Widget kv(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(children: [
            pw.SizedBox(width: 170, child: pw.Text(k, style: const pw.TextStyle(color: PdfColors.grey700))),
            pw.Expanded(child: pw.Text(v, style: const pw.TextStyle(fontWeight: pw.FontWeight.bold))),
          ]),
        );
    final rows = c.history.entries.take(500).toList();
    doc.addPage(pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.cyan, width: 2))),
        child: pw.Row(children: [
          pw.Text('SUDOSEND', style: const pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.cyan800)),
          pw.Spacer(),
          pw.Text('${c.identity.name} · ${DateTime.now().toIso8601String().substring(0, 16).replaceAll('T', ' ')}'),
        ]),
      ),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}', style: const pw.TextStyle(color: PdfColors.grey600)),
      ),
      build: (_) => [
        pw.SizedBox(height: 10),
        pw.Text('Summary', style: const pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        kv('Files received', '${st.filesReceived} (${formatBytes(st.bytesReceived)})'),
        kv('Files sent', '${st.filesSent} (${formatBytes(st.bytesSent)})'),
        kv('Transfers / failed', '${st.transfers} / ${st.failed}'),
        kv('Average speed', st.averageSpeed > 0 ? formatSpeed(st.averageSpeed) : '-'),
        kv('Peak speed', st.peakSpeed > 0 ? formatSpeed(st.peakSpeed) : '-'),
        kv('Duplicate groups', '${c.library.duplicateGroups().length}'),
        if (c.disk != null) kv('Free space', '${formatBytes(c.disk!.$1)} of ${formatBytes(c.disk!.$2)}'),
        pw.SizedBox(height: 14),
        pw.Text('Top senders', style: const pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        for (final s in st.topSenders(10)) kv(s.$1, '${s.$2} files · ${formatBytes(s.$3)}'),
        pw.SizedBox(height: 14),
        pw.Text('Received by type', style: const pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        for (final s in st.topCategories()) kv(s.$1.folder, '${s.$2} files · ${formatBytes(s.$3)}'),
        pw.SizedBox(height: 14),
        pw.Text('Transfers (latest ${rows.length})', style: const pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headerStyle: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          headers: ['Time', 'Dir', 'Device', 'Status', 'Files', 'Size', 'Speed'],
          data: [
            for (final e in rows)
              [
                e.at.toIso8601String().substring(0, 16).replaceAll('T', ' '),
                e.direction == TransferDirection.incoming ? 'in' : 'out',
                c.displayName(e.fingerprint ?? '', e.peerName),
                e.status.name,
                '${e.fileCount}',
                formatBytes(e.totalBytes),
                e.avgSpeed > 0 ? formatSpeed(e.avgSpeed) : '',
              ],
          ],
        ),
      ],
    ));
    return doc.save();
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.color, required this.label, required this.value});
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Glass(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value,
                textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5)),
          ),
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({required this.icon, required this.color, required this.label, required this.value, required this.fraction});
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(value, textDirection: TextDirection.ltr, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.02, 1.0),
              minHeight: 6,
              color: color,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityChart extends StatelessWidget {
  const _ActivityChart({required this.buckets});
  final List<ActivityBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final peak = buckets.fold<int>(0, (a, b) => math.max(a, b.total));
    return Column(
      children: [
        SizedBox(
          height: 150,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final b in buckets)
                Expanded(
                  child: Tooltip(
                    message: '${b.label}\n↓ ${formatBytes(b.received)}  ↑ ${formatBytes(b.sent)}',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _bar(b.sent, peak, AppColors.cyan),
                          _bar(b.received, peak, AppColors.mint),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < buckets.length; i++)
              Expanded(
                child: Text(
                  i % 2 == 0 ? buckets[i].label : '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 9.5),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legend(AppColors.mint, context.tr('dash_received')),
            const SizedBox(width: 16),
            _legend(AppColors.cyan, context.tr('dash_sent')),
          ],
        ),
      ],
    );
  }

  Widget _bar(int v, int peak, Color color) {
    final h = peak == 0 || v == 0 ? 0.0 : math.max(3.0, 140 * v / peak);
    return Container(
      height: h,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
    );
  }

  Widget _legend(Color c, String label) => Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ],
      );
}

class _StorageCard extends StatelessWidget {
  const _StorageCard({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final d = controller.disk;
    final byDevice = controller.usageByDevice().entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final byCat = controller.usageByCategory().entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final low = controller.storageLow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (d == null)
          Text(context.tr('storage_unknown'), style: const TextStyle(color: AppColors.muted))
        else ...[
          Row(
            children: [
              Icon(low ? Icons.sd_card_alert_rounded : Icons.sd_storage_rounded, color: low ? AppColors.danger : AppColors.mint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(context.tr('storage_free', {'free': formatBytes(d.$1), 'total': formatBytes(d.$2)}),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: d.$2 == 0 ? 0 : 1 - d.$1 / d.$2,
              minHeight: 10,
              color: low ? AppColors.danger : AppColors.cyan,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          if (low) ...[
            const SizedBox(height: 6),
            Text(context.tr('storage_low_body', {'free': formatBytes(d.$1)}), style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
          ],
        ],
        const SizedBox(height: 14),
        Text(context.tr('storage_by_device'), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        for (final e in byDevice.take(6))
          _BarRow(
            icon: Icons.devices_rounded,
            color: AppColors.violet,
            label: e.key,
            value: formatBytes(e.value),
            fraction: e.value / math.max(1, byDevice.first.value),
          ),
        const SizedBox(height: 10),
        Text(context.tr('storage_by_type'), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        for (final e in byCat)
          _BarRow(
            icon: categoryIcon(e.key),
            color: categoryColor(e.key),
            label: categoryLabel(context, e.key),
            value: formatBytes(e.value),
            fraction: e.value / math.max(1, byCat.first.value),
          ),
      ],
    );
  }
}

class _DupGroup extends StatelessWidget {
  const _DupGroup({required this.controller, required this.group});
  final AppController controller;
  final List<LibraryItem> group;

  @override
  Widget build(BuildContext context) {
    final keep = group.reduce((a, b) => a.receivedAt.isBefore(b.receivedAt) ? a : b);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.copy_all_rounded, color: AppColors.amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(keep.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${group.length} × ${formatBytes(keep.size)} · ${group.map((i) => i.device).toSet().join(', ')}',
                    overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => GlassDialog(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(ctx.tr('dash_keep_one_confirm', {'n': group.length - 1, 'name': keep.name}),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                              child: GhostButton(
                                  label: ctx.tr('cancel'), expand: true, onPressed: () => Navigator.pop(ctx, false))),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GhostButton(
                              label: ctx.tr('delete'),
                              color: AppColors.danger,
                              expand: true,
                              onPressed: () => Navigator.pop(ctx, true),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
              if (ok != true) return;
              for (final i in group) {
                if (i.path != keep.path) await controller.deleteLibraryItem(i);
              }
            },
            child: Text(context.tr('dash_keep_one'), style: const TextStyle(color: AppColors.amber)),
          ),
        ],
      ),
    );
  }
}
