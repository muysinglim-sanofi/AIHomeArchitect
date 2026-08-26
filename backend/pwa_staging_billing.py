"""PWA STAGING — the BILLING SEAM. A caller of the Billing Engine, not a copy.

What this module is
-------------------
`pwa_staging_api` is an ACCESS to the canonical generation engine. This is the
same idea for money: every decision below is made by the canonical modules —

    promo.resolve_generation_access   -> the TIER (admin / premium / promo / free)
    billing.reserve_decision          -> the indicative read-only gate
    billing.try_hold                  -> THE right to generate (atomic, per-user
                                         advisory lock, conditional HOLD)
    intent_observer.observe_intent_end-> the terminal transition, which itself
                                         calls billing.apply_billing_for_intent_
                                         transition (COMMIT / RELEASE)

There is no arithmetic in this file, no balance is computed here, no ledger row
is written here. What this file owns is exactly one thing the canonical modules
cannot know: **how a PWA generation maps onto a billing Intent.**

Intent ≠ Job (docs/GENERATION_INTENT_V1_SPEC.md)
------------------------------------------------
The PWA already had a durable single-flight for the RENDER:

    pwa_staging.claim_generation(idempotency_key, ...)   -- migration 0004

That is a JOB claim: it elects one renderer and survives a restart. It says
nothing about money. `generation_intents` carries the idempotence of the
BILLING, and the two are deliberately separate objects keyed off the SAME
logical operation:

    idempotency_key  --(sha256, stable)-->  intent_id  -->  hold:<intent_id>

Because the mapping is a pure function of (user, idempotency_key), every path
that reuses the key reuses the intent, and `billing_try_hold` is idempotent on
`hold:<intent_id>`. So:

    F5 while rendering          -> same key -> same intent -> no second hold
    retry after a transport error-> same key -> same intent -> no second hold
    backend restart + replay    -> same key -> same intent -> no second hold
    two concurrent submits      -> one claim winner; the advisory lock in the
                                   RPC serialises anything that gets past it

and the user cannot lose two credits for one Vision.

The ONE canonical anomaly, stated rather than hidden
----------------------------------------------------
`billing._decide` is a DIRECT projection: FAILED -> RELEASE(+1) unconditionally,
never a compensation that looks at the past. A generation that fails, releases,
and is then retried under the SAME intent therefore nets HOLD-RELEASE-COMMIT = 0
— the retry is free. That is documented canonical behaviour (billing.py module
docstring, "ANOMALIE CONNUE"), it errs toward the user, and reproducing it is
correct: inventing a compensation here would fork the billing brain, which is
the one thing this whole phase exists to avoid. `pwa_staging_billing_test.py`
pins it as a measured fact rather than an assumption.

Free tier
---------
D1 (PWA_MONETIZATION_AUDIT §6bis): ONE free generation per anonymous Web guest,
at FULL quality and FULL resolution, watermarked. The amount is not a constant
in this file — it is `billing.effective_trial_credits()`, i.e. the canonical
ON-mode trial, passed through to the RPC's `p_trial_credits`. `run_pwa_staging`
pins `ACCOUNT_SYSTEM_ENABLED=true` so that value is 1, and the DB contract test
asserts the TRIAL row that lands is +1.
"""
from __future__ import annotations

import hashlib
import logging
from dataclasses import dataclass
from typing import Optional

from fastapi import HTTPException

log = logging.getLogger("aih")

# `error_code` stays the CANONICAL one mobile already emits, so no client has to
# learn a second vocabulary for the same event. `billing_state` is the finer
# semantic the PWA localisation layer switches on (docs: backend returns codes,
# the client translates them).
_QUOTA_EXHAUSTED = "QUOTA_EXHAUSTED"

_BILLING_STATE = {
    "insufficient_credits": "FREE_EXHAUSTED",   # free bucket spent, no pass
    "pass_exhausted": "PASS_EXHAUSTED",         # a pass exists but is spent
    "no_active_pass": "PASS_REQUIRED",          # premium role, no measurable pass
}


