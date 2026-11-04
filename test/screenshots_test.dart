// Renders the real screens with demo data to PNG files (used for the README).
// Skipped unless SHOTS_DIR is set:
//   SHOTS_DIR=docs/screenshots flutter test test/screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sudosend/app/scope.dart';
import 'package:sudosend/state/app_controller.dart';
import 'package:sudosend/state/audit.dart';
import 'package:sudosend/state/chat.dart';
import 'package:sudosend/state/devices.dart';
import 'package:sudosend/state/history.dart';
import 'package:sudosend/state/library.dart';
import 'package:sudosend/state/outbox.dart';
import 'package:sudosend/state/trash.dart';
import 'package:sudosend/ui/chat_page.dart';
import 'package:sudosend/ui/dashboard_page.dart';
import 'package:sudosend/ui/device_page.dart';
import 'package:sudosend/ui/devices_page.dart';
import 'package:sudosend/ui/home.dart';
import 'package:sudosend/ui/settings_page.dart';
import 'package:sudosend/ui/storage_map_page.dart';
import 'package:sudosend/ui/theme.dart';
import 'package:wraith_core/identity.dart';
import 'package:wraith_core/journal.dart';
import 'package:wraith_core/models.dart';
import 'package:wraith_core/pairing.dart';

final String? _out = Platform.environment['SHOTS_DIR'];
final String _flutter = Platform.environment['FLUTTER_ROOT'] ?? '/tmp/fl';

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(
        ByteData.view(Uint8List.fromList(File(f).readAsBytesSync()).buffer)));
  }
  await loader.load();
}

Future<AppController> _demo(Directory dir, {String lang = 'en'}) async {
  final c = AppController();
  await c.settings.load(dir);
  c.settings.language = lang;
  c.identity = await DeviceIdentity.loadOrCreate(dir);
  await c.identity.rename('Seif-Phone');
  c.trust = await TrustStore.load(dir);
  c.history = await HistoryStore.load(dir);
  c.chat = await ChatStore.load(dir);
  c.library = await LibraryStore.load(dir);
  c.devices = await DeviceRegistry.load(dir);
  c.audit = await AuditLog.load(dir);
  c.journal = Journal(File(p.join(dir.path, 'journal.jsonl')));
  c.trash = await TrashStore.load(dir, c.journal);
  c.outbox = await OutboxStore.load(dir);
  c.saveDir = dir;
  c.localAddresses = [InternetAddress('192.168.1.23')];
  final laptop = 'A' * 32, tab = 'B' * 32, pc = 'C' * 32, pi = 'D' * 32;
  c.demoPeers = [
    Peer(
        id: laptop,
        name: 'Work-Laptop',
        platform: 'windows',
        address: InternetAddress('192.168.1.40'),
        port: 47824,
        lastSeen: DateTime.now()),
    Peer(
        id: tab,
        name: 'Galaxy Tab S9',
        platform: 'android',
        address: InternetAddress('192.168.1.51'),
        port: 47824,
        lastSeen: DateTime.now()),
    Peer(
        id: pc,
        name: 'Studio-Mac',
        platform: 'macos',
        address: InternetAddress('192.168.1.60'),
        port: 47824,
        lastSeen: DateTime.now()),
    Peer(
        id: pi,
        name: 'raspberrypi',
        platform: 'linux',
        address: InternetAddress('192.168.1.77'),
        port: 47824,
        lastSeen: DateTime.now()),
  ];
  await c.trust.add(laptop, 'Work-Laptop');
  await c.trust.add(tab, 'Galaxy Tab S9');
  c.demoPairing = PairingInfo(
    name: 'Seif-Phone',
    fingerprint: c.identity.fingerprint,
    addresses: c.localAddresses,
    port: 47824,
    token: 'demo-token-1234',
  );
  final now = DateTime.now();
  Future<void> h(TransferDirection d, String peer, String plat, int n,
          int bytes, String first, int minsAgo) =>
      c.history.add(HistoryEntry(
        id: '${d.name}$minsAgo',
        direction: d,
        peerName: peer,
        peerPlatform: plat,
        fileCount: n,
        totalBytes: bytes,
        status: TransferStatus.done,
        isText: false,
        at: now.subtract(Duration(minutes: minsAgo)),
        firstName: first,
        transferMs: 2400,
        peakSpeed: 38e6,
      ));
  await h(TransferDirection.incoming, 'Work-Laptop', 'windows', 3,
      48 * 1024 * 1024, 'Q4-report.pdf', 4);
  await h(TransferDirection.outgoing, 'Galaxy Tab S9', 'android', 12,
      312 * 1024 * 1024, 'IMG_2041.jpg', 35);
  await h(TransferDirection.incoming, 'Studio-Mac', 'macos', 1,
      1800 * 1024 * 1024, 'demo-reel.mov', 190);
  for (final (name, who, size, mins) in [
    ('Q4-report.pdf', 'Work-Laptop', 4 * 1024 * 1024, 4),
    ('invoice-1042.pdf', 'Work-Laptop', 220 * 1024, 4),
    ('IMG_2041.jpg', 'Galaxy Tab S9', 3 * 1024 * 1024, 30),
    ('demo-reel.mov', 'Studio-Mac', 1800 * 1024 * 1024, 190),
    ('podcast-ep12.mp3', 'Studio-Mac', 42 * 1024 * 1024, 700),
    ('backup.zip', 'raspberrypi', 220 * 1024 * 1024, 2000),
    ('notes.txt', 'Work-Laptop', 12 * 1024, 3000),
  ]) {
    final file = File(p.join(dir.path, 'inbox', name))
      ..createSync(recursive: true)
      ..writeAsStringSync('demo');
    c.library.add(LibraryItem(
      path: file.path,
      name: name,
      size: size,
      sha256: name.hashCode.toRadixString(16).padLeft(64, '0'),
      receivedAt: now.subtract(Duration(minutes: mins)),
      device: who,
    ));
  }
  c.chat
      .add(laptop, 'Work-Laptop', 'Sent you the Q4 report 👆', outgoing: false);
  c.chat.add(laptop, 'Work-Laptop', 'Got it, thanks!', outgoing: true).state =
      ChatState.sent;
  c.chat.add(tab, 'Galaxy Tab S9', 'Where did you put the photos?',
      outgoing: false, unread: true);
  c.ready = true;
  return c;
}

