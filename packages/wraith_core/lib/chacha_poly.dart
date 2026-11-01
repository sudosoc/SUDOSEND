// Fast pure-Dart ChaCha20-Poly1305 AEAD (RFC 8439).
//
// package:cryptography's pure-Dart cipher is a general implementation; this
// one is specialised for throughput: an unrolled 20-round block function on
// local integers, 32-bit word XOR, and Poly1305 with 26-bit limbs (the
// "donna-32" layout, which fits in Dart's 64-bit integers). Output is
// byte-for-byte identical to any RFC 8439 implementation — the tests check it
// against package:cryptography and the RFC test vectors.

import 'dart:typed_data';

class ChaCha20Poly1305 {
  ChaCha20Poly1305._();

  static int _le32(Uint8List b, int i) => b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);

  static Uint32List _state(Uint8List key, Uint8List nonce) {
    if (key.length != 32) throw ArgumentError('key must be 32 bytes');
    if (nonce.length != 12) throw ArgumentError('nonce must be 12 bytes');
    final s = Uint32List(16);
    s[0] = 0x61707865;
    s[1] = 0x3320646e;
    s[2] = 0x79622d32;
    s[3] = 0x6b206574;
    for (var i = 0; i < 8; i++) {
      s[4 + i] = _le32(key, i * 4);
    }
    s[13] = _le32(nonce, 0);
    s[14] = _le32(nonce, 4);
    s[15] = _le32(nonce, 8);
    return s;
  }

  /// One ChaCha20 block of [s] into [o] (both 16 words).
  static void _block(Uint32List s, Uint32List o) {
    var x0 = s[0];
    var x1 = s[1];
    var x2 = s[2];
    var x3 = s[3];
    var x4 = s[4];
    var x5 = s[5];
    var x6 = s[6];
    var x7 = s[7];
    var x8 = s[8];
    var x9 = s[9];
    var x10 = s[10];
    var x11 = s[11];
    var x12 = s[12];
    var x13 = s[13];
    var x14 = s[14];
    var x15 = s[15];
    for (var i = 0; i < 10; i++) {
      x0 = (x0 + x4) & 0xFFFFFFFF;
      x12 ^= x0;
      x12 = ((x12 << 16) & 0xFFFFFFFF) | (x12 >> 16);
      x8 = (x8 + x12) & 0xFFFFFFFF;
      x4 ^= x8;
      x4 = ((x4 << 12) & 0xFFFFFFFF) | (x4 >> 20);
      x0 = (x0 + x4) & 0xFFFFFFFF;
      x12 ^= x0;
      x12 = ((x12 << 8) & 0xFFFFFFFF) | (x12 >> 24);
      x8 = (x8 + x12) & 0xFFFFFFFF;
      x4 ^= x8;
      x4 = ((x4 << 7) & 0xFFFFFFFF) | (x4 >> 25);
      x1 = (x1 + x5) & 0xFFFFFFFF;
      x13 ^= x1;
      x13 = ((x13 << 16) & 0xFFFFFFFF) | (x13 >> 16);
      x9 = (x9 + x13) & 0xFFFFFFFF;
      x5 ^= x9;
      x5 = ((x5 << 12) & 0xFFFFFFFF) | (x5 >> 20);
      x1 = (x1 + x5) & 0xFFFFFFFF;
      x13 ^= x1;
      x13 = ((x13 << 8) & 0xFFFFFFFF) | (x13 >> 24);
      x9 = (x9 + x13) & 0xFFFFFFFF;
      x5 ^= x9;
      x5 = ((x5 << 7) & 0xFFFFFFFF) | (x5 >> 25);
      x2 = (x2 + x6) & 0xFFFFFFFF;
      x14 ^= x2;
      x14 = ((x14 << 16) & 0xFFFFFFFF) | (x14 >> 16);
      x10 = (x10 + x14) & 0xFFFFFFFF;
      x6 ^= x10;
      x6 = ((x6 << 12) & 0xFFFFFFFF) | (x6 >> 20);
      x2 = (x2 + x6) & 0xFFFFFFFF;
      x14 ^= x2;
      x14 = ((x14 << 8) & 0xFFFFFFFF) | (x14 >> 24);
      x10 = (x10 + x14) & 0xFFFFFFFF;
      x6 ^= x10;
      x6 = ((x6 << 7) & 0xFFFFFFFF) | (x6 >> 25);
      x3 = (x3 + x7) & 0xFFFFFFFF;
      x15 ^= x3;
      x15 = ((x15 << 16) & 0xFFFFFFFF) | (x15 >> 16);
      x11 = (x11 + x15) & 0xFFFFFFFF;
      x7 ^= x11;
      x7 = ((x7 << 12) & 0xFFFFFFFF) | (x7 >> 20);
      x3 = (x3 + x7) & 0xFFFFFFFF;
      x15 ^= x3;
      x15 = ((x15 << 8) & 0xFFFFFFFF) | (x15 >> 24);
      x11 = (x11 + x15) & 0xFFFFFFFF;
      x7 ^= x11;
      x7 = ((x7 << 7) & 0xFFFFFFFF) | (x7 >> 25);
      x0 = (x0 + x5) & 0xFFFFFFFF;
      x15 ^= x0;
      x15 = ((x15 << 16) & 0xFFFFFFFF) | (x15 >> 16);
      x10 = (x10 + x15) & 0xFFFFFFFF;
      x5 ^= x10;
      x5 = ((x5 << 12) & 0xFFFFFFFF) | (x5 >> 20);
      x0 = (x0 + x5) & 0xFFFFFFFF;
      x15 ^= x0;
      x15 = ((x15 << 8) & 0xFFFFFFFF) | (x15 >> 24);
      x10 = (x10 + x15) & 0xFFFFFFFF;
      x5 ^= x10;
      x5 = ((x5 << 7) & 0xFFFFFFFF) | (x5 >> 25);
      x1 = (x1 + x6) & 0xFFFFFFFF;
      x12 ^= x1;
      x12 = ((x12 << 16) & 0xFFFFFFFF) | (x12 >> 16);
      x11 = (x11 + x12) & 0xFFFFFFFF;
      x6 ^= x11;
      x6 = ((x6 << 12) & 0xFFFFFFFF) | (x6 >> 20);
      x1 = (x1 + x6) & 0xFFFFFFFF;
      x12 ^= x1;
      x12 = ((x12 << 8) & 0xFFFFFFFF) | (x12 >> 24);
      x11 = (x11 + x12) & 0xFFFFFFFF;
      x6 ^= x11;
      x6 = ((x6 << 7) & 0xFFFFFFFF) | (x6 >> 25);
      x2 = (x2 + x7) & 0xFFFFFFFF;
      x13 ^= x2;
      x13 = ((x13 << 16) & 0xFFFFFFFF) | (x13 >> 16);
      x8 = (x8 + x13) & 0xFFFFFFFF;
      x7 ^= x8;
      x7 = ((x7 << 12) & 0xFFFFFFFF) | (x7 >> 20);
      x2 = (x2 + x7) & 0xFFFFFFFF;
      x13 ^= x2;
      x13 = ((x13 << 8) & 0xFFFFFFFF) | (x13 >> 24);
      x8 = (x8 + x13) & 0xFFFFFFFF;
      x7 ^= x8;
      x7 = ((x7 << 7) & 0xFFFFFFFF) | (x7 >> 25);
      x3 = (x3 + x4) & 0xFFFFFFFF;
      x14 ^= x3;
      x14 = ((x14 << 16) & 0xFFFFFFFF) | (x14 >> 16);
      x9 = (x9 + x14) & 0xFFFFFFFF;
      x4 ^= x9;
      x4 = ((x4 << 12) & 0xFFFFFFFF) | (x4 >> 20);
      x3 = (x3 + x4) & 0xFFFFFFFF;
      x14 ^= x3;
      x14 = ((x14 << 8) & 0xFFFFFFFF) | (x14 >> 24);
      x9 = (x9 + x14) & 0xFFFFFFFF;
      x4 ^= x9;
      x4 = ((x4 << 7) & 0xFFFFFFFF) | (x4 >> 25);
    }
    o[0] = (x0 + s[0]) & 0xFFFFFFFF;
    o[1] = (x1 + s[1]) & 0xFFFFFFFF;
    o[2] = (x2 + s[2]) & 0xFFFFFFFF;
    o[3] = (x3 + s[3]) & 0xFFFFFFFF;
    o[4] = (x4 + s[4]) & 0xFFFFFFFF;
    o[5] = (x5 + s[5]) & 0xFFFFFFFF;
    o[6] = (x6 + s[6]) & 0xFFFFFFFF;
    o[7] = (x7 + s[7]) & 0xFFFFFFFF;
    o[8] = (x8 + s[8]) & 0xFFFFFFFF;
    o[9] = (x9 + s[9]) & 0xFFFFFFFF;
    o[10] = (x10 + s[10]) & 0xFFFFFFFF;
    o[11] = (x11 + s[11]) & 0xFFFFFFFF;
    o[12] = (x12 + s[12]) & 0xFFFFFFFF;
    o[13] = (x13 + s[13]) & 0xFFFFFFFF;
    o[14] = (x14 + s[14]) & 0xFFFFFFFF;
    o[15] = (x15 + s[15]) & 0xFFFFFFFF;
  }


  static final bool _littleEndian = Endian.host == Endian.little;

  /// XORs [length] bytes of [input] with the keystream starting at block [counter].
  static void _xor(Uint32List state, int counter, Uint8List input, Uint8List output, int length) {
    final ks = Uint32List(16);
    final blocks = length >> 6;
    if (_littleEndian) {
      final src = (input.offsetInBytes & 3) == 0 ? input : Uint8List.fromList(input);
      final in32 = src.buffer.asUint32List(src.offsetInBytes, blocks * 16);
      final out32 = output.buffer.asUint32List(output.offsetInBytes, blocks * 16);
      for (var b = 0; b < blocks; b++) {
        state[12] = (counter + b) & 0xFFFFFFFF;
        _block(state, ks);
        final base = b << 4;
        for (var j = 0; j < 16; j++) {
          out32[base + j] = in32[base + j] ^ ks[j];
        }
      }
      input = src;
    } else {
      for (var b = 0; b < blocks; b++) {
        state[12] = (counter + b) & 0xFFFFFFFF;
        _block(state, ks);
        final base = b << 6;
        for (var j = 0; j < 64; j++) {
          final w = ks[j >> 2] >> ((j & 3) * 8);
          output[base + j] = input[base + j] ^ (w & 0xFF);
        }
      }
    }
    final done = blocks << 6;
    final rem = length - done;
    if (rem > 0) {
      state[12] = (counter + blocks) & 0xFFFFFFFF;
      _block(state, ks);
      for (var j = 0; j < rem; j++) {
        final w = ks[j >> 2] >> ((j & 3) * 8);
        output[done + j] = input[done + j] ^ (w & 0xFF);
      }
    }
  }

  static Uint8List _polyKey(Uint32List state) {
    final ks = Uint32List(16);
    state[12] = 0;
    _block(state, ks);
    final key = Uint8List(32);
    for (var j = 0; j < 32; j++) {
      key[j] = (ks[j >> 2] >> ((j & 3) * 8)) & 0xFF;
    }
    return key;
  }

  static Uint8List _tag(Uint8List polyKey, Uint8List? aad, Uint8List ct) {
    final mac = _Poly1305(polyKey);
    final aadLength = aad?.length ?? 0;
    if (aad != null && aad.isNotEmpty) mac.padded(aad);
    mac.padded(ct);
    final lengths = Uint8List(16);
    final bd = ByteData.sublistView(lengths);
    bd.setUint32(0, aadLength & 0xFFFFFFFF, Endian.little);
    bd.setUint32(4, (aadLength >> 32) & 0xFFFFFFFF, Endian.little);
    bd.setUint32(8, ct.length & 0xFFFFFFFF, Endian.little);
    bd.setUint32(12, (ct.length >> 32) & 0xFFFFFFFF, Endian.little);
    mac.block(lengths, 0);
    return mac.finish();
  }

  /// Returns `ciphertext ‖ 16-byte tag`.
  static Uint8List seal(Uint8List key, Uint8List nonce, Uint8List plaintext, {Uint8List? aad}) {
    final n = plaintext.length;
    final out = Uint8List(n + 16);
    final state = _state(key, nonce);
    final polyKey = _polyKey(state);
    _xor(state, 1, plaintext, out, n);
    out.setRange(n, n + 16, _tag(polyKey, aad, Uint8List.sublistView(out, 0, n)));
    return out;
  }

  /// Opens `ciphertext ‖ tag`; returns null if authentication fails.
  static Uint8List? open(Uint8List key, Uint8List nonce, Uint8List sealed, {Uint8List? aad}) {
    if (sealed.length < 16) return null;
    final n = sealed.length - 16;
    final ct = Uint8List.sublistView(sealed, 0, n);
    final state = _state(key, nonce);
    final tag = _tag(_polyKey(state), aad, ct);
    var diff = 0;
    for (var i = 0; i < 16; i++) {
      diff |= tag[i] ^ sealed[n + i];
    }
    if (diff != 0) return null;
    final out = Uint8List(n);
    _xor(state, 1, ct, out, n);
    return out;
  }
}

