"""Turning ABA's KHQR payload into pixels. Presentation, and nothing else.

WHY THIS EXISTS
---------------
ABA's Purchase API returns the payment as a STRING — `qr_string`, the EMV KHQR
payload — and, on this rail, never as an image. Measured 2026-09-05 on the
sandbox: `abapay_khqr_deeplink` answers 200 JSON with `qr_string`,
`abapay_deeplink`, `checkout_qr_url`, `description` and `status`, and no image
field of any kind. (`download_qr`, ABA's own image endpoint, appears only inside
the opaque base64 checkout token, which `payway.py` deliberately refuses to
parse.) A customer cannot scan a string, so something has to draw it.

WHAT THIS MODULE IS ALLOWED TO DO, AND NOTHING MORE
---------------------------------------------------
It takes the EXACT payload PayWay returned and encodes it, byte for byte, into
a standard QR symbol. It does not parse it, normalise it, re-order it, recompute
its CRC, substitute a field, or construct a payload of its own. If PayWay's
string changed by one character the symbol would change with it — which is the
whole point.

That distinction is the difference between rendering a payment and creating one.
Payment authority stays exactly where it was: PayWay's Check Transaction decides
whether money moved, and the Billing Engine grants. A QR on a screen decides
nothing.

DELIBERATELY PLAIN
------------------
Black modules, white ground, the standard four-module quiet zone, error level M,
no logo in the centre, no rounded cells, no colour. A bank's payment code is not
a place for decoration, and an overlaid logo is exactly the kind of alteration
that turns "we rendered their payload" into "we made our own artwork".

NO ARBITRARY-INPUT ENDPOINT
---------------------------
There is no route that renders a caller-supplied string. The only call site is
`pwa_staging_payments.start_checkout`, which passes the value it just received
from PayWay for the order it just created. The browser cannot reach this code
with a payload of its own.
"""
from __future__ import annotations

import base64
import io

import segno

#: Error correction. `M` (~15%) is the usual level for KHQR: enough resilience
#: for a phone camera on a screen, without inflating the symbol. Nothing is
#: overlaid on the code, so the higher levels buy nothing here.
_ERROR = "m"

#: Device pixels per QR module. 8 puts a ~69-module KHQR symbol at ~616 px,
#: which downsamples cleanly into the ~220 px the modal gives it on a 2x screen.
_SCALE = 8

#: The quiet zone, in modules. FOUR is what the specification requires; a
#: smaller border is the most common reason a code will not scan against a
#: light background.
_BORDER = 4


class KhqrRenderError(RuntimeError):
    """The payload could not be encoded. Never raised for an empty payload."""


def render_khqr_png_b64(qr_string: str) -> str:
    """Encode [qr_string] EXACTLY as given and return a base64 PNG.

    Returns `''` for an empty payload — the normal case on any rail that does
    not return one, and not an error: an absent QR is a state the payment sheet
    already renders.

    The output is DETERMINISTIC: the same payload always produces the same
    bytes, which is what makes it testable and what lets a reviewer confirm the
    image belongs to the payload rather than to us.
    """
    payload = qr_string or ""
    if not payload:
        return ""
    try:
        # `mode='byte'` is stated rather than inferred. A KHQR payload contains
        # lowercase letters and `@`, so QR alphanumeric mode cannot represent it
        # and any encoder would fall back to byte mode anyway — saying so keeps
        # the choice from silently changing if a future payload happens to be
        # representable some other way, which would alter the symbol for the
        # same logical content.
        code = segno.make(payload, mode="byte", encoding="utf-8", error=_ERROR)
        buf = io.BytesIO()
        code.save(buf, kind="png", scale=_SCALE, border=_BORDER,
                  dark="#000000", light="#ffffff")
    except Exception as exc:  # noqa: BLE001 - any encoder failure is one case
        raise KhqrRenderError(
            f"could not encode a {len(payload)}-character KHQR payload") from exc
    return base64.b64encode(buf.getvalue()).decode("ascii")
