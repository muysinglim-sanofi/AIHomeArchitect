-- ─────────────────────────────────────────────────────────────────────────────
-- _TEST_billing_route_revenuecat.sql — VALIDATION du Commit 5b (routage SQL)
-- ─────────────────────────────────────────────────────────────────────────────
-- SQL PUR self-asserting, rôle privilégié, BASE DE TEST JETABLE. Chaque scénario en
-- BEGIN…ROLLBACK (fixtures annulées ; le ledger append-only tolère INSERT + ROLLBACK).
-- Prérequis : migrations billing PR0 + identité (5a) + 20260716_billing_route_revenuecat
-- appliquées ; 2 comptes A/B dans auth.users. (Le dispatch webhook — CANCELLATION+
-- CUSTOMER_SUPPORT, REFUND_REVERSED — est testé côté Python : _route_revenuecat_validation.py.)
-- ─────────────────────────────────────────────────────────────────────────────

select set_config('bill5b.a', '00000000-0000-0000-0000-0000000000aa', false);  -- A (identité RC originale)
select set_config('bill5b.b', '00000000-0000-0000-0000-0000000000bb', false);  -- B (cible)

do $$
declare v_a uuid := current_setting('bill5b.a')::uuid; v_b uuid := current_setting('bill5b.b')::uuid;
begin
  if v_a = '00000000-0000-0000-0000-0000000000aa' or v_b = '00000000-0000-0000-0000-0000000000bb' then
    raise exception 'Remplace bill5b.a / bill5b.b par de vrais UUID staging'; end if;
  if not exists (select 1 from auth.users where id=v_a) then raise exception 'A absent d''auth.users'; end if;
  if not exists (select 1 from auth.users where id=v_b) then raise exception 'B absent d''auth.users'; end if;
  if v_a=v_b then raise exception 'A=B'; end if;
  raise notice 'Garde OK';
end $$;


-- Helper de fixture product réutilisé
-- (inséré dans chaque bloc car ROLLBACK)


-- ══════════ 1. ACTIF (non fusionné) → cible = original, grant + rôle sur A ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5b.a')::uuid; v_b uuid := current_setting('bill5b.b')::uuid;
        v_prod uuid; v_res jsonb;
begin
  insert into public.products(sku,type,credits_granted,duration_days)
    values ('t5b-'||substr(gen_random_uuid()::text,1,8),'PASS',30,7) returning id into v_prod;
  v_res := public.billing_grant_purchase_routed(v_a,'revenuecat','t5b:tx:'||gen_random_uuid()::text,
             v_prod,30,7,7.99,'USD',now()+interval '7 days','{}'::jsonb);
  if v_res->>'routing_code' <> 'active' then raise exception '1: routing=% (attendu active)', v_res->>'routing_code'; end if;
  if (v_res->>'effective_user_id')::uuid <> v_a then raise exception '1: effective<>A'; end if;
  if v_res->>'decision' <> 'granted' then raise exception '1: decision=%', v_res->>'decision'; end if;
  if not exists (select 1 from public.passes where user_id=v_a) then raise exception '1: pas de pass sur A'; end if;
  if not exists (select 1 from public.user_roles where user_id=v_a and role='premium') then raise exception '1: pas de rôle sur A'; end if;
  raise notice '1 OK';
end $$;
rollback;


-- ══════════ 2. A fermé, merge billing_reconciliation_pending → grant reste sur A ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5b.a')::uuid; v_b uuid := current_setting('bill5b.b')::uuid;
        v_prod uuid; v_res jsonb;
begin
  insert into public.products(sku,type,credits_granted,duration_days)
    values ('t5b-'||substr(gen_random_uuid()::text,1,8),'PASS',30,7) returning id into v_prod;
  insert into public.account_state(user_id,merged_closed,merged_into) values (v_a,true,v_b);
  insert into public.identity_merges(from_user_id,to_user_id,status)
    values (v_a,v_b,'billing_reconciliation_pending');
  v_res := public.billing_grant_purchase_routed(v_a,'revenuecat','t5b:tx:'||gen_random_uuid()::text,
             v_prod,30,7,7.99,'USD',now()+interval '7 days','{}'::jsonb);
  if v_res->>'routing_code' <> 'pending_stay_a' then raise exception '2: routing=%', v_res->>'routing_code'; end if;
  if (v_res->>'effective_user_id')::uuid <> v_a then raise exception '2: effective<>A (le grant doit rester sur A)'; end if;
  if exists (select 1 from public.passes where user_id=v_b) then raise exception '2: pass créé sur B (interdit en pending)'; end if;
  raise notice '2 OK';
