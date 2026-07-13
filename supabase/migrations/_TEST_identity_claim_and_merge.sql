-- ─────────────────────────────────────────────────────────────────────────────
-- _TEST_identity_claim_and_merge.sql — VALIDATION du Commit 2 (déterministe)
-- ─────────────────────────────────────────────────────────────────────────────
-- SQL PUR self-asserting. À exécuter en rôle privilégié (postgres/service_role) sur une
-- BASE DE TEST / STAGING JETABLE — jamais en production. Chaque scénario est en BEGIN…ROLLBACK :
-- toutes les fixtures (tickets, merges, sessions, passes…) sont annulées. La CONCURRENCE
-- (2 connexions) n'est PAS testable ici → voir backend/e2e_identity_merge_concurrency.py.
-- Prérequis : migrations Commit 1 + Commit 2 appliquées ; 2 comptes de test dans auth.users :
--   A = utilisateur ANONYME (is_anonymous=true), B = utilisateur PERMANENT (is_anonymous=false).
-- ─────────────────────────────────────────────────────────────────────────────

-- ⟵ REMPLACER par les UUID de tes 2 comptes de TEST staging :
select set_config('identity_test.a', '00000000-0000-0000-0000-0000000000aa', false);  -- A anonyme
select set_config('identity_test.b', '00000000-0000-0000-0000-0000000000bb', false);  -- B permanent
select set_config('identity_test.c', '', false);  -- (optionnel) 2e utilisateur ANONYME → active le test b_anonymous

-- Garde : placeholders remplacés + A anonyme + B permanent + C (2e anonyme) REQUIS
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid;
        v_c text := current_setting('identity_test.c');
begin
  if v_a = '00000000-0000-0000-0000-0000000000aa' or v_b = '00000000-0000-0000-0000-0000000000bb' then
    raise exception 'Remplace identity_test.a / identity_test.b par de vrais UUID staging';
  end if;
  if v_c = '' then
    raise exception 'identity_test.c REQUIS (2e compte ANONYME staging vierge, ≠ A/B) — test b_anonymous sans SKIP';
  end if;
  if not exists (select 1 from auth.users where id=v_a and is_anonymous is true) then
    raise exception 'A doit exister et être anonyme (is_anonymous=true)'; end if;
  if not exists (select 1 from auth.users where id=v_b and is_anonymous is not true) then
    raise exception 'B doit exister et être permanent (is_anonymous=false)'; end if;
  if not exists (select 1 from auth.users where id=v_c::uuid and is_anonymous is true) then
    raise exception 'C doit exister et être anonyme (is_anonymous=true)'; end if;
  if v_c::uuid in (v_a, v_b) then raise exception 'C doit être distinct de A et B'; end if;
  raise notice 'Garde OK : A anonyme, B permanent, C anonyme';
end $$;

-- ══════════ 1. Happy A-free → revocation_pending + déplacement + fermeture + trial propagé ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid;
        v_status text; v_fc text; v_sid uuid;
begin
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)
    values ('t-happy', v_a, now() + interval '15 min');
  insert into public.sessions(user_id) values (v_a) returning id into v_sid;
  insert into public.account_state(user_id, trial_ever_granted) values (v_a, true)
    on conflict (user_id) do update set trial_ever_granted = true;

  select status, failure_code into v_status, v_fc
    from public.identity_claim_and_merge('t-happy', v_b);

  if v_status <> 'revocation_pending' or v_fc is not null then
    raise exception '1: attendu revocation_pending/NULL, obtenu %/%', v_status, v_fc; end if;
  if not exists (select 1 from public.sessions where id=v_sid and user_id=v_b) then
    raise exception '1: session non déplacée vers B'; end if;
  if not exists (select 1 from public.account_state where user_id=v_a and merged_closed) then
    raise exception '1: A non fermé'; end if;
  if not exists (select 1 from public.account_state where user_id=v_b and trial_ever_granted) then
    raise exception '1: trial_ever_granted non propagé vers B'; end if;
  if not exists (select 1 from public.identity_merge_tickets where ticket_hash='t-happy' and consumed_at is not null) then
    raise exception '1: ticket non consommé'; end if;
  raise notice '1 OK';
end $$;
rollback;

