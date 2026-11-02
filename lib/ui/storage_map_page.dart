import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:wraith_core/organize.dart';
import 'package:wraith_core/util.dart';

import '../app/scope.dart';
import '../state/app_controller.dart';
import 'background.dart';
import 'glass.dart';
import 'library_page.dart' show categoryColor, categoryLabel;
import 'sync_page.dart' show SubPageHeader;
import 'theme.dart';

/// One rectangle of the map; children are shown when you tap it.
class MapNode {
  MapNode(this.label, this.size, this.color, [List<MapNode>? children]) : children = children ?? [];
  final String label;
  int size;
  final Color color;
  final List<MapNode> children;
}

const _palette = [AppColors.cyan, AppColors.violet, AppColors.pink, AppColors.amber, AppColors.mint, Color(0xFF60A5FA), Color(0xFFF472B6)];

/// Storage heatmap: a treemap where area = space used. Three views — by
/// device (→ type → day), by type (→ device), and real folders on disk.
class StorageMapPage extends StatefulWidget {
  const StorageMapPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<StorageMapPage> createState() => _StorageMapPageState();
}

class _StorageMapPageState extends State<StorageMapPage> {
  String _mode = 'device'; // device | type | disk
  final List<MapNode> _path = [];
  MapNode? _disk;
  bool _scanning = false;

  AppController get c => widget.controller;

  MapNode _byDevice(BuildContext context) {
    final root = MapNode(context.tr('heat_all'), 0, AppColors.cyan);
    final devices = <String, MapNode>{};
    var color = 0;
    for (final i in c.library.items) {
      final d = devices.putIfAbsent(i.device, () {
        final n = MapNode(i.device, 0, _palette[color++ % _palette.length]);
        root.children.add(n);
        return n;
      });
      final cat = d.children.where((x) => x.label == categoryLabel(context, i.category)).firstOrNull ??
          (MapNode(categoryLabel(context, i.category), 0, categoryColor(i.category))..let(d.children.add));
      final day = dateFolder(i.receivedAt);
      final dn = cat.children.where((x) => x.label == day).firstOrNull ??
          (MapNode(day, 0, categoryColor(i.category))..let(cat.children.add));
      dn.size += i.size;
      cat.size += i.size;
      d.size += i.size;
      root.size += i.size;
    }
    return root;
  }

  MapNode _byType(BuildContext context) {
    final root = MapNode(context.tr('heat_all'), 0, AppColors.cyan);
    for (final i in c.library.items) {
      final label = categoryLabel(context, i.category);
      final cat = root.children.where((x) => x.label == label).firstOrNull ??
          (MapNode(label, 0, categoryColor(i.category))..let(root.children.add));
      final dev = cat.children.where((x) => x.label == i.device).firstOrNull ??
          (MapNode(i.device, 0, categoryColor(i.category))..let(cat.children.add));
      dev.size += i.size;
      cat.size += i.size;
      root.size += i.size;
    }
    return root;
  }

