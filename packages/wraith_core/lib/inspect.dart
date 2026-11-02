// File Metadata Explorer: reads what a file says about itself, without
// running or fully parsing it. Supported:
//   JPEG / PNG   EXIF (camera, dates, exposure, GPS), PNG text, dimensions
//   PDF          version, Info dictionary (title, author, producer, dates), encryption
//   DOCX/XLSX/PPTX  docProps (title, author, last editor, dates, app, pages), macros
//   MP4/MOV/M4A/3GP  creation date, duration, video size, ISO 6709 location
//   MP3          ID3v2 title, artist, album, year, genre
// Every reader is defensive: bad or hostile input yields fewer fields, never
// an exception.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class MetaField {
  const MetaField(this.group, this.key, this.value);

  /// file | image | camera | gps | document | media | audio | security
  final String group;
  final String key;
  final String value;

  @override
  String toString() => '$group/$key=$value';
}

class FileMetadata {
  final List<MetaField> fields = [];
  double? latitude;
  double? longitude;
  String? format;

  bool get hasLocation => latitude != null && longitude != null;

  void add(String group, String key, Object? value) {
    if (value == null) return;
    final v = '$value'.replaceAll('\u0000', '').trim();
    if (v.isEmpty) return;
    fields.add(MetaField(group, key, v.length > 300 ? '${v.substring(0, 300)}…' : v));
  }

  String? operator [](String key) => fields.where((f) => f.key == key).firstOrNull?.value;
}

/// Reads metadata from a file on disk (only the parts it needs).
Future<FileMetadata> inspectFile(String path) async {
  final meta = FileMetadata();
  final file = File(path);
  RandomAccessFile? raf;
  try {
    final stat = await file.stat();
    meta.add('file', 'size', stat.size);
    meta.add('file', 'modified', stat.modified.toIso8601String());
    meta.add('file', 'accessed', stat.accessed.toIso8601String());
    raf = await file.open();
    final size = stat.size;
    final head = await _readAt(raf, 0, size < 512 * 1024 ? size : 512 * 1024);
    final tail = size > head.length ? await _readAt(raf, size - (size < 128 * 1024 ? size : 128 * 1024), size < 128 * 1024 ? size : 128 * 1024) : head;
    final lower = path.toLowerCase();
    if (_isJpeg(head)) {
      meta.format = 'JPEG';
      _jpeg(head, meta);
    } else if (_isPng(head)) {
      meta.format = 'PNG';
      _png(head, meta);
    } else if (_starts(head, '%PDF-')) {
      meta.format = 'PDF';
      _pdf(head, tail, meta);
    } else if (_starts(head, 'PK') && (lower.endsWith('x') || lower.endsWith('m'))) {
      meta.format = 'Office Open XML';
      await _ooxml(raf, size, tail, meta);
    } else if (head.length >= 12 && String.fromCharCodes(head, 4, 8) == 'ftyp') {
      meta.format = 'MPEG-4 / QuickTime';
      await _mp4(raf, size, meta);
    } else if (_starts(head, 'ID3')) {
      meta.format = 'MP3 (ID3)';
      _id3(head, meta);
    }
  } catch (_) {
    // Partial results are fine.
  } finally {
    await raf?.close();
  }
  return meta;
}

/// Same as [inspectFile] for in-memory data (tests, small files).
FileMetadata inspectBytes(Uint8List bytes) {
  final meta = FileMetadata();
  try {
    if (_isJpeg(bytes)) {
      meta.format = 'JPEG';
      _jpeg(bytes, meta);
    } else if (_isPng(bytes)) {
      meta.format = 'PNG';
      _png(bytes, meta);
    } else if (_starts(bytes, '%PDF-')) {
      meta.format = 'PDF';
      _pdf(bytes, bytes, meta);
    } else if (_starts(bytes, 'ID3')) {
      meta.format = 'MP3 (ID3)';
      _id3(bytes, meta);
    }
  } catch (_) {}
  return meta;
}

Future<Uint8List> _readAt(RandomAccessFile raf, int at, int len) async {
  await raf.setPosition(at);
  return raf.read(len);
}