-- ══════════ 2. Idempotence : re-appel même ticket → même merge_id, pas de double déplacement ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid;
        v_id1 uuid; v_id2 uuid; v_st text;
begin
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)
    values ('t-idem', v_a, now() + interval '15 min');
  insert into public.sessions(user_id) values (v_a);
  select merge_id into v_id1 from public.identity_claim_and_merge('t-idem', v_b);
  select merge_id, status into v_id2, v_st from public.identity_claim_and_merge('t-idem', v_b);
  if v_id1 <> v_id2 then raise exception '2: merge_id différent au replay (% vs %)', v_id1, v_id2; end if;
  if (select count(*) from public.identity_merges where ticket_hash='t-idem') <> 1 then
    raise exception '2: plus d''une ligne pour le ticket'; end if;
  raise notice '2 OK (%)', v_st;
end $$;
rollback;

-- ══════════ 3. target_mismatch : A→C existant, nouveau ticket A→B ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid;
        v_c uuid := gen_random_uuid();
        v_status text; v_fc text; v_existing uuid; v_meta jsonb;
begin
  insert into public.identity_merges(from_user_id, to_user_id, status, ticket_hash)
    values (v_a, v_c, 'running', 't-existing') returning merge_id into v_existing;
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)
    values ('t-mismatch', v_a, now() + interval '15 min');
  select status, failure_code, metadata into v_status, v_fc, v_meta
    from public.identity_claim_and_merge('t-mismatch', v_b);
  if v_status <> 'conflict' or v_fc <> 'target_mismatch' then
    raise exception '3: attendu conflict/target_mismatch, obtenu %/%', v_status, v_fc; end if;
  if (v_meta->>'existing_merge_id')::uuid <> v_existing then
    raise exception '3: existing_merge_id incorrect'; end if;
  if not exists (select 1 from public.identity_merges where merge_id=v_existing and status='running') then
    raise exception '3: la ligne A→C a été mutée'; end if;
  raise notice '3 OK';
end $$;
rollback;

-- ══════════ 4. duplicate_merge_attempt : A→B existant (autre ticket), nouveau ticket A→B ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid;
        v_status text; v_fc text;
begin
  insert into public.identity_merges(from_user_id, to_user_id, status, ticket_hash)
    values (v_a, v_b, 'revocation_pending', 't-first');
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)
    values ('t-dup', v_a, now() + interval '15 min');
  select status, failure_code into v_status, v_fc
    from public.identity_claim_and_merge('t-dup', v_b);
  if v_status <> 'conflict' or v_fc <> 'duplicate_merge_attempt' then
    raise exception '4: attendu conflict/duplicate_merge_attempt, obtenu %/%', v_status, v_fc; end if;
  raise notice '4 OK';
end $$;
rollback;

-- ══════════ 5. cycle : B→A bloquant, ticket A→B ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid;
        v_status text; v_fc text;
begin
  insert into public.identity_merges(from_user_id, to_user_id, status, ticket_hash)
    values (v_b, v_a, 'running', 't-cycle-existing');
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)
    values ('t-cycle', v_a, now() + interval '15 min');
  select status, failure_code into v_status, v_fc
    from public.identity_claim_and_merge('t-cycle', v_b);
  if v_status <> 'conflict' or v_fc <> 'cycle' then
    raise exception '5: attendu conflict/cycle, obtenu %/%', v_status, v_fc; end if;
  raise notice '5 OK';
end $$;
rollback;

-- ══════════ 6a. settlement : intent RUNNING sur A → waiting, ticket NON consommé ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid;
        v_status text;
begin
  insert into public.generation_intents(intent_id, user_id, status)
    values ('int-run-a', v_a, 'RUNNING');
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)
    values ('t-settle-run', v_a, now() + interval '15 min');
  select status into v_status from public.identity_claim_and_merge('t-settle-run', v_b);
  if v_status <> 'waiting_for_settlement' then
    raise exception '6a: attendu waiting_for_settlement, obtenu %', v_status; end if;
  if exists (select 1 from public.identity_merge_tickets where ticket_hash='t-settle-run' and consumed_at is not null) then
    raise exception '6a: ticket consommé alors qu''il doit rester rejouable'; end if;
  raise notice '6a OK';
end $$;
rollback;

