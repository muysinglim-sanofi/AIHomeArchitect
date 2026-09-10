/// Getting a generated vision OUT of Ayden — shared, or saved.
///
/// Both are browser capabilities, and the browser is honest about them only at
/// runtime, so this is an interface with a web implementation injected in
/// `main_pwa.dart` (the same shape as the history bridge and the external
/// launcher). Tests and the offline mock get [PwaUnsupportedImageExporter],
/// which answers `unsupported` and draws nothing.
///
/// WHAT THE WEB ACTUALLY ALLOWS, and why the UX says what it says
/// -------------------------------------------------------------
/// There is no web API that writes to the iOS Photo Library. Nothing here
/// pretends otherwise. What iOS Safari does have is the **Web Share API with
/// files** (`navigator.share({files})`), which opens the system share sheet —
/// and that sheet is where "Save Image" lives, alongside Messages, Mail and
/// every app the person has. So on an iPhone the honest way to save a picture
/// IS the share sheet, and that is what the Save action opens.
///
/// A DESKTOP share sheet is a different thing, and preprod showed it: Windows
/// Chrome answers `canShare({files}) == true`, and tapping "Save image" opened
/// the Windows share flyout — which offers apps to send the picture to, and no
/// way to save it. A control labelled "Save image" that shares instead is
/// wrong, so the sheet is the save only where the sheet actually saves: the
/// touch platforms whose sheet carries "Save Image" / "Add to Photos". A
/// pointer platform downloads, which is what its user expects and what its
/// browser is good at. `(pointer: coarse)` asks that as a capability rather
/// than reading the user-agent string for a brand name.
///
/// Where the sheet is unavailable, or is offered and refuses, the same bytes
/// go out as a real download — an object URL and an `<a download>`.
///
/// THE GESTURE, and why [prefetch] exists
/// --------------------------------------
/// `navigator.share` is gated on transient user activation, and a call outside
/// that window is rejected — measured directly on preprod as `NotAllowedError
/// - Must be handling a user gesture`. Fetching a multi-megabyte render from
/// its signed URL inside the tap is exactly what spends the window, so the
/// bytes are warmed when the picture is OPENED and the tap only calls `share`.
/// This is hardening against a documented constraint, not a repair of a defect
/// seen in the product path.
///
/// In both cases what leaves is the GENERATED IMAGE, fetched from its signed
/// URL at full resolution. Never a screenshot of the interface, never a link.
library;

/// What happened, in terms the UI can speak about honestly.
enum PwaExportOutcome {
  /// The system took over: the share sheet opened, or the file downloaded.
  done,

  /// The person dismissed the system sheet. Not a failure.
  cancelled,

  /// The browser cannot do this at all.
  unsupported,

  /// It was attempted and failed — the image could not be fetched, or the
  /// platform refused.
  failed,
}

abstract class PwaImageExporter {
  /// Whether this browser can share actual FILES. False means the Share action
  /// must not promise a system sheet.
  bool get canShareFiles;

  /// Warm [url]'s bytes so a later [share] or [save] runs inside the tap's own
  /// activation window. Best-effort and never throwing: a cold cache costs the
  /// sheet, not the picture.
  Future<void> prefetch({required String url, required String fileName});

  /// Hand the image itself to the platform share sheet.
  Future<PwaExportOutcome> share({
    required String url,
    required String fileName,
    required String title,
  });

  /// Put the image where the person keeps things: the share sheet on a
  /// platform whose sheet offers "Save Image", a download everywhere else.
  Future<PwaExportOutcome> save({
    required String url,
    required String fileName,
  });
}

/// The answer in tests, in the offline mock, and on any platform that is not a
/// browser: nothing is offered and nothing is claimed.
class PwaUnsupportedImageExporter implements PwaImageExporter {
  const PwaUnsupportedImageExporter();

  @override
  bool get canShareFiles => false;

  @override
  Future<void> prefetch({
    required String url,
    required String fileName,
  }) async {}

  @override
  Future<PwaExportOutcome> share({
    required String url,
    required String fileName,
    required String title,
  }) async =>
      PwaExportOutcome.unsupported;

  @override
  Future<PwaExportOutcome> save({
    required String url,
    required String fileName,
  }) async =>
      PwaExportOutcome.unsupported;
}

/// Did the share sheet ANSWER a request to save, or must the download still
/// run?
///
/// `done` means the platform took over. `cancelled` means the person saw the
/// sheet and closed it — an answer, and downloading behind their back would be
/// the app overruling them. Everything else means the sheet was not the save
/// on this platform, and someone who asked for a file has not got one.
///
/// MEASURED, not assumed (preprod, 2026-09-10): desktop Chrome answers
/// `canShare({files}) == true` and then rejects `share()` with
/// `NotAllowedError - Must be handling a user gesture`. Save stopped there and
/// reported a failure, so the control did nothing at all.
bool pwaSheetAnsweredSave(PwaExportOutcome outcome) =>
    outcome == PwaExportOutcome.done || outcome == PwaExportOutcome.cancelled;

/// A file name a person will recognise in their camera roll or downloads.
/// `Ayden-Studio-Living-Room-Warm-Modern-v2.jpg` rather than a UUID.
String pwaVisionFileName({
  required int visionNumber,
  String roomLabel = '',
  String atmosphereLabel = '',
}) {
  String slug(String s) => s
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final parts = <String>[
    'Ayden-Studio',
    if (slug(roomLabel).isNotEmpty) slug(roomLabel),
    if (slug(atmosphereLabel).isNotEmpty) slug(atmosphereLabel),
    'v$visionNumber',
  ];
  return '${parts.join('-')}.jpg';
}