bool _isJpeg(Uint8List b) => b.length > 3 && b[0] == 0xFF && b[1] == 0xD8;
bool _isPng(Uint8List b) => b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
bool _starts(Uint8List b, String s) {
  if (b.length < s.length) return false;
  for (var i = 0; i < s.length; i++) {
    if (b[i] != s.codeUnitAt(i)) return false;
  }
  return true;
}

// ─────────────────────────── JPEG / EXIF ───────────────────────────

void _jpeg(Uint8List b, FileMetadata meta) {
  var i = 2;
  while (i + 4 <= b.length) {
    if (b[i] != 0xFF) return;
    final marker = b[i + 1];
    if (marker == 0xFF) {
      i++;
      continue;
    }
    if (marker == 0xDA || marker == 0xD9) return;
    if ((marker >= 0xD0 && marker <= 0xD7) || marker == 0x01) {
      i += 2;
      continue;
    }
    final len = (b[i + 2] << 8) | b[i + 3];
    if (len < 2 || i + 2 + len > b.length) return;
    final p = i + 4;
    if (marker == 0xE1 && p + 6 <= b.length && _starts(Uint8List.sublistView(b, p), 'Exif\u0000\u0000')) {
      _exif(Uint8List.sublistView(b, p + 6, i + 2 + len), meta);
    } else if (marker == 0xE1 && _starts(Uint8List.sublistView(b, p), 'http://ns.adobe.com/xap/1.0/')) {
      meta.add('security', 'xmp', 'present');
    } else if ((marker >= 0xC0 && marker <= 0xC3) && p + 5 <= b.length) {
      meta.add('image', 'height', (b[p + 1] << 8) | b[p + 2]);
      meta.add('image', 'width', (b[p + 3] << 8) | b[p + 4]);
    } else if (marker == 0xFE) {
      meta.add('image', 'comment', latin1.decode(Uint8List.sublistView(b, p, i + 2 + len), allowInvalid: true));
    }
    i += 2 + len;
  }
}

class _Tiff {
  _Tiff(this.d, this.le);
  final Uint8List d;
  final bool le;

  static _Tiff? of(Uint8List d) {
    if (d.length < 8) return null;
    if (d[0] == 0x49 && d[1] == 0x49) return _Tiff(d, true);
    if (d[0] == 0x4D && d[1] == 0x4D) return _Tiff(d, false);
    return null;
  }

  bool ok(int o, int n) => o >= 0 && o + n <= d.length;
  int u16(int o) => le ? d[o] | (d[o + 1] << 8) : (d[o] << 8) | d[o + 1];
  int u32(int o) => le
      ? d[o] | (d[o + 1] << 8) | (d[o + 2] << 16) | (d[o + 3] << 24)
      : (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3];
  int s32(int o) {
    final v = u32(o);
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }

  /// tag → (type, count, valueOffsetOrInline position)
  Map<int, (int, int, int)> ifd(int at) {
    final out = <int, (int, int, int)>{};
    if (!ok(at, 2)) return out;
    final n = u16(at);
    for (var k = 0; k < n && k < 512; k++) {
      final e = at + 2 + 12 * k;
      if (!ok(e, 12)) break;
      final type = u16(e + 2);
      final count = u32(e + 4);
      final size = _size(type) * count;
      out[u16(e)] = (type, count, size <= 4 ? e + 8 : u32(e + 8));
    }
    return out;
  }

  static int _size(int t) => switch (t) {
        3 || 8 => 2,
        4 || 9 || 11 => 4,
        5 || 10 || 12 => 8,
        _ => 1,
      };

  String? str(Map<int, (int, int, int)> m, int tag) {
    final e = m[tag];
    if (e == null || e.$1 != 2 || !ok(e.$3, e.$2)) return null;
    return latin1.decode(Uint8List.sublistView(d, e.$3, e.$3 + e.$2), allowInvalid: true);
  }

  int? integer(Map<int, (int, int, int)> m, int tag) {
    final e = m[tag];
    if (e == null) return null;
    if (e.$1 == 3 && ok(e.$3, 2)) return u16(e.$3);
    if (e.$1 == 4 && ok(e.$3, 4)) return u32(e.$3);
    return null;
  }

