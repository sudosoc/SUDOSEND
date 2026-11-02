import 'package:flutter/material.dart';
import 'package:wraith_core/organize.dart';
import 'package:wraith_core/util.dart';

import '../app/scope.dart';
import '../state/app_controller.dart';
import 'background.dart';
import 'glass.dart';
import 'library_page.dart' show categoryColor, categoryIcon, categoryLabel;
import 'preview_page.dart' show openSafely;
import 'settings_page.dart' show InfoButton;
import 'sync_page.dart' show SubPageHeader;
import 'theme.dart';

/// Search every trusted device's received files at once; identical copies
/// (same SHA-256) are grouped, with where each came from.
class RemoteSearchPage extends StatefulWidget {
  const RemoteSearchPage({super.key, required this.controller, this.initial = ''});
  final AppController controller;
  final String initial;

  @override
  State<RemoteSearchPage> createState() => _RemoteSearchPageState();
}

class _RemoteSearchPageState extends State<RemoteSearchPage> {
  late final TextEditingController _q = TextEditingController(text: widget.initial);
  FileCategory? _cat;
  List<RemoteHit>? _hits;
  bool _busy = false;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    if (widget.initial.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final hits = await c.searchEverywhere(_q.text.trim(), category: _cat);
    if (!mounted) return;
    setState(() {
      _hits = hits;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final devices = c.trustedOnline.where((p) => c.settings.prefsFor(p.id).search).length;
    // Group identical files by hash, biggest groups first.
    final groups = <String, List<RemoteHit>>{};
    for (final h in _hits ?? const <RemoteHit>[]) {
      (groups[h.sha256] ??= []).add(h);
    }
    final ordered = groups.values.toList()..sort((a, b) => b.length.compareTo(a.length));
    return Scaffold(
      backgroundColor: AppColors.bgTop,
      body: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackground()),
          SafeArea(
            child: Column(
              children: [
                SubPageHeader(title: context.tr('rs_title')),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Glass(
                          radius: 18,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: TextField(
                            controller: _q,
                            autofocus: widget.initial.isEmpty,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _run(),
                            decoration: InputDecoration(
                              hintText: context.tr('lib_search'),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              icon: const Icon(Icons.travel_explore_rounded, color: AppColors.cyan),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GlowButton(label: context.tr('rs_go'), onPressed: _busy ? null : _run),
                    ],
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final cat in FileCategory.values)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: FilterChip(
                            avatar: Icon(categoryIcon(cat), size: 16, color: categoryColor(cat)),
                            label: Text(categoryLabel(context, cat)),
                            selected: _cat == cat,
                            onSelected: (v) => setState(() => _cat = v ? cat : null),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(context.tr('rs_scope', {'n': devices}),
                            style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      ),
                      InfoButton(title: context.tr('rs_title'), body: context.tr('i_remote_search')),
                    ],
                  ),
                ),
                Expanded(
                  child: _busy
                      ? const Center(child: CircularProgressIndicator())
                      : _hits == null
                          ? const SizedBox.shrink()
                          : ordered.isEmpty
                              ? Center(child: Text(context.tr('lib_no_match'), style: const TextStyle(color: AppColors.muted)))
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                                  itemCount: ordered.length,
                                  itemBuilder: (context, i) => _HitGroup(controller: c, hits: ordered[i]),
                                ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HitGroup extends StatelessWidget {
  const _HitGroup({required this.controller, required this.hits});
  final AppController controller;
  final List<RemoteHit> hits;

  @override
  Widget build(BuildContext context) {
    final first = hits.first;
    // The oldest copy points at where the file originally came from.
    final oldest = hits.reduce((a, b) => a.receivedAt.isBefore(b.receivedAt) ? a : b);
    final local = hits.any((h) => h.holder == null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Glass(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(icon: categoryIcon(first.category), color: categoryColor(first.category), size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(first.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(
                        '${formatBytes(first.size)} · ${context.tr('rs_copies', {'n': hits.length})} · '
                        '${context.tr('rs_origin', {'name': oldest.from})}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final h in hits)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(h.holder == null ? Icons.smartphone_rounded : Icons.devices_rounded,
                        size: 17, color: h.holder == null ? AppColors.mint : AppColors.cyan),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${h.holderName} · ${dateFolder(h.receivedAt)} · ${context.tr('prev_from')}: ${h.from}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    if (h.holder == null)
                      TextButton(
                        onPressed: h.localPath == null ? null : () => openSafely(context, controller, h.localPath!),
                        child: Text(context.tr('open')),
                      )
                    else if (!local)
                      TextButton.icon(
                        icon: const Icon(Icons.download_rounded, size: 17),
                        label: Text(context.tr('rs_get')),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final asked = context.tr('rs_asked', {'name': h.holderName});
                          final error = await controller.fetchHit(h);
                          messenger.showSnackBar(SnackBar(content: Text(error ?? asked)));
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
