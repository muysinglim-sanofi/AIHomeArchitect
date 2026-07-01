-- ============================================================
-- Billing Engine — PR0 : schéma dormant
-- Paste into: Supabase Dashboard → SQL Editor → Run
-- ============================================================
--
-- Spec : docs/BILLING_ENGINE_SPEC.md (§4 data model, §4.0 modèle d'événements).
--
-- ADDITIF + DORMANT. Crée les 6 objets du coffre-fort + le seed du catalogue.
-- AUCUN code applicatif ne les lit/écrit encore. Zéro impact runtime, zéro
-- changement dans /generate, AUCUN hook billing branché (ça vient plus tard).
--
-- Lecture event-first (spec §4.0) :
--   ledger_entries = LE JOURNAL D'ÉVÉNEMENTS du crédit (append-only).
--   wallets        = projection recalculable du ledger (cache).
--   products       = ce qui peut être acquis (catalogue configurable).
--   orders/payments= flux d'acquisition entrant (idempotent par provider tx).
--   passes         = droit temporel (fenêtre de validité).
--
-- Garde-fous DB posés dès maintenant (avant toute donnée réelle) :
--   • ledger_entries : APPEND-ONLY physique — service_role n'a que SELECT+INSERT
--     (ni UPDATE ni DELETE) → « aucun crédit supprimé » (règle R3) au niveau
--     privilège. Corrections = écritures compensatoires.
--   • idempotence dure : UNIQUE(provider, provider_transaction_id) sur payments ;
--     UNIQUE(idempotency_key) sur ledger_entries ; UNIQUE(idempotency_key) sur orders.
--   • CHECK sur tous les enums de statut/type + montants/crédits >= 0.
--
-- Rollback :
--   drop table if exists public.wallets;
--   drop table if exists public.ledger_entries;
--   drop table if exists public.passes;
--   drop table if exists public.payments;
--   drop table if exists public.orders;
--   drop table if exists public.products;
--   drop function if exists public.billing_set_updated_at();
-- ============================================================


-- ── updated_at générique (billing) ───────────────────────────
create or replace function public.billing_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;


-- ── products (catalogue configurable) ────────────────────────
-- « Ce qui peut être acquis. » Prix mobile réel = stores (price_usd indicatif).
create table if not exists public.products (
  id                     uuid        primary key default gen_random_uuid(),
  sku                    text        not null unique,
  type                   text        not null check (type in ('PASS', 'CREDIT_PACK')),
  credits_granted        int         not null check (credits_granted >= 0),
  duration_days          int         check (duration_days is null or duration_days > 0),  -- NULL pour les packs
  price_usd              numeric(10, 2),   -- indicatif (vérité mobile = stores)
  currency               text        not null default 'USD',
  revenuecat_product_id  text,
  apple_product_id       text,
  google_product_id      text,
  khqr_enabled           boolean     not null default false,
  metadata               jsonb       not null default '{}'::jsonb,  -- hook promo/pays (non interprété en V1)
  active                 boolean     not null default true,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

drop trigger if exists trg_products_updated_at on public.products;
create trigger trg_products_updated_at before update on public.products
  for each row execute function public.billing_set_updated_at();

alter table public.products enable row level security;
drop policy if exists "products: active read" on public.products;
create policy "products: active read" on public.products
  for select using (active);   -- catalogue : tout le monde (authentifié) voit les produits actifs


-- ── orders ───────────────────────────────────────────────────
-- Une commande, créée AVANT paiement (règle R1 : le paiement n'accorde jamais
-- directement des crédits ; il crée une transaction que l'Engine traite).
create table if not exists public.orders (
  id                uuid        primary key default gen_random_uuid(),
  user_id           uuid        not null references auth.users(id) on delete cascade,
  product_id        uuid        not null references public.products(id),
  status            text        not null
                                check (status in ('PENDING', 'PAID', 'FAILED', 'CANCELLED', 'REFUNDED'))
                                default 'PENDING',
  provider          text        not null check (provider in ('revenuecat', 'khqr')),
  amount            numeric(10, 2),
  currency          text        not null default 'USD',
  idempotency_key   text        unique,   -- dédup création d'ordre
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index if not exists orders_user_idx on public.orders(user_id);
create index if not exists orders_status_idx on public.orders(status) where status = 'PENDING';

drop trigger if exists trg_orders_updated_at on public.orders;
create trigger trg_orders_updated_at before update on public.orders
  for each row execute function public.billing_set_updated_at();

alter table public.orders enable row level security;
drop policy if exists "orders: owner read" on public.orders;
create policy "orders: owner read" on public.orders
  for select using (auth.uid() = user_id);


-- ── payments (Flux 1 entrant — idempotent) ───────────────────
-- `PurchaseCompleted`. UNIQUE(provider, provider_transaction_id) = clé
-- d'idempotence paiement (webhook rejoué 2× → no-op). Table sensible :
-- service-role uniquement (pas de lecture client).
create table if not exists public.payments (
  id                       uuid        primary key default gen_random_uuid(),
  order_id                 uuid        references public.orders(id) on delete set null,
  provider                 text        not null check (provider in ('revenuecat', 'khqr')),
  provider_transaction_id  text        not null,
  status                   text        not null
                                       check (status in ('SUCCESS', 'FAILED', 'PENDING', 'REFUNDED')),
  amount                   numeric(10, 2),
  currency                 text,
  raw_payload              jsonb,      -- audit
  received_at              timestamptz not null default now(),
  unique (provider, provider_transaction_id)
);

create index if not exists payments_order_idx on public.payments(order_id);

alter table public.payments enable row level security;
-- Aucune policy authenticated → lecture client interdite ; service_role bypass RLS.


-- ── passes (droit temporel) ──────────────────────────────────
-- `PassGranted`. « actif » dérivé = status=ACTIVE AND now() BETWEEN starts/ends.
create table if not exists public.passes (
  id               uuid        primary key default gen_random_uuid(),
  user_id          uuid        not null references auth.users(id) on delete cascade,
  product_id       uuid        not null references public.products(id),
  source_order_id  uuid        references public.orders(id) on delete set null,
  starts_at        timestamptz not null,
  ends_at          timestamptz not null,
  status           text        not null
                               check (status in ('ACTIVE', 'EXPIRED', 'CANCELLED'))
                               default 'ACTIVE',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index if not exists passes_user_idx on public.passes(user_id);
-- Sweep expiry : les Pass ACTIVE dont ends_at est passé.
create index if not exists passes_active_expiry_idx
  on public.passes(status, ends_at) where status = 'ACTIVE';

drop trigger if exists trg_passes_updated_at on public.passes;
create trigger trg_passes_updated_at before update on public.passes
  for each row execute function public.billing_set_updated_at();

alter table public.passes enable row level security;
drop policy if exists "passes: owner read" on public.passes;
create policy "passes: owner read" on public.passes
  for select using (auth.uid() = user_id);


-- ── ledger_entries (LE JOURNAL D'ÉVÉNEMENTS — append-only) ───
-- Cœur du système (spec §4.5/§4.0). Une ligne = un événement crédit.
-- id bigint séquentiel : l'ORDRE est la vérité. available_delta signé (§4.6).
-- idempotency_key = garantie anti-doublon (ex. "hold:<intent_id>",
-- "commit:<intent_id>", "grant:order:<order_id>").
create table if not exists public.ledger_entries (
  id                bigint      generated always as identity primary key,
  user_id           uuid        not null references auth.users(id) on delete cascade,
  entry_type        text        not null
                                check (entry_type in
                                  ('GRANT', 'HOLD', 'COMMIT', 'RELEASE',
                                   'REFUND', 'ADJUSTMENT', 'EXPIRE', 'TRIAL')),
  available_delta   int         not null,   -- effet sur le solde disponible (§4.6)
  pass_id           uuid        references public.passes(id) on delete set null,  -- crédit scoppé (expire avec le Pass)
  reference_type    text        check (reference_type in ('ORDER', 'GENERATION_INTENT', 'ADMIN', 'PROMO')),
  reference_id      text,       -- order_id | intent_id | …
  idempotency_key   text        not null unique,   -- ← anti-doublon DUR
  metadata          jsonb       not null default '{}'::jsonb,
  created_at        timestamptz not null default now()
);

create index if not exists ledger_user_idx on public.ledger_entries(user_id);
create index if not exists ledger_user_created_idx on public.ledger_entries(user_id, id);
create index if not exists ledger_reference_idx on public.ledger_entries(reference_type, reference_id);

alter table public.ledger_entries enable row level security;
drop policy if exists "ledger: owner read" on public.ledger_entries;
create policy "ledger: owner read" on public.ledger_entries
  for select using (auth.uid() = user_id);
-- APPEND-ONLY : voir les grants plus bas — service_role n'a QUE SELECT+INSERT.


-- ── wallets (projection recalculable du ledger) ──────────────
-- N'EST PAS la source de vérité (le ledger l'est). Cache pour lecture rapide
-- du gate de génération / de l'UI. ledger_version = dernier ledger_entries.id
-- appliqué (permet le recompute).
create table if not exists public.wallets (
  user_id           uuid        primary key references auth.users(id) on delete cascade,
  available_credits int         not null default 0,
  held_credits      int         not null default 0,
  active_pass_id    uuid        references public.passes(id) on delete set null,
  pass_expires_at   timestamptz,
  ledger_version    bigint      not null default 0,
  updated_at        timestamptz not null default now()
);

drop trigger if exists trg_wallets_updated_at on public.wallets;
create trigger trg_wallets_updated_at before update on public.wallets
  for each row execute function public.billing_set_updated_at();

alter table public.wallets enable row level security;
drop policy if exists "wallets: owner read" on public.wallets;
create policy "wallets: owner read" on public.wallets
  for select using (auth.uid() = user_id);


-- ── Table-level privilege grants ─────────────────────────────
-- Comme Wave 5.17b / Intent PR0 : RLS filtre les lignes mais NE donne PAS le
-- privilège table-level. On accorde explicitement. anon : RIEN.
--
-- ⚠️ ledger_entries : service_role a SELECT + INSERT UNIQUEMENT (append-only).
--    Pas d'UPDATE, pas de DELETE → « aucun crédit supprimé » (R3) physique.

grant select, insert, update on public.products       to service_role;
grant select, insert, update on public.orders         to service_role;
grant select, insert, update on public.payments       to service_role;
grant select, insert, update on public.passes         to service_role;
grant select, insert         on public.ledger_entries to service_role;   -- APPEND-ONLY
grant select, insert, update on public.wallets        to service_role;

grant select on public.products       to authenticated;
grant select on public.orders         to authenticated;
grant select on public.passes         to authenticated;
grant select on public.ledger_entries to authenticated;
grant select on public.wallets        to authenticated;
-- payments : PAS de grant authenticated (sensible).


-- ── Seed du catalogue (figé — spec §2.1) ─────────────────────
-- Données inertes (aucun lecteur en PR0). Les *_product_id (RevenueCat/Apple/
-- Google) sont NULL pour l'instant → à remplir quand les produits store seront
-- créés. Prix indicatifs ; la vérité mobile vient des stores.
insert into public.products (sku, type, credits_granted, duration_days, price_usd, khqr_enabled) values
  ('weekly_pass', 'PASS',        60,  7,   7.99,  true),
  ('annual_pass', 'PASS',        300, 365, 79.00, true),
  ('pack_10',     'CREDIT_PACK', 10,  null, 1.99, true),
  ('pack_25',     'CREDIT_PACK', 25,  null, 3.99, true),
  ('pack_50',     'CREDIT_PACK', 50,  null, 6.99, true),
  ('pack_100',    'CREDIT_PACK', 100, null, 11.99, true)
on conflict (sku) do nothing;


-- ── Sanity-check queries ─────────────────────────────────────
--   select sku, type, credits_granted, duration_days, price_usd from public.products order by price_usd;
--     -- attendu : 6 lignes (weekly/annual + 4 packs)
--   select count(*) from public.ledger_entries;   -- 0
--   select count(*) from public.wallets;           -- 0
--
-- RLS activé partout :
--   select relname, relrowsecurity from pg_class
--     where relname in ('products','orders','payments','passes','ledger_entries','wallets');
--     -- relrowsecurity = true partout
--
-- APPEND-ONLY du ledger (service_role ne doit PAS avoir update/delete) :
--   select privilege_type from information_schema.role_table_grants
--     where table_name = 'ledger_entries' and grantee = 'service_role';
--     -- attendu : SELECT, INSERT uniquement (ni UPDATE ni DELETE)


-- ============================================================
-- Fin PR0 Billing (schéma dormant). Prochain : brancher les événements
-- (reserve/commit/release) sur les transitions Intent — /generate ET PR4.
-- ============================================================