  List<double> rationals(Map<int, (int, int, int)> m, int tag) {
    final e = m[tag];
    if (e == null || (e.$1 != 5 && e.$1 != 10)) return const [];
    final out = <double>[];
    for (var k = 0; k < e.$2 && k < 8; k++) {
      final o = e.$3 + 8 * k;
      if (!ok(o, 8)) break;
      final num = e.$1 == 10 ? s32(o) : u32(o);
      final den = e.$1 == 10 ? s32(o + 4) : u32(o + 4);
      out.add(den == 0 ? 0 : num / den);
    }
    return out;
  }
}

void _exif(Uint8List tiffBytes, FileMetadata meta) {
  final t = _Tiff.of(tiffBytes);
  if (t == null || !t.ok(4, 4)) return;
  final ifd0 = t.ifd(t.u32(4));
  meta.add('camera', 'make', t.str(ifd0, 0x010F));
  meta.add('camera', 'model', t.str(ifd0, 0x0110));
  meta.add('image', 'software', t.str(ifd0, 0x0131));
  meta.add('image', 'dateTime', t.str(ifd0, 0x0132));
  meta.add('image', 'artist', t.str(ifd0, 0x013B));
  meta.add('image', 'copyright', t.str(ifd0, 0x8298));
  meta.add('image', 'orientation', t.integer(ifd0, 0x0112));
  final exifAt = t.integer(ifd0, 0x8769);
  if (exifAt != null) {
    final ex = t.ifd(exifAt);
    meta.add('image', 'dateTaken', t.str(ex, 0x9003));
    meta.add('image', 'offsetTime', t.str(ex, 0x9011));
    final exposure = t.rationals(ex, 0x829A);
    if (exposure.isNotEmpty && exposure.first > 0) {
      meta.add('camera', 'exposure', exposure.first < 1 ? '1/${(1 / exposure.first).round()} s' : '${exposure.first} s');
    }
    final f = t.rationals(ex, 0x829D);
    if (f.isNotEmpty) meta.add('camera', 'aperture', 'f/${f.first.toStringAsFixed(1)}');
    meta.add('camera', 'iso', t.integer(ex, 0x8827));
    final focal = t.rationals(ex, 0x920A);
    if (focal.isNotEmpty) meta.add('camera', 'focalLength', '${focal.first.toStringAsFixed(1)} mm');
    meta.add('camera', 'lens', t.str(ex, 0xA434));
    meta.add('image', 'width', t.integer(ex, 0xA002));
    meta.add('image', 'height', t.integer(ex, 0xA003));
    final serial = t.str(ex, 0xA431);
    if (serial != null) meta.add('security', 'cameraSerial', serial);
  }
  final gpsAt = t.integer(ifd0, 0x8825);
  if (gpsAt != null) {
    final g = t.ifd(gpsAt);
    final lat = t.rationals(g, 2), lon = t.rationals(g, 4);
    if (lat.length == 3 && lon.length == 3) {
      var la = lat[0] + lat[1] / 60 + lat[2] / 3600;
      var lo = lon[0] + lon[1] / 60 + lon[2] / 3600;
      if (t.str(g, 1)?.startsWith('S') ?? false) la = -la;
      if (t.str(g, 3)?.startsWith('W') ?? false) lo = -lo;
      if (la.abs() <= 90 && lo.abs() <= 180 && (la != 0 || lo != 0)) {
        meta.latitude = la;
        meta.longitude = lo;
        meta.add('gps', 'coordinates', '${la.toStringAsFixed(6)}, ${lo.toStringAsFixed(6)}');
      }
    }
    final alt = t.rationals(g, 6);
    if (alt.isNotEmpty) meta.add('gps', 'altitude', '${alt.first.toStringAsFixed(1)} m');
  }
}

// ─────────────────────────── PNG ───────────────────────────