end $$;
rollback;


-- ══════════ 3. A fermé, merge revocation_pending, B valide → grant sur B ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5b.a')::uuid; v_b uuid := current_setting('bill5b.b')::uuid;
        v_prod uuid; v_res jsonb;
begin
  insert into public.products(sku,type,credits_granted,duration_days)
    values ('t5b-'||substr(gen_random_uuid()::text,1,8),'PASS',30,7) returning id into v_prod;
  insert into public.account_state(user_id,merged_closed,merged_into) values (v_a,true,v_b);
  insert into public.identity_merges(from_user_id,to_user_id,status) values (v_a,v_b,'revocation_pending');
  v_res := public.billing_grant_purchase_routed(v_a,'revenuecat','t5b:tx:'||gen_random_uuid()::text,
             v_prod,30,7,7.99,'USD',now()+interval '7 days','{}'::jsonb);
  if v_res->>'routing_code' <> 'routed_to_b' then raise exception '3: routing=%', v_res->>'routing_code'; end if;
  if (v_res->>'effective_user_id')::uuid <> v_b then raise exception '3: effective<>B'; end if;
  if not exists (select 1 from public.passes where user_id=v_b) then raise exception '3: pas de pass sur B'; end if;
  if exists (select 1 from public.passes where user_id=v_a) then raise exception '3: pass créé sur A (interdit)'; end if;
  if not exists (select 1 from public.user_roles where user_id=v_b and role='premium') then raise exception '3: pas de rôle sur B'; end if;
  raise notice '3 OK';
end $$;
rollback;


-- ══════════ 4. A fermé, merge completed → grant sur B ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5b.a')::uuid; v_b uuid := current_setting('bill5b.b')::uuid;
        v_prod uuid; v_res jsonb;
begin
  insert into public.products(sku,type,credits_granted,duration_days)
    values ('t5b-'||substr(gen_random_uuid()::text,1,8),'PASS',30,7) returning id into v_prod;
  insert into public.account_state(user_id,merged_closed,merged_into) values (v_a,true,v_b);
  insert into public.identity_merges(from_user_id,to_user_id,status) values (v_a,v_b,'completed');
  v_res := public.billing_grant_purchase_routed(v_a,'revenuecat','t5b:tx:'||gen_random_uuid()::text,
             v_prod,30,7,7.99,'USD',now()+interval '7 days','{}'::jsonb);
  if v_res->>'routing_code' <> 'routed_to_b' then raise exception '4: routing=%', v_res->>'routing_code'; end if;
  if (v_res->>'effective_user_id')::uuid <> v_b then raise exception '4: effective<>B'; end if;
  raise notice '4 OK';
end $$;
rollback;


-- ══════════ 5. B absent d'auth.users → manual_review, aucun grant ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5b.a')::uuid;
        v_ghost uuid := '11111111-2222-3333-4444-555555555555'; v_prod uuid; v_res jsonb;
begin
  insert into public.products(sku,type,credits_granted,duration_days)
    values ('t5b-'||substr(gen_random_uuid()::text,1,8),'PASS',30,7) returning id into v_prod;
  insert into public.account_state(user_id,merged_closed,merged_into) values (v_a,true,v_ghost);
  insert into public.identity_merges(from_user_id,to_user_id,status) values (v_a,v_ghost,'revocation_pending');
  v_res := public.billing_grant_purchase_routed(v_a,'revenuecat','t5b:tx:'||gen_random_uuid()::text,
             v_prod,30,7,7.99,'USD',now()+interval '7 days','{}'::jsonb);
  if v_res->>'decision' <> 'manual_review' or v_res->>'routing_code' <> 'manual_target_missing' then
    raise exception '5: %/%', v_res->>'routing_code', v_res->>'decision'; end if;
  if exists (select 1 from public.passes where user_id in (v_a,v_ghost)) then raise exception '5: grant écrit'; end if;
  raise notice '5 OK';
