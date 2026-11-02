import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:video_player/video_player.dart';
import 'package:wraith_core/inspect.dart';
import 'package:wraith_core/organize.dart';
import 'package:wraith_core/risk.dart';
import 'package:wraith_core/util.dart';

import '../app/scope.dart';
import '../platform/desktop.dart';
import '../state/app_controller.dart';
import '../state/library.dart';
import 'glass.dart';
import 'theme.dart';

const _images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'jfif'};
const _text = {
  'txt', 'md', 'csv', 'tsv', 'json', 'log', 'xml', 'yaml', 'yml', 'toml', 'ini', 'conf', 'cfg', 'html', 'htm', 'css', //
  'js', 'py', 'dart', 'java', 'kt', 'c', 'h', 'cpp', 'hpp', 'cs', 'go', 'rs', 'rb', 'php', 'swift', 'sh', 'bash', 'ps1',
  'bat', 'sql', 'srt', 'vtt', 'gradle', 'properties', 'env',
};

bool get _videoSupported => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

/// Opens a file after a warning if it could be dangerous.
Future<void> openSafely(BuildContext context, AppController c, String path) async {
  final risk = await c.riskOf(path);
  if (risk.level != RiskLevel.none && context.mounted) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => GlassDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBadge(
              icon: Icons.gpp_maybe_rounded,
              color: risk.level == RiskLevel.danger ? AppColors.danger : AppColors.amber,
              size: 56,
            ),
            const SizedBox(height: 12),
            Text(ctx.tr(risk.level == RiskLevel.danger ? 'risk_danger_title' : 'risk_caution_title'),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(ctx.tr('risk_${risk.reason}'), textAlign: TextAlign.center, style: const TextStyle(height: 1.4)),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: GlowButton(label: ctx.tr('cancel'), expand: true, onPressed: () => Navigator.pop(ctx, false))),
                const SizedBox(width: 10),
                Expanded(
                  child: GhostButton(
                    label: ctx.tr('risk_open_anyway'),
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
  }
  await c.openFile(path);
}

/// In-app viewer for received files: swipe between them.
class PreviewPage extends StatefulWidget {
  const PreviewPage({super.key, required this.controller, required this.items, required this.index});
  final AppController controller;
  final List<LibraryItem> items;
  final int index;

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  late final PageController _pages = PageController(initialPage: widget.index < 0 ? 0 : widget.index);
  late int _current = widget.index < 0 ? 0 : widget.index;
  bool _info = false;

  AppController get c => widget.controller;
  LibraryItem get item => widget.items[_current];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(item.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            tooltip: context.tr('prev_info'),
            icon: Icon(_info ? Icons.info_rounded : Icons.info_outline_rounded),
            onPressed: () => setState(() => _info = !_info),
          ),
          IconButton(
            tooltip: context.tr('open'),
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: () => openSafely(context, c, item.path),
          ),
          if (isDesktop)
            IconButton(
              tooltip: context.tr('show_in_folder'),
              icon: const Icon(Icons.folder_open_rounded),
              onPressed: () => c.reveal(item.path),
            ),
          IconButton(
            tooltip: context.tr('delete'),
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _delete(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: widget.items.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, i) => _Viewer(key: ValueKey(widget.items[i].path), controller: c, item: widget.items[i]),
            ),
          ),
          if (_info) _InfoPanel(controller: c, item: item),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final target = item;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => GlassDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ctx.tr('delete_confirm', {'name': target.name}), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: GhostButton(label: ctx.tr('cancel'), expand: true, onPressed: () => Navigator.pop(ctx, false))),
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
    if (ok != true || !context.mounted) return;
    final nav = Navigator.of(context);
    await c.deleteLibraryItem(target);
    nav.pop();
  }
}

class _Viewer extends StatelessWidget {
  const _Viewer({super.key, required this.controller, required this.item});
  final AppController controller;
  final LibraryItem item;