-- ══════════ 6b. settlement : HOLD non soldé sur B → waiting ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid;
        v_status text;
begin
  insert into public.ledger_entries(user_id, entry_type, available_delta, reference_type, reference_id, idempotency_key)
    values (v_b, 'HOLD', -1, 'GENERATION_INTENT', 'int-hold-b', 'hold:int-hold-b');
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)
    values ('t-settle-hold', v_a, now() + interval '15 min');
  select status into v_status from public.identity_claim_and_merge('t-settle-hold', v_b);
  if v_status <> 'waiting_for_settlement' then
    raise exception '6b: attendu waiting_for_settlement, obtenu %', v_status; end if;
  raise notice '6b OK';
end $$;
rollback;

-- ══════════ 7. premium/premium → manual_review, AUCUN déplacement ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid;
        v_status text; v_fc text; v_prod uuid; v_sid uuid;
begin
  insert into public.products(sku, type, credits_granted) values ('test_merge_pass', 'PASS', 30)
    returning id into v_prod;
  insert into public.passes(user_id, product_id, starts_at, ends_at, status)
    values (v_a, v_prod, now() - interval '1 day', now() + interval '5 day', 'ACTIVE');
  insert into public.passes(user_id, product_id, starts_at, ends_at, status)
    values (v_b, v_prod, now() - interval '1 day', now() + interval '5 day', 'ACTIVE');
  insert into public.sessions(user_id) values (v_a) returning id into v_sid;
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)
    values ('t-pp', v_a, now() + interval '15 min');
  select status, failure_code into v_status, v_fc from public.identity_claim_and_merge('t-pp', v_b);
  if v_status <> 'billing_conflict_manual_review' or v_fc <> 'both_users_premium' then
    raise exception '7: attendu manual_review/both_users_premium, obtenu %/%', v_status, v_fc; end if;
  if not exists (select 1 from public.sessions where id=v_sid and user_id=v_a) then
    raise exception '7: session déplacée alors qu''aucun déplacement ne doit avoir lieu'; end if;
  if exists (select 1 from public.account_state where user_id=v_a and merged_closed) then
    raise exception '7: A fermé alors qu''il doit rester actif'; end if;
  raise notice '7 OK';
end $$;
rollback;

-- ══════════ 8. A premium / B free → billing_reconciliation_pending, passes NON déplacés ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid;
        v_status text; v_prod uuid;
begin
  insert into public.products(sku, type, credits_granted) values ('test_merge_pass', 'PASS', 30)
    returning id into v_prod;
  insert into public.passes(user_id, product_id, starts_at, ends_at, status)
    values (v_a, v_prod, now() - interval '1 day', now() + interval '5 day', 'ACTIVE');
  insert into public.sessions(user_id) values (v_a);
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)
    values ('t-apbf', v_a, now() + interval '15 min');
  select status into v_status from public.identity_claim_and_merge('t-apbf', v_b);
  if v_status <> 'billing_reconciliation_pending' then
    raise exception '8: attendu billing_reconciliation_pending, obtenu %', v_status; end if;
  if not exists (select 1 from public.passes where user_id=v_a and status='ACTIVE') then
    raise exception '8: le pass de A a été déplacé/modifié (interdit en Commit 2)'; end if;
  if not exists (select 1 from public.sessions where user_id=v_b) then
    raise exception '8: session non déplacée'; end if;
  raise notice '8 OK';
end $$;
rollback;

-- ══════════ 9. same_user (précondition) → conflict/same_user ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_status text; v_fc text;
begin
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)
    values ('t-same', v_a, now() + interval '15 min');
  select status, failure_code into v_status, v_fc from public.identity_claim_and_merge('t-same', v_a);
  if v_status <> 'conflict' or v_fc <> 'same_user' then
    raise exception '9: attendu conflict/same_user, obtenu %/%', v_status, v_fc; end if;
  raise notice '9 OK';
end $$;
rollback;