end $$;
rollback;


-- ══════════ 6. B lui-même merged_closed (chaîne A→B→C) → manual_review, aucun grant ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5b.a')::uuid; v_b uuid := current_setting('bill5b.b')::uuid;
        v_c uuid := '99999999-8888-7777-6666-555555555555'; v_prod uuid; v_res jsonb;
begin
  insert into public.products(sku,type,credits_granted,duration_days)
    values ('t5b-'||substr(gen_random_uuid()::text,1,8),'PASS',30,7) returning id into v_prod;
  insert into public.account_state(user_id,merged_closed,merged_into) values (v_a,true,v_b);
  insert into public.account_state(user_id,merged_closed,merged_into) values (v_b,true,v_c);  -- B fermé → chaîne
  insert into public.identity_merges(from_user_id,to_user_id,status) values (v_a,v_b,'completed');
  v_res := public.billing_grant_purchase_routed(v_a,'revenuecat','t5b:tx:'||gen_random_uuid()::text,
             v_prod,30,7,7.99,'USD',now()+interval '7 days','{}'::jsonb);
  if v_res->>'decision' <> 'manual_review' or v_res->>'routing_code' <> 'manual_target_closed' then
    raise exception '6: %/%', v_res->>'routing_code', v_res->>'decision'; end if;
  if exists (select 1 from public.passes where user_id in (v_a,v_b)) then raise exception '6: grant écrit'; end if;
  raise notice '6 OK';
end $$;
rollback;


-- ══════════ 7. merge conflict / manual_review → manual_review, aucun grant ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5b.a')::uuid; v_b uuid := current_setting('bill5b.b')::uuid;
        v_prod uuid; v_res jsonb;
begin
  insert into public.products(sku,type,credits_granted,duration_days)
    values ('t5b-'||substr(gen_random_uuid()::text,1,8),'PASS',30,7) returning id into v_prod;
  insert into public.account_state(user_id,merged_closed,merged_into) values (v_a,true,v_b);
  insert into public.identity_merges(from_user_id,to_user_id,status) values (v_a,v_b,'billing_conflict_manual_review');
  v_res := public.billing_grant_purchase_routed(v_a,'revenuecat','t5b:tx:'||gen_random_uuid()::text,
             v_prod,30,7,7.99,'USD',now()+interval '7 days','{}'::jsonb);
  if v_res->>'decision' <> 'manual_review' or v_res->>'routing_code' <> 'manual_merge_status' then
    raise exception '7: %/%', v_res->>'routing_code', v_res->>'decision'; end if;
  if exists (select 1 from public.passes where user_id in (v_a,v_b)) then raise exception '7: grant écrit'; end if;
  raise notice '7 OK';
end $$;
rollback;


-- ══════════ 8. Transaction dupliquée → aucun double (idempotence héritée) ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5b.a')::uuid; v_prod uuid; v_tx text := 't5b:dup:'||gen_random_uuid()::text;
        v_r1 jsonb; v_r2 jsonb; v_n_orders int; v_n_pass int; v_n_ledger int;
begin
  insert into public.products(sku,type,credits_granted,duration_days)
    values ('t5b-'||substr(gen_random_uuid()::text,1,8),'PASS',30,7) returning id into v_prod;
  v_r1 := public.billing_grant_purchase_routed(v_a,'revenuecat',v_tx,v_prod,30,7,7.99,'USD',now()+interval '7 days','{}'::jsonb);
  v_r2 := public.billing_grant_purchase_routed(v_a,'revenuecat',v_tx,v_prod,30,7,7.99,'USD',now()+interval '7 days','{}'::jsonb);
  select count(*) into v_n_orders from public.orders where user_id=v_a;
  select count(*) into v_n_pass from public.passes where user_id=v_a;
  select count(*) into v_n_ledger from public.ledger_entries where user_id=v_a and entry_type='GRANT';
  if v_r1->>'decision' <> 'granted' then raise exception '8: 1er appel decision=%', v_r1->>'decision'; end if;
  if v_r2->>'decision' <> 'duplicate' then raise exception '8: 2e appel decision=% (attendu duplicate)', v_r2->>'decision'; end if;
  if v_n_orders <> 1 or v_n_pass <> 1 or v_n_ledger <> 1 then
    raise exception '8: double (orders=% pass=% ledger=%)', v_n_orders, v_n_pass, v_n_ledger; end if;
  raise notice '8 OK';
