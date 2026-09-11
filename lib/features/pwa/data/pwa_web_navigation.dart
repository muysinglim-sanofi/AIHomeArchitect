/// Batch 3.4b — web-only History API + sessionStorage adapters.
///
/// Imported ONLY by `main_pwa` (the web entrypoint). It pulls in `package:web`
/// / `dart:js_interop`, so it must never be reached from the widget tree or the
/// mobile entrypoint (those compile for the VM in `flutter test`, where these
/// libraries are unavailable). Tests use the in-memory fakes instead.
library;

import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:web/web.dart' as web;

import '../application/pwa_intro_gate.dart';
import '../application/pwa_url_bridge.dart';
import 'pwa_external_launcher.dart';
import 'pwa_image_export.dart';

/// Real browser history bridge (pushState / replaceState / popstate).
///
/// [prefix] is the build's route prefix (`/kh` in production, `''` elsewhere):
/// removed on every read, restored on every write — see [pwaStripRoutePrefix].
class WebPwaUrlBridge implements PwaUrlBridge {
  WebPwaUrlBridge({this.prefix = ''});

  final String prefix;
  JSFunction? _listener;

  @override
  Uri current() {
    final loc = web.window.location;
    return pwaStripRoutePrefix(
      Uri.parse('${loc.pathname}${loc.search}'),
      prefix,
    );
  }

  @override
  void push(String location) => web.window.history
      .pushState(null, '', pwaApplyRoutePrefix(location, prefix));

  @override
  void replace(String location) => web.window.history
      .replaceState(null, '', pwaApplyRoutePrefix(location, prefix));

  @override
  void onPop(void Function(Uri) callback) {
    _listener = ((web.Event _) => callback(current())).toJS;
    web.window.addEventListener('popstate', _listener);
  }

  @override
  void dispose() {
    final l = _listener;
    if (l != null) {
      web.window.removeEventListener('popstate', l);
      _listener = null;
    }
  }
}

/// The page's own origin (`https://preprod.aydenstudio.com`), for the OAuth
/// `redirect_to` — GoTrue must send the browser back to THIS deployment, and
/// deriving it from the page is the only way one bundle serves preview
/// channels, preprod and live alike. It is an address, not a credential.
String webPwaOrigin() => web.window.location.origin;

/// The FULL boot URL, fragment included. `WebPwaUrlBridge.current` drops the
/// fragment on purpose (routes never live there); the OAuth return does not
/// have that luxury, because GoTrue still mirrors its errors into the hash.
Uri webPwaBootUri() => Uri.parse(web.window.location.href);

/// Real `window.sessionStorage` — survives F5, cleared when the tab closes, so
/// the cinematic plays once per tab session (§7).
class WebPwaSessionStore implements PwaSessionStore {
  @override
  String? read(String key) => web.window.sessionStorage.getItem(key);

  @override
  void write(String key, String value) =>
      web.window.sessionStorage.setItem(key, value);
}

/// Real navigation to somewhere outside the app — today, the ABA Mobile
/// deeplink from the payment sheet.
///
/// `location.href` rather than `window.open`: a custom scheme opened in a new
/// tab leaves an empty tab behind on every mobile browser, and mobile is where
/// this button exists at all. Assigning href hands the URL to the OS, which
/// either opens ABA Mobile or does nothing — and doing nothing is fine, because
/// the QR is still on screen underneath.
class WebPwaExternalLauncher implements PwaExternalLauncher {
  const WebPwaExternalLauncher();

  @override
  void open(String url) {
    if (url.isEmpty) return;
    web.window.location.href = url;
  }

  @override
  void openNewTab(String url) {
    if (url.isEmpty) return;
    // `noopener` severs `window.opener`, so ABA's page cannot reach back into
    // this one. Standard hygiene for any cross-origin link, and mandatory for
    // one that is about to ask somebody for money.
    web.window.open(url, '_blank', 'noopener,noreferrer');
  }
}

/// Share and save, over the real browser APIs.
///
/// The whole contract, and its limits, are documented on [PwaImageExporter].
/// In short: the picture is fetched from its signed URL as BYTES, wrapped in a
/// `File`, and handed to `navigator.share` when the browser accepts files —
/// which on iOS opens the system sheet where "Save Image" lives. Otherwise it
/// is downloaded through an object URL. Nothing here screenshots the UI and
/// nothing shares a bare link.
class WebPwaImageExporter implements PwaImageExporter {
  WebPwaImageExporter();

  /// The last file fetched, and the URL it came from. One entry, because one
  /// picture is open at a time — and it is what lets [share] run without a
  /// network round-trip inside the tap.
  String _warmUrl = '';
  web.File? _warm;