-- ══════════ 10. reprise waiting après EXPIRATION (invariant #1) ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid;
        v_status text;
begin
  -- 1er appel : intent RUNNING → waiting, ticket non consommé
  insert into public.generation_intents(intent_id, user_id, status) values ('int-exp', v_a, 'RUNNING');
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)
    values ('t-exp', v_a, now() + interval '15 min');
  insert into public.sessions(user_id) values (v_a);
  select status into v_status from public.identity_claim_and_merge('t-exp', v_b);
  if v_status <> 'waiting_for_settlement' then raise exception '10: 1er appel attendu waiting, obtenu %', v_status; end if;
  -- le settlement se termine + le ticket EXPIRE
  update public.generation_intents set status='SUCCEEDED' where intent_id='int-exp';
  update public.identity_merge_tickets set expires_at = now() - interval '1 min' where ticket_hash='t-exp';
  -- reprise autorisée malgré l'expiration (merge existe pour ce ticket)
  select status into v_status from public.identity_claim_and_merge('t-exp', v_b);
  if v_status <> 'revocation_pending' then
    raise exception '10: reprise post-expiration attendue revocation_pending, obtenu %', v_status; end if;
  raise notice '10 OK';
end $$;
rollback;

-- ══════════ 11. tickets : ticket_not_found + ticket_expired (exceptions) ══════════
do $$
declare v_b uuid := current_setting('identity_test.b')::uuid; v_ok boolean;
begin
  begin
    perform public.identity_claim_and_merge('t-absent', v_b);
    raise exception '11: ticket_not_found non levé';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'ticket_not_found' then raise exception '11: attendu ticket_not_found, obtenu %', sqlerrm; end if;
  end;
  raise notice '11 OK (ticket_not_found)';
end $$;

begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid;
begin
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)
    values ('t-old', v_a, now() - interval '1 min');   -- expiré, aucun merge
  begin
    perform public.identity_claim_and_merge('t-old', v_b);
    raise exception '11b: ticket_expired non levé';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'ticket_expired' then raise exception '11b: attendu ticket_expired, obtenu %', sqlerrm; end if;
  end;
  raise notice '11b OK (ticket_expired)';
end $$;
rollback;

-- ══════════ 12. b_not_found (précondition via RPC) → conflict/b_not_found ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_status text; v_fc text;
begin
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)
    values ('t-bnf', v_a, now() + interval '15 min');
  select status, failure_code into v_status, v_fc
    from public.identity_claim_and_merge('t-bnf', gen_random_uuid());  -- B inexistant
  if v_status <> 'conflict' or v_fc <> 'b_not_found' then
    raise exception '12: attendu conflict/b_not_found, obtenu %/%', v_status, v_fc; end if;
  raise notice '12 OK';
end $$;
rollback;

-- ══════════ 13. a_merged_closed → conflict/a_merged_closed ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid; v_status text; v_fc text;
begin
  insert into public.account_state(user_id, merged_closed) values (v_a, true)
    on conflict (user_id) do update set merged_closed = true;
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)
    values ('t-amc', v_a, now() + interval '15 min');
  select status, failure_code into v_status, v_fc from public.identity_claim_and_merge('t-amc', v_b);
  if v_status <> 'conflict' or v_fc <> 'a_merged_closed' then
    raise exception '13: attendu conflict/a_merged_closed, obtenu %/%', v_status, v_fc; end if;
  raise notice '13 OK';
end $$;
rollback;

-- ══════════ 14. b_merged_closed → conflict/b_merged_closed ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid; v_status text; v_fc text;
begin
  insert into public.account_state(user_id, merged_closed) values (v_b, true)
    on conflict (user_id) do update set merged_closed = true;
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)
    values ('t-bmc', v_a, now() + interval '15 min');
  select status, failure_code into v_status, v_fc from public.identity_claim_and_merge('t-bmc', v_b);
  if v_status <> 'conflict' or v_fc <> 'b_merged_closed' then
    raise exception '14: attendu conflict/b_merged_closed, obtenu %/%', v_status, v_fc; end if;
  raise notice '14 OK';
end $$;
rollback;

-- ══════════ 15. b_has_blocking_merge (B est SOURCE d'un merge bloquant) ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid; v_status text; v_fc text;
begin
  insert into public.identity_merges(from_user_id, to_user_id, status, ticket_hash)
    values (v_b, gen_random_uuid(), 'running', 't-bhbm-existing');
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)
    values ('t-bhbm', v_a, now() + interval '15 min');
  select status, failure_code into v_status, v_fc from public.identity_claim_and_merge('t-bhbm', v_b);
  if v_status <> 'conflict' or v_fc <> 'b_has_blocking_merge' then
    raise exception '15: attendu conflict/b_has_blocking_merge, obtenu %/%', v_status, v_fc; end if;
  raise notice '15 OK';