end $$;
rollback;


-- ══════════ 9. A fermé, merged_into NULL → manual_review ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5b.a')::uuid; v_prod uuid; v_res jsonb;
begin
  insert into public.products(sku,type,credits_granted,duration_days)
    values ('t5b-'||substr(gen_random_uuid()::text,1,8),'PASS',30,7) returning id into v_prod;
  insert into public.account_state(user_id,merged_closed,merged_into) values (v_a,true,null);
  v_res := public.billing_grant_purchase_routed(v_a,'revenuecat','t5b:tx:'||gen_random_uuid()::text,
             v_prod,30,7,7.99,'USD',now()+interval '7 days','{}'::jsonb);
  if v_res->>'routing_code' <> 'manual_no_target' then raise exception '9: routing=%', v_res->>'routing_code'; end if;
  raise notice '9 OK';
end $$;
rollback;


-- ══════════ 10. role_apply : pending→A, revocation→B ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5b.a')::uuid; v_b uuid := current_setting('bill5b.b')::uuid; v_res jsonb;
begin
  insert into public.account_state(user_id,merged_closed,merged_into) values (v_a,true,v_b);
  insert into public.identity_merges(from_user_id,to_user_id,status) values (v_a,v_b,'revocation_pending');
  v_res := public.billing_route_role_apply(v_a, now()+interval '30 days', 'TRANSFER', 'ev1');
  if (v_res->>'effective_user_id')::uuid <> v_b or v_res->>'decision' <> 'applied' then
    raise exception '10: role non routé vers B (%/%)', v_res->>'routing_code', v_res->>'decision'; end if;
  if not exists (select 1 from public.user_roles where user_id=v_b and role='premium') then raise exception '10: pas de rôle B'; end if;
  if exists (select 1 from public.user_roles where user_id=v_a and role='premium') then raise exception '10: rôle écrit sur A'; end if;
  raise notice '10 OK';
end $$;
rollback;


-- ══════════ 11. GARDE anti-ancien : EXPIRATION ancienne ne raccourcit pas un premium plus récent ══════════
begin;
do $$
declare v_b uuid := current_setting('bill5b.b')::uuid; v_res jsonb; v_exp timestamptz; v_notes text;
begin
  -- B a un premium RÉCENT (expire +30j, notes='recent-renewal'). Une EXPIRATION ANCIENNE arrive.
  insert into public.user_roles(user_id,role,granted_by,expires_at,notes)
    values (v_b,'premium',v_b, now()+interval '30 days', 'recent-renewal');
  v_res := public.billing_route_role_apply(v_b, now()-interval '1 day', 'EXPIRATION', 'ev-old');
  select expires_at, notes into v_exp, v_notes from public.user_roles where user_id=v_b and role='premium';
  if v_exp is null or v_exp < now()+interval '29 days' then
    raise exception '11: premium récent de B raccourci par une EXPIRATION ancienne (expires=%)', v_exp; end if;
  -- granted_by/notes du droit RÉCENT NON écrasés par l'événement ANCIEN (contrat anti-ancien).
  if v_notes is distinct from 'recent-renewal' then
    raise exception '11: notes du droit récent écrasées par un événement ancien (notes=%)', v_notes; end if;
  raise notice '11 OK';
end $$;
rollback;


-- ══════════ 12. B premium ILLIMITÉ (NULL) → jamais raccourci ══════════
begin;
do $$
declare v_b uuid := current_setting('bill5b.b')::uuid; v_res jsonb; v_exp timestamptz;
begin
  insert into public.user_roles(user_id,role,granted_by,expires_at) values (v_b,'premium',v_b, null);  -- illimité
  v_res := public.billing_route_role_apply(v_b, now()+interval '7 days', 'RENEWAL', 'ev-fin');
  select expires_at into v_exp from public.user_roles where user_id=v_b and role='premium';
  if v_exp is not null then raise exception '12: premium illimité de B raccourci (expires=%)', v_exp; end if;
  raise notice '12 OK';
