// QR / link pairing.
//
//   sudosend://pair?v=1&n=<name>&fp=<fingerprint>&a=<ip>,<ip>&p=<port>&t=<token>
//
// The link is shown by the receiver (as a QR code) and carries:
//  * fp — the receiver's identity fingerprint. The sender aborts if the device
//         that answers proves a different key, so scanning authenticates the
//         receiver without comparing a code.
//  * t  — a one-time pairing token. The sender presents it inside the
//         encrypted session; the receiver then knows the sender is whoever saw
//         its screen, trusts it and accepts without a prompt.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'models.dart';
import 'util.dart';

final RegExp _fpPattern = RegExp(r'^[0-9A-F]{32}$');
final RegExp _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{16,64}$');

String newPairingToken() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

class PairingInfo {
  const PairingInfo({
    required this.name,
    required this.fingerprint,
    required this.addresses,
    required this.port,
    this.token,
  });

  final String name;
  final String fingerprint;
  final List<InternetAddress> addresses;
  final int port;
  final String? token;

  String toUri() => Uri(
        scheme: 'sudosend',
        host: 'pair',
        queryParameters: {
          'v': '1',
          'n': name,
          'fp': fingerprint,
          'a': addresses.map((a) => a.address).join(','),
          'p': '$port',
          if (token != null) 't': token!,
        },
      ).toString();

  static PairingInfo? tryParse(String input) {
    final Uri uri;
    try {
      uri = Uri.parse(input.trim());
    } catch (_) {
      return null;
    }
    if (uri.scheme != 'sudosend' || uri.host != 'pair') return null;
    final q = uri.queryParameters;
    if (q['v'] != '1') return null;
    final fp = (q['fp'] ?? '').toUpperCase();
    if (!_fpPattern.hasMatch(fp)) return null;
    final port = int.tryParse(q['p'] ?? '');
    if (port == null || port < 1 || port > 65535) return null;
    final addresses = <InternetAddress>[];
    for (final raw in (q['a'] ?? '').split(',')) {
      final a = InternetAddress.tryParse(raw.trim());
      if (a != null && a.type == InternetAddressType.IPv4 && !addresses.any((x) => x.address == a.address)) {
        addresses.add(a);
      }
      if (addresses.length >= 8) break;
    }
    if (addresses.isEmpty) return null;
    final token = q['t'];
    return PairingInfo(
      name: sanitizeDeviceName(q['n'] ?? 'Device'),
      fingerprint: fp,
      addresses: addresses,
      port: port,
      token: token != null && _tokenPattern.hasMatch(token) ? token : null,
    );
  }

  Peer toPeer() => Peer(
        id: fingerprint,
        name: name,
        platform: 'unknown',
        address: addresses.first,
        alternates: addresses.skip(1).toList(),
        port: port,
        lastSeen: DateTime.now(),
      );
}