  @override
  Widget build(BuildContext context) {
    final ext = item.extension;
    if (!File(item.path).existsSync()) return _Fallback(controller: controller, item: item, missing: true);
    if (_images.contains(ext) || (Platform.isAndroid && (ext == 'heic' || ext == 'heif'))) {
      return InteractiveViewer(
        maxScale: 8,
        child: Center(
          child: Image.file(
            File(item.path),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _Fallback(controller: controller, item: item),
          ),
        ),
      );
    }
    if (ext == 'pdf') return PdfViewer.file(item.path);
    if ((item.category == FileCategory.videos || item.category == FileCategory.audio) && _videoSupported) {
      return _MediaPlayer(path: item.path, audio: item.category == FileCategory.audio);
    }
    if (_text.contains(ext) || item.name.toLowerCase() == 'dockerfile') return _TextView(path: item.path, ext: ext);
    return _Fallback(controller: controller, item: item);
  }
}

class _TextView extends StatelessWidget {
  const _TextView({required this.path, required this.ext});
  final String path;
  final String ext;
  static const int maxBytes = 1024 * 1024;

  Future<(String, bool)> _load() async {
    final f = File(path);
    final len = await f.length();
    final raf = await f.open();
    try {
      final bytes = await raf.read(len < maxBytes ? len : maxBytes);
      var text = utf8.decode(bytes, allowMalformed: true);
      if (ext == 'json') {
        try {
          text = const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
        } catch (_) {}
      }
      return (text, len > maxBytes);
    } finally {
      await raf.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(String, bool)>(
      future: _load(),
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) return const Center(child: CircularProgressIndicator());
        return Container(
          color: const Color(0xFF0B1022),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data.$2)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(context.tr('prev_truncated'), style: const TextStyle(color: AppColors.amber, fontSize: 12)),
                  ),
                SelectableText(data.$1,
                    textDirection: TextDirection.ltr, style: kMono.copyWith(fontSize: 12.5, color: AppColors.text, height: 1.45)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MediaPlayer extends StatefulWidget {
  const _MediaPlayer({required this.path, required this.audio});
  final String path;
  final bool audio;

  @override
  State<_MediaPlayer> createState() => _MediaPlayerState();
}

class _MediaPlayerState extends State<_MediaPlayer> {
  late final VideoPlayerController _v = VideoPlayerController.file(File(widget.path));
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _v.initialize().then((_) {
      if (mounted) setState(() {});
    }, onError: (Object _) {
      if (mounted) setState(() => _failed = true);
    });
    _v.addListener(_tick);
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _v.removeListener(_tick);
    _v.dispose();
    super.dispose();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (_failed) return Center(child: Text(context.tr('prev_unsupported'), style: const TextStyle(color: AppColors.muted)));
    if (!_v.value.isInitialized) return const Center(child: CircularProgressIndicator());
    final playing = _v.value.isPlaying;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: widget.audio
                ? const Icon(Icons.audiotrack_rounded, size: 120, color: AppColors.amber)
                : AspectRatio(aspectRatio: _v.value.aspectRatio, child: VideoPlayer(_v)),
          ),
        ),
        VideoProgressIndicator(_v, allowScrubbing: true, colors: const VideoProgressColors(playedColor: AppColors.cyan)),
        Row(
          children: [
            IconButton(
              iconSize: 36,
              color: Colors.white,
              icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
              onPressed: () => playing ? _v.pause() : _v.play(),
            ),
            Text('${_fmt(_v.value.position)} / ${_fmt(_v.value.duration)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          ],
        ),
      ],
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.controller, required this.item, this.missing = false});
  final AppController controller;
  final LibraryItem item;
  final bool missing;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(fileIcon(item.name), size: 72, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(item.name, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(context.tr(missing ? 'lib_missing' : 'prev_unsupported'),
                textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
            if (!missing) ...[
              const SizedBox(height: 16),
              GhostButton(
                label: context.tr('prev_open_system'),
                icon: Icons.open_in_new_rounded,
                color: AppColors.cyan,
                onPressed: () => openSafely(context, controller, item.path),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.controller, required this.item});
  final AppController controller;
  final LibraryItem item;

  @override
  Widget build(BuildContext context) {
    final twins = controller.library.sameContent(item.sha256, except: item.path);
    Widget row(String k, String v, {bool mono = false, String? copy}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 110, child: Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 12.5))),
              Expanded(
                child: Text(v,
                    textDirection: mono ? TextDirection.ltr : null,
                    style: (mono ? kMono : const TextStyle()).copyWith(fontSize: 12.5, color: Colors.white)),
              ),
              if (copy != null)
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: copy));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('copied'))));
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.copy_rounded, size: 15, color: AppColors.muted),
                  ),
                ),
            ],
          ),
        );
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
      color: const Color(0xFF0E1530),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row(context.tr('prev_size'), formatBytes(item.size)),
            row(context.tr('prev_from'), item.device),
            row(context.tr('prev_received'), '${dateFolder(item.receivedAt)} ${TimeOfDay.fromDateTime(item.receivedAt).format(context)}'),
            row(context.tr('prev_type'), item.category.folder),
            row('SHA-256', item.sha256, mono: true, copy: item.sha256),
            row(context.tr('prev_path'), item.path, mono: true, copy: item.path),
            if (controller.settings.showMetadata) _MetadataSection(path: item.path, showGps: controller.settings.showGps, openUrl: controller.openUrl),
            if (twins.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(context.tr('prev_identical', {'n': twins.length}),
                  style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w700, fontSize: 12.5)),
              for (final t in twins.take(5))
                Text('• ${t.path}', textDirection: TextDirection.ltr, style: kMono.copyWith(fontSize: 11.5, color: AppColors.muted)),
            ],
          ],
        ),
      ),
    );
  }
}