end $$;
rollback;


-- ══════════ 13. grant + rôle sur la MÊME identité (routed_to_b) ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5b.a')::uuid; v_b uuid := current_setting('bill5b.b')::uuid; v_prod uuid; v_res jsonb;
begin
  insert into public.products(sku,type,credits_granted,duration_days)
    values ('t5b-'||substr(gen_random_uuid()::text,1,8),'PASS',30,7) returning id into v_prod;
  insert into public.account_state(user_id,merged_closed,merged_into) values (v_a,true,v_b);
  insert into public.identity_merges(from_user_id,to_user_id,status) values (v_a,v_b,'completed');
  v_res := public.billing_grant_purchase_routed(v_a,'revenuecat','t5b:tx:'||gen_random_uuid()::text,
             v_prod,30,7,7.99,'USD',now()+interval '7 days','{}'::jsonb);
  -- grant (order/pass/ledger) ET rôle DOIVENT être sur la même identité B
  if not exists (select 1 from public.passes where user_id=v_b) then raise exception '13: pass pas sur B'; end if;
  if not exists (select 1 from public.ledger_entries where user_id=v_b and entry_type='GRANT') then raise exception '13: ledger pas sur B'; end if;
  if not exists (select 1 from public.user_roles where user_id=v_b and role='premium') then raise exception '13: rôle pas sur B'; end if;
  if exists (select 1 from public.user_roles where user_id=v_a and role='premium') then raise exception '13: rôle sur A'; end if;
  raise notice '13 OK';
end $$;
rollback;


-- ══════════ 10b. role_apply : merge billing_reconciliation_pending → rôle reste sur A ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5b.a')::uuid; v_b uuid := current_setting('bill5b.b')::uuid; v_res jsonb;
begin
  insert into public.account_state(user_id,merged_closed,merged_into) values (v_a,true,v_b);
  insert into public.identity_merges(from_user_id,to_user_id,status) values (v_a,v_b,'billing_reconciliation_pending');
  v_res := public.billing_route_role_apply(v_a, now()+interval '30 days', 'TRANSFER', 'ev-pend');
  if (v_res->>'effective_user_id')::uuid <> v_a or v_res->>'routing_code' <> 'pending_stay_a' then
    raise exception '10b: rôle non routé vers A (%/%)', v_res->>'routing_code', v_res->>'effective_user_id'; end if;
  if not exists (select 1 from public.user_roles where user_id=v_a and role='premium') then raise exception '10b: pas de rôle A'; end if;
  if exists (select 1 from public.user_roles where user_id=v_b and role='premium') then raise exception '10b: rôle écrit sur B (interdit en pending)'; end if;
  raise notice '10b OK';
end $$;
rollback;


-- ══════════ 15. A fermé + merged_into=B mais AUCUNE ligne merge → manual_no_merge ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5b.a')::uuid; v_b uuid := current_setting('bill5b.b')::uuid; v_prod uuid; v_res jsonb;
begin
  insert into public.products(sku,type,credits_granted,duration_days)
    values ('t5b-'||substr(gen_random_uuid()::text,1,8),'PASS',30,7) returning id into v_prod;
  insert into public.account_state(user_id,merged_closed,merged_into) values (v_a,true,v_b);  -- fermé mais AUCUN merge
  v_res := public.billing_grant_purchase_routed(v_a,'revenuecat','t5b:tx:'||gen_random_uuid()::text,
             v_prod,30,7,7.99,'USD',now()+interval '7 days','{}'::jsonb);
  if v_res->>'routing_code' <> 'manual_no_merge' or v_res->>'decision' <> 'manual_review' then
    raise exception '15: %/%', v_res->>'routing_code', v_res->>'decision'; end if;
  if exists (select 1 from public.passes where user_id in (v_a,v_b)) then raise exception '15: grant écrit'; end if;
  raise notice '15 OK';
end $$;
rollback;


