-- ═══════════════════════════════════════════════════════════════════════════
-- RC-PR2 · Ticket 0 — Fige le mapping store → product dans le repo
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CONTEXTE. Le seed du catalogue (20260701_billing_engine_pr0_schema.sql:276)
-- laisse volontairement products.{revenuecat,apple,google}_product_id à NULL.
-- Le mapping des 2 Pass a ensuite été appliqué MANUELLEMENT en Supabase prod
-- (2026-07-08) — donc le runtime prod est déjà correct. MAIS le repo ne
-- persiste pas ce mapping : toute base recréée (staging, CI, nouvelle prod)
-- repartirait avec des colonnes NULL → le webhook RC-PR2 ne pourrait plus
-- résoudre product_id → crédits. Cette migration PERSISTE le mapping.
--
-- PORTÉE STRICTE. Met à jour UNIQUEMENT products.{apple,revenuecat}_product_id
-- des SKU 'weekly_pass' et 'annual_pass'. Ne touche à AUCUNE autre colonne,
-- AUCUNE autre ligne, AUCUNE autre table. Aucun code applicatif ne lit encore
-- products avant RC-PR2 → impact runtime = néant (fige l'état prod existant).
--
-- IDEMPOTENTE. UPDATE ciblé par sku, ré-exécutable sans effet de bord :
-- rejouée, elle réécrit les mêmes valeurs. Aucun INSERT (les lignes existent
-- déjà via le seed PR0, garanties par `on conflict (sku) do nothing`).
--
-- IDs store (source de vérité = App Store Connect / dashboard RevenueCat) :
--   weekly_pass → com.aydenstudio.app.weekly
--   annual_pass → com.aydenstudio.app.annual
-- google_product_id reste NULL (Android non configuré à ce stade).
-- ═══════════════════════════════════════════════════════════════════════════

update public.products
   set apple_product_id      = 'com.aydenstudio.app.weekly',
       revenuecat_product_id = 'com.aydenstudio.app.weekly'
 where sku = 'weekly_pass';

update public.products
   set apple_product_id      = 'com.aydenstudio.app.annual',
       revenuecat_product_id = 'com.aydenstudio.app.annual'
 where sku = 'annual_pass';

-- ── Sanity-check (à exécuter à la main après migration) ──────────────────────
--   select sku, apple_product_id, revenuecat_product_id
--     from public.products
--    where sku in ('weekly_pass', 'annual_pass');
--   attendu :
--     weekly_pass | com.aydenstudio.app.weekly | com.aydenstudio.app.weekly
--     annual_pass | com.aydenstudio.app.annual | com.aydenstudio.app.annual
