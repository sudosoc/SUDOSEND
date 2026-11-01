import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:wraith_core/organize.dart';
import 'package:wraith_core/util.dart';

import '../app/scope.dart';
import '../state/app_controller.dart';
import '../state/library.dart';
import 'dashboard_page.dart';
import 'glass.dart';
import 'preview_page.dart';
import 'theme.dart';

IconData categoryIcon(FileCategory c) => switch (c) {
      FileCategory.documents => Icons.description_rounded,
      FileCategory.pictures => Icons.image_rounded,
      FileCategory.videos => Icons.movie_rounded,
      FileCategory.audio => Icons.audiotrack_rounded,
      FileCategory.archives => Icons.inventory_2_rounded,
      FileCategory.applications => Icons.apps_rounded,
      FileCategory.code => Icons.code_rounded,
      FileCategory.other => Icons.insert_drive_file_rounded,
    };

Color categoryColor(FileCategory c) => switch (c) {
      FileCategory.documents => AppColors.cyan,
      FileCategory.pictures => AppColors.pink,
      FileCategory.videos => AppColors.violet,
      FileCategory.audio => AppColors.amber,
      FileCategory.archives => AppColors.mint,
      FileCategory.applications => AppColors.danger,
      FileCategory.code => AppColors.cyan,
      FileCategory.other => AppColors.muted,
    };

String categoryLabel(BuildContext context, FileCategory c) => context.tr('cat_${c.name}');

