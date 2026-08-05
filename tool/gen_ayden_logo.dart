// Batch 2.1 Tranche 1.1 — derive a TRANSPARENT hero logo from the official
// raster (assets/branding/app_icon_1024_black.png) WITHOUT redrawing the mark:
// the solid black background becomes transparent (alpha from max channel), the
// gold compass + white AYDEN are preserved with their anti-aliased edges. Run:
//   dart run tool/gen_ayden_logo.dart
// ignore_for_file: depend_on_referenced_packages, avoid_print
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final srcBytes =
      File('assets/branding/app_icon_1024_black.png').readAsBytesSync();
  final src = img.decodeImage(srcBytes);
  if (src == null) {
    stderr.writeln('could not decode official logo');
    exitCode = 1;
    return;
  }
  final out = img.Image(width: src.width, height: src.height, numChannels: 4);
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
      final maxc = r > g ? (r > b ? r : b) : (g > b ? g : b);
      // Near-black → transparent; gold/white → opaque; preserves AA edges.
      final a = ((maxc - 8) * 1.35).round().clamp(0, 255);
      out.setPixelRgba(x, y, r, g, b, a);
    }
  }
  File('assets/branding/ayden_logo_hero.png')
      .writeAsBytesSync(img.encodePng(out));
  print('wrote assets/branding/ayden_logo_hero.png (${out.width}x${out.height})');
}
