// Signed delivery receipts — cryptographic proof of delivery.
//
// When a transfer completes, the receiver signs a receipt with its long-term
// Ed25519 identity key: who sent what to whom, every file's name, size and
// SHA-256, when, and the session transcript hash. The sender verifies the
// signature and that every hash matches what it sent. Either side can export
// the receipt; anyone can check it later with `sudosend verify receipt.json`
// without trusting SUDOSEND's servers (there are none) or either device.

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import 'identity.dart';
import 'models.dart';

const String kReceiptFormat = 'sudosend-receipt/1';
const String _signingLabel = 'WRAITH/1 receipt\n';

String hexOf(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

class ReceiptFile {
  const ReceiptFile(this.name, this.size, this.sha256Hex);
  final String name;
  final int size;
  final String sha256Hex;

  Map<String, Object> toJson() => {'name': name, 'size': size, 'sha256': sha256Hex};
}

class DeliveryReceipt {
  DeliveryReceipt({required this.body, required this.signature, required this.signerKey});

  /// The exact UTF-8 JSON text that was signed.
  final String body;
  final List<int> signature;

  /// Receiver's Ed25519 public key.
  final List<int> signerKey;

  Map<String, dynamic> get data => jsonDecode(body) as Map<String, dynamic>;
  String get signerFingerprint => fingerprintOf(signerKey);

  static Future<DeliveryReceipt> create({
    required DeviceIdentity receiver,
    required String senderFingerprint,
    required String senderName,
    required List<ReceiptFile> files,
    required List<int> transcript,
    String? text,
    DateTime? completed,
  }) async {
    final payload = <String, Object?>{
      'type': kReceiptFormat,
      'protocol': 'WRAITH/1',
      'sender': {'fingerprint': senderFingerprint, 'name': senderName},
      'receiver': {'fingerprint': receiver.fingerprint, 'name': receiver.name},
      'completed': (completed ?? DateTime.now()).toUtc().toIso8601String(),
      'session': hexOf(transcript),
      'files': [for (final f in files) f.toJson()],
      'total_bytes': files.fold<int>(0, (a, f) => a + f.size),
      if (text != null) 'text_sha256': crypto.sha256.convert(utf8.encode(text)).toString(),
    };
    final body = jsonEncode(payload);
    final sig = await Ed25519().sign(utf8.encode('$_signingLabel$body'), keyPair: receiver.keyPair);
    return DeliveryReceipt(body: body, signature: sig.bytes, signerKey: receiver.publicKey);
  }

  /// Checks the Ed25519 signature and that the signer is the named receiver.
  Future<bool> verifySignature() async {
    try {
      final ok = await Ed25519().verify(
        utf8.encode('$_signingLabel$body'),
        signature: Signature(signature, publicKey: SimplePublicKey(signerKey, type: KeyPairType.ed25519)),
      );
      if (!ok) return false;
      final receiver = data['receiver'];
      return data['type'] == kReceiptFormat &&
          receiver is Map &&
          receiver['fingerprint'] == signerFingerprint;
    } catch (_) {
      return false;
    }
  }

  /// Sender-side check: signature valid, bound to this session and these
  /// parties, and every file hash equals what was actually sent.
  Future<void> verifyFor({
    required String senderFingerprint,
    required String receiverFingerprint,
    required List<int> transcript,
    required List<ReceiptFile> sent,
    String? text,
  }) async {
    if (!await verifySignature()) throw const WraithException('Delivery receipt signature is invalid');
    final d = data;
    if ((d['sender'] as Map?)?['fingerprint'] != senderFingerprint ||
        (d['receiver'] as Map?)?['fingerprint'] != receiverFingerprint ||
        d['session'] != hexOf(transcript)) {
      throw const WraithException('Delivery receipt belongs to a different session');
    }
    final files = (d['files'] as List?) ?? const [];
    if (files.length != sent.length) throw const WraithException('Delivery receipt lists different files');
    for (var i = 0; i < sent.length; i++) {
      final f = files[i] as Map;
      if (f['size'] != sent[i].size || f['sha256'] != sent[i].sha256Hex) {
        throw WraithException('Delivery receipt hash mismatch on "${sent[i].name}"');
      }
    }
    if (text != null && d['text_sha256'] != crypto.sha256.convert(utf8.encode(text)).toString()) {
      throw const WraithException('Delivery receipt text hash mismatch');
    }
  }

  Map<String, Object?> toExport() => {
        'format': kReceiptFormat,
        'receipt': data,
        'signed_body': body,
        'signature': base64Encode(signature),
        'signer_public_key': base64Encode(signerKey),
        'signer_fingerprint': signerFingerprint,
        'verify': 'sudosend verify <this file>',
      };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toExport());

  static DeliveryReceipt fromExport(Map<String, dynamic> m) {
    if (m['format'] != kReceiptFormat) throw const WraithException('Not a SUDOSEND receipt');
    return DeliveryReceipt(
      body: m['signed_body'] as String,
      signature: base64Decode(m['signature'] as String),
      signerKey: base64Decode(m['signer_public_key'] as String),
    );
  }

  static DeliveryReceipt parse(String json) => fromExport(jsonDecode(json) as Map<String, dynamic>);
}
