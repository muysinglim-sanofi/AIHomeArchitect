-- ROLLBACK for 20260918_cambodia_pack_pricing.sql.  NOT APPLIED.
--
-- Restores the prices the catalogue held before the Cambodia pricing change,
-- read off production on 2026-09-18 before anything was touched:
--
--   pack_10   1.99      pack_25   3.99
--   pack_50   6.99      pack_100 11.99
--
-- …and removes the two badges, because the rows carried `metadata = {}` — no
-- badge at all — before the change. Putting an empty string back instead would
-- render an empty pill.
--
-- `credits_granted` is, here as there, only ever a guard.

BEGIN;

UPDATE public.products SET price_usd = 1.99,  updated_at = now()
 WHERE sku = 'pack_10'  AND type = 'CREDIT_PACK' AND credits_granted = 10;

UPDATE public.products SET price_usd = 3.99,  updated_at = now()
 WHERE sku = 'pack_25'  AND type = 'CREDIT_PACK' AND credits_granted = 25;

UPDATE public.products SET price_usd = 6.99,  updated_at = now()
 WHERE sku = 'pack_50'  AND type = 'CREDIT_PACK' AND credits_granted = 50;

UPDATE public.products SET price_usd = 11.99, updated_at = now()
 WHERE sku = 'pack_100' AND type = 'CREDIT_PACK' AND credits_granted = 100;

UPDATE public.products
   SET metadata = coalesce(metadata, '{}'::jsonb) - 'badge',
       updated_at = now()
 WHERE sku IN ('pack_10', 'pack_25', 'pack_50', 'pack_100')
   AND type = 'CREDIT_PACK';

DO $$
DECLARE
  v_bad text;
BEGIN
  SELECT string_agg(sku || '=' || price_usd, ', ')
    INTO v_bad
    FROM public.products
   WHERE type = 'CREDIT_PACK'
     AND (sku, price_usd) NOT IN (
           ('pack_10',  1.99),
           ('pack_25',  3.99),
           ('pack_50',  6.99),
           ('pack_100', 11.99));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'ROLLBACK_NOT_AS_INTENDED: %', v_bad;
  END IF;
END $$;

COMMIT;