/// File Metadata Explorer: EXIF, document properties, media info and
/// security flags, grouped and translated.
class _MetadataSection extends StatelessWidget {
  const _MetadataSection({required this.path, required this.showGps, required this.openUrl});
  final String path;
  final bool showGps;
  final Future<bool> Function(String url) openUrl;

  static const _order = ['security', 'gps', 'camera', 'image', 'document', 'media', 'audio', 'file'];

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FileMetadata>(
      future: inspectFile(path),
      builder: (context, snap) {
        final m = snap.data;
        if (m == null) return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator(minHeight: 2));
        final fields = m.fields.where((f) => (showGps || f.group != 'gps') && f.key != 'size').toList();
        final groups = <String, List<MetaField>>{};
        for (final f in fields) {
          (groups[f.group] ??= []).add(f);
        }
        String label(String key) {
          final k = 'mk_$key';
          final t = context.tr(k);
          return t == k ? key : t;
        }

        String value(MetaField f) {
          if (f.key == 'size') return formatBytes(int.tryParse(f.value) ?? 0);
          if (f.value == 'yes') return context.tr('mv_yes');
          if (f.value == 'present') return context.tr('mv_present');
          return f.value;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.manage_search_rounded, size: 18, color: AppColors.cyan),
                const SizedBox(width: 6),
                Text(context.tr('meta_title'), style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                if (m.format != null) ...[
                  const SizedBox(width: 8),
                  Text(m.format!, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ],
            ),
            if (m.hasLocation && showGps)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_rounded, size: 16, color: AppColors.pink),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(context.tr('meta_has_location'),
                          style: const TextStyle(color: AppColors.pink, fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                    TextButton(
                      onPressed: () => openUrl(
                          'https://www.openstreetmap.org/?mlat=${m.latitude}&mlon=${m.longitude}#map=16/${m.latitude}/${m.longitude}'),
                      child: Text(context.tr('meta_map')),
                    ),
                  ],
                ),
              ),
            if (!showGps && m.hasLocation)
              Text(context.tr('meta_gps_hidden'), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            for (final g in _order)
              if (groups[g] != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 2),
                  child: Text(context.tr('mg_$g').toUpperCase(),
                      style: TextStyle(
                          color: g == 'security' ? AppColors.amber : AppColors.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2)),
                ),
                for (final f in groups[g]!)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 130, child: Text(label(f.key), style: const TextStyle(color: AppColors.muted, fontSize: 12))),
                        Expanded(
                          child: SelectableText(value(f),
                              style: TextStyle(fontSize: 12, color: g == 'security' ? AppColors.amber : Colors.white)),
                        ),
                      ],
                    ),
                  ),
              ],
          ],
        );
      },
    );
  }
}
