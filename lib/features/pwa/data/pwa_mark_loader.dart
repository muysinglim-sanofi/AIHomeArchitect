/// How the ABA marks' SVG bytes are obtained.
///
/// The two official files live under `web/aba/` and are fetched by the same
/// relative, same-origin URL the earlier PNGs used, through flutter_svg.
///
/// WHY NOT flutter_svg's OWN NETWORK LOADER. It hands whatever the server
/// returns to the XML parser — a 404 page, or `flutter_test`'s stub 400 with
/// an empty body — and the resulting "Invalid SVG data" escapes the picture
/// cache as an uncaught async error, which fails a widget test even when an
/// `errorBuilder` is shown. [PwaSvgUrlLoader] checks the status and answers
/// anything but a 200 with an SVG that draws nothing: a missing mark is
/// absent, never a broken glyph and never an exception.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

/// An SVG that draws nothing (a zero-sized viewBox).
const String kPwaEmptySvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 0 0"/>';

/// Fetches one mark by same-origin URL, status-checked.
class PwaSvgUrlLoader extends SvgLoader<Uint8List> {
  const PwaSvgUrlLoader(this.url, {super.theme, super.colorMapper});

  final String url;

  @override
  Future<Uint8List?> prepareMessage(BuildContext? context) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        return res.bodyBytes;
      }
    } catch (_) {
      // Offline, blocked, misconfigured: the mark is simply absent.
    }
    return Uint8List.fromList(utf8.encode(kPwaEmptySvg));
  }

  @override
  String provideSvg(Uint8List? message) => message == null
      ? kPwaEmptySvg
      : utf8.decode(message, allowMalformed: true);

  @override
  int get hashCode => Object.hash(url, theme, colorMapper);

  @override
  bool operator ==(Object other) =>
      other is PwaSvgUrlLoader &&
      other.url == url &&
      other.theme == theme &&
      other.colorMapper == colorMapper;
}

/// How a mark's bytes are obtained for a given asset path.
///
/// Production fetches from `web/aba/`; tests point this at the checked-in
/// files so every pumped screen draws the real artwork.
typedef PwaMarkLoader = BytesLoader Function(String asset);

final pwaMarkLoaderProvider =
    Provider<PwaMarkLoader>((_) => (asset) => PwaSvgUrlLoader(asset));
