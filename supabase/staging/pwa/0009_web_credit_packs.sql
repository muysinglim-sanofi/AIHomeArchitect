-- ============================================================================
-- AYDEN STUDIO PWA — the CAMBODIA WEB catalogue: 10 / 30 / 300 spaces
-- 0009 — additive + idempotent.  Schema: public.  STAGING ONLY.
-- ----------------------------------------------------------------------------
-- THE COMMERCIAL DECISION (2026-08-26), and nothing else
--
--     STARTER      10 spaces   $4.99
--     POPULAR      30 spaces   $7.99
--     BEST VALUE  300 spaces  $47.99   (shown against $79.99, 40% off)
--
--   Three finite-credit packs. There is no "unlimited" product and no unlimited
--   entitlement anywhere in this file — `credits_granted` is a positive integer
--   for all three, which is the only shape the Billing Engine can grant.
--
-- WHERE THE MARKETING NUMBER LIVES, AND WHY IT IS NOT A PRICE COLUMN
--
--   `$79.99` is a CROSSED-OUT number. It is not payable, it is not what ABA is
--   asked to charge, and giving it a column next to `price_usd` would create two
--   plausible answers to "what does this cost" one join away from the payment
--   path. That is exactly the mistake worth engineering against.
--
--   `products.metadata jsonb` already exists (billing PR0 schema, default '{}'),
--   and NOTHING in the billing path reads it — verified across billing.py, the
--   seam, and every migration in this repository. So it is the honest home for
--   display-only product data:
--
--       metadata->>'list_price_usd'   the crossed-out reference price
--       metadata->>'badge'            a MACHINE code the client translates
--
--   The discount percentage is deliberately NOT stored. It is derived from the
--   two prices at render time, so a displayed "40% OFF" can never disagree with
--   the numbers beside it. A third stored number is a third thing to drift.
--
--   `badge` is a code ('starter' / 'popular' / 'best_value'), never a label.
--   The client translates it into Khmer, English and French — the same rule the
--   rest of this product already follows for `billing_state` and `error_code`.
--   Storing the English word "POPULAR" in a database would be storing an
--   untranslated string in the one place no translator will ever look.
--
-- WHAT THIS FILE MUST NOT TOUCH, and asserts it did not
--
--   `weekly_pass` and `annual_pass` carry Apple / RevenueCat product ids. They
--   are sold BY THE APP STORES, their pricing is agreed with Apple, and their
--   entitlement is granted by the RevenueCat webhook. ABA PayWay is web-only and
--   this catalogue change is web-only. §"IOS / REVENUECAT PROTECTION" of the
--   brief is enforced at the bottom of this file by a DO block that raises if
--   either row moved.
--
-- WHAT HAPPENS TO THE PACKS BEING RETIRED
--
--   `pack_25` / `pack_50` / `pack_100` become `active = false`. NOT deleted:
--   54 orders reference `products(id)` and history must stay readable. Inactive
--   is also exactly what the existing code already understands — `catalogue()`
--   and `resolve_web_product()` both filter on `active = true` — so a retired
--   pack disappears from the paywall and can no longer be bought, with no new
--   concept invented for it.
-- ============================================================================

-- ── 1. STARTER — 10 spaces, $4.99 ───────────────────────────────────────────
-- The row already exists at $1.99. Repricing a product is an UPDATE of
-- `price_usd`; the 54 historical orders keep their own `orders.amount`, which is
-- stamped per order precisely so a price change never rewrites what someone paid.
update public.products
   set price_usd = 4.99,
       metadata  = coalesce(metadata, '{}'::jsonb) || '{"badge":"starter"}'::jsonb,
       active    = true,
       khqr_enabled = true,
       updated_at = now()
 where sku = 'pack_10';

-- ── 2. POPULAR — 30 spaces, $7.99 ───────────────────────────────────────────
-- A NEW row. `weekly_pass` also grants 30 spaces at $7.99 and is deliberately
-- NOT reused: it is a 7-day PASS sold in the app stores. This is a perpetual
-- CREDIT_PACK sold on the web. Same numbers, different products, and merging
-- them would put ABA PayWay inside an Apple-managed subscription.
insert into public.products
  (sku, type, credits_granted, duration_days, price_usd, currency, khqr_enabled,
   active, metadata)
