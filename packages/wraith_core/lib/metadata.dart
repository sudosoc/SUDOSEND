// Photo metadata scrubbing before sending.
//
// JPEG
//   location: empties the EXIF GPS directory in place (entries and values are
//             zeroed, the directory count set to 0) and drops XMP / IPTC,
//             which can carry location too. Date, camera and orientation stay.
//   all:      drops every APP1 (EXIF, XMP), APP13 (IPTC), comments and other
//             application segments, then writes a tiny new EXIF block that
//             holds only the orientation, so photos are not shown sideways.
//             JFIF (APP0), the ICC colour profile (APP2) and Adobe (APP14)
//             are kept: they describe how to show the image, not who took it.
// PNG
//   drops eXIf and iTXt (XMP) chunks; "all" also drops tEXt, zTXt and tIME.
//
// The image data itself is never touched: only header segments change.
// Anything that does not parse cleanly is left exactly as it was.

import 'dart:typed_data';

enum MetadataMode { off, location, all }

MetadataMode metadataModeFrom(String? s) => switch (s) {
      'off' => MetadataMode.off,
      'all' => MetadataMode.all,
      _ => MetadataMode.location,
    };

bool canScrub(String name) {
  final n = name.toLowerCase();
  return n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.jfif') || n.endsWith('.png');
}

/// Returns cleaned bytes, or null when nothing needed to change (or the file
/// is not a JPEG/PNG this code understands).
Uint8List? scrubMetadata(Uint8List bytes, MetadataMode mode) {
  if (mode == MetadataMode.off) return null;
  if (bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8) return _jpeg(bytes, mode == MetadataMode.all);
  if (bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
    return _png(bytes, mode == MetadataMode.all);
  }
  return null;
}

// ─────────────────────────── JPEG ───────────────────────────

const _exifHeader = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]; // "Exif\0\0"

bool _startsWith(Uint8List d, int at, List<int> prefix) {
  if (at + prefix.length > d.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (d[at + i] != prefix[i]) return false;
  }
  return true;
}

Uint8List? _jpeg(Uint8List b, bool all) {
  final segments = <Uint8List>[];
  var changed = false;
  int? orientation;
  var insertAt = 0; // index in [segments] for a new EXIF block (after APP0)
  var i = 2;
  Uint8List? tail;
  while (i < b.length) {
    if (b[i] != 0xFF) return null; // not where a marker should be: leave the file alone
    if (i + 1 >= b.length) return null;
    final marker = b[i + 1];
    if (marker == 0xFF) {
      i++; // fill byte
      continue;
    }
    if (marker == 0xDA || marker == 0xD9) {
      tail = Uint8List.sublistView(b, i); // scan data and the rest: copied verbatim
      break;
    }
    if ((marker >= 0xD0 && marker <= 0xD7) || marker == 0x01) {
      segments.add(Uint8List.sublistView(b, i, i + 2));
      i += 2;
      continue;
    }
    if (i + 4 > b.length) return null;
    final len = (b[i + 2] << 8) | b[i + 3];
    if (len < 2 || i + 2 + len > b.length) return null;
    final seg = Uint8List.sublistView(b, i, i + 2 + len);
    final payloadAt = i + 4;
    var keep = true;
    if (marker == 0xE1) {
      if (_startsWith(b, payloadAt, _exifHeader)) {
        final tiff = Uint8List.fromList(Uint8List.sublistView(b, payloadAt + 6, i + 2 + len));
        if (all) {
          orientation ??= _Tiff.parse(tiff)?.orientation();
          keep = false;
        } else {
          final t = _Tiff.parse(tiff);
          if (t != null && t.scrubGps()) {
            final copy = Uint8List.fromList(seg);
            copy.setRange(10, 10 + tiff.length, tiff);
            segments.add(copy);
            changed = true;
            i += 2 + len;
            continue;
          }
        }
      } else {
        keep = false; // XMP and other APP1 payloads
      }
    } else if (marker == 0xED) {
      keep = false; // IPTC / Photoshop
    } else if (all && (marker == 0xFE || (marker >= 0xE3 && marker <= 0xEF && marker != 0xEE))) {
      keep = false; // comments, maker/vendor blocks
    }
    if (keep) {
      segments.add(seg);
      if (marker == 0xE0 && segments.length == 1) insertAt = 1;
    } else {
      changed = true;
    }
    i += 2 + len;
  }
  if (tail == null) return null; // no image data found
  if (all && orientation != null && orientation >= 2 && orientation <= 8) {
    segments.insert(insertAt, _orientationExif(orientation));
  }
  if (!changed) return null;
  final out = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
  for (final s in segments) {
    out.add(s);
  }
  out.add(tail);
  return out.takeBytes();
}