void _png(Uint8List b, FileMetadata meta) {
  var i = 8;
  while (i + 12 <= b.length) {
    final len = (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
    final type = String.fromCharCodes(b, i + 4, i + 8);
    final data = i + 8;
    if (data + len > b.length) return;
    if (type == 'IHDR' && len >= 13) {
      meta.add('image', 'width', (b[data] << 24) | (b[data + 1] << 16) | (b[data + 2] << 8) | b[data + 3]);
      meta.add('image', 'height', (b[data + 4] << 24) | (b[data + 5] << 16) | (b[data + 6] << 8) | b[data + 7]);
      meta.add('image', 'bitDepth', b[data + 8]);
    } else if (type == 'tEXt' || type == 'iTXt') {
      final raw = Uint8List.sublistView(b, data, data + len);
      final z = raw.indexOf(0);
      if (z > 0) {
        final key = latin1.decode(Uint8List.sublistView(raw, 0, z));
        var value = utf8.decode(Uint8List.sublistView(raw, z + 1), allowMalformed: true);
        if (type == 'iTXt') value = value.split('\u0000').last;
        if (key == 'XML:com.adobe.xmp') {
          meta.add('security', 'xmp', 'present');
        } else {
          meta.add('image', key, value);
        }
      }
    } else if (type == 'eXIf') {
      _exif(Uint8List.sublistView(b, data, data + len), meta);
    } else if (type == 'IEND') {
      return;
    }
    i = data + len + 4;
  }
}

// ─────────────────────────── PDF ───────────────────────────

void _pdf(Uint8List head, Uint8List tail, FileMetadata meta) {
  final h = latin1.decode(head, allowInvalid: true);
  final t = identical(head, tail) ? h : latin1.decode(tail, allowInvalid: true);
  final version = RegExp(r'^%PDF-(\d\.\d)').firstMatch(h);
  meta.add('document', 'pdfVersion', version?.group(1));
  final text = '$h\n$t';
  for (final (key, name) in const [
    ('title', 'Title'),
    ('author', 'Author'),
    ('subject', 'Subject'),
    ('keywords', 'Keywords'),
    ('creator', 'Creator'),
    ('producer', 'Producer'),
  ]) {
    final m = RegExp('/$name\\s*\\(((?:\\\\.|[^\\\\)]){0,300})\\)').firstMatch(text);
    if (m != null) meta.add('document', key, _pdfString(m.group(1)!));
  }
  for (final (key, name) in const [('created', 'CreationDate'), ('modified', 'ModDate')]) {
    final m = RegExp('/$name\\s*\\(D:(\\d{4})(\\d{2})?(\\d{2})?(\\d{2})?(\\d{2})?').firstMatch(text);
    if (m != null) {
      meta.add('document', key,
          '${m.group(1)}-${m.group(2) ?? '01'}-${m.group(3) ?? '01'} ${m.group(4) ?? '00'}:${m.group(5) ?? '00'}');
    }
  }
  if (text.contains('/Encrypt')) meta.add('security', 'encrypted', 'yes');
  if (RegExp(r'/JavaScript|/JS\s').hasMatch(text)) meta.add('security', 'javascript', 'yes');
  if (text.contains('/OpenAction') || text.contains('/Launch')) meta.add('security', 'autoAction', 'yes');
  if (text.contains('/EmbeddedFile')) meta.add('security', 'embeddedFiles', 'yes');
}

String _pdfString(String s) {
  // UTF-16BE strings start with FE FF (shown here as þÿ in latin1).
  if (s.startsWith('þÿ')) {
    final units = <int>[];
    final b = latin1.encode(s.substring(2));
    for (var i = 0; i + 1 < b.length; i += 2) {
      units.add((b[i] << 8) | b[i + 1]);
    }
    return String.fromCharCodes(units);
  }
  return s.replaceAllMapped(RegExp(r'\\([()\\])'), (m) => m[1]!);
}

// ─────────────────────────── Office Open XML (ZIP) ───────────────────────────

Future<void> _ooxml(RandomAccessFile raf, int size, Uint8List tail, FileMetadata meta) async {
  // End of central directory: last 22..65557 bytes.
  var eocd = -1;
  for (var i = tail.length - 22; i >= 0 && i >= tail.length - 65557; i--) {
    if (tail[i] == 0x50 && tail[i + 1] == 0x4B && tail[i + 2] == 0x05 && tail[i + 3] == 0x06) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) return;
  int le16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
  int le32(Uint8List b, int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
  final entries = le16(tail, eocd + 10);
  final cdSize = le32(tail, eocd + 12);
  final cdOffset = le32(tail, eocd + 16);
  if (cdSize <= 0 || cdSize > 4 * 1024 * 1024 || cdOffset + cdSize > size) return;
  final cd = await _readAt(raf, cdOffset, cdSize);
  final wanted = <String, (int, int, int, int)>{}; // name → (method, compSize, size, localOffset)
  var p = 0;
  var macros = false;
  for (var k = 0; k < entries && p + 46 <= cd.length; k++) {
    if (le32(cd, p) != 0x02014b50) break;
    final method = le16(cd, p + 10);
    final comp = le32(cd, p + 20);
    final usize = le32(cd, p + 24);
    final nameLen = le16(cd, p + 28), extraLen = le16(cd, p + 30), commentLen = le16(cd, p + 32);
    final local = le32(cd, p + 42);
    if (p + 46 + nameLen > cd.length) break;
    final name = utf8.decode(Uint8List.sublistView(cd, p + 46, p + 46 + nameLen), allowMalformed: true);
    if (name == 'docProps/core.xml' || name == 'docProps/app.xml') wanted[name] = (method, comp, usize, local);
    if (name.toLowerCase().endsWith('vbaproject.bin')) macros = true;
    p += 46 + nameLen + extraLen + commentLen;
  }
  if (macros) meta.add('security', 'macros', 'yes');
  Future<String?> read(String name) async {
    final e = wanted[name];
    if (e == null || e.$2 > 2 * 1024 * 1024 || e.$3 > 4 * 1024 * 1024) return null;
    final lh = await _readAt(raf, e.$4, 30);
    if (lh.length < 30 || le32(lh, 0) != 0x04034b50) return null;
    final dataAt = e.$4 + 30 + le16(lh, 26) + le16(lh, 28);
    final data = await _readAt(raf, dataAt, e.$2);
    final bytes = e.$1 == 0 ? data : (e.$1 == 8 ? ZLibDecoder(raw: true).convert(data) : null);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  String? tag(String xml, String t) {
    final m = RegExp('<$t(?:\\s[^>]*)?>([^<]{0,300})</$t>').firstMatch(xml);
    return m == null ? null : _xmlUnescape(m.group(1)!);
  }

  final core = await read('docProps/core.xml');
  if (core != null) {
    meta.add('document', 'title', tag(core, 'dc:title'));
    meta.add('document', 'subject', tag(core, 'dc:subject'));
    meta.add('document', 'author', tag(core, 'dc:creator'));
    meta.add('document', 'lastModifiedBy', tag(core, 'cp:lastModifiedBy'));
    meta.add('document', 'created', tag(core, 'dcterms:created'));
    meta.add('document', 'modified', tag(core, 'dcterms:modified'));
    meta.add('document', 'revision', tag(core, 'cp:revision'));
  }
  final app = await read('docProps/app.xml');
  if (app != null) {
    meta.add('document', 'application', tag(app, 'Application'));
    meta.add('document', 'company', tag(app, 'Company'));
    meta.add('document', 'pages', tag(app, 'Pages'));
    meta.add('document', 'words', tag(app, 'Words'));
    meta.add('document', 'slides', tag(app, 'Slides'));
  }
}

String _xmlUnescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

// ─────────────────────────── MP4 / QuickTime ───────────────────────────

Future<void> _mp4(RandomAccessFile raf, int size, FileMetadata meta) async {
  final epoch1904 = DateTime.utc(1904);
  Future<void> walk(int start, int end, int depth) async {
    var at = start;
    var guard = 0;
    while (at + 8 <= end && guard++ < 4096) {
      final h = await _readAt(raf, at, 16);
      if (h.length < 8) return;
      var len = (h[0] << 24) | (h[1] << 16) | (h[2] << 8) | h[3];
      final type = String.fromCharCodes(h, 4, 8);
      var headerLen = 8;
      if (len == 1 && h.length >= 16) {
        len = 0;
        for (var k = 8; k < 16; k++) {
          len = len * 256 + h[k];
        }
        headerLen = 16;
      } else if (len == 0) {
        len = end - at;
      }
      if (len < headerLen || at + len > end) return;
      final body = at + headerLen;
      switch (type) {
        case 'moov' || 'trak' || 'udta' || 'mdia' when depth < 6:
          await walk(body, at + len, depth + 1);
        case 'meta' when depth < 6:
          await walk(body + 4, at + len, depth + 1); // full box: skip version/flags
        case 'ilst' when depth < 7:
          await walk(body, at + len, depth + 1);
        case 'mvhd':
          final d = await _readAt(raf, body, 32);
          if (d.isNotEmpty) {
            final v1 = d[0] == 1;
            int u32(int o) => (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3];
            int u64(int o) => u32(o) * 0x100000000 + u32(o + 4);
            final created = v1 ? u64(4) : u32(4);
            final scale = v1 ? u32(20) : u32(12);
            final duration = v1 ? u64(24) : u32(16);
            if (created > 0) meta.add('media', 'created', epoch1904.add(Duration(seconds: created)).toIso8601String());
            if (scale > 0) {
              final s = duration / scale;
              meta.add('media', 'duration', '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).round().toString().padLeft(2, '0')}');
            }
          }
        case 'tkhd':
          final d = await _readAt(raf, body, 92);
          if (d.length >= 84) {
            final off = d[0] == 1 ? 84 : 72;
            if (d.length >= off + 8) {
              final w = ((d[off] << 24) | (d[off + 1] << 16) | (d[off + 2] << 8) | d[off + 3]) >> 16;
              final hh = ((d[off + 4] << 24) | (d[off + 5] << 16) | (d[off + 6] << 8) | d[off + 7]) >> 16;
              if (w > 0 && hh > 0) meta.add('media', 'videoSize', '$w × $hh');
            }
          }
        case '©xyz':
          // ISO 6709 location, e.g. "+30.0444+031.2357/"
          final d = await _readAt(raf, body, (len - headerLen).clamp(0, 64));
          final s = latin1.decode(d.length > 4 ? Uint8List.sublistView(d, 4) : d, allowInvalid: true);
          final m = RegExp(r'([+-]\d+(?:\.\d+)?)([+-]\d+(?:\.\d+)?)').firstMatch(s);
          if (m != null) {
            final la = double.tryParse(m.group(1)!), lo = double.tryParse(m.group(2)!);
            if (la != null && lo != null && la.abs() <= 90 && lo.abs() <= 180) {
              meta.latitude = la;
              meta.longitude = lo;
              meta.add('gps', 'coordinates', '${la.toStringAsFixed(6)}, ${lo.toStringAsFixed(6)}');
            }
          }
        case '©too':
          final d = await _readAt(raf, body, (len - headerLen).clamp(0, 128));
          meta.add('media', 'encoder', latin1.decode(d.where((c) => c >= 32 && c < 127).toList()));
        case 'ftyp':
          final d = await _readAt(raf, body, 4);
          meta.add('media', 'brand', String.fromCharCodes(d));
      }
      at += len;
    }
  }

  await walk(0, size, 0);
}

// ─────────────────────────── MP3 / ID3v2 ───────────────────────────

void _id3(Uint8List b, FileMetadata meta) {
  if (b.length < 10) return;
  final version = b[3];
  int syncsafe(int o) => (b[o] << 21) | (b[o + 1] << 14) | (b[o + 2] << 7) | b[o + 3];
  final end = (10 + syncsafe(6)).clamp(0, b.length);
  var i = 10;
  const names = {
    'TIT2': 'title',
    'TPE1': 'artist',
    'TALB': 'album',
    'TYER': 'year',
    'TDRC': 'year',
    'TCON': 'genre',
    'TENC': 'encoder',
  };
  while (i + 10 <= end) {
    final id = String.fromCharCodes(b, i, i + 4);
    if (id.codeUnits.any((c) => c < 0x30 || c > 0x5A)) break;
    final size = version == 4 ? syncsafe(i + 4) : (b[i + 4] << 24) | (b[i + 5] << 16) | (b[i + 6] << 8) | b[i + 7];
    final data = i + 10;
    if (size <= 0 || data + size > end) break;
    final key = names[id];
    if (key != null && size > 1) {
      final enc = b[data];
      final raw = Uint8List.sublistView(b, data + 1, data + size);
      String text;
      if (enc == 1 || enc == 2) {
        final units = <int>[];
        var k = 0;
        var bigEndian = enc == 2;
        if (enc == 1 && raw.length >= 2) {
          bigEndian = raw[0] == 0xFE;
          k = 2;
        }
        for (; k + 1 < raw.length; k += 2) {
          units.add(bigEndian ? (raw[k] << 8) | raw[k + 1] : raw[k] | (raw[k + 1] << 8));
        }
        text = String.fromCharCodes(units);
      } else if (enc == 3) {
        text = utf8.decode(raw, allowMalformed: true);
      } else {
        text = latin1.decode(raw, allowInvalid: true);
      }
      meta.add('audio', key, text);
    }
    i = data + size;
  }
}