@dataclass(frozen=True)
class PwaBillingContext:
    """Everything the render path needs to know about money, resolved once."""

    user_id: str
    intent_id: str
    tier: str              # the ROLE tier: admin | premium | promo_* | free
    is_free: bool          # consumes the free bucket (AccessDecision.consumes_free_quota)
    watermark: bool        # free tier -> the canonical mark is baked into the bytes
    free_credits: int
    pass_credits: int
    total_credits: int
    has_active_pass: bool

    @property
    def access_source(self) -> str:
        """WHY this person may generate — the vocabulary RC_PR3B_ENFORCEMENT
        settled on. `tier` alone is not the answer: it is the ROLE, and a role
        is features. A measured pass is what a purchase actually produces."""
        if self.has_active_pass:
            return "pass"
        if self.tier in ("admin", "premium", "promo_unlimited", "promo_limited"):
            return "entitlement"
        return "free"

    @property
    def public_state(self) -> dict:
        """The billing facts a client may see. No user_id, no intent id, no
        internal reason string — just what the UI needs to render a state."""
        return {
            "tier": self.tier,
            "access_source": self.access_source,
            "watermarked": self.watermark,
            "free_credits": self.free_credits,
            "pass_credits": self.pass_credits,
            "credits_available": self.total_credits,
            "has_active_pass": self.has_active_pass,
        }


def intent_id_for(user_id: str, idempotency_key: str) -> str:
    """The ONE mapping: (user, logical generation) -> billing intent.

    Deterministic, so a replay is the same intent; user-scoped, so two tenants
    can never collide on a key the browser chose; prefixed, so a row's origin is
    readable in the database without a join. 128 bits of digest — the mobile
    recipe truncates to 12 hex because it also had to fit a log line, which is
    not a constraint here.
    """
    digest = hashlib.sha256(
        f"pwa:{user_id}:{idempotency_key}".encode("utf-8")).hexdigest()[:32]
    return f"pwa:{digest}"


def _deny(reason: str, *, gate=None, hold: Optional[dict] = None) -> HTTPException:
    """A refusal the UI can act on, and that no localisation has to parse.

    Deliberately NOT a free-text message: §24 of the brief and the mobile
    contract agree that the backend emits a semantic code and the client
    translates it. `user_message` is kept because every other error payload in
    this adapter carries one and a client that ignores codes must still have
    something to show — but it is the fallback, not the interface.
    """
    state = _BILLING_STATE.get(reason, "FREE_EXHAUSTED")
    available = 0
    detail = {
        "error_code": _QUOTA_EXHAUSTED,
        "billing_state": state,
        "reason": reason,
        "paywall": "pass",
        "retryable": False,
        "render_started": False,
        "user_message": ("Your free vision has been used. Unlock Ayden Studio "
                         "to keep designing this space."),
    }
    if gate is not None:
        available = gate.total_credits
        detail.update({
            "wallet_available": gate.wallet_available,
            "free_credits": gate.free_credits,
            "pass_credits": gate.pass_credits,
            "credits_available": gate.total_credits,
            "has_active_pass": gate.has_active_pass,
        })
    elif hold is not None:
        available = int(hold.get("total_after") or 0)
        detail["wallet_available"] = available
        detail["credits_available"] = available
    return HTTPException(status_code=402, detail=detail)


async def resolve(user_id: str) -> tuple:
    """TIER + indicative balance, read-only, BEFORE anything is spent.

    Returns (AccessDecision, ReserveDecision). Both come from the canonical
    modules; this function only calls them in the canonical order.

    `resolve_generation_access` reads `usage_log` for a legacy `free_remaining`
    display figure. That table is deliberately absent here (§8.4: the free
    counter IS the ledger free bucket) and the canonical read fails open to 0,
    so the tier is unaffected. The warning it logs is truthful — the legacy
    counter really is not there — and is left rather than silenced.
    """
    import billing  # noqa: PLC0415 — lazy, mirrors main.py
    from promo import resolve_generation_access  # noqa: PLC0415

    decision = await resolve_generation_access(user_id)
    gate = await billing.reserve_decision(
        user_id=user_id,
        is_free=decision.consumes_free_quota,
        tier=decision.tier,
    )
    return decision, gate