/// APP1 segment with a minimal big-endian EXIF holding only Orientation.
Uint8List _orientationExif(int orientation) {
  final d = BytesBuilder();
  const payloadLen = 6 + 8 + 2 + 12 + 4;
  d.add([0xFF, 0xE1, ((payloadLen + 2) >> 8) & 0xFF, (payloadLen + 2) & 0xFF]);
  d.add(_exifHeader);
  d.add([0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08]); // "MM", 42, IFD0 at 8
  d.add([0x00, 0x01]); // one entry
  d.add([0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, orientation, 0x00, 0x00]);
  d.add([0x00, 0x00, 0x00, 0x00]); // no next IFD
  return d.takeBytes();
}

class _Tiff {
  _Tiff(this.d, this.le, this.ifd0);
  final Uint8List d;
  final bool le;
  final int ifd0;

  static _Tiff? parse(Uint8List d) {
    if (d.length < 8) return null;
    final bool le;
    if (d[0] == 0x49 && d[1] == 0x49) {
      le = true;
    } else if (d[0] == 0x4D && d[1] == 0x4D) {
      le = false;
    } else {
      return null;
    }
    final t = _Tiff(d, le, 0);
    if (t.u16(2) != 42) return null;
    final ifd0 = t.u32(4);
    if (ifd0 < 8 || ifd0 + 2 > d.length) return null;
    return _Tiff(d, le, ifd0);
  }

  int u16(int o) => le ? d[o] | (d[o + 1] << 8) : (d[o] << 8) | d[o + 1];
  int u32(int o) => le
      ? d[o] | (d[o + 1] << 8) | (d[o + 2] << 16) | (d[o + 3] << 24)
      : (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3];

  void zero(int from, int to) {
    for (var k = from; k < to && k < d.length; k++) {
      d[k] = 0;
    }
  }

  /// Offsets of the 12-byte entries of the directory at [ifd], bounds-checked.
  Iterable<int> entries(int ifd) sync* {
    if (ifd + 2 > d.length) return;
    final n = u16(ifd);
    for (var k = 0; k < n; k++) {
      final e = ifd + 2 + 12 * k;
      if (e + 12 > d.length) return;
      yield e;
    }
  }

  int? orientation() {
    for (final e in entries(ifd0)) {
      if (u16(e) == 0x0112) return u16(e + 8);
    }
    return null;
  }

  static int _typeSize(int type) => switch (type) {
        3 || 8 => 2,
        4 || 9 || 11 => 4,
        5 || 10 || 12 => 8,
        _ => 1,
      };

  /// Empties the GPS directory. Returns true if there was one.
  bool scrubGps() {
    for (final e in entries(ifd0)) {
      if (u16(e) != 0x8825) continue;
      final gps = u32(e + 8);
      if (gps < 8 || gps + 2 > d.length) return false;
      for (final g in entries(gps).toList()) {
        final size = _typeSize(u16(g + 2)) * u32(g + 4);
        if (size > 4) {
          final at = u32(g + 8);
          if (at >= 8 && at < d.length) zero(at, at + size);
        }
        zero(g, g + 12);
      }
      zero(gps, gps + 2); // directory count = 0, and the next-IFD link right after reads 0
      return true;
    }
    return false;
  }
}

// ─────────────────────────── PNG ───────────────────────────

Uint8List? _png(Uint8List b, bool all) {
  final out = BytesBuilder(copy: false)..add(Uint8List.sublistView(b, 0, 8));
  var changed = false;
  var i = 8;
  while (i + 12 <= b.length) {
    final len = (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
    final end = i + 12 + len;
    if (len < 0 || end > b.length) return null;
    final type = String.fromCharCodes(b, i + 4, i + 8);
    final drop = type == 'eXIf' || type == 'iTXt' || (all && (type == 'tEXt' || type == 'zTXt' || type == 'tIME'));
    if (drop) {
      changed = true;
    } else {
      out.add(Uint8List.sublistView(b, i, end));
    }
    i = end;
    if (type == 'IEND') break;
  }
  if (i < b.length) out.add(Uint8List.sublistView(b, i));
  return changed ? out.takeBytes() : null;
}