  /// `navigator.canShare` exists only where Web Share level 2 does, and it is
  /// the only trustworthy answer: user agents that expose `share` for text
  /// still refuse files. Probed with a real, tiny file rather than assumed.
  @override
  bool get canShareFiles {
    try {
      // A one-byte JPEG is enough to ask the real question: some agents expose
      // `share` for text and refuse files, and only `canShare({files})` tells
      // them apart. Never assumed from the user agent string.
      final probe = web.File(
        [Uint8List(1).toJS].toJS,
        'probe.jpg',
        web.FilePropertyBag(type: 'image/jpeg'),
      );
      final data = web.ShareData(files: [probe].toJS);
      return web.window.navigator.canShare(data);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> prefetch({
    required String url,
    required String fileName,
  }) async {
    if (url.isEmpty || _warmUrl == url) return;
    final file = await _fetchAsFile(url, fileName);
    if (file != null) {
      _warmUrl = url;
      _warm = file;
    }
  }

  /// Is the share sheet on this platform a place a picture can be saved?
  /// True on a touch platform (iPhone, Android), false on a pointer one, where
  /// preprod showed the sheet forwarding to apps and offering no save at all.
  bool get _sheetCanSave {
    try {
      return web.window.matchMedia('(pointer: coarse)').matches;
    } catch (_) {
      return false;
    }
  }

  Future<web.File?> _fetchAsFile(String url, String fileName) async {
    if (_warmUrl == url && _warm != null) return _warm;
    try {
      final res = await web.window.fetch(url.toJS).toDart;
      if (!res.ok) return null;
      final buf = await res.arrayBuffer().toDart;
      final type = res.headers.get('content-type') ?? 'image/jpeg';
      return web.File(
        [buf].toJS,
        fileName,
        web.FilePropertyBag(type: type),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<PwaExportOutcome> share({
    required String url,
    required String fileName,
    required String title,
  }) async {
    if (!canShareFiles) return PwaExportOutcome.unsupported;
    final file = await _fetchAsFile(url, fileName);
    if (file == null) return PwaExportOutcome.failed;
    // From here on nothing may `await` before `share`: the call is gated on
    // transient user activation, and any round-trip in between spends it.
    try {
      await web.window.navigator
          .share(web.ShareData(files: [file].toJS, title: title))
          .toDart;
      return PwaExportOutcome.done;
    } catch (e) {
      // `AbortError` is the person closing the sheet. That is a choice, not a
      // fault, and the UI must not apologise for it.
      final name = e.toString();
      if (name.contains('AbortError')) return PwaExportOutcome.cancelled;
      // `NotAllowedError` is the platform refusing the sheet — no activation
      // left, or a browser that advertises file sharing and does not offer it.
      // That is not the same as a broken picture, and SAVE turns it into a
      // download rather than an apology.
      if (name.contains('NotAllowedError')) return PwaExportOutcome.unsupported;
      return PwaExportOutcome.failed;
    }
  }

  @override
  Future<PwaExportOutcome> save({
    required String url,
    required String fileName,
  }) async {
    // On a platform whose share sheet offers "Save Image" — every iPhone —
    // that sheet IS the save. There is no web API that writes to the Photo
    // Library, and offering a download there would put the file somewhere the
    // person did not ask for.
    if (canShareFiles && _sheetCanSave) {
      final outcome = await share(url: url, fileName: fileName, title: fileName);
      if (pwaSheetAnsweredSave(outcome)) return outcome;
    }
    final file = await _fetchAsFile(url, fileName);
    if (file == null) return PwaExportOutcome.failed;
    try {
      final objectUrl = web.URL.createObjectURL(file);
      final a = web.document.createElement('a') as web.HTMLAnchorElement
        ..href = objectUrl
        ..download = fileName
        ..style.display = 'none';
      web.document.body!.append(a);
      a.click();
      a.remove();
      // Freed on the next turn: revoking synchronously can beat the download.
      Future<void>.delayed(const Duration(seconds: 30),
          () => web.URL.revokeObjectURL(objectUrl));
      return PwaExportOutcome.done;
    } catch (_) {
      return PwaExportOutcome.failed;
    }
  }
}

/// Moves the image picker's `<input type=file>` onto the middle of [zone], so
/// WebKit grows its "Photo Library · Take Photo · Choose File" menu from the
/// zone that was tapped rather than from the page's top-left corner. The why,
/// with the WebKit source line, is in `pwa_file_picker_anchor.dart`.
///
/// The host element is the plugin's own (`image_picker_for_web` creates it at
/// registration and clicks the input inside it). It is made fixed, transparent
/// and deaf to touches, and parked on a 2pt band at the zone's vertical centre;
/// the input fills it. Any failure leaves the picker exactly as it was — the
/// placement is a nicety, opening is not.
void pwaAnchorFilePicker(Rect zone) {
  try {
    const hostId = '__image_picker_web-file-input';
    final host = web.document.getElementById(hostId);
    if (host == null) return;
    if (web.document.getElementById('ayden-picker-anchor') == null) {
      final style = web.document.createElement('style')
        ..id = 'ayden-picker-anchor'
        ..textContent = '#$hostId{position:fixed;display:block;margin:0;'
            'opacity:0;pointer-events:none;overflow:hidden;z-index:-1}'
            '#$hostId>input{position:absolute;left:0;top:0;width:100%;'
            'height:100%;margin:0;padding:0;border:0;opacity:0}';
      web.document.head?.append(style);
    }
    (host as web.HTMLElement).style
      ..left = '${zone.left}px'
      ..top = '${zone.center.dy - 1}px'
      ..width = '${zone.width}px'
      ..height = '2px';
  } catch (_) {
    // Never between a person and their photo library.
  }
}