  Future<void> _scanDisk() async {
    final dir = c.saveDir;
    if (dir == null || _scanning) return;
    setState(() => _scanning = true);
    final raw = await compute(scanFolderSizes, dir.path);
    MapNode build(Map<String, Object?> m, int depth) {
      final children = (m['c'] as List<Object?>? ?? const []).cast<Map<String, Object?>>();
      return MapNode(
        m['n'] as String,
        (m['s'] as num).toInt(),
        _palette[depth % _palette.length],
        [for (final ch in children) build(ch, depth + 1)],
      );
    }

    if (!mounted) return;
    setState(() {
      _disk = build(raw, 0);
      _scanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final root = switch (_mode) {
      'type' => _byType(context),
      'disk' => _disk,
      _ => _byDevice(context),
    };
    var node = root;
    for (final step in _path) {
      node = node?.children.where((x) => x.label == step.label).firstOrNull ?? node;
    }
    return Scaffold(
      backgroundColor: AppColors.bgTop,
      body: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackground()),
          SafeArea(
            child: Column(
              children: [
                SubPageHeader(title: context.tr('heat_title')),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: 'device', label: Text(context.tr('heat_by_device'))),
                      ButtonSegment(value: 'type', label: Text(context.tr('heat_by_type'))),
                      ButtonSegment(value: 'disk', label: Text(context.tr('heat_by_folder'))),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (v) {
                      setState(() {
                        _mode = v.first;
                        _path.clear();
                      });
                      if (_mode == 'disk' && _disk == null) _scanDisk();
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      if (_path.isNotEmpty)
                        IconButton(
                          tooltip: context.tr('heat_up'),
                          icon: const Icon(Icons.arrow_upward_rounded),
                          onPressed: () => setState(() => _path.removeLast()),
                        ),
                      Expanded(
                        child: Text(
                          [context.tr('heat_all'), ..._path.map((e) => e.label)].join('  ›  '),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                        ),
                      ),
                      if (node != null)
                        Text(formatBytes(node.size), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _scanning
                        ? Center(child: Text(context.tr('heat_scanning'), style: const TextStyle(color: AppColors.muted)))
                        : node == null || node.size == 0
                            ? Center(child: Text(context.tr('heat_empty'), style: const TextStyle(color: AppColors.muted)))
                            : Treemap(
                                nodes: node.children.where((x) => x.size > 0).toList()
                                  ..sort((a, b) => b.size.compareTo(a.size)),
                                onTap: (n) {
                                  if (n.children.isNotEmpty) setState(() => _path.add(n));
                                },
                              ),
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

extension _Let<T> on T {
  void let(void Function(T) f) => f(this);
}

/// Squarified treemap: rectangle area proportional to size; the biggest
/// folders, types and devices stand out at a glance.
class Treemap extends StatelessWidget {
  const Treemap({super.key, required this.nodes, required this.onTap});
  final List<MapNode> nodes;
  final ValueChanged<MapNode> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final rects = squarify([for (final n in nodes) n.size.toDouble()], Offset.zero & box.biggest);
      final total = nodes.fold<int>(0, (a, n) => a + n.size);
      return Stack(
        children: [
          for (var i = 0; i < nodes.length && i < rects.length; i++)
            Positioned.fromRect(
              rect: rects[i].deflate(1.5),
              child: Tooltip(
                message: '${nodes[i].label}\n${formatBytes(nodes[i].size)} · ${(100 * nodes[i].size / math.max(1, total)).toStringAsFixed(1)}%',
                child: Material(
                  color: nodes[i].color.withValues(alpha: 0.25 + 0.55 * math.sqrt(nodes[i].size / math.max(1, nodes.first.size))),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onTap(nodes[i]),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: rects[i].width < 46 || rects[i].height < 30
                          ? const SizedBox.shrink()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(nodes[i].label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.white)),
                                if (rects[i].height > 46)
                                  Text(formatBytes(nodes[i].size),
                                      style: const TextStyle(fontSize: 11, color: Colors.white70)),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// Squarified treemap layout (Bruls, Huizing & van Wijk). [sizes] must be
/// sorted from largest to smallest.
List<Rect> squarify(List<double> sizes, Rect area) {
  final out = List<Rect>.filled(sizes.length, Rect.zero);
  final total = sizes.fold<double>(0, (a, b) => a + b);
  if (total <= 0 || area.isEmpty) return out;
  final scale = area.width * area.height / total;
  final areas = [for (final s in sizes) s * scale];
  var rect = area;
  var i = 0;
  while (i < areas.length) {
    final short = math.min(rect.width, rect.height);
    final row = <int>[i];
    var rowSum = areas[i];
    double worst(List<int> r, double sum) {
      var w = 0.0;
      for (final k in r) {
        final a = areas[k];
        if (a <= 0) continue;
        final side = sum / short;
        final other = a / side;
        w = math.max(w, math.max(side / other, other / side));
      }
      return w;
    }

    var j = i + 1;
    while (j < areas.length) {
      final candidate = [...row, j];
      if (worst(candidate, rowSum + areas[j]) > worst(row, rowSum)) break;
      row.add(j);
      rowSum += areas[j];
      j++;
    }
    final thick = rowSum / short;
    var offset = 0.0;
    for (final k in row) {
      final len = areas[k] / thick;
      out[k] = rect.width >= rect.height
          ? Rect.fromLTWH(rect.left, rect.top + offset, thick, len)
          : Rect.fromLTWH(rect.left + offset, rect.top, len, thick);
      offset += len;
    }
    rect = rect.width >= rect.height
        ? Rect.fromLTRB(rect.left + thick, rect.top, rect.right, rect.bottom)
        : Rect.fromLTRB(rect.left, rect.top + thick, rect.right, rect.bottom);
    i = j;
  }
  return out;
}

/// Folder sizes under [root], 3 levels deep (runs in a background isolate).
Map<String, Object?> scanFolderSizes(String root) {
  Map<String, Object?> walk(Directory d, int depth) {
    var size = 0;
    final kids = <Map<String, Object?>>[];
    try {
      for (final e in d.listSync(followLinks: false)) {
        final name = p.basename(e.path);
        if (e is File) {
          try {
            size += e.lengthSync();
          } catch (_) {}
        } else if (e is Directory) {
          final child = depth < 3 ? walk(e, depth + 1) : {'n': name, 's': _dirSize(e), 'c': const []};
          size += (child['s'] as int);
          kids.add(child);
        }
      }
    } catch (_) {}
    return {'n': p.basename(d.path), 's': size, 'c': kids};
  }

  return walk(Directory(root), 0);
}

int _dirSize(Directory d) {
  var total = 0;
  try {
    for (final e in d.listSync(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += e.lengthSync();
        } catch (_) {}
      }
    }
  } catch (_) {}
  return total;
}
