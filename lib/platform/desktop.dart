import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

bool get isDesktop => Platform.isLinux || Platform.isWindows || Platform.isMacOS;
bool get hasCamera => Platform.isAndroid || Platform.isIOS;

/// Opens a file with the system's default app (desktop).
Future<bool> openWithSystem(String path) async {
  try {
    if (Platform.isLinux) {
      await Process.start('xdg-open', [path], mode: ProcessStartMode.detached);
    } else if (Platform.isWindows) {
      await Process.start('explorer', [path], mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      await Process.start('open', [path], mode: ProcessStartMode.detached);
    } else {
      return false;
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Shows a file in its folder (desktop).
Future<bool> revealInFolder(String path) async {
  try {
    if (Platform.isWindows) {
      await Process.start('explorer', ['/select,${p.normalize(path)}'], mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      await Process.start('open', ['-R', path], mode: ProcessStartMode.detached);
    } else if (Platform.isLinux) {
      final dir = FileSystemEntity.isDirectorySync(path) ? path : p.dirname(path);
      await Process.start('xdg-open', [dir], mode: ProcessStartMode.detached);
    } else {
      return false;
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Best-effort desktop notification (Linux notify-send, macOS osascript).
Future<void> desktopNotify(String title, String body) async {
  try {
    if (Platform.isLinux) {
      await Process.run('notify-send', ['-a', 'SUDOSEND', '-i', 'sudosend', title, body]);
    } else if (Platform.isMacOS) {
      String q(String s) => s.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
      await Process.run('osascript', ['-e', 'display notification "${q(body)}" with title "${q(title)}"']);
    }
  } catch (_) {}
}

/// Keeps one app instance per user on desktop. A second launch (e.g. from
/// "Send to → SUDOSEND" or "Open with") hands its file arguments to the
/// running instance over a loopback socket and exits.
class SingleInstance {
  static const int port = 47834;
  static const String _hello = 'SUDOSEND-INSTANCE/1';

  static Future<bool> handOff(List<String> args) async {
    Socket? socket;
    try {
      socket = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(milliseconds: 400));
      final greeting = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(milliseconds: 600));
      if (greeting != _hello) return false;
      final absolute = [for (final a in args) File(a).absolute.path];
      socket.writeln(jsonEncode({'args': absolute}));
      await socket.flush();
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  static Future<void> listen(void Function(List<String> args) onArgs) async {
    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      server.listen((client) {
        client.writeln(_hello);
        utf8.decoder.bind(client).transform(const LineSplitter()).first.timeout(const Duration(seconds: 3)).then(
          (line) {
            final m = jsonDecode(line) as Map<String, dynamic>;
            onArgs([for (final a in (m['args'] as List<dynamic>)) a as String]);
          },
          onError: (Object _) {},
        ).whenComplete(client.destroy);
      });
    } catch (_) {
      // Port taken by something else: run without single-instance support.
    }
  }
}
