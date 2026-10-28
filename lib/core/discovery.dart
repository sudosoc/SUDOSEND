import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'identity.dart';
import 'models.dart';
import 'util.dart';
import 'wraith.dart';

/// LAN discovery over UDP: multicast + limited broadcast + /24 directed
/// broadcast, so it works on most home routers, hotspots and campus Wi-Fi.
///
/// Announcements are unauthenticated by design — they are only hints.
/// The real identity is proven during the handshake, and a fingerprint
/// mismatch aborts the transfer.
class Discovery {
  Discovery({required this.identity, required this.transferPort, required this.onChanged});

  final DeviceIdentity identity;
  final int transferPort;
  final void Function() onChanged;

  static final InternetAddress group = InternetAddress('239.255.77.23');
  static final RegExp _fpPattern = RegExp(r'^[0-9A-F]{32}$');
  static const Duration _interval = Duration(seconds: 3);
  static const Duration _stale = Duration(seconds: 10);

  RawDatagramSocket? _socket;
  Timer? _announceTimer;
  Timer? _pruneTimer;
  int _ticks = 0;
  List<InternetAddress> _targets = [];
  final Map<String, Peer> _peers = {};

  List<Peer> get peers => _peers.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Future<void> start() async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      kDiscoveryPort,
      reuseAddress: true,
      reusePort: Platform.isLinux || Platform.isMacOS,
    );
    socket.broadcastEnabled = true;
    socket.multicastLoopback = false;
    try {
      socket.joinMulticast(group);
    } catch (_) {
      // Some interfaces refuse multicast; broadcast still works.
    }
    socket.listen(_onEvent);
    _socket = socket;
    await _refreshTargets();
    _announce('announce');
    _announceTimer = Timer.periodic(_interval, (_) async {
      if (++_ticks % 5 == 0) await _refreshTargets();
      _announce('announce');
    });
    _pruneTimer = Timer.periodic(const Duration(seconds: 2), (_) => _prune());
  }

  /// Ask everyone to answer right now (pull-to-refresh).
  Future<void> rescan() async {
    await _refreshTargets();
    _announce('announce');
  }

  Future<void> stop() async {
    _announce('bye');
    _announceTimer?.cancel();
    _pruneTimer?.cancel();
    _socket?.close();
    _socket = null;
  }

  Future<void> _refreshTargets() async {
    final targets = <String>{'255.255.255.255', group.address};
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
        }
      }
    } catch (_) {}
    _targets = targets.map(InternetAddress.new).toList();
  }

  List<int> _payload(String type) => utf8.encode(jsonEncode({
        'wraith': 1,
        't': type,
        'id': identity.fingerprint,
        'name': identity.name,
        'platform': platformName(),
        'port': transferPort,
      }));

  void _announce(String type) {
    final socket = _socket;
    if (socket == null) return;
    final data = _payload(type);
    for (final target in _targets) {
      try {
        socket.send(data, target, kDiscoveryPort);
      } catch (_) {}
    }
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;
    Datagram? dg;
    while ((dg = socket.receive()) != null) {
      _handle(dg!);
    }
  }

  void _handle(Datagram dg) {
    if (dg.data.length > 2048) return;
    final Map<String, dynamic> m;
    try {
      final decoded = jsonDecode(utf8.decode(dg.data));
      if (decoded is! Map<String, dynamic>) return;
      m = decoded;
    } catch (_) {
      return;
    }
    if (m['wraith'] != 1) return;
    final id = m['id'];
    final type = m['t'];
    if (id is! String || !_fpPattern.hasMatch(id) || id == identity.fingerprint) return;

    if (type == 'bye') {
      if (_peers.remove(id) != null) onChanged();
      return;
    }
    final port = m['port'];
    if (port is! int || port < 1 || port > 65535) return;
    final rawName = m['name'];
    final rawPlatform = m['platform'];
    final peer = Peer(
      id: id,
      name: sanitizeDeviceName(rawName is String ? rawName : 'Unknown device'),
      platform: rawPlatform is String && rawPlatform.length < 16 ? rawPlatform : 'unknown',
      address: dg.address,
      port: port,
      lastSeen: DateTime.now(),
    );
    final previous = _peers[id];
    _peers[id] = peer;
    final changed = previous == null ||
        previous.name != peer.name ||
        previous.address.address != peer.address.address ||
        previous.port != peer.port;
    if (changed) onChanged();

    // Answer newcomers directly so they see us immediately.
    if (type == 'announce' && previous == null) {
      try {
        _socket?.send(_payload('reply'), dg.address, kDiscoveryPort);
      } catch (_) {}
    }
  }

  void _prune() {
    final now = DateTime.now();
    final before = _peers.length;
    _peers.removeWhere((_, p) => now.difference(p.lastSeen) > _stale);
    if (_peers.length != before) onChanged();
  }
}