async def open_gate(*, user_id: str, idempotency_key: str) -> PwaBillingContext:
    """The READ-ONLY gate. Raises 402 before ANY provider call — including the
    refine advisor, which is itself a paid gpt-4o call.

    This is deliberately stricter than mobile, which gates just before the
    render. The brief is explicit (Étape C): a visitor with no entitlement must
    be refused *before any OpenAI call*, so an exhausted guest cannot make the
    advisor loop cost money. Nothing is written here — the reservation happens
    after the durable claim, so no credit is ever held by a caller that does not
    own the operation.
    """
    decision, gate = await resolve(user_id=user_id)
    ctx = PwaBillingContext(
        user_id=user_id,
        intent_id=intent_id_for(user_id, idempotency_key),
        tier=decision.tier,
        is_free=decision.consumes_free_quota,
        # THE WATERMARK RULE, and it is not `not clean_watermark` alone.
        #
        # `resolve_generation_access` returns tier='free' for anyone without an
        # admin/premium ROLE — and buying a pass does not write a role. On
        # mobile the RevenueCat webhook writes `user_roles.premium` as a
        # SEPARATE event; on the Web there is no such webhook yet, and there
        # will not be one for ABA either. Marking on the role alone therefore
        # watermarked a customer who had just paid (measured, BILL05).
        #
        # RC_PR3B_ENFORCEMENT already settled the vocabulary for this exact
        # split: the ROLE grants FEATURES, the measured PASS proves the
        # PURCHASE. A clean image is a feature of having bought the product, so
        # either signal is sufficient — and only the absence of BOTH means free.
        watermark=not decision.clean_watermark and not gate.has_active_pass,
        free_credits=gate.free_credits,
        pass_credits=gate.pass_credits,
        total_credits=gate.total_credits,
        has_active_pass=gate.has_active_pass,
    )
    log.info("[pwa-billing] gate user=%s tier=%s source=%s free=%d pass=%d "
             "total=%d allow=%s reason=%s watermark=%s",
             user_id[:8], ctx.tier, ctx.access_source, gate.free_credits,
             gate.pass_credits, gate.total_credits, gate.allow,
             gate.reason or "-", ctx.watermark)
    if not gate.allow:
        raise _deny(gate.reason or "insufficient_credits", gate=gate)
    return ctx


async def reserve(ctx: PwaBillingContext, *, iteration: int, action_type: str,
                  idempotency_key: str) -> None:
    """THE reservation. Called ONLY by the winner of the durable claim.

    Two writes, in this order and no other:
      1. the canonical `generation_intents` row (RUNNING, `session_id = NULL`);
      2. `billing_try_hold` — atomic gate + HOLD under a per-user advisory lock.

    The intent row exists first because the HOLD references it
    (`reference_id = intent_id`) and because a terminal transition has to have
    something to transition. Both are idempotent, so a replay of the same
    logical generation re-enters here without a second row or a second debit.

    Raises 402 (paywall) or 503 (billing temporarily unavailable) — always
    BEFORE the provider call, so a refusal costs nothing.
    """
    import billing  # noqa: PLC0415
    from main import supa  # noqa: PLC0415 — the staging service-role client

    await _open_intent(supa, ctx, iteration=iteration, action_type=action_type,
                       idempotency_key=idempotency_key)

    hold = await billing.try_hold(
        user_id=ctx.user_id, intent_id=ctx.intent_id, tier=ctx.tier, supa=supa)
    if hold.get("granted"):
        log.info("[pwa-billing] HOLD granted intent=%s bucket=%s after=%s idem=%s",
                 ctx.intent_id, hold.get("bucket"), hold.get("total_after"),
                 hold.get("idempotent"))
        return

    reason = hold.get("reason") or "insufficient_credits"
    # The intent is RUNNING but nothing was reserved. Terminalise it so no
    # phantom RUNNING row is left behind, then refuse. `observe_intent_end`
    # writes RELEASE only if a HOLD exists — there is none, so this is a status
    # change and nothing else.
    await settle(ctx, succeeded=False, error={"error_code": "ATOMIC_DENY",
                                              "reason": reason})
    if reason == "atomic_hold_missing":
        # The RPC is not installed. That is an outage, not a paywall: never show
        # a person a purchase screen because a migration was not applied.
        log.error("[pwa-billing] billing_try_hold RPC ABSENT — apply "
                  "supabase/staging/pwa/0006_billing_canonical.sql")
        raise HTTPException(
            status_code=503,
            detail={"error_code": "BILLING_UNAVAILABLE",
                    "billing_state": "BILLING_UNAVAILABLE",
                    "user_message": "We're finishing an update. Please try again "
                                    "in a moment.",
                    "retryable": True, "render_started": False},
        )
    log.info("[pwa-billing] HOLD denied intent=%s reason=%s -> 402 before OpenAI",
             ctx.intent_id, reason)
    raise _deny(reason, hold=hold)