Future<void> _shot(WidgetTester t, GlobalKey key, String name) async {
  await t.pump(const Duration(milliseconds: 400));
  await t.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    File(p.join(_out!, '$name.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

void main() {
  final enabled = _out != null;
  testWidgets('screenshots', skip: !enabled, (t) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _font('IBMPlexSans', [
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold'])
        'assets/fonts/IBMPlexSans-$w.ttf',
    ]);
    await _font('IBMPlexMono', ['assets/fonts/IBMPlexMono-Regular.ttf']);
    await _font('IBMPlexSansArabic', [
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold'])
        'assets/fonts/IBMPlexSansArabic-$w.ttf',
    ]);
    await _font('MaterialIcons', [
      '$_flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
    ]);
    Future<void> run(String prefix, Size viewSize, String lang) async {
      final c = await t.runAsync(() => _demo(
          Directory.systemTemp.createTempSync('sudosend-shots'),
          lang: lang));
      final key = GlobalKey();
      final nav = GlobalKey<NavigatorState>();
      t.view.physicalSize = viewSize * 2;
      t.view.devicePixelRatio = 2;
      await t.pumpWidget(RepaintBoundary(
        key: key,
        child: AppScope(
          settings: c!.settings,
          child: MaterialApp(
            navigatorKey: nav,
            debugShowCheckedModeBanner: false,
            theme: buildTheme(arabic: lang == 'ar'),
            locale: Locale(lang),
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: HomeScreen(controller: c),
          ),
        ),
      ));
      for (final (tab, name) in [
        (0, 'home'),
        (4, 'files'),
        (2, 'activity'),
        (3, 'messages')
      ]) {
        c.setTab(tab);
        await t.pump();
        await _shot(t, key, '$prefix-$name');
      }
      c.setTab(0);
      await t.pump();
      Future<void> page(String name, Widget Function() build) async {
        unawaited(nav.currentState!
            .push(MaterialPageRoute<void>(builder: (_) => build())));
        await t.pump();
        await _shot(t, key, '$prefix-$name');
        nav.currentState!.pop();
        await t.pump(const Duration(milliseconds: 400));
      }

      openMyDevice(nav.currentContext!, c);
      await t.pump();
      await _shot(t, key, '$prefix-my-device');
      nav.currentState!.pop();
      await t.pump(const Duration(milliseconds: 400));
      await page('settings', () => SettingsPage(controller: c));
      await page('devices', () => DevicesPage(controller: c));
      await page(
          'device',
          () => DevicePage(
              controller: c, fingerprint: 'A' * 32, name: 'Work-Laptop'));
      await page(
          'chat',
          () => ChatThreadPage(
              controller: c, fingerprint: 'A' * 32, name: 'Work-Laptop'));
      await page('dashboard', () => DashboardPage(controller: c));
      await page('storage', () => StorageMapPage(controller: c));
    }

    await run('phone', const Size(390, 844), 'en');
    await run('phone-ar', const Size(390, 844), 'ar');
    await run('desktop', const Size(1280, 800), 'en');
  });
}