end $$;
rollback;

-- ══════════ 16. unresolved_chain (B est DESTINATION d'un merge non terminal) ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid; v_status text; v_fc text;
begin
  insert into public.identity_merges(from_user_id, to_user_id, status, ticket_hash)
    values (gen_random_uuid(), v_b, 'running', 't-uc-existing');   -- X→B en cours
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)
    values ('t-uc', v_a, now() + interval '15 min');
  select status, failure_code into v_status, v_fc from public.identity_claim_and_merge('t-uc', v_b);
  if v_status <> 'conflict' or v_fc <> 'unresolved_chain' then
    raise exception '16: attendu conflict/unresolved_chain, obtenu %/%', v_status, v_fc; end if;
  raise notice '16 OK';
end $$;
rollback;

-- ══════════ 17. Helper direct : a_not_found (défense) · a_not_anonymous · b_anonymous (si C) ══════════
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid;
        v_c text := current_setting('identity_test.c');
begin
  -- a_not_found : INACCESSIBLE via le RPC (le ticket a une FK auth.users ON DELETE CASCADE) → testé sur le helper
  if public.identity_merge_precondition_code(gen_random_uuid(), v_b, null) <> 'a_not_found' then
    raise exception '17: a_not_found'; end if;
  if public.identity_merge_precondition_code(v_a, gen_random_uuid(), null) <> 'b_not_found' then
    raise exception '17: b_not_found'; end if;
  -- a_not_anonymous : A=permanent(B), B=anonyme(A)
  if public.identity_merge_precondition_code(v_b, v_a, null) <> 'a_not_anonymous' then
    raise exception '17: a_not_anonymous'; end if;
  -- b_anonymous : REQUIS (C = 2e anonyme, garanti non-vide par la garde)
  if public.identity_merge_precondition_code(v_a, v_c::uuid, null) <> 'b_anonymous' then
    raise exception '17: b_anonymous'; end if;
  raise notice '17 OK (a_not_found défense + a_not_anonymous + b_anonymous)';
end $$;

-- ══════════ 18. Replay des 8 statuts IDEMPOTENTS (paramétré) ══════════
-- data_merged · billing_reconciliation_pending · billing_conflict_manual_review · revocation_pending
-- · completed · failed · conflict · abandoned.  Pour CHACUN : même merge_id · statut inchangé ·
-- AUCUN redéplacement · consumed_at COALESCE-réparé. Chaque itération est isolée (sous-transaction).
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid;
        v_statuses text[] := array['data_merged','billing_reconciliation_pending',
          'billing_conflict_manual_review','revocation_pending','completed','failed','conflict','abandoned'];
        v_st text; v_id uuid; v_out uuid; v_out_st text; v_sid uuid; v_ct timestamptz;
begin
  foreach v_st in array v_statuses loop
    begin  -- sous-transaction : annulée à la fin de l'itération (fixtures isolées)
      insert into public.identity_merges(from_user_id, to_user_id, status, ticket_hash, completed_at)
        values (v_a, v_b, v_st, 't-replay',
                case when v_st in ('completed','failed','conflict','abandoned') then now() else null end)
        returning merge_id into v_id;
      insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)  -- consumed_at NULL
        values ('t-replay', v_a, now() + interval '15 min');
      insert into public.sessions(user_id) values (v_a) returning id into v_sid;  -- ne doit PAS bouger

      select merge_id, status into v_out, v_out_st from public.identity_claim_and_merge('t-replay', v_b);

      if v_out <> v_id then raise exception 'replay %: merge_id changé', v_st; end if;
      if v_out_st <> v_st then raise exception 'replay %: statut changé (%)', v_st, v_out_st; end if;
      if not exists (select 1 from public.sessions where id=v_sid and user_id=v_a) then
        raise exception 'replay %: session redéplacée', v_st; end if;
      select consumed_at into v_ct from public.identity_merge_tickets where ticket_hash='t-replay';
      if v_ct is null then raise exception 'replay %: consumed_at non réparé', v_st; end if;
      raise notice 'replay % OK', v_st;

      raise exception 'ROLLBACK_ITER';  -- annule les fixtures de cette itération
    exception when others then
      if sqlerrm <> 'ROLLBACK_ITER' then raise; end if;  -- ré-émet les vraies erreurs
    end;
  end loop;
  raise notice '18 OK (8 statuts idempotents)';
