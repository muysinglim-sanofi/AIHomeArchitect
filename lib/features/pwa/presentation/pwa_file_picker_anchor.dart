/// WHERE THE PHOTO PICKER OPENS.
///
/// On an iPhone, "Photo Library · Take Photo · Choose File" is WebKit's own
/// menu, and WebKit decides how it looks — but it grows from a rectangle the
/// PAGE controls. `Source/WebKit/UIProcess/ios/forms/WKFileUploadPanel.mm`:
///
///     CGRect elementRect = parameters->elementRectInMainFrameViewCoordinates();
///     bool elementIsVisible = page && CGRectIntersectsRect(elementRect,
///         page->unobscuredContentRect());
///     _menuPresentationRect = elementIsVisible ? elementRect
///         : CGRect { [view lastInteractionLocation], CGSizeZero };
///
/// The element is the `<input type=file>` that `image_picker_for_web` injects
/// and clicks. The plugin appends it to `<body>` UNSTYLED ("TODO(ditman):
/// Append inside the `view` of the running app"), so it sat in the page's
/// top-left corner — measured at 390×844: `0,0 253×21`, visible, opacity 1 —
/// and the menu grew from THERE. Whenever that corner left the unobscured rect
/// (Safari's bars collapsing, the page scrolled) WebKit fell back to the last
/// touch point instead. Hence "sometimes high, sometimes low", and never
/// centred on the upload area.
///
/// So, inside the tap and before the picker is asked for, the input is moved
/// — invisibly — onto a 2pt band across the middle of the zone that was
/// tapped. WebKit then anchors at that band's bottom-centre, which is the
/// zone's centre, every time. The menu stays iOS's; only the point it grows
/// from is ours. Nothing is drawn, nothing intercepts a touch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Anchors the next file-picker menu to a zone, in logical pixels (the same
/// CSS pixels the browser uses, since the Flutter view fills the viewport). A
/// no-op everywhere but the browser, where `main_pwa.dart` overrides it.
final pwaFilePickerAnchorProvider =
    Provider<void Function(Rect zone)>((ref) => (_) {});

/// Anchor the picker to the widget that owns [context]. Call it synchronously
/// inside the tap, BEFORE the picker is asked for: the plugin clicks its input
/// in that same turn, and that click is when WebKit reads the rectangle.
void pwaAnchorFilePickerTo(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize || !box.attached) return;
  final zone = box.localToGlobal(Offset.zero) & box.size;
  ProviderScope.containerOf(context, listen: false)
      .read(pwaFilePickerAnchorProvider)(zone);
}
