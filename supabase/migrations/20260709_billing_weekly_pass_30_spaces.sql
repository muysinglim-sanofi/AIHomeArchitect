-- ============================================================================
-- Billing — Weekly pass = 30 spaces  (décision produit 2026-07-09)
-- ============================================================================
-- Aligne le montant crédité par un achat weekly_pass sur la nouvelle offre
-- produit : 30 « spaces » (au lieu de 60). L'annual_pass reste à 300.
--
-- Chemin actif vérifié : billing.grant_purchase lit products.credits_granted
-- (SELECT id, type, credits_granted, duration_days) et le passe au RPC
-- billing_grant_purchase (p_credits). Changer cette valeur suffit — aucun
-- montant n'est codé en dur côté backend ni webhook.
--
-- NE TOUCHE PAS l'historique :
--   • les entrées ledger GRANT déjà émises (anciens weekly à 60) restent
--     telles quelles — cette migration ne modifie que la table `products` ;
--   • les nouveaux achats weekly créditeront +30 à partir de maintenant.
--
-- Idempotente : réexécutable sans effet de bord (0 ligne au 2ᵉ passage grâce
-- au guard `is distinct from`).
-- ============================================================================

update public.products
   set credits_granted = 30
 where sku = 'weekly_pass'
   and credits_granted is distinct from 30;

-- ── Vérification ────────────────────────────────────────────────────────────
--   select sku, type, credits_granted, duration_days, price_usd
--     from public.products
--    where sku in ('weekly_pass', 'annual_pass')
--    order by price_usd;
--   Attendu :
--     weekly_pass | PASS | 30  | 7   | 7.99
--     annual_pass | PASS | 300 | 365 | 79.99