end $$;
rollback;

-- ══════════ 21. ticket_consumed_without_merge (EXCEPTION) ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid;
begin
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at, consumed_at)
    values ('t-cwm', v_a, now() + interval '15 min', now());  -- consommé mais SANS merge
  begin
    perform public.identity_claim_and_merge('t-cwm', v_b);
    raise exception '21: exception non levée';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'ticket_consumed_without_merge' then
      raise exception '21: attendu ticket_consumed_without_merge, obtenu %', sqlerrm; end if;
  end;
  raise notice '21 OK';
end $$;
rollback;

-- ══════════ 22. ticket_consumed_mismatch (merge existant, autre B) → EXCEPTION ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid; v_c uuid := gen_random_uuid();
begin
  insert into public.identity_merges(from_user_id, to_user_id, status, ticket_hash)
    values (v_a, v_c, 'revocation_pending', 't-mism');  -- merge existant vers C
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at, consumed_at)
    values ('t-mism', v_a, now() + interval '15 min', now());
  begin
    perform public.identity_claim_and_merge('t-mism', v_b);  -- demande B ≠ C
    raise exception '22: exception non levée';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'ticket_consumed_mismatch' then
      raise exception '22: attendu ticket_consumed_mismatch, obtenu %', sqlerrm; end if;
  end;
  raise notice '22 OK';
end $$;
rollback;

-- ══════════ 23. Reprise waiting → précondition devenue invalide → même ligne en conflict ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid; v_id1 uuid; v_id2 uuid; v_st text; v_fc text;
begin
  insert into public.generation_intents(intent_id, user_id, status) values ('gi-resume', v_a, 'RUNNING');
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)
    values ('t-resume', v_a, now() + interval '15 min');
  select merge_id, status into v_id1, v_st from public.identity_claim_and_merge('t-resume', v_b);
  if v_st <> 'waiting_for_settlement' then raise exception '23: 1er appel attendu waiting, obtenu %', v_st; end if;
  -- settlement terminé MAIS B devient merged_closed
  update public.generation_intents set status='SUCCEEDED' where intent_id='gi-resume';
  insert into public.account_state(user_id, merged_closed) values (v_b, true)
    on conflict (user_id) do update set merged_closed = true;
  select merge_id, status, failure_code into v_id2, v_st, v_fc from public.identity_claim_and_merge('t-resume', v_b);
  if v_st <> 'conflict' or v_fc <> 'b_merged_closed' then
    raise exception '23: reprise attendue conflict/b_merged_closed, obtenu %/%', v_st, v_fc; end if;
  if v_id1 <> v_id2 then raise exception '23: merge_id changé à la reprise'; end if;
  raise notice '23 OK';
end $$;
rollback;

-- ══════════ 23b. Reprise RUNNING → précondition devenue invalide → même ligne en conflict ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid; v_id uuid; v_out uuid; v_st text; v_fc text;
begin
  insert into public.identity_merges(from_user_id, to_user_id, status, ticket_hash)
    values (v_a, v_b, 'running', 't-run-resume') returning merge_id into v_id;
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)
    values ('t-run-resume', v_a, now() + interval '15 min');
  insert into public.account_state(user_id, merged_closed) values (v_b, true)  -- B devient fermé
    on conflict (user_id) do update set merged_closed = true;
  select merge_id, status, failure_code into v_out, v_st, v_fc
    from public.identity_claim_and_merge('t-run-resume', v_b);
  if v_st <> 'conflict' or v_fc <> 'b_merged_closed' then
    raise exception '23b: reprise running attendue conflict/b_merged_closed, obtenu %/%', v_st, v_fc; end if;
  if v_out <> v_id then raise exception '23b: merge_id changé'; end if;
  if not exists (select 1 from public.identity_merge_tickets where ticket_hash='t-run-resume' and consumed_at is not null) then
    raise exception '23b: ticket non consommé'; end if;
  raise notice '23b OK';
