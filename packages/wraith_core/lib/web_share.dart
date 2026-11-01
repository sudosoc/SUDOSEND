// Browser share: send files to — and receive files from — any device that
// only has a web browser (iPhone, a friend's laptop, a smart TV…).
//
// A tiny HTTP server serves a one-page site under an unguessable path:
//   http://<ip>:<port>/s/<128-bit token>/
// Only people who scan the QR / get the link can open it, it stops when the
// user stops sharing or after [ttl], and wrong-token probing is rate-limited.
// It is plain HTTP on the local network, so the UI tells users it is not
// end-to-end encrypted like app-to-app transfers.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import 'models.dart';
import 'pairing.dart';
import 'util.dart';

class WebShareEvent {
  WebShareEvent(this.kind, this.address, this.name, this.size, {this.path}) : at = DateTime.now();

  /// visit | download | upload
  final String kind;
  final String address;
  final String name;
  final int size;
  final String? path;
  final DateTime at;
}

class WebShare {
  WebShare({
    required this.files,
    required this.saveDir,
    this.uploadDirFor,
    this.text,
    this.allowUpload = false,
    this.deviceName = 'SUDOSEND',
    this.onEvent,
    this.onStopped,
    this.ttl = const Duration(minutes: 30),
    this.basePort = 47840,
    this.pin,
    this.maxDownloads,
  });

  /// Optional PIN visitors must enter (WeTransfer-Pro-style protected link).
  final String? pin;

  /// Stop sharing after this many completed file downloads (self-destructing link).
  final int? maxDownloads;

  int downloads = 0;

  final List<FileEntry> files;
  final String? text;
  final bool allowUpload;
  final String deviceName;
  final Future<Directory> Function() saveDir;

  /// Optional per-file folder for uploads (smart organization).
  final Future<Directory> Function(String fileName)? uploadDirFor;
  final void Function(WebShareEvent event)? onEvent;
  final void Function()? onStopped;
  final Duration ttl;

  /// First port to try; 0 = any free port (tests).
  final int basePort;

  HttpServer? _server;
  Timer? _expiry;
  late final String token = newPairingToken();
  int port = 0;
  DateTime? expiresAt;
  final Map<String, List<int>> _failures = {};

  bool get running => _server != null;

  List<String> urls(Iterable<InternetAddress> addresses) =>
      [for (final a in addresses) 'http://${a.address}:$port/s/$token/'];