-- ══════════ 16a. Contrainte : completed + billing_conflict_manual_review EXCLUSIFS pour A ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5b.a')::uuid; v_b uuid := current_setting('bill5b.b')::uuid; v_failed boolean := false;
begin
  insert into public.identity_merges(from_user_id,to_user_id,status) values (v_a,v_b,'completed');
  begin
    insert into public.identity_merges(from_user_id,to_user_id,status) values (v_a,v_b,'billing_conflict_manual_review');
  exception when unique_violation then v_failed := true;
  end;
  if not v_failed then
    raise exception '16a: 2 lignes BLOQUANTES coexistent pour A (index unique partiel attendu)'; end if;
  raise notice '16a OK (index unique : completed & billing_conflict_manual_review ne coexistent pas)';
end $$;
rollback;


-- ══════════ 16b. « Statut le plus récent gagne » : completed ANCIENNE + conflict RÉCENTE → manual_review ══════════
begin;
do $$
declare v_a uuid := current_setting('bill5b.a')::uuid; v_b uuid := current_setting('bill5b.b')::uuid; v_prod uuid; v_res jsonb;
begin
  insert into public.products(sku,type,credits_granted,duration_days)
    values ('t5b-'||substr(gen_random_uuid()::text,1,8),'PASS',30,7) returning id into v_prod;
  insert into public.account_state(user_id,merged_closed,merged_into) values (v_a,true,v_b);
  insert into public.identity_merges(from_user_id,to_user_id,status,started_at)
    values (v_a,v_b,'completed', now()-interval '1 hour');    -- ANCIENNE (bloquante)
  insert into public.identity_merges(from_user_id,to_user_id,status,started_at)
    values (v_a,v_b,'conflict', now());                        -- NOUVELLE (terminale, hors index)
  v_res := public.billing_grant_purchase_routed(v_a,'revenuecat','t5b:tx:'||gen_random_uuid()::text,
             v_prod,30,7,7.99,'USD',now()+interval '7 days','{}'::jsonb);
  -- Le PLUS RÉCENT (conflict) prime → manual_review, aucun grant. On n'ignore pas une ligne
  -- ambiguë récente pour router sur une ancienne completed.
  if v_res->>'decision' <> 'manual_review' or v_res->>'routing_code' <> 'manual_merge_status' then
    raise exception '16b: %/% (conflict récente doit primer → manual_review)', v_res->>'routing_code', v_res->>'decision'; end if;
  if exists (select 1 from public.passes where user_id in (v_a,v_b)) then raise exception '16b: grant écrit'; end if;
  raise notice '16b OK (statut le plus récent gagne)';
end $$;
rollback;


-- ══════════ 14. Privilèges : publiques service_role OK ; helper PRIVÉ interdit ══════════
do $$
declare pub text[] := array[
    'public.billing_route_target(uuid)',
    'public.billing_grant_purchase_routed(uuid, text, text, uuid, int, int, numeric, text, timestamptz, jsonb)',
    'public.billing_route_role_apply(uuid, timestamptz, text, text)'];
  priv text := 'public.billing_upsert_premium_role(uuid, timestamptz, text)';
  f text;
begin
  -- Fonctions routées publiques : anon/authenticated SANS EXECUTE, service_role AVEC.
  foreach f in array pub loop
    if has_function_privilege('anon', f, 'EXECUTE') then raise exception '14: anon EXECUTE sur %', f; end if;
    if has_function_privilege('authenticated', f, 'EXECUTE') then raise exception '14: authenticated EXECUTE sur %', f; end if;
    if not has_function_privilege('service_role', f, 'EXECUTE') then raise exception '14: service_role manque EXECUTE sur %', f; end if;
  end loop;
  -- Helper PRIVÉ : service_role NE DOIT PAS pouvoir l'exécuter directement (anti-contournement).
  if has_function_privilege('service_role', priv, 'EXECUTE') then
    raise exception '14: service_role a EXECUTE sur le helper privé % (contournement possible)', priv; end if;
  if has_function_privilege('anon', priv, 'EXECUTE') then raise exception '14: anon EXECUTE sur helper privé'; end if;
  if has_function_privilege('authenticated', priv, 'EXECUTE') then raise exception '14: authenticated EXECUTE sur helper privé'; end if;
  raise notice '14 OK (routées publiques service_role ; helper privé inaccessible)';
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Fin. Tous les blocs doivent afficher « N OK » sans exception.
-- ─────────────────────────────────────────────────────────────────────────────