end $$;
rollback;

-- ══════════ 24. HOLD soldé (COMMIT même user+intent) → ne bloque plus ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid; v_st text;
begin
  insert into public.ledger_entries(user_id, entry_type, available_delta, reference_type, reference_id, idempotency_key)
    values (v_b, 'HOLD', -1, 'GENERATION_INTENT', 'int-settled', 'hold:int-settled');
  insert into public.ledger_entries(user_id, entry_type, available_delta, reference_type, reference_id, idempotency_key)
    values (v_b, 'COMMIT', 0, 'GENERATION_INTENT', 'int-settled', 'commit:int-settled');
  insert into public.sessions(user_id) values (v_a);
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)
    values ('t-settled', v_a, now() + interval '15 min');
  select status into v_st from public.identity_claim_and_merge('t-settled', v_b);
  if v_st = 'waiting_for_settlement' then raise exception '24: HOLD soldé bloque encore'; end if;
  if v_st <> 'revocation_pending' then raise exception '24: attendu revocation_pending, obtenu %', v_st; end if;
  raise notice '24 OK';
end $$;
rollback;

-- ══════════ 25. COMMIT d'un AUTRE user, même intent → ne solde PAS le HOLD ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid; v_st text;
begin
  insert into public.ledger_entries(user_id, entry_type, available_delta, reference_type, reference_id, idempotency_key)
    values (v_b, 'HOLD', -1, 'GENERATION_INTENT', 'int-shared', 'hold:int-shared');
  -- COMMIT homonyme mais pour A (autre user) → ne doit PAS solder le HOLD de B
  insert into public.ledger_entries(user_id, entry_type, available_delta, reference_type, reference_id, idempotency_key)
    values (v_a, 'COMMIT', 0, 'GENERATION_INTENT', 'int-shared', 'commit:int-shared');
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)
    values ('t-shared', v_a, now() + interval '15 min');
  select status into v_st from public.identity_claim_and_merge('t-shared', v_b);
  if v_st <> 'waiting_for_settlement' then
    raise exception '25: COMMIT d''un autre user a soldé le HOLD (obtenu %)', v_st; end if;
  raise notice '25 OK';
end $$;
rollback;

-- ══════════ 26. promo_redemptions : doublon reste sur A · non-colliding déplacé ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid; v_pc1 uuid; v_pc2 uuid; v_st text;
begin
  insert into public.promo_codes(code, type) values ('MERGECODE1','unlimited') returning id into v_pc1;
  insert into public.promo_codes(code, type) values ('MERGECODE2','unlimited') returning id into v_pc2;
  insert into public.promo_redemptions(promo_code_id, user_id) values (v_pc1, v_a);  -- doublon (aussi sur B)
  insert into public.promo_redemptions(promo_code_id, user_id) values (v_pc1, v_b);
  insert into public.promo_redemptions(promo_code_id, user_id) values (v_pc2, v_a);  -- non-colliding
  insert into public.sessions(user_id) values (v_a);
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)
    values ('t-promo', v_a, now() + interval '15 min');
  select status into v_st from public.identity_claim_and_merge('t-promo', v_b);
  if v_st <> 'revocation_pending' then raise exception '26: attendu revocation_pending, obtenu %', v_st; end if;
  if not exists (select 1 from public.promo_redemptions where promo_code_id=v_pc1 and user_id=v_a) then
    raise exception '26: le doublon de A a été supprimé/déplacé'; end if;
  if not exists (select 1 from public.promo_redemptions where promo_code_id=v_pc2 and user_id=v_b) then
    raise exception '26: la redemption non-colliding n''a pas été déplacée'; end if;
  if exists (select 1 from public.promo_redemptions where promo_code_id=v_pc2 and user_id=v_a) then
    raise exception '26: la redemption non-colliding est encore sur A'; end if;
  raise notice '26 OK';
end $$;
rollback;

-- ══════════ 27. Happy COMPLET : 4 tables déplacées · financier + trial INCHANGÉS ══════════
begin;
do $$
declare v_a uuid := current_setting('identity_test.a')::uuid;
        v_b uuid := current_setting('identity_test.b')::uuid;
        v_status text; v_prod uuid; v_led_before int; v_led_after int;