async def _open_intent(supa, ctx: PwaBillingContext, *, iteration: int,
                       action_type: str, idempotency_key: str) -> None:
    """The canonical intent row for this logical generation.

    `session_id` is NULL and always will be: the Web has no mobile chat session
    (PWA_MONETIZATION_AUDIT §8.3), and the link to the project is carried by
    `pwa_staging`. The `intent` jsonb keeps the canonical key names so the same
    dashboards read both platforms.

    Best-effort by design, exactly like the mobile observer: if this write
    fails, `billing_try_hold` still runs and is still the authority — the HOLD
    is what stops an unpaid render, not this row.
    """
    import asyncio  # noqa: PLC0415

    row = {
        "intent_id": ctx.intent_id,
        "user_id": ctx.user_id,
        "session_id": None,
        "iteration": iteration,
        "status": "RUNNING",
        "intent": {"surface": "pwa", "action": action_type, "tier": ctx.tier},
        "client_request_id": idempotency_key,
        "started_at": "now()",
    }
    try:
        res = await asyncio.to_thread(
            lambda: supa.table("generation_intents")
            .upsert(row, on_conflict="intent_id", ignore_duplicates=True)
            .execute()
        )
        fresh = bool(getattr(res, "data", None))
        log.info("[pwa-billing] intent %s intent_id=%s action=%s iter=%d",
                 "NEW" if fresh else "REPLAY", ctx.intent_id, action_type, iteration)
    except Exception as exc:  # noqa: BLE001 — the HOLD is the authority, not this
        log.warning("[pwa-billing] intent row write failed (swallowed) "
                    "intent=%s err=%s", ctx.intent_id, type(exc).__name__)


async def settle(ctx: PwaBillingContext, *, succeeded: bool,
                 result_ref: Optional[dict] = None,
                 error: Optional[dict] = None) -> None:
    """Close the intent, which is what commits or releases the credit.

    Delegates to `intent_observer.observe_intent_end`, the SAME function the
    mobile handler and the reconciliation worker call. It transitions the row
    and then calls `billing.apply_billing_for_intent_transition`, which writes
    COMMIT(0) or RELEASE(+1) into the SAME bucket the HOLD chose. Nothing about
    that decision is re-implemented here.

    Never raises: an accounting write must not turn a delivered image into an
    error the person sees.
    """
    from intent_observer import observe_intent_end  # noqa: PLC0415
    from main import supa  # noqa: PLC0415

    status = "SUCCEEDED" if succeeded else "FAILED"
    try:
        await observe_intent_end(
            ctx.intent_id, status,
            result_ref=result_ref, error=error,
            is_free=ctx.is_free, supa=supa)
        log.info("[pwa-billing] intent %s -> %s", ctx.intent_id, status)
    except Exception as exc:  # noqa: BLE001
        log.warning("[pwa-billing] settle failed (swallowed) intent=%s status=%s "
                    "err=%s", ctx.intent_id, status, type(exc).__name__)


# ── the catalogue, and the payment seam that is deliberately empty ───────────


def billing_state_for(reason: Optional[str]) -> str:
    """The client-facing code for a refusal reason. One mapping, one place."""
    return _BILLING_STATE.get(reason or "", "FREE_EXHAUSTED")


def _display_price(raw) -> Optional[float]:
    """A reference price from `metadata`, or None. Never raises, never guesses.

    `metadata` is free-form jsonb, so this is the boundary where a value someone
    typed by hand becomes a number — or does not. A malformed entry yields None
    and the row simply renders without a crossed-out price, which is the correct
    degradation: a missing discount badge is a cosmetic loss, and a catalogue
    read that 500s over a marketing field would take the whole paywall down.
    """
    if raw is None or raw == "":
        return None
    try:
        value = float(raw)
    except (TypeError, ValueError):
        return None
    # A reference price that is not above the real one is not a discount. Zero
    # and negatives are nonsense; equal is a "discount" of nothing.
    return value if value > 0 else None