values
  ('pack_30', 'CREDIT_PACK', 30, null, 7.99, 'USD', true, true,
   '{"badge":"popular"}'::jsonb)
on conflict (sku) do update
   set credits_granted = excluded.credits_granted,
       price_usd       = excluded.price_usd,
       khqr_enabled    = excluded.khqr_enabled,
       active          = excluded.active,
       metadata        = coalesce(public.products.metadata, '{}'::jsonb)
                         || excluded.metadata,
       updated_at      = now();

-- ── 3. BEST VALUE — 300 spaces, $47.99 (ref $79.99, 40% off) ────────────────
-- `price_usd` is 47.99. That is the number `resolve_web_product` reads, the
-- number the PayWay Purchase request is signed with, and the number the customer
-- is charged. 79.99 lives in `metadata` and is read by nothing but a widget.
insert into public.products
  (sku, type, credits_granted, duration_days, price_usd, currency, khqr_enabled,
   active, metadata)
values
  ('pack_300', 'CREDIT_PACK', 300, null, 47.99, 'USD', true, true,
   '{"badge":"best_value","list_price_usd":79.99}'::jsonb)
on conflict (sku) do update
   set credits_granted = excluded.credits_granted,
       price_usd       = excluded.price_usd,
       khqr_enabled    = excluded.khqr_enabled,
       active          = excluded.active,
       metadata        = coalesce(public.products.metadata, '{}'::jsonb)
                         || excluded.metadata,
       updated_at      = now();

-- ── 4. Retire the packs the catalogue no longer offers ──────────────────────
update public.products
   set active = false, updated_at = now()
 where sku in ('pack_25', 'pack_50', 'pack_100')
   and active;

-- ── 5. There is no unlimited product, and this proves it ────────────────────
-- Not a comment: an assertion. "Unlimited" is a concept the Billing Engine
-- cannot express — every grant is `p_credits int` — and the cheapest way to keep
-- it that way is to fail loudly if a row ever claims otherwise.
do $$
declare
  v_bad int;
begin
  select count(*) into v_bad
    from public.products
   where active
     and (credits_granted is null or credits_granted <= 0
          or coalesce(metadata->>'unlimited', 'false') <> 'false');
  if v_bad > 0 then
    raise exception 'REFUSING: % active product(s) claim an unlimited or '
                    'non-positive entitlement. Every pack must grant a finite '
                    'number of spaces.', v_bad;
  end if;
end $$;

-- ── 6. The app-store products did not move ──────────────────────────────────
-- The iOS / RevenueCat protection, enforced rather than promised.
do $$
declare
  v_weekly record;
  v_annual record;
begin
  select credits_granted, duration_days, price_usd, apple_product_id, active
    into v_weekly from public.products where sku = 'weekly_pass';
  select credits_granted, duration_days, price_usd, apple_product_id, active
    into v_annual from public.products where sku = 'annual_pass';

  if v_weekly.credits_granted <> 30 or v_weekly.duration_days <> 7
     or v_weekly.price_usd <> 7.99
     or v_weekly.apple_product_id <> 'com.aydenstudio.app.weekly'
     or not v_weekly.active then
    raise exception 'REFUSING: weekly_pass was modified. It is an App Store '
                    'product and this is a web-only catalogue change.';
  end if;

  if v_annual.credits_granted <> 300 or v_annual.duration_days <> 365
     or v_annual.price_usd <> 79.99
     or v_annual.apple_product_id <> 'com.aydenstudio.app.annual'
     or not v_annual.active then
    raise exception 'REFUSING: annual_pass was modified. It is an App Store '
                    'product and this is a web-only catalogue change.';
  end if;
end $$;

-- ── 7. The web catalogue is exactly the three packs ─────────────────────────
do $$
declare
  v_skus text;
begin
  select string_agg(sku || '=' || credits_granted || '@' || price_usd, ', '
                    order by price_usd)
    into v_skus
    from public.products
   where active and khqr_enabled
     and apple_product_id is null and revenuecat_product_id is null;
  if v_skus is distinct from
     'pack_10=10@4.99, pack_30=30@7.99, pack_300=300@47.99' then
    raise exception 'REFUSING: the web-sellable catalogue is "%" — expected '
                    'pack_10=10@4.99, pack_30=30@7.99, pack_300=300@47.99',
                    v_skus;
  end if;
end $$;