/// The Files tab: every received file, searchable, as a list or a timeline.
class LibraryTab extends StatefulWidget {
  const LibraryTab({super.key, required this.controller});
  final AppController controller;

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> {
  final _search = TextEditingController();
  LibraryQuery _q = const LibraryQuery();
  bool _timeline = true;
  bool _filters = false;
  Timer? _debounce;

  AppController get c => widget.controller;

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _setQuery(LibraryQuery q) => setState(() => _q = q);

  @override
  Widget build(BuildContext context) {
    final results = c.library.search(_q);
    final total = results.fold<int>(0, (a, i) => a + i.size);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Glass(
                  radius: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: context.tr('lib_search'),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      icon: const Icon(Icons.search_rounded, color: AppColors.muted),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _search.clear();
                                _setQuery(_q.copyWith(text: ''));
                              },
                            ),
                    ),
                    onChanged: (v) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 200), () => _setQuery(_q.copyWith(text: v)));
                    },
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: context.tr('lib_filters'),
                onPressed: () => setState(() => _filters = !_filters),
                icon: Icon(Icons.tune_rounded, color: _q.copyWith(text: '').isEmpty ? AppColors.text : AppColors.cyan),
              ),
              IconButton(
                tooltip: context.tr(_timeline ? 'lib_list' : 'lib_timeline'),
                onPressed: () => setState(() => _timeline = !_timeline),
                icon: Icon(_timeline ? Icons.view_list_rounded : Icons.timeline_rounded),
              ),
              IconButton(
                tooltip: context.tr('dash_title'),
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => DashboardPage(controller: c))),
                icon: const Icon(Icons.insights_rounded, color: AppColors.violet),
              ),
            ],
          ),
        ),
        if (_filters) _FilterPanel(controller: c, query: _q, onChanged: _setQuery),
        if (c.storageLow)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Glass(
              padding: const EdgeInsets.all(12),
              borderColor: AppColors.danger.withValues(alpha: 0.5),
              child: Row(
                children: [
                  const Icon(Icons.sd_card_alert_rounded, color: AppColors.danger),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(context.tr('storage_low_body', {'free': formatBytes(c.disk!.$1)}),
                        style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Text(context.tr('lib_count', {'n': results.length, 'size': formatBytes(total)}),
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              const Spacer(),
              PopupMenuButton<String>(
                tooltip: context.tr('lib_sort'),
                initialValue: _q.sort,
                onSelected: (v) => _setQuery(_q.copyWith(sort: v)),
                itemBuilder: (_) => [
                  for (final s in const ['newest', 'oldest', 'largest', 'smallest', 'name'])
                    PopupMenuItem(value: s, child: Text(context.tr('sort_$s'))),
                ],
                child: Row(
                  children: [
                    const Icon(Icons.sort_rounded, size: 18, color: AppColors.muted),
                    const SizedBox(width: 4),
                    Text(context.tr('sort_${_q.sort}'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: c.library.items.isEmpty
              ? _Empty(controller: c)
              : results.isEmpty
                  ? Center(child: Text(context.tr('lib_no_match'), style: const TextStyle(color: AppColors.muted)))
                  : _timeline && (_q.sort == 'newest' || _q.sort == 'oldest')
                      ? _Timeline(controller: c, items: results)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                          itemCount: results.length,
                          itemBuilder: (context, i) => FileTile(controller: c, item: results[i], all: results),
                        ),
        ),
      ],
    );
  }
}

class _Empty extends StatefulWidget {
  const _Empty({required this.controller});
  final AppController controller;

  @override
  State<_Empty> createState() => _EmptyState();
}

class _EmptyState extends State<_Empty> {
  (int, int)? _progress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IconBadge(icon: Icons.folder_open_rounded, color: AppColors.cyan, size: 60),
            const SizedBox(height: 14),
            Text(context.tr('lib_empty'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            Text(context.tr('lib_empty_sub'),
                textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 16),
            if (_progress != null)
              Text(context.tr('lib_scanning', {'done': _progress!.$1, 'total': _progress!.$2}),
                  style: const TextStyle(color: AppColors.cyan))
            else
              GhostButton(
                label: context.tr('lib_scan'),
                icon: Icons.manage_search_rounded,
                color: AppColors.cyan,
                onPressed: () async {
                  setState(() => _progress = (0, 0));
                  await widget.controller.scanLibrary(onProgress: (d, t) {
                    if (mounted) setState(() => _progress = (d, t));
                  });
                  if (mounted) setState(() => _progress = null);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({required this.controller, required this.query, required this.onChanged});
  final AppController controller;
  final LibraryQuery query;
  final ValueChanged<LibraryQuery> onChanged;

  static const _sizes = <(String, int?, int?)>[
    ('size_any', null, null),
    ('size_small', null, 1024 * 1024),
    ('size_medium', 1024 * 1024, 100 * 1024 * 1024),
    ('size_large', 100 * 1024 * 1024, 1024 * 1024 * 1024),
    ('size_huge', 1024 * 1024 * 1024, null),
  ];

  @override
  Widget build(BuildContext context) {
    final devices = controller.library.devices;
    String dateLabel() {
      if (query.from == null && query.to == null) return context.tr('date_any');
      String d(DateTime? t) => t == null ? '…' : dateFolder(t);
      return '${d(query.from)} → ${d(query.to)}';
    }

    final sizeIndex = _sizes.indexWhere((s) => s.$2 == query.minSize && s.$3 == query.maxSize);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Glass(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final cat in FileCategory.values)
                  FilterChip(
                    avatar: Icon(categoryIcon(cat), size: 16, color: categoryColor(cat)),
                    label: Text(categoryLabel(context, cat)),
                    selected: query.category == cat,
                    onSelected: (v) => onChanged(query.copyWith(category: () => v ? cat : null)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<String?>(
                  value: devices.contains(query.device) ? query.device : null,
                  hint: Text(context.tr('lib_all_devices')),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text(context.tr('lib_all_devices'))),
                    for (final d in devices) DropdownMenuItem<String?>(value: d, child: Text(d)),
                  ],
                  onChanged: (v) => onChanged(query.copyWith(device: () => v)),
                ),
                DropdownButton<int>(
                  value: sizeIndex < 0 ? 0 : sizeIndex,
                  items: [
                    for (var i = 0; i < _sizes.length; i++)
                      DropdownMenuItem(value: i, child: Text(context.tr(_sizes[i].$1))),
                  ],
                  onChanged: (i) {
                    final s = _sizes[i ?? 0];
                    onChanged(query.copyWith(minSize: () => s.$2, maxSize: () => s.$3));
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.date_range_rounded, size: 16),
                  label: Text(dateLabel()),
                  onPressed: () async {
                    final now = DateTime.now();
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(now.year, now.month, now.day),
                      initialDateRange: query.from != null && query.to != null
                          ? DateTimeRange(start: query.from!, end: query.to!)
                          : null,
                    );
                    if (range != null) onChanged(query.copyWith(from: () => range.start, to: () => range.end));
                  },
                ),
                FilterChip(
                  avatar: const Icon(Icons.copy_all_rounded, size: 16),
                  label: Text(context.tr('lib_dups_only')),
                  selected: query.duplicatesOnly,
                  onSelected: (v) => onChanged(query.copyWith(duplicatesOnly: v)),
                ),
                if (!query.copyWith(text: '').isEmpty)
                  TextButton(
                    onPressed: () => onChanged(LibraryQuery(text: query.text, sort: query.sort)),
                    child: Text(context.tr('lib_clear_filters')),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(context.tr('lib_search_tip'), style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

/// Files grouped by day, newest first: "what did I get on Tuesday?".
class _Timeline extends StatelessWidget {
  const _Timeline({required this.controller, required this.items});
  final AppController controller;
  final List<LibraryItem> items;

  @override
  Widget build(BuildContext context) {
    final days = <String, List<LibraryItem>>{};
    for (final i in items) {
      (days[dateFolder(i.receivedAt)] ??= []).add(i);
    }
    final keys = days.keys.toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      itemCount: keys.length,
      itemBuilder: (context, k) {
        final day = days[keys[k]]!;
        final byDevice = <String, int>{};
        for (final i in day) {
          byDevice[i.device] = (byDevice[i.device] ?? 0) + 1;
        }
        final size = day.fold<int>(0, (a, i) => a + i.size);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: kAccentGradient),
                  ),
                  const SizedBox(width: 10),
                  Text(_dayLabel(context, day.first.receivedAt), style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${day.length} · ${formatBytes(size)} · ${byDevice.entries.map((e) => '${e.key} ${e.value}').join(' · ')}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            for (final i in day) FileTile(controller: controller, item: i, all: items),
          ],
        );
      },
    );
  }

  static String _dayLabel(BuildContext context, DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return context.tr('today');
    if (diff == 1) return context.tr('yesterday');
    return MaterialLocalizations.of(context).formatFullDate(day);
  }
}

class FileTile extends StatelessWidget {
  const FileTile({super.key, required this.controller, required this.item, required this.all});
  final AppController controller;
  final LibraryItem item;
  final List<LibraryItem> all;

  @override
  Widget build(BuildContext context) {
    final cat = item.category;
    final missing = !File(item.path).existsSync();
    final isDup = item.duplicateOf != null;
    Widget leading = IconBadge(icon: categoryIcon(cat), color: categoryColor(cat), size: 44);
    if (cat == FileCategory.pictures && !missing && const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'}.contains(item.extension)) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(item.path),
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          cacheWidth: 132,
          errorBuilder: (_, __, ___) => leading,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Glass(
        padding: const EdgeInsets.all(10),
        onTap: missing
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => PreviewPage(controller: controller, items: all, index: all.indexOf(item)),
                )),
        child: Opacity(
          opacity: missing ? 0.45 : 1,
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      '${formatBytes(item.size)} · ${item.device} · ${TimeOfDay.fromDateTime(item.receivedAt).format(context)}'
                      '${missing ? ' · ${context.tr('lib_missing')}' : ''}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (isDup)
                Tooltip(
                  message: context.tr('lib_dup_of', {'name': item.duplicateOf!.split(Platform.pathSeparator).last}),
                  child: const Icon(Icons.copy_all_rounded, color: AppColors.amber, size: 20),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