/// Poly1305 with five 26-bit limbs.
class _Poly1305 {
  _Poly1305(Uint8List key)
      : r0 = _le(key, 0) & 0x3ffffff,
        r1 = (_le(key, 3) >> 2) & 0x3ffff03,
        r2 = (_le(key, 6) >> 4) & 0x3ffc0ff,
        r3 = (_le(key, 9) >> 6) & 0x3f03fff,
        r4 = (_le(key, 12) >> 8) & 0x00fffff,
        pad0 = _le(key, 16),
        pad1 = _le(key, 20),
        pad2 = _le(key, 24),
        pad3 = _le(key, 28);

  static int _le(Uint8List b, int i) => b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);

  final int r0, r1, r2, r3, r4;
  final int pad0, pad1, pad2, pad3;
  int h0 = 0, h1 = 0, h2 = 0, h3 = 0, h4 = 0;

  /// Absorbs one full 16-byte block at [o].
  void block(Uint8List m, int o) {
    const mask = 0x3ffffff;
    final s1 = r1 * 5, s2 = r2 * 5, s3 = r3 * 5, s4 = r4 * 5;
    var a0 = h0 + (_le(m, o) & mask);
    var a1 = h1 + ((_le(m, o + 3) >> 2) & mask);
    var a2 = h2 + ((_le(m, o + 6) >> 4) & mask);
    var a3 = h3 + ((_le(m, o + 9) >> 6) & mask);
    var a4 = h4 + ((_le(m, o + 12) >> 8) | (1 << 24));

    var d0 = a0 * r0 + a1 * s4 + a2 * s3 + a3 * s2 + a4 * s1;
    var d1 = a0 * r1 + a1 * r0 + a2 * s4 + a3 * s3 + a4 * s2;
    var d2 = a0 * r2 + a1 * r1 + a2 * r0 + a3 * s4 + a4 * s3;
    var d3 = a0 * r3 + a1 * r2 + a2 * r1 + a3 * r0 + a4 * s4;
    var d4 = a0 * r4 + a1 * r3 + a2 * r2 + a3 * r1 + a4 * r0;

    var c = d0 >> 26;
    a0 = d0 & mask;
    d1 += c;
    c = d1 >> 26;
    a1 = d1 & mask;
    d2 += c;
    c = d2 >> 26;
    a2 = d2 & mask;
    d3 += c;
    c = d3 >> 26;
    a3 = d3 & mask;
    d4 += c;
    c = d4 >> 26;
    a4 = d4 & mask;
    a0 += c * 5;
    c = a0 >> 26;
    a0 &= mask;
    a1 += c;
    h0 = a0;
    h1 = a1;
    h2 = a2;
    h3 = a3;
    h4 = a4;
  }

  /// Absorbs [data] zero-padded to a multiple of 16 bytes (RFC 8439 AEAD).
  void padded(Uint8List data) {
    final full = data.length & ~15;
    for (var o = 0; o < full; o += 16) {
      block(data, o);
    }
    if (full < data.length) {
      final last = Uint8List(16)..setRange(0, data.length - full, data, full);
      block(last, 0);
    }
  }

  Uint8List finish() {
    const mask = 0x3ffffff;
    var c = h1 >> 26;
    h1 &= mask;
    h2 += c;
    c = h2 >> 26;
    h2 &= mask;
    h3 += c;
    c = h3 >> 26;
    h3 &= mask;
    h4 += c;
    c = h4 >> 26;
    h4 &= mask;
    h0 += c * 5;
    c = h0 >> 26;
    h0 &= mask;
    h1 += c;

    // Compute h - p and keep it if it is not negative.
    var g0 = h0 + 5;
    c = g0 >> 26;
    g0 &= mask;
    var g1 = h1 + c;
    c = g1 >> 26;
    g1 &= mask;
    var g2 = h2 + c;
    c = g2 >> 26;
    g2 &= mask;
    var g3 = h3 + c;
    c = g3 >> 26;
    g3 &= mask;
    final g4 = h4 + c - (1 << 26);
    // sel = all ones if g4 >= 0 (use g), zero otherwise (keep h).
    final sel = ~(g4 >> 63);
    h0 = (h0 & ~sel) | (g0 & sel);
    h1 = (h1 & ~sel) | (g1 & sel);
    h2 = (h2 & ~sel) | (g2 & sel);
    h3 = (h3 & ~sel) | (g3 & sel);
    h4 = (h4 & ~sel) | ((g4 & mask) & sel);

    final w0 = (h0 | (h1 << 26)) & 0xFFFFFFFF;
    final w1 = ((h1 >> 6) | (h2 << 20)) & 0xFFFFFFFF;
    final w2 = ((h2 >> 12) | (h3 << 14)) & 0xFFFFFFFF;
    final w3 = ((h3 >> 18) | (h4 << 8)) & 0xFFFFFFFF;

    var f = w0 + pad0;
    final t0 = f & 0xFFFFFFFF;
    f = w1 + pad1 + (f >> 32);
    final t1 = f & 0xFFFFFFFF;
    f = w2 + pad2 + (f >> 32);
    final t2 = f & 0xFFFFFFFF;
    f = w3 + pad3 + (f >> 32);
    final t3 = f & 0xFFFFFFFF;

    final out = Uint8List(16);
    final bd = ByteData.sublistView(out);
    bd.setUint32(0, t0, Endian.little);
    bd.setUint32(4, t1, Endian.little);
    bd.setUint32(8, t2, Endian.little);
    bd.setUint32(12, t3, Endian.little);
    return out;
  }
}
