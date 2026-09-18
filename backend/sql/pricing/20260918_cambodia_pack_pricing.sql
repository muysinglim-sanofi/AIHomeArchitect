-- CAMBODIA PWA — one-time credit pack pricing.  NOT APPLIED.
--
-- WHY THIS IS SQL AND NOT CODE. The catalogue is `public.products`, and it is
-- the ONLY place a price exists: the client receives the catalogue and sends
-- back a sku, and `resolve_web_product` reads `price_usd` by that sku alone to
-- build the PayWay amount. There is no constant in Dart and none in Python, so
-- a price change is a data change — four rows — and nothing else.
--
-- WHAT CHANGES
--   pack_10   1.99 -> 2.50      badge: none
--   pack_25   3.99 -> 5.00      badge: popular      (MOST POPULAR)
--   pack_50   6.99 -> 8.00      badge: none
--   pack_100 11.99 -> 14.00     badge: best_value   (BEST VALUE)
--
-- WHAT DOES NOT CHANGE. `credits_granted` is untouched by every statement
-- below: the price a pack costs and the Spaces it grants are independent, and
-- this file may never blur that. Nor are `type`, `duration_days`, `active`,
-- `khqr_enabled`, the two store ids, or any row that is not one of these four
-- — `weekly_pass` and `annual_pass` are the mobile store's products and are
-- deliberately not addressed here.
--
-- The badge is DISPLAY ONLY. `catalogue()` passes `metadata.badge` through as a
-- machine code the client translates; nothing in the payment path reads it.
--
-- Guarded, idempotent, and safe to re-run: each UPDATE names its sku, asserts
-- the credits it expects to find, and would touch nothing if the catalogue were
-- not the one this file was written against.

BEGIN;

-- 1. Prices. `credits_granted` appears only in the WHERE clause — as a guard,
--    never as an assignment.
UPDATE public.products SET price_usd = 2.50,  updated_at = now()
 WHERE sku = 'pack_10'  AND type = 'CREDIT_PACK' AND credits_granted = 10;

UPDATE public.products SET price_usd = 5.00,  updated_at = now()
 WHERE sku = 'pack_25'  AND type = 'CREDIT_PACK' AND credits_granted = 25;

UPDATE public.products SET price_usd = 8.00,  updated_at = now()
 WHERE sku = 'pack_50'  AND type = 'CREDIT_PACK' AND credits_granted = 50;

UPDATE public.products SET price_usd = 14.00, updated_at = now()
 WHERE sku = 'pack_100' AND type = 'CREDIT_PACK' AND credits_granted = 100;

-- 2. Merchandising. Merged into `metadata` rather than replacing it, so any
--    other key the row may carry survives.
UPDATE public.products
   SET metadata = coalesce(metadata, '{}'::jsonb)
                  || jsonb_build_object('badge', 'popular'),
       updated_at = now()
 WHERE sku = 'pack_25' AND type = 'CREDIT_PACK';

UPDATE public.products
   SET metadata = coalesce(metadata, '{}'::jsonb)
                  || jsonb_build_object('badge', 'best_value'),
       updated_at = now()
 WHERE sku = 'pack_100' AND type = 'CREDIT_PACK';

-- 3. The other two carry no badge. Removing the key is deliberate: an empty
--    string would render an empty pill.
UPDATE public.products
   SET metadata = coalesce(metadata, '{}'::jsonb) - 'badge',
       updated_at = now()
 WHERE sku IN ('pack_10', 'pack_50') AND type = 'CREDIT_PACK';

-- 4. Refuse the whole thing unless the catalogue now reads exactly as intended.
DO $$
DECLARE
  v_bad text;
BEGIN
  SELECT string_agg(sku || '=' || price_usd || '/' || credits_granted, ', ')
    INTO v_bad
    FROM public.products
   WHERE type = 'CREDIT_PACK'
     AND (sku, price_usd, credits_granted) NOT IN (
           ('pack_10',  2.50,  10),
           ('pack_25',  5.00,  25),
           ('pack_50',  8.00,  50),
           ('pack_100', 14.00, 100));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CATALOGUE_NOT_AS_INTENDED: %', v_bad;
  END IF;
END $$;

COMMIT;
