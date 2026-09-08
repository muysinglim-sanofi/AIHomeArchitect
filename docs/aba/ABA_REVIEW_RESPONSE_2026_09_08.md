# ABA merchant review — response (2026-09-08)

Feedback received from ABA on 2026-09-08 for `https://preprod.aydenstudio.com`, and
what changed. The Telegram message to send is at the end. Nothing in this document is
production: the site is the dedicated preprod, the API is the staging deployment, and
PayWay is the sandbox.

## Feedback → change

| # | ABA feedback | Change on preprod |
|---|---|---|
| 1 | "Please kindly change ABA LOGO and description follow our Payment option format." | Wallet payment option now uses ABA's supplied tile (`ABA BANK.svg`, byte for byte) with the copy **ABA KHQR** / **Scan to pay with any banking app**. The old sentence ("…that supports KHQR.") is gone. No chevron: the row is informational and Buy remains the only purchase control. |
| 2 | "You already have your own success screen. So you can skip ABA success screen by submit parameter: skip_success_page = 1" | The signed Purchase request posted by ABA's official JS plugin now carries `skip_success_page=1` (last hashed field). Settlement is unchanged: Check Transaction → APPROVED → exactly one credit grant. |
| 3 | "Please remove ABA KHQR on your success screen header." | Ayden's success card no longer shows the ABA tile or "ABA KHQR" in its header. While a payment is in progress the method is still named. |
| 4 | "Please add We accept logo on your Website footer. You can use our LOGO below." | ABA's supplied `abakhqr-we-accept.svg` (byte for byte) sits in the website footer of the Home, Projects and Profile pages, captioned "We accept" in the page's language. The previous placement beside the Profile tab label is removed; no duplicates. |

The generated PNG stand-ins used for the first review are removed from the served
folder and referenced by no UI code.

## Check Transaction logic (as implemented — verified in the code, not from memory)

Source: backend `pwa_staging_payments.py` (`verify_and_settle` ~707-830, `_may_check`
~832-837, constants ~130-149, routes ~1130-1257), `payway.py` (status codes ~163-171,
lifetime ~320-325), PWA `pwa_payment_controller.dart` (~224-256) and
`pwa_payment.dart` (~99, ~159-207).

| Question | Answer |
|---|---|
| A. Initial delay before the first call | No Check Transaction at checkout creation. The browser posts the Purchase form to PayWay and arms a 3 000 ms timer in the same instant; the first status poll triggers the first Check Transaction ≈ 3 s (+ one round trip) after the Purchase POST. The server floor never delays it (first check has no previous check). |
| B. Recurring interval | Client: 3.0 s, re-armed after each answer (server hint `poll_interval_ms: 3000`, clamped 1–15 s). Server: minimum 3.0 s between two real Check Transaction calls per transaction. Effective cadence measured 3.96 s. No burst, no exponential backoff. |
| C. Stop conditions | The client stops on any terminal state: GRANTED, FAILED, EXPIRED, CANCELLED (also on explicit cancel/reset and when the tab closes). The server short-circuits GRANTED / FAILED / CANCELLED without calling PayWay again. |
| D. After APPROVED (`payment_status_code 0`) | Amount and currency are checked against the catalogue; state VERIFIED → `billing_grant_purchase` (idempotent) → GRANTED, exactly once; the client stops. |
| E. Provider failure / decline | `payment_status_code` 3 DECLINED, 7 CANCELLED, 4 REFUNDED → FAILED (order FAILED), client stops and offers Retry. 2 PENDING keeps polling; gateway 5xx / transport errors keep polling with the row unchanged. |
| F. NOT_CREATED | Envelope not `00` (e.g. status 6 "not found") on a plugin row more than 30 s after issue → FAILED / NOT_CREATED, polling stops. Inside 30 s the poll simply continues. |
| G. User cancel / close | "Cancel this payment": one forced Check Transaction first (a payment that just landed wins), otherwise CANCELLED (order CANCELLED). Closing ABA's popup alone sends nothing; polling continues until a terminal state, the inline cancel, or the tab closes. |
| H. Local expiry | `expires_at` = issue time + lifetime; evaluated lazily on the next verify: one final Check Transaction, then EXPIRED (order CANCELLED) unless PayWay says APPROVED or a terminal failure. No background sweep. |
| I. Maximum polling lifetime | 30 minutes (`PAYWAY_QR_LIFETIME_MINUTES`, default 30, floor 3), also the `lifetime` sent in the Purchase request. ≈ 450 Check Transaction calls at most per transaction (452 observed on one left unpaid). |
| J. Pushback | The signed pushback (HMAC-SHA512 verified, required) triggers one immediate Check Transaction and can settle the order server-to-server without the browser; the browser stops at its next poll. |

Unchanged in this pass: polling interval and lifetime (ABA did not object to them).

## Open point for ABA (needed to confirm item 2 end to end)

With `skip_success_page=1` and no `continue_success_url` in the request, the documentation
says the merchant-profile "Success URL for Web Continuation" is used. If that field is
**empty** on the sandbox merchant, ABA's popup closes in place after payment and Ayden's
own success screen follows; if it is **set**, the plugin navigates the page away. We
therefore ask ABA to confirm the profile value (see message).

## Message for the ABA Telegram group

> Hello ABA team, thank you for the review.
>
> We have updated https://preprod.aydenstudio.com with all four points:
> 1. Payment option now uses your official ABA logo and the description "ABA KHQR — Scan to pay with any banking app".
> 2. Our Purchase request now submits skip_success_page = 1, so your success page is skipped and only our own success screen is shown.
> 3. "ABA KHQR" has been removed from the header of our success screen.
> 4. Your official "We accept" logo is now in the website footer (Home, Projects and Profile pages).
>
> Check Transaction logic, as implemented:
> • Frequency: we do not call Check Transaction when the checkout is created. The first call is made about 3 seconds after the Purchase form is submitted, then every 3 seconds after each answer (about one call every 4 seconds in practice, measured 3.96 s). Our server also enforces a minimum of 3 seconds between two calls for the same tran_id; there is no retry burst.
> • Stop conditions: we stop on the first definitive answer — APPROVED (we verify amount and currency, credit the customer once, and mark the order granted), DECLINED / CANCELLED / REFUNDED (order failed), a "transaction not found" answer more than 30 seconds after checkout (order failed), the customer cancelling (one last check first), or our transaction lifetime expiring (one last check, then expired). Your pushback, once its signature is verified, triggers one immediate Check Transaction and settles the order on our side.
> • Maximum duration: 30 minutes per transaction (the lifetime we send in the Purchase request), i.e. at most about 450 calls per transaction. If the customer closes the browser, polling stops with it.
>
> One question for skip_success_page: our request sends no continue_success_url, so per your documentation the profile-level "Success URL for Web Continuation" applies. Could you confirm that this field is empty for our sandbox merchant (and will be for production), so that the checkout closes in place after payment?
>
> Preprod URL for your review: https://preprod.aydenstudio.com
> Thank you again — we look forward to your feedback.