begin
  insert into public.products(sku, type, credits_granted) values ('test_merge_pass','PASS',30) returning id into v_prod;
  insert into public.sessions(user_id) values (v_a);
  insert into public.usage_log(user_id, call_type, status) values (v_a, 'generate', 'success');
  insert into public.generation_intents(intent_id, user_id, status) values ('gi-happy', v_a, 'SUCCEEDED');
  insert into public.device_tokens(token, user_id, platform) values ('dt-happy', v_a, 'ios');
  -- financier : PASS inactif (n'active pas le premium, ne doit pas bouger) + order + ledger
  insert into public.passes(user_id, product_id, starts_at, ends_at, status)
    values (v_a, v_prod, now()-interval '10 day', now()-interval '1 day', 'EXPIRED');
  insert into public.orders(user_id, product_id, provider, idempotency_key)
    values (v_a, v_prod, 'revenuecat', 'ord-happy');
  insert into public.ledger_entries(user_id, entry_type, available_delta, idempotency_key)
    values (v_a, 'GRANT', 5, 'grant-happy');
  select count(*) into v_led_before from public.ledger_entries where user_id=v_a;
  insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at)
    values ('t-full', v_a, now() + interval '15 min');

  select status into v_status from public.identity_claim_and_merge('t-full', v_b);
  if v_status <> 'revocation_pending' then raise exception '27: attendu revocation_pending, obtenu %', v_status; end if;
  -- déplacés vers B
  if exists (select 1 from public.sessions           where user_id=v_a) then raise exception '27: sessions non déplacées'; end if;
  if exists (select 1 from public.usage_log          where user_id=v_a) then raise exception '27: usage_log non déplacé'; end if;
  if exists (select 1 from public.generation_intents where user_id=v_a) then raise exception '27: generation_intents non déplacé'; end if;
  if exists (select 1 from public.device_tokens      where user_id=v_a) then raise exception '27: device_tokens non déplacé'; end if;
  if not exists (select 1 from public.device_tokens where token='dt-happy' and user_id=v_b) then
    raise exception '27: device_token pas chez B'; end if;
  -- financier INCHANGÉ (reste sur A)
  if not exists (select 1 from public.passes where user_id=v_a and status='EXPIRED') then raise exception '27: pass déplacé (interdit)'; end if;
  if not exists (select 1 from public.orders where user_id=v_a and idempotency_key='ord-happy') then raise exception '27: order déplacé (interdit)'; end if;
  select count(*) into v_led_after from public.ledger_entries where user_id=v_a;
  if v_led_after <> v_led_before then raise exception '27: ledger de A modifié (% -> %)', v_led_before, v_led_after; end if;
  if exists (select 1 from public.ledger_entries where user_id=v_b and idempotency_key like 'trial:%') then
    raise exception '27: nouveau trial ledger créé pour B (interdit en Commit 2)'; end if;
  raise notice '27 OK';
end $$;
rollback;

-- ── FIN — chaque scénario doit émettre son NOTICE « N OK » ; sinon une EXCEPTION a été levée.
-- Couverture : 1 happy · 2 idempotence · 3 target_mismatch · 4 duplicate · 5 cycle · 6a/6b settlement ·
-- 7 premium/premium · 8 A-prem/B-free · 9 same_user · 10 reprise post-expiration · 11/11b tickets ·
-- 12 b_not_found · 13 a_merged_closed · 14 b_merged_closed · 15 b_has_blocking_merge · 16 unresolved_chain ·
-- 17 helper (a_not_found défense + a_not_anonymous + b_anonymous REQUIS via C) ·
-- 18 replay PARAMÉTRÉ des 8 statuts idempotents (data_merged/billing_reconciliation_pending/
--    billing_conflict_manual_review/revocation_pending/completed/failed/conflict/abandoned) ·
-- 21 ticket_consumed_without_merge · 22 ticket_consumed_mismatch · 23 reprise waiting→conflict ·
-- 23b reprise running→conflict · 24 HOLD soldé · 25 COMMIT autre-user · 26 promo dédup ·
-- 27 happy complet (4 tables déplacées + passes/orders/ledger/trial intacts).