async def catalogue() -> list:
    """The purchasable products, READ from the canonical `products` table.

    Never a constant in the client: `credits_granted` is what the Billing Engine
    will actually grant, and a Web build that disagreed with it would show a
    price for something else.

    HONEST NOTE, surfaced rather than hidden: the rows currently configured are
    the MOBILE store products (`apple_product_id` / `revenuecat_product_id` are
    set, `khqr_enabled` is true but no web provider exists yet). They are
    returned with `store_only: true` so the Paywall can say "not purchasable on
    the Web yet" instead of implying a Web checkout that does not exist. When
    ABA is wired, a web-purchasable product is a row in this table — not a new
    constant in Dart.
    """
    import asyncio  # noqa: PLC0415

    from main import supa  # noqa: PLC0415

    try:
        res = await asyncio.to_thread(
            lambda: supa.table("products")
            .select("sku, type, credits_granted, duration_days, price_usd, "
                    "currency, khqr_enabled, apple_product_id, "
                    "revenuecat_product_id, metadata")
            .eq("active", True).order("price_usd").execute()
        )
        rows = getattr(res, "data", None) or []
    except Exception as exc:  # noqa: BLE001 — a catalogue read must never 500 the screen
        log.warning("[pwa-billing] catalogue read failed: %s", type(exc).__name__)
        return []

    out = []
    for r in rows:
        store_only = bool(r.get("apple_product_id") or r.get("revenuecat_product_id"))
        meta = r.get("metadata") if isinstance(r.get("metadata"), dict) else {}
        out.append({
            "sku": r.get("sku"),
            "type": r.get("type"),
            "credits": r.get("credits_granted"),
            "duration_days": r.get("duration_days"),
            # THE payable price. The only number in this payload that any part
            # of the payment path reads.
            "price_usd": float(r["price_usd"]) if r.get("price_usd") is not None else None,
            "currency": r.get("currency") or "USD",
            # ── display-only, from `products.metadata` ──────────────────────
            #
            # `list_price_usd` is a CROSSED-OUT number: bigger than the price,
            # never charged, and read by nothing but a widget. It is carried in
            # a separate key from `price_usd` rather than as a second "price"
            # so that no caller can plausibly confuse the two, and the PayWay
            # amount is resolved by `pwa_staging_payments.resolve_web_product`
            # from `price_usd` alone — this payload is not even in that path.
            #
            # `badge` is a MACHINE code ('starter' / 'popular' / 'best_value'),
            # never a label. The client translates it, the same way it already
            # translates `billing_state` and `error_code`. A database is the one
            # place a translator will never look, so no English marketing word
            # is stored in one.
            "list_price_usd": _display_price(meta.get("list_price_usd")),
            "badge": str(meta.get("badge") or ""),
            # True when this row exists to be bought in an app store. The Web
            # cannot sell it until a web provider is configured for it.
            "store_only": store_only,
            "web_enabled": bool(r.get("khqr_enabled")) and not store_only,
        })
    return out


def payment_provider_id() -> str:
    """Which acquisition RAIL this deployment sells on. SERVER-owned.

    2026-08-18 — this used to be `PWA_PAYMENT_PROVIDER or 'none'`, a promise that
    the answer would come from the server the day a provider existed. That day
    arrived: `pwa_staging_payments.provider_id()` returns `khqr` when — and only
    when — real ABA PayWay sandbox credentials are present, and `none` otherwise.
    The environment variable still wins when set, which keeps it a kill switch.

    The value is the RAIL (`khqr`), not the gateway brand (`payway`), because
    that is what `orders.provider` means and what the client's vocabulary should
    match. The gateway is reported separately by `/pwa/staging/payments/config`.
    """
    import pwa_staging_payments  # noqa: PLC0415 — lazy: payments imports billing

    return pwa_staging_payments.provider_id()


def payment_provider_configured() -> bool:
    """Whether that rail can actually take money right now.

    Still false whenever credentials are absent, and it must stay that way: a
    Paywall that offers a purchase it cannot complete is worse than one that says
    payments are not open.
    """
    import pwa_staging_payments  # noqa: PLC0415

    return pwa_staging_payments.is_open()