  Future<void> start() async {
    final attempts = basePort == 0 ? 1 : 10;
    for (var i = 0; i < attempts && _server == null; i++) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, basePort == 0 ? 0 : basePort + i);
      } on SocketException {
        continue;
      }
    }
    final server = _server;
    if (server == null) throw const WraithException('Could not open a port for browser sharing');
    server.autoCompress = false;
    server.idleTimeout = const Duration(seconds: 30);
    port = server.port;
    expiresAt = DateTime.now().add(ttl);
    _expiry = Timer(ttl, stop);
    server.listen((req) => unawaited(_handle(req).catchError((Object _) {
          try {
            req.response.statusCode = HttpStatus.internalServerError;
            unawaited(req.response.close());
          } catch (_) {}
        })));
  }

  Future<void> stop() async {
    final server = _server;
    if (server == null) return;
    _server = null;
    _expiry?.cancel();
    await server.close(force: true);
    onStopped?.call();
  }

  // ─────────────────────────── HTTP ───────────────────────────

  bool _limited(String ip) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final hits = (_failures[ip] ?? <int>[])..removeWhere((t) => now - t > 10 * 60 * 1000);
    _failures[ip] = hits;
    return hits.length >= 20;
  }

  void _headers(HttpResponse res, String type) {
    res.headers
      ..set(HttpHeaders.contentTypeHeader, type)
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'no-referrer')
      ..set('X-Frame-Options', 'DENY')
      ..set('Content-Security-Policy',
          "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; img-src data:");
  }

  Future<void> _handle(HttpRequest req) async {
    final ip = req.connectionInfo?.remoteAddress.address ?? '?';
    final res = req.response;
    final seg = req.uri.pathSegments;
    if (_limited(ip)) {
      res.statusCode = HttpStatus.tooManyRequests;
      await res.close();
      return;
    }
    final ok = seg.length >= 2 &&
        seg[0] == 's' &&
        constantTimeEquals(utf8.encode(seg[1]), utf8.encode(token));
    if (!ok) {
      _failures[ip]!.add(DateTime.now().millisecondsSinceEpoch);
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    final rest = seg.sublist(2).where((s) => s.isNotEmpty).toList();

    // PIN gate: everything except the PIN form needs the session cookie.
    if (pin != null && !_hasSession(req)) {
      if (rest.length == 1 && rest[0] == 'pin' && req.method == 'POST') {
        final body = await utf8.decoder.bind(req).join();
        final given = Uri.splitQueryString(body)['pin'] ?? '';
        if (constantTimeEquals(utf8.encode(given), utf8.encode(pin!))) {
          res.statusCode = HttpStatus.seeOther;
          res.headers
            ..set(HttpHeaders.locationHeader, './')
            ..set(HttpHeaders.setCookieHeader,
                'ss=${_sessionValue()}; Path=/s/$token/; HttpOnly; SameSite=Strict; Max-Age=${ttl.inSeconds}');
          await res.close();
        } else {
          _failures[ip]!.add(DateTime.now().millisecondsSinceEpoch);
          final arabic = (req.headers.value(HttpHeaders.acceptLanguageHeader) ?? '').toLowerCase().startsWith('ar');
          _headers(res, 'text/html; charset=utf-8');
          res.statusCode = HttpStatus.forbidden;
          res.write(_pinPage(arabic, wrong: true));
          await res.close();
        }
        return;
      }
      if (rest.isEmpty && req.method == 'GET' && req.uri.path.endsWith('/')) {
        final arabic = (req.headers.value(HttpHeaders.acceptLanguageHeader) ?? '').toLowerCase().startsWith('ar');
        _headers(res, 'text/html; charset=utf-8');
        res.write(_pinPage(arabic));
        await res.close();
        return;
      }
      if (!(rest.isEmpty && req.method == 'GET')) {
        res.statusCode = HttpStatus.forbidden;
        await res.close();
        return;
      }
    }

    if (rest.isEmpty && req.method == 'GET') {
      if (!req.uri.path.endsWith('/')) {
        res.statusCode = HttpStatus.movedPermanently;
        res.headers.set(HttpHeaders.locationHeader, '${req.uri.path}/');
        await res.close();
        return;
      }
      final arabic = (req.headers.value(HttpHeaders.acceptLanguageHeader) ?? '').toLowerCase().startsWith('ar');
      _headers(res, 'text/html; charset=utf-8');
      res.write(_page(arabic));
      await res.close();
      onEvent?.call(WebShareEvent('visit', ip, '', 0));
      return;
    }

    if (rest.length == 2 && rest[0] == 'f' && req.method == 'GET') {
      final i = int.tryParse(rest[1]);
      if (i == null || i < 0 || i >= files.length) {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }
      final f = files[i];
      final file = File(f.path!);
      final name = p.basename(f.name);
      _headers(res, 'application/octet-stream');
      res.headers
        ..contentLength = await file.length()
        ..set('Content-Disposition',
            "attachment; filename=\"${name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_')}\"; filename*=UTF-8''${Uri.encodeComponent(name)}");
      await res.addStream(file.openRead());
      await res.close();
      onEvent?.call(WebShareEvent('download', ip, f.name, f.size));
      downloads++;
      final limit = maxDownloads;
      if (limit != null && downloads >= limit) {
        // Self-destruct: give the response a moment to flush, then stop.
        unawaited(Future<void>.delayed(const Duration(seconds: 2), stop));
      }
      return;
    }

    if (rest.length == 1 && rest[0] == 't' && req.method == 'GET' && text != null) {
      _headers(res, 'text/plain; charset=utf-8');
      res.write(text);
      await res.close();
      return;
    }

    if (rest.length == 1 && rest[0] == 'u' && req.method == 'POST' && allowUpload) {
      final raw = req.uri.queryParameters['name'] ?? 'upload';
      final name = sanitizeFileName(raw);
      final dir = await (uploadDirFor?.call(name) ?? saveDir());
      await dir.create(recursive: true);
      final part = File(p.join(dir.path, '.$name.web-part'));
      final sink = part.openWrite();
      var size = 0;
      try {
        await for (final chunk in req) {
          size += chunk.length;
          sink.add(chunk);
        }
        await sink.close();
      } catch (_) {
        await sink.close();
        if (await part.exists()) await part.delete();
        rethrow;
      }
      final dest = await uniqueFile(dir, name);
      await part.rename(dest.path);
      _headers(res, 'application/json');
      res.write(jsonEncode({'ok': true, 'name': p.basename(dest.path), 'size': size}));
      await res.close();
      onEvent?.call(WebShareEvent('upload', ip, p.basename(dest.path), size, path: dest.path));
      return;
    }

    res.statusCode = HttpStatus.notFound;
    await res.close();
  }

  late final List<int> _secret = utf8.encode(newPairingToken());

  String _sessionValue() =>
      crypto.Hmac(crypto.sha256, _secret).convert(utf8.encode('$token|$pin')).toString();

  bool _hasSession(HttpRequest req) {
    final expected = _sessionValue();
    for (final c in req.cookies) {
      if (c.name == 'ss' && constantTimeEquals(utf8.encode(c.value), utf8.encode(expected))) return true;
    }
    return false;
  }

  String _pinPage(bool ar, {bool wrong = false}) {
    String t(String en, String arText) => ar ? arText : en;
    return '''<!doctype html><html lang="${ar ? 'ar' : 'en'}" dir="${ar ? 'rtl' : 'ltr'}"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>SUDOSEND</title><style>
body{margin:0;min-height:100vh;display:grid;place-items:center;font:16px system-ui,sans-serif;color:#eaf0ff;background:#060816}
form{background:rgba(255,255,255,.07);border:1px solid rgba(255,255,255,.14);border-radius:22px;padding:26px;text-align:center;width:min(320px,90vw)}
input{width:100%;box-sizing:border-box;font-size:28px;letter-spacing:8px;text-align:center;padding:12px;border-radius:14px;border:1px solid rgba(255,255,255,.2);background:rgba(0,0,0,.3);color:#fff}
button{margin-top:14px;width:100%;border:0;border-radius:14px;padding:12px;font-weight:800;background:linear-gradient(135deg,#38e1ff,#8b5cf6);color:#070a16}
.e{color:#fb7185}</style></head><body><form method="post" action="pin">
<h2>🔒 ${t('Enter PIN', 'اكتب الرقم السري')}</h2>${wrong ? '<p class="e">${t('Wrong PIN', 'الرقم غلط')}</p>' : ''}
<input name="pin" inputmode="numeric" autocomplete="one-time-code" autofocus maxlength="12">
<button>${t('Open', 'فتح')}</button></form></body></html>''';
  }

  // ─────────────────────────── Page ───────────────────────────

  String _page(bool ar) {
    String t(String en, String arText) => ar ? arText : en;
    const esc = HtmlEscape();
    final rows = StringBuffer();
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      rows.write('<a class="row" href="f/$i" download><span class="ic">⇣</span>'
          '<span class="nm">${esc.convert(f.name)}</span><span class="sz">${formatBytes(f.size)}</span></a>');
    }
    final textBlock = text == null
        ? ''
        : '<div class="card"><h2>${t('Text', 'نص')}</h2><pre id="tx">${esc.convert(text!)}</pre>'
            '<button onclick="copyTx(this)">${t('Copy', 'نسخ')}</button></div>';
    final filesBlock = files.isEmpty
        ? ''
        : '<div class="card"><h2>${t('Files', 'الملفات')} · ${files.length}</h2>$rows'
            '${files.length > 1 ? '<button onclick="document.querySelectorAll(\'a.row\').forEach((a,i)=>setTimeout(()=>a.click(),i*600))">${t('Download all', 'تنزيل الكل')}</button>' : ''}</div>';
    final uploadBlock = !allowUpload
        ? ''
        : '''<div class="card"><h2>${t('Send to', 'ابعت لـ')} ${esc.convert(deviceName)}</h2>
<label class="drop" id="drop"><input id="pick" type="file" multiple hidden>
<b>${t('Choose files', 'اختار ملفات')}</b><br><small>${t('or drop them here', 'أو اسحبها هنا')}</small></label>
<div id="log"></div></div>''';
    return '''<!doctype html><html lang="${ar ? 'ar' : 'en'}" dir="${ar ? 'rtl' : 'ltr'}"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>SUDOSEND · ${esc.convert(deviceName)}</title>
<style>
*{box-sizing:border-box}body{margin:0;min-height:100vh;font:15px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,"Noto Sans Arabic",sans-serif;color:#eaf0ff;
background:radial-gradient(1200px 600px at 10% 0%,#3b2a7a 0%,transparent 60%),radial-gradient(900px 600px at 100% 60%,#0f4a63 0%,transparent 60%),#060816}
main{max-width:640px;margin:0 auto;padding:22px 16px 40px}
header{display:flex;align-items:center;gap:12px;margin-bottom:18px}
.logo{width:44px;height:44px;border-radius:14px;background:linear-gradient(135deg,#38e1ff,#8b5cf6);display:grid;place-items:center;color:#070a16;font-weight:900;font-size:22px}
h1{font-size:20px;letter-spacing:3px;margin:0}header small{color:#8e9bb8}
.card{background:rgba(255,255,255,.07);border:1px solid rgba(255,255,255,.14);border-radius:22px;padding:16px;margin-bottom:14px;backdrop-filter:blur(18px)}
h2{font-size:13px;letter-spacing:1.4px;text-transform:uppercase;color:#8e9bb8;margin:0 0 10px}
.row{display:flex;gap:10px;align-items:center;padding:11px 10px;border-radius:14px;color:inherit;text-decoration:none}
.row:hover{background:rgba(56,225,255,.08)}.ic{color:#38e1ff;font-weight:900}.nm{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.sz{color:#8e9bb8;font-size:13px}
button{margin-top:10px;border:0;border-radius:14px;padding:11px 18px;font-weight:800;color:#070a16;background:linear-gradient(135deg,#38e1ff,#8b5cf6);cursor:pointer}
pre{white-space:pre-wrap;word-break:break-word;background:rgba(0,0,0,.25);border-radius:14px;padding:12px;margin:0}
.drop{display:block;text-align:center;padding:26px;border:2px dashed rgba(56,225,255,.45);border-radius:18px;cursor:pointer}
.drop.on{background:rgba(56,225,255,.08)}
.item{margin-top:10px;font-size:13px}.bar{height:7px;border-radius:7px;background:rgba(255,255,255,.08);overflow:hidden;margin-top:4px}
.bar i{display:block;height:100%;width:0;background:linear-gradient(90deg,#38e1ff,#8b5cf6)}
.note{color:#8e9bb8;font-size:12px;text-align:center;margin-top:18px}
</style></head><body><main>
<header><div class="logo">⚡</div><div><h1>SUDOSEND</h1><small>${esc.convert(deviceName)}</small></div></header>
$filesBlock$textBlock$uploadBlock
<p class="note">${t('Shared over your local network. Get the app for end-to-end encrypted transfers: github.com/sudosoc/SUDOSEND-APP', 'مشارَك على شبكتك المحلية. حمّل التطبيق لتحويلات مشفّرة من الطرف للطرف: github.com/sudosoc/SUDOSEND-APP')}</p>
</main>
<script>
function copyTx(b){const t=document.getElementById('tx');const r=document.createRange();r.selectNodeContents(t);const s=getSelection();s.removeAllRanges();s.addRange(r);
try{document.execCommand('copy');b.textContent='✓'}catch(e){}}
const pick=document.getElementById('pick'),drop=document.getElementById('drop'),log=document.getElementById('log');
function up(f){return new Promise(r=>{const d=document.createElement('div');d.className='item';d.textContent=f.name;const b=document.createElement('div');b.className='bar';const i=document.createElement('i');b.appendChild(i);d.appendChild(b);log.appendChild(d);
const x=new XMLHttpRequest();x.open('POST','u?name='+encodeURIComponent(f.name));x.upload.onprogress=e=>{if(e.lengthComputable)i.style.width=(e.loaded/e.total*100)+'%'};
x.onload=()=>{i.style.width='100%';d.firstChild.textContent='✓ '+f.name;r()};x.onerror=()=>{d.firstChild.textContent='✗ '+f.name;r()};x.send(f)})}
async function send(list){for(const f of list){await up(f)}}
if(pick){pick.onchange=()=>send(pick.files);
['dragenter','dragover'].forEach(e=>drop.addEventListener(e,v=>{v.preventDefault();drop.classList.add('on')}));
['dragleave','drop'].forEach(e=>drop.addEventListener(e,v=>{v.preventDefault();drop.classList.remove('on')}));
drop.addEventListener('drop',v=>send(v.dataTransfer.files));}
</script></body></html>''';
  }
}
