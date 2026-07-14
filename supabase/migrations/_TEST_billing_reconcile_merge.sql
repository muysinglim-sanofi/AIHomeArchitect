-- ─────────────────────────────────────────────────────────────────────────────
-- _TEST_billing_reconcile_merge.sql — VALIDATION du Commit 5a (déterministe)
-- ─────────────────────────────────────────────────────────────────────────────
-- SQL PUR self-asserting. Rôle privilégié (postgres/service_role) sur une BASE DE TEST /
-- STAGING JETABLE — jamais en production. Chaque scénario est en BEGIN…ROLLBACK : toutes
-- les fixtures (products, passes, ledger, identity_merges, user_roles, orders, payments,
-- wallets) sont annulées. Le ledger est append-only (INSERT ok ; le ROLLBACK annule les
-- INSERT — ce n'est pas un DELETE, le trigger ne s'y oppose pas).
-- Prérequis : migrations Commit 1/2 + billing PR0 + 20260715_billing_reconcile_merge
-- appliquées ; 2 comptes de test dans auth.users : A et B (n'importe quel type).
-- ─────────────────────────────────────────────────────────────────────────────

-- ⟵ REMPLACER par les UUID de tes 2 comptes de TEST staging :
select set_config('bill5a.a', '00000000-0000-0000-0000-0000000000aa', false);  -- A (source)
select set_config('bill5a.b', '00000000-0000-0000-0000-0000000000bb', false);  -- B (cible)

do $$
declare v_a uuid := current_setting('bill5a.a')::uuid;
        v_b uuid := current_setting('bill5a.b')::uuid;
begin
  if v_a = '00000000-0000-0000-0000-0000000000aa' or v_b = '00000000-0000-0000-0000-0000000000bb' then
    raise exception 'Remplace bill5a.a / bill5a.b par de vrais UUID staging';
  end if;
  if not exists (select 1 from auth.users where id = v_a) then raise exception 'A doit exister dans auth.users'; end if;
  if not exists (select 1 from auth.users where id = v_b) then raise exception 'B doit exister dans auth.users'; end if;
  if v_a = v_b then raise exception 'A et B doivent être distincts'; end if;
  raise notice 'Garde OK : A=% B=%', v_a, v_b;
end $$;


-- ══════════ 1. A 1 pass net>0, B 0 → transfert complet + conservation + rôles ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5a.a')::uuid; v_b uuid := current_setting('bill5a.b')::uuid;
        v_prod uuid; v_pass uuid; v_mid uuid; v_status text; v_fc text;
        v_before int; v_after int; v_wa int; v_wb int;
begin
  insert into public.products(sku, type, credits_granted, duration_days)
    values ('t5a-'||substr(gen_random_uuid()::text,1,8), 'PASS', 30, 7) returning id into v_prod;
  insert into public.passes(user_id, product_id, starts_at, ends_at, status)
    values (v_a, v_prod, now()-interval '1 day', now()+interval '6 days', 'ACTIVE') returning id into v_pass;
  insert into public.ledger_entries(user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
    values (v_a, 'GRANT', 30, v_pass, 'ORDER', 'o1', 't5a:grant:'||v_pass::text);
  insert into public.user_roles(user_id, role, granted_by, expires_at)
    values (v_a, 'premium', v_a, now()+interval '6 days');
  insert into public.identity_merges(from_user_id, to_user_id, status)
    values (v_a, v_b, 'billing_reconciliation_pending') returning merge_id into v_mid;

  select coalesce(sum(available_delta),0) into v_before from public.ledger_entries where user_id in (v_a, v_b);
  select status, failure_code into v_status, v_fc from public.billing_reconcile_merge(v_mid);

  if v_status <> 'revocation_pending' or v_fc is not null then raise exception '1: statut %/%', v_status, v_fc; end if;
  if not exists (select 1 from public.passes where id=v_pass and user_id=v_b) then raise exception '1: pass non déplacé vers B'; end if;
  if not exists (select 1 from public.ledger_entries where idempotency_key='merge:'||v_mid::text||':debit'
                  and user_id=v_a and available_delta=-30 and reference_type='MERGE' and reference_id=v_mid::text) then
    raise exception '1: écriture debit A manquante/incorrecte'; end if;
  if not exists (select 1 from public.ledger_entries where idempotency_key='merge:'||v_mid::text||':credit'
                  and user_id=v_b and available_delta=30 and reference_type='MERGE' and reference_id=v_mid::text) then
    raise exception '1: écriture credit B manquante/incorrecte'; end if;
  select coalesce(sum(available_delta),0) into v_after from public.ledger_entries where user_id in (v_a, v_b);
  if v_after <> v_before then raise exception '1: somme globale ledger changée % → %', v_before, v_after; end if;
  select available_credits into v_wb from public.wallets where user_id=v_b;
  if coalesce(v_wb,-1) <> 30 then raise exception '1: wallet B=% (attendu 30)', v_wb; end if;
  select available_credits into v_wa from public.wallets where user_id=v_a;
  if coalesce(v_wa,-1) <> 0 then raise exception '1: wallet A=% (attendu 0, pas de crédit du pass)', v_wa; end if;
  if not exists (select 1 from public.user_roles where user_id=v_b and role='premium'
                  and (expires_at is null or expires_at > now())) then raise exception '1: premium B non actif'; end if;
  if exists (select 1 from public.user_roles where user_id=v_a and role='premium'
              and (expires_at is null or expires_at > now())) then raise exception '1: premium A encore actif'; end if;
  raise notice '1 OK';
end $$;
rollback;


-- ══════════ 1b. user_roles : B illimité NON raccourci · A (sans rôle) → UPSERT crée une ligne INACTIVE ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5a.a')::uuid; v_b uuid := current_setting('bill5a.b')::uuid;
        v_prod uuid; v_pass uuid; v_mid uuid; v_status text;
begin
  insert into public.products(sku, type, credits_granted, duration_days)
    values ('t5a-'||substr(gen_random_uuid()::text,1,8), 'PASS', 30, 7) returning id into v_prod;
  insert into public.passes(user_id, product_id, starts_at, ends_at, status)
    values (v_a, v_prod, now()-interval '1 day', now()+interval '6 days', 'ACTIVE') returning id into v_pass;
  insert into public.ledger_entries(user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
    values (v_a, 'GRANT', 30, v_pass, 'ORDER', 'o1', 't5a:grant:'||v_pass::text);
  -- B a un premium ILLIMITÉ (expires_at NULL) ; A n'a AUCUN rôle premium.
  insert into public.user_roles(user_id, role, granted_by, expires_at) values (v_b, 'premium', v_b, null);
  insert into public.identity_merges(from_user_id, to_user_id, status)
    values (v_a, v_b, 'billing_reconciliation_pending') returning merge_id into v_mid;

  select status into v_status from public.billing_reconcile_merge(v_mid);
  if v_status <> 'revocation_pending' then raise exception '1b: statut %', v_status; end if;
  -- Garde-fou #1 : B reste ILLIMITÉ (expires_at TOUJOURS NULL, pas raccourci à P.ends_at)
  if not exists (select 1 from public.user_roles where user_id=v_b and role='premium' and expires_at is null) then
    raise exception '1b: premium illimité de B raccourci'; end if;
  -- A n'avait AUCUNE ligne → parité _expire_premium (UPSERT) : une ligne premium est CRÉÉE, INACTIVE.
  if not exists (select 1 from public.user_roles where user_id=v_a and role='premium') then
    raise exception '1b: rôle premium A non créé (parité _expire_premium UPSERT attendue)'; end if;
  if exists (select 1 from public.user_roles where user_id=v_a and role='premium'
              and (expires_at is null or expires_at > now())) then
    raise exception '1b: rôle premium A actif (devrait être inactif/expiré)'; end if;
  raise notice '1b OK';
end $$;
rollback;


-- ══════════ 1c. GARDE-FOU #1 (branche GREATEST) : B premium fini PLUS TARD que P.ends_at → NON raccourci ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5a.a')::uuid; v_b uuid := current_setting('bill5a.b')::uuid;
        v_prod uuid; v_pass uuid; v_mid uuid; v_status text; v_exp timestamptz;
begin
  insert into public.products(sku, type, credits_granted, duration_days)
    values ('t5a-'||substr(gen_random_uuid()::text,1,8), 'PASS', 30, 7) returning id into v_prod;
  insert into public.passes(user_id, product_id, starts_at, ends_at, status)
    values (v_a, v_prod, now()-interval '1 day', now()+interval '6 days', 'ACTIVE') returning id into v_pass;  -- P.ends_at ≈ +6j
  insert into public.ledger_entries(user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
    values (v_a, 'GRANT', 30, v_pass, 'ORDER', 'o1', 't5a:grant:'||v_pass::text);
  -- B : premium FINI expirant BIEN PLUS TARD (≈ +40j) que le pass de A, et AUCUN pass actif (v_cnt_b=0).
  insert into public.user_roles(user_id, role, granted_by, expires_at) values (v_b, 'premium', v_b, now()+interval '40 days');
  insert into public.identity_merges(from_user_id, to_user_id, status)
    values (v_a, v_b, 'billing_reconciliation_pending') returning merge_id into v_mid;

  select status into v_status from public.billing_reconcile_merge(v_mid);
  if v_status <> 'revocation_pending' then raise exception '1c: statut %', v_status; end if;
  select expires_at into v_exp from public.user_roles where user_id=v_b and role='premium';
  -- Le premium de B ne doit PAS être raccourci à P.ends_at (≈+6j) : il reste ≈+40j (GREATEST).
  if v_exp is null or v_exp < now()+interval '39 days' then
    raise exception '1c: premium fini de B raccourci (expires=% < +39j)', v_exp; end if;
  raise notice '1c OK';
end $$;
rollback;


-- ══════════ 1d. GARDE-FOU #1 (branche GREATEST) : B premium fini PLUS TÔT que P.ends_at → ÉTENDU à P.ends_at ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5a.a')::uuid; v_b uuid := current_setting('bill5a.b')::uuid;
        v_prod uuid; v_pass uuid; v_mid uuid; v_status text; v_exp timestamptz; v_pends timestamptz;
begin
  insert into public.products(sku, type, credits_granted, duration_days)
    values ('t5a-'||substr(gen_random_uuid()::text,1,8), 'PASS', 30, 7) returning id into v_prod;
  insert into public.passes(user_id, product_id, starts_at, ends_at, status)
    values (v_a, v_prod, now()-interval '1 day', now()+interval '6 days', 'ACTIVE') returning id into v_pass;
  select ends_at into v_pends from public.passes where id=v_pass;
  insert into public.ledger_entries(user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
    values (v_a, 'GRANT', 30, v_pass, 'ORDER', 'o1', 't5a:grant:'||v_pass::text);
  -- B : premium FINI expirant PLUS TÔT (≈ +2j) que le pass de A (≈+6j), et AUCUN pass actif.
  insert into public.user_roles(user_id, role, granted_by, expires_at) values (v_b, 'premium', v_b, now()+interval '2 days');
  insert into public.identity_merges(from_user_id, to_user_id, status)
    values (v_a, v_b, 'billing_reconciliation_pending') returning merge_id into v_mid;

  select status into v_status from public.billing_reconcile_merge(v_mid);
  if v_status <> 'revocation_pending' then raise exception '1d: statut %', v_status; end if;
  select expires_at into v_exp from public.user_roles where user_id=v_b and role='premium';
  -- GREATEST(+2j, P.ends_at≈+6j) = P.ends_at : le premium de B est ÉTENDU à la fenêtre du pass.
  if v_exp is null or v_exp <> v_pends then
    raise exception '1d: premium de B non étendu à P.ends_at (expires=% attendu %)', v_exp, v_pends; end if;
  raise notice '1d OK';
end $$;
rollback;


-- ══════════ 2. net=0 → pass transféré, AUCUNE écriture compensatoire ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5a.a')::uuid; v_b uuid := current_setting('bill5a.b')::uuid;
        v_prod uuid; v_pass uuid; v_mid uuid; v_status text;
begin
  insert into public.products(sku, type, credits_granted, duration_days)
    values ('t5a-'||substr(gen_random_uuid()::text,1,8), 'PASS', 30, 7) returning id into v_prod;
  insert into public.passes(user_id, product_id, starts_at, ends_at, status)
    values (v_a, v_prod, now()-interval '1 day', now()+interval '6 days', 'ACTIVE') returning id into v_pass;
  insert into public.ledger_entries(user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
    values (v_a, 'GRANT', 30, v_pass, 'ORDER', 'o1', 't5a:grant:'||v_pass::text);
  insert into public.ledger_entries(user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
    values (v_a, 'HOLD', -30, v_pass, 'GENERATION_INTENT', 'i1', 't5a:hold:'||v_pass::text);  -- net = 0
  insert into public.identity_merges(from_user_id, to_user_id, status)
    values (v_a, v_b, 'billing_reconciliation_pending') returning merge_id into v_mid;

  select status into v_status from public.billing_reconcile_merge(v_mid);
  if v_status <> 'revocation_pending' then raise exception '2: statut %', v_status; end if;
  if not exists (select 1 from public.passes where id=v_pass and user_id=v_b) then raise exception '2: pass non déplacé'; end if;
  if exists (select 1 from public.ledger_entries where idempotency_key like 'merge:'||v_mid::text||':%') then
    raise exception '2: écriture compensatoire créée alors que net=0'; end if;
  raise notice '2 OK';
end $$;
rollback;


-- ══════════ 3. A 0 pass actif → manual_review (SOURCE_PASS_COUNT_INVALID), 0 mutation ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5a.a')::uuid; v_b uuid := current_setting('bill5a.b')::uuid;
        v_prod uuid; v_mid uuid; v_status text; v_fc text;
begin
  insert into public.products(sku, type, credits_granted, duration_days)
    values ('t5a-'||substr(gen_random_uuid()::text,1,8), 'PASS', 30, 7) returning id into v_prod;
  -- pass EXPIRÉ (donc 0 pass ACTIF pour A) — simule une dérive entre merge et reconcile
  insert into public.passes(user_id, product_id, starts_at, ends_at, status)
    values (v_a, v_prod, now()-interval '10 days', now()-interval '1 day', 'ACTIVE');
  insert into public.identity_merges(from_user_id, to_user_id, status)
    values (v_a, v_b, 'billing_reconciliation_pending') returning merge_id into v_mid;

  select status, failure_code into v_status, v_fc from public.billing_reconcile_merge(v_mid);
  if v_status <> 'billing_conflict_manual_review' or v_fc <> 'SOURCE_PASS_COUNT_INVALID' then
    raise exception '3: %/% (attendu manual_review/SOURCE_PASS_COUNT_INVALID)', v_status, v_fc; end if;
  if exists (select 1 from public.ledger_entries where idempotency_key like 'merge:'||v_mid::text||':%') then
    raise exception '3: mutation financière alors que manual_review'; end if;
  raise notice '3 OK';
end $$;
rollback;


-- ══════════ 4. A plusieurs passes actifs → manual_review (SOURCE_PASS_COUNT_INVALID), 0 mutation ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5a.a')::uuid; v_b uuid := current_setting('bill5a.b')::uuid;
        v_prod uuid; v_p1 uuid; v_p2 uuid; v_mid uuid; v_status text; v_fc text;
begin
  insert into public.products(sku, type, credits_granted, duration_days)
    values ('t5a-'||substr(gen_random_uuid()::text,1,8), 'PASS', 30, 7) returning id into v_prod;
  insert into public.passes(user_id, product_id, starts_at, ends_at, status)
    values (v_a, v_prod, now()-interval '1 day', now()+interval '6 days', 'ACTIVE') returning id into v_p1;
  insert into public.passes(user_id, product_id, starts_at, ends_at, status)
    values (v_a, v_prod, now()-interval '1 day', now()+interval '3 days', 'ACTIVE') returning id into v_p2;
  insert into public.identity_merges(from_user_id, to_user_id, status)
    values (v_a, v_b, 'billing_reconciliation_pending') returning merge_id into v_mid;

  select status, failure_code into v_status, v_fc from public.billing_reconcile_merge(v_mid);
  if v_status <> 'billing_conflict_manual_review' or v_fc <> 'SOURCE_PASS_COUNT_INVALID' then
    raise exception '4: %/%', v_status, v_fc; end if;
  if exists (select 1 from public.passes where id in (v_p1, v_p2) and user_id=v_b) then
    raise exception '4: un pass a été déplacé vers B'; end if;
  raise notice '4 OK';
end $$;
rollback;


-- ══════════ 5. B possède déjà un pass actif → manual_review (TARGET_ALREADY_PREMIUM), 0 mutation ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5a.a')::uuid; v_b uuid := current_setting('bill5a.b')::uuid;
        v_prod uuid; v_pa uuid; v_mid uuid; v_status text; v_fc text;
begin
  insert into public.products(sku, type, credits_granted, duration_days)
    values ('t5a-'||substr(gen_random_uuid()::text,1,8), 'PASS', 30, 7) returning id into v_prod;
  insert into public.passes(user_id, product_id, starts_at, ends_at, status)
    values (v_a, v_prod, now()-interval '1 day', now()+interval '6 days', 'ACTIVE') returning id into v_pa;
  insert into public.passes(user_id, product_id, starts_at, ends_at, status)
    values (v_b, v_prod, now()-interval '1 day', now()+interval '6 days', 'ACTIVE');  -- B déjà premium
  insert into public.identity_merges(from_user_id, to_user_id, status)
    values (v_a, v_b, 'billing_reconciliation_pending') returning merge_id into v_mid;

  select status, failure_code into v_status, v_fc from public.billing_reconcile_merge(v_mid);
  if v_status <> 'billing_conflict_manual_review' or v_fc <> 'TARGET_ALREADY_PREMIUM' then
    raise exception '5: %/%', v_status, v_fc; end if;
  if not exists (select 1 from public.passes where id=v_pa and user_id=v_a) then
    raise exception '5: le pass de A a été déplacé'; end if;
  raise notice '5 OK';
end $$;
rollback;


-- ══════════ 6. net<0 → manual_review (NET_NEGATIVE), 0 mutation ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5a.a')::uuid; v_b uuid := current_setting('bill5a.b')::uuid;
        v_prod uuid; v_pass uuid; v_mid uuid; v_status text; v_fc text;
begin
  insert into public.products(sku, type, credits_granted, duration_days)
    values ('t5a-'||substr(gen_random_uuid()::text,1,8), 'PASS', 30, 7) returning id into v_prod;
  insert into public.passes(user_id, product_id, starts_at, ends_at, status)
    values (v_a, v_prod, now()-interval '1 day', now()+interval '6 days', 'ACTIVE') returning id into v_pass;
  insert into public.ledger_entries(user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
    values (v_a, 'GRANT', 5, v_pass, 'ORDER', 'o1', 't5a:grant:'||v_pass::text);
  insert into public.ledger_entries(user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
    values (v_a, 'HOLD', -10, v_pass, 'GENERATION_INTENT', 'i1', 't5a:hold:'||v_pass::text);  -- net = -5
  insert into public.identity_merges(from_user_id, to_user_id, status)
    values (v_a, v_b, 'billing_reconciliation_pending') returning merge_id into v_mid;

  select status, failure_code into v_status, v_fc from public.billing_reconcile_merge(v_mid);
  if v_status <> 'billing_conflict_manual_review' or v_fc <> 'NET_NEGATIVE' then
    raise exception '6: %/%', v_status, v_fc; end if;
  if exists (select 1 from public.passes where id=v_pass and user_id=v_b) then raise exception '6: pass déplacé'; end if;
  if exists (select 1 from public.ledger_entries where idempotency_key like 'merge:'||v_mid::text||':%') then
    raise exception '6: mutation financière'; end if;
  raise notice '6 OK';
end $$;
rollback;


-- ══════════ 7. Rejeu après succès → no-op idempotent (0 nouveau crédit/débit, pass non re-déplacé) ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5a.a')::uuid; v_b uuid := current_setting('bill5a.b')::uuid;
        v_prod uuid; v_pass uuid; v_mid uuid; v_status text; v_n1 int; v_n2 int;
begin
  insert into public.products(sku, type, credits_granted, duration_days)
    values ('t5a-'||substr(gen_random_uuid()::text,1,8), 'PASS', 30, 7) returning id into v_prod;
  insert into public.passes(user_id, product_id, starts_at, ends_at, status)
    values (v_a, v_prod, now()-interval '1 day', now()+interval '6 days', 'ACTIVE') returning id into v_pass;
  insert into public.ledger_entries(user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
    values (v_a, 'GRANT', 30, v_pass, 'ORDER', 'o1', 't5a:grant:'||v_pass::text);
  insert into public.identity_merges(from_user_id, to_user_id, status)
    values (v_a, v_b, 'billing_reconciliation_pending') returning merge_id into v_mid;

  perform public.billing_reconcile_merge(v_mid);   -- 1er appel → succès
  select count(*) into v_n1 from public.ledger_entries where idempotency_key like 'merge:'||v_mid::text||':%';
  select status into v_status from public.billing_reconcile_merge(v_mid);   -- 2e appel → no-op
  select count(*) into v_n2 from public.ledger_entries where idempotency_key like 'merge:'||v_mid::text||':%';

  if v_status <> 'revocation_pending' then raise exception '7: statut rejeu %', v_status; end if;
  if v_n1 <> 2 or v_n2 <> 2 then raise exception '7: écritures merge % puis % (attendu 2/2)', v_n1, v_n2; end if;
  if (select count(*) from public.passes where id=v_pass and user_id=v_b) <> 1 then
    raise exception '7: pass non/ré-déplacé'; end if;
  raise notice '7 OK';
end $$;
rollback;


-- ══════════ 8. orders et payments INCHANGÉS (seul le pass bouge) ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5a.a')::uuid; v_b uuid := current_setting('bill5a.b')::uuid;
        v_prod uuid; v_pass uuid; v_mid uuid; v_order uuid; v_pay uuid; v_ord_user uuid;
begin
  insert into public.products(sku, type, credits_granted, duration_days)
    values ('t5a-'||substr(gen_random_uuid()::text,1,8), 'PASS', 30, 7) returning id into v_prod;
  insert into public.orders(user_id, product_id, status, provider, idempotency_key)
    values (v_a, v_prod, 'PAID', 'revenuecat', 'order:revenuecat:t5a-'||substr(gen_random_uuid()::text,1,8)) returning id into v_order;
  insert into public.payments(order_id, provider, provider_transaction_id, status, amount)
    values (v_order, 'revenuecat', 't5a-tx-'||substr(gen_random_uuid()::text,1,8), 'SUCCESS', 7.99) returning id into v_pay;
  insert into public.passes(user_id, product_id, source_order_id, starts_at, ends_at, status)
    values (v_a, v_prod, v_order, now()-interval '1 day', now()+interval '6 days', 'ACTIVE') returning id into v_pass;
  insert into public.ledger_entries(user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
    values (v_a, 'GRANT', 30, v_pass, 'ORDER', v_order::text, 't5a:grant:'||v_pass::text);
  insert into public.identity_merges(from_user_id, to_user_id, status)
    values (v_a, v_b, 'billing_reconciliation_pending') returning merge_id into v_mid;

  perform public.billing_reconcile_merge(v_mid);

  select user_id into v_ord_user from public.orders where id=v_order;
  if v_ord_user <> v_a then raise exception '8: orders.user_id modifié (% au lieu de A)', v_ord_user; end if;
  if not exists (select 1 from public.payments where id=v_pay and order_id=v_order) then
    raise exception '8: payment modifié/supprimé'; end if;
  if not exists (select 1 from public.passes where id=v_pass and user_id=v_b and source_order_id=v_order) then
    raise exception '8: pass mal déplacé ou source_order_id modifié'; end if;
  raise notice '8 OK';
end $$;
rollback;


-- ══════════ 9. RPC inaccessible à anon / authenticated ══════════
do $$
begin
  if has_function_privilege('anon', 'public.billing_reconcile_merge(uuid)', 'EXECUTE') then
    raise exception '9: anon a EXECUTE (interdit)'; end if;
  if has_function_privilege('authenticated', 'public.billing_reconcile_merge(uuid)', 'EXECUTE') then
    raise exception '9: authenticated a EXECUTE (interdit)'; end if;
  if not has_function_privilege('service_role', 'public.billing_reconcile_merge(uuid)', 'EXECUTE') then
    raise exception '9: service_role manque EXECUTE'; end if;
  raise notice '9 OK';
end $$;


-- ══════════ 10. Trigger append-only ledger toujours actif (UPDATE et DELETE bloqués) ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5a.a')::uuid; v_id bigint;
begin
  insert into public.ledger_entries(user_id, entry_type, available_delta, idempotency_key)
    values (v_a, 'ADJUSTMENT', 1, 't5a:append:'||gen_random_uuid()::text) returning id into v_id;
  -- IMPORTANT : les messages-sentinelles de SUCCÈS ne doivent PAS contenir « append-only »,
  -- sinon le filtre `sqlerrm not like '%append-only%'` les avalerait comme le message du
  -- trigger → le test deviendrait vacuous. Seul le message du TRIGGER contient « append-only ».
  begin
    update public.ledger_entries set available_delta = 2 where id = v_id;
    raise exception 'REGRESSION_10: UPDATE sur ledger a reussi (trigger de mutation absent)';
  exception when others then
    if sqlerrm not like '%append-only%' then raise; end if;   -- ne ravale QUE le message du trigger
  end;
  begin
    delete from public.ledger_entries where id = v_id;
    raise exception 'REGRESSION_10: DELETE sur ledger a reussi (trigger de mutation absent)';
  exception when others then
    if sqlerrm not like '%append-only%' then raise; end if;
  end;
  raise notice '10 OK (append-only préservé après extension du CHECK)';
end $$;
rollback;

-- ─────────────────────────────────────────────────────────────────────────────
-- Fin. Tous les blocs doivent afficher « N OK » sans exception.
-- ─────────────────────────────────────────────────────────────────────────────
