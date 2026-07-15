-- ============================================================================
-- _TEST_ft1_freetrial.sql — tests RUNTIME de FT1a UNIQUEMENT (rollback, SQL Editor)
-- ============================================================================
-- PRÉREQUIS UNIQUE : 20260717_ft1a_freetrial_signup_bonus.sql appliquée.
--   Ce test NE dépend PAS de la migration ft1b (le flip trial 3→1 est testé, de
--   façon entièrement réversible, par _TEST_ft1b_flip_rollback.sql). Il n'appelle
--   PAS billing_try_hold → aucune application durable de ft1b requise.
--
-- Insère des fixtures sous session_replication_role=replica (saute triggers + FK)
-- puis ROLLBACK — le ROLLBACK ne nettoie QUE ses propres fixtures ; aucune donnée
-- conservée, aucun compte réel touché, aucune migration modifiée.
--
-- Couvre : config 1/2/3, colonnes, mark, claim atomique, bonus nouveau compte,
-- SUR-CRÉDIT LEGACY (ancien TRIAL +3 → bonus 0, jamais 5), compte existant,
-- merged_closed, double claim, ABSENCE de nouveau verrou dans FT1a.
-- ============================================================================

begin;
set local session_replication_role = replica;

-- ── Fixtures auth.users (is_anonymous contrôlé) ─────────────────────────────
insert into auth.users (id, aud, role, is_anonymous, created_at, updated_at) values
  ('b0000000-0000-0000-0000-000000000000','authenticated','authenticated', false, now(), now()), -- n0 nouveau, aucun trial
  ('b1000000-0000-0000-0000-000000000000','authenticated','authenticated', false, now(), now()), -- n1 nouveau, TRIAL +1
  ('c0000000-0000-0000-0000-000000000000','authenticated','authenticated', false, now(), now()), -- l0 legacy TRIAL +3, 0 conso
  ('c1000000-0000-0000-0000-000000000000','authenticated','authenticated', false, now(), now()), -- l1 legacy, 1 conso
  ('c2000000-0000-0000-0000-000000000000','authenticated','authenticated', false, now(), now()), -- l2 legacy, 2 conso
  ('c3000000-0000-0000-0000-000000000000','authenticated','authenticated', false, now(), now()), -- l3 legacy, 3 conso
  ('d0000000-0000-0000-0000-000000000000','authenticated','authenticated', false, now(), now()), -- dc double-claim
  ('e0000000-0000-0000-0000-000000000000','authenticated','authenticated', false, now(), now()), -- ex compte existant (jamais marqué)
  ('a0000000-0000-0000-0000-000000000000','authenticated','authenticated', true,  now(), now()), -- an encore anonyme
  ('cc000000-0000-0000-0000-000000000000','authenticated','authenticated', false, now(), now()), -- cl_perm permanent+fermé (défensif)
  ('ce000000-0000-0000-0000-000000000000','authenticated','authenticated', true,  now(), now()), -- cl_anon anonyme+fermé (réaliste A)
  ('aa000000-0000-0000-0000-000000000000','authenticated','authenticated', true,  now(), now()), -- mka mark anonyme
  ('ab000000-0000-0000-0000-000000000000','authenticated','authenticated', false, now(), now()), -- mkp mark permanent
  ('ac000000-0000-0000-0000-000000000000','authenticated','authenticated', true,  now(), now()); -- mkg mark anon + déjà accordé

-- account_state : éligibles = marqués pendant l'anonymat (état END post-conversion)
insert into public.account_state (user_id, signup_bonus_eligible) values
  ('b0000000-0000-0000-0000-000000000000', true),
  ('b1000000-0000-0000-0000-000000000000', true),
  ('c0000000-0000-0000-0000-000000000000', true),
  ('c1000000-0000-0000-0000-000000000000', true),
  ('c2000000-0000-0000-0000-000000000000', true),
  ('c3000000-0000-0000-0000-000000000000', true),
  ('d0000000-0000-0000-0000-000000000000', true),
  ('a0000000-0000-0000-0000-000000000000', true);
insert into public.account_state (user_id, signup_bonus_eligible, merged_closed) values
  ('cc000000-0000-0000-0000-000000000000', true, true),       -- cl_perm permanent+fermé (défensif)
  ('ce000000-0000-0000-0000-000000000000', true, true);       -- cl_anon anonyme+fermé (réaliste), granted_at NULL
insert into public.account_state (user_id, signup_bonus_eligible, signup_bonus_granted_at) values
  ('ac000000-0000-0000-0000-000000000000', false, now());     -- mkg déjà accordé
-- ex, mka, mkp : PAS de ligne account_state

-- ledger : n1 = TRIAL +1 ; l0..l3 = TRIAL +3 + k HOLD(-1) (droits accordés = 3)
insert into public.ledger_entries (user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key) values
  ('b1000000-0000-0000-0000-000000000000','TRIAL', 1, null,'PROMO','trial','trial:b1000000-0000-0000-0000-000000000000'),
  ('c0000000-0000-0000-0000-000000000000','TRIAL', 3, null,'PROMO','trial','trial:c0000000-0000-0000-0000-000000000000'),
  ('c1000000-0000-0000-0000-000000000000','TRIAL', 3, null,'PROMO','trial','trial:c1000000-0000-0000-0000-000000000000'),
  ('c1000000-0000-0000-0000-000000000000','HOLD', -1, null,'GENERATION_INTENT','i1','hold:c1-i1'),
  ('c2000000-0000-0000-0000-000000000000','TRIAL', 3, null,'PROMO','trial','trial:c2000000-0000-0000-0000-000000000000'),
  ('c2000000-0000-0000-0000-000000000000','HOLD', -1, null,'GENERATION_INTENT','i1','hold:c2-i1'),
  ('c2000000-0000-0000-0000-000000000000','HOLD', -1, null,'GENERATION_INTENT','i2','hold:c2-i2'),
  ('c3000000-0000-0000-0000-000000000000','TRIAL', 3, null,'PROMO','trial','trial:c3000000-0000-0000-0000-000000000000'),
  ('c3000000-0000-0000-0000-000000000000','HOLD', -1, null,'GENERATION_INTENT','i1','hold:c3-i1'),
  ('c3000000-0000-0000-0000-000000000000','HOLD', -1, null,'GENERATION_INTENT','i2','hold:c3-i2'),
  ('c3000000-0000-0000-0000-000000000000','HOLD', -1, null,'GENERATION_INTENT','i3','hold:c3-i3');

do $$
declare v jsonb; n int; s int; t int; w int;
begin
  -- Tcfg — billing_free_config() = (1,2,3)
  select anon_free, signup_bonus, total_free into n, s, t from public.billing_free_config();
  if not (n=1 and s=2 and t=3) then raise exception 'FAILED Tcfg: (%,%,%)', n,s,t; end if;
  raise notice 'PASS Tcfg config=(1,2,3)';

  -- Tcols — colonnes account_state
  perform 1 from information_schema.columns where table_schema='public' and table_name='account_state'
    and column_name in ('signup_bonus_eligible','signup_bonus_granted_at') having count(*)=2;
  if not found then raise exception 'FAILED Tcols'; end if;
  raise notice 'PASS Tcols colonnes';

  -- ═══ LEGACY TRIAL +3 : aucun sur-crédit, bonus_due=0, droits conservés ═══
  -- T1 — TRIAL +3, 0 conso → reste 3, already_entitled, bonus 0, pas de signup
  v := public.billing_grant_signup_bonus('c0000000-0000-0000-0000-000000000000');
  if v->>'decision' <> 'already_entitled' then raise exception 'FAILED T1 decision=%', v->>'decision'; end if;
  if (v->>'bonus_granted')::int <> 0 then raise exception 'FAILED T1 bonus=%', v->>'bonus_granted'; end if;
  select available_credits into w from public.wallets where user_id='c0000000-0000-0000-0000-000000000000';
  if w is distinct from 3 then raise exception 'FAILED T1 wallet=% (attendu 3)', w; end if;
  raise notice 'PASS T1 legacy+3/0conso reste 3';

  -- T2 — TRIAL +3, 1 conso → reste 2
  v := public.billing_grant_signup_bonus('c1000000-0000-0000-0000-000000000000');
  if v->>'decision' <> 'already_entitled' then raise exception 'FAILED T2 decision=%', v->>'decision'; end if;
  select available_credits into w from public.wallets where user_id='c1000000-0000-0000-0000-000000000000';
  if w is distinct from 2 then raise exception 'FAILED T2 wallet=% (attendu 2)', w; end if;
  raise notice 'PASS T2 legacy+3/1conso reste 2';

  -- T3 — TRIAL +3, 2 conso → reste 1
  v := public.billing_grant_signup_bonus('c2000000-0000-0000-0000-000000000000');
  if v->>'decision' <> 'already_entitled' then raise exception 'FAILED T3 decision=%', v->>'decision'; end if;
  select available_credits into w from public.wallets where user_id='c2000000-0000-0000-0000-000000000000';
  if w is distinct from 1 then raise exception 'FAILED T3 wallet=% (attendu 1)', w; end if;
  raise notice 'PASS T3 legacy+3/2conso reste 1';

  -- T4 — TRIAL +3, 3 conso → reste 0
  v := public.billing_grant_signup_bonus('c3000000-0000-0000-0000-000000000000');
  if v->>'decision' <> 'already_entitled' then raise exception 'FAILED T4 decision=%', v->>'decision'; end if;
  select available_credits into w from public.wallets where user_id='c3000000-0000-0000-0000-000000000000';
  if w is distinct from 0 then raise exception 'FAILED T4 wallet=% (attendu 0)', w; end if;
  raise notice 'PASS T4 legacy+3/3conso reste 0';

  -- T5+T6 — AUCUNE entrée signup pour les 4 legacy, bonus_granted=0
  select count(*) into n from public.ledger_entries where idempotency_key in (
    'signup:c0000000-0000-0000-0000-000000000000','signup:c1000000-0000-0000-0000-000000000000',
    'signup:c2000000-0000-0000-0000-000000000000','signup:c3000000-0000-0000-0000-000000000000');
  if n <> 0 then raise exception 'FAILED T5: % entrées signup legacy (attendu 0)', n; end if;
  raise notice 'PASS T5+T6 aucun signup / bonus 0 pour legacy';

  -- ═══ NOUVEAUX COMPTES : bonus +2 ═══
  -- T8 — TRIAL +1 existant → signup +2, wallet 3
  v := public.billing_grant_signup_bonus('b1000000-0000-0000-0000-000000000000');
  if v->>'decision' <> 'granted' or (v->>'bonus_granted')::int <> 2 then raise exception 'FAILED T8: %', v; end if;
  select available_credits into w from public.wallets where user_id='b1000000-0000-0000-0000-000000000000';
  if w is distinct from 3 then raise exception 'FAILED T8 wallet=% (attendu 3)', w; end if;
  raise notice 'PASS T8 TRIAL+1 → +2 = 3';

  -- T9 — aucun trial → TRIAL +1 créé ET signup +2, wallet 3
  v := public.billing_grant_signup_bonus('b0000000-0000-0000-0000-000000000000');
  if v->>'decision' <> 'granted' or (v->>'bonus_granted')::int <> 2 then raise exception 'FAILED T9: %', v; end if;
  select coalesce(sum(available_delta),0) into t from public.ledger_entries
    where idempotency_key='trial:b0000000-0000-0000-0000-000000000000';
  if t <> 1 then raise exception 'FAILED T9: trial créé=% (attendu 1)', t; end if;
  select available_credits into w from public.wallets where user_id='b0000000-0000-0000-0000-000000000000';
  if w is distinct from 3 then raise exception 'FAILED T9 wallet=% (attendu 3)', w; end if;
  raise notice 'PASS T9 aucun trial → TRIAL+1 + signup+2 = 3';

  -- T10 — double claim (logique) → une seule attribution
  v := public.billing_grant_signup_bonus('d0000000-0000-0000-0000-000000000000');
  if v->>'decision' <> 'granted' then raise exception 'FAILED T10a: %', v->>'decision'; end if;
  v := public.billing_grant_signup_bonus('d0000000-0000-0000-0000-000000000000');
  if v->>'decision' <> 'already_processed' then raise exception 'FAILED T10b decision=% (attendu already_processed)', v->>'decision'; end if;
  select count(*) into n from public.ledger_entries where idempotency_key='signup:d0000000-0000-0000-0000-000000000000';
  if n <> 1 then raise exception 'FAILED T10: % entrées signup (attendu 1)', n; end if;
  raise notice 'PASS T10 double claim → une seule attribution';

  -- T11 — anon-init APRÈS claim ne réarme pas
  --   (a) permanent déjà accordé (dc) → not_anonymous, eligible reste false
  v := public.billing_mark_signup_eligible('d0000000-0000-0000-0000-000000000000');
  if v->>'reason' <> 'not_anonymous' then raise exception 'FAILED T11a reason=%', v->>'reason'; end if;
  perform 1 from public.account_state where user_id='d0000000-0000-0000-0000-000000000000' and signup_bonus_eligible=false;
  if not found then raise exception 'FAILED T11a: eligible réarmé'; end if;
  --   (b) anonyme + déjà accordé (mkg) → already_granted, pas de réarmement
  v := public.billing_mark_signup_eligible('ac000000-0000-0000-0000-000000000000');
  if v->>'reason' <> 'already_granted' then raise exception 'FAILED T11b reason=%', v->>'reason'; end if;
  perform 1 from public.account_state where user_id='ac000000-0000-0000-0000-000000000000' and signup_bonus_eligible=false;
  if not found then raise exception 'FAILED T11b: eligible réarmé après octroi'; end if;
  raise notice 'PASS T11 anon-init post-claim ne réarme pas';

  -- T12 — merged_closed refusé par mark ET grant, sur les DEUX états réels :
  --   (a) ANONYME+fermé (ce = ancien A après merge, réaliste) :
  --       mark → merged_closed ; grant → still_anonymous (l'anonymat gate d'abord).
  --   (b) PERMANENT+fermé (cc, défensif) :
  --       grant → merged_closed (le claim WHERE merged_closed=false échoue) ;
  --       mark → not_anonymous (mark refuse un permanent avant le check fermé).
  v := public.billing_mark_signup_eligible('ce000000-0000-0000-0000-000000000000');
  if v->>'reason' <> 'merged_closed' then raise exception 'FAILED T12a mark=%', v->>'reason'; end if;
  v := public.billing_grant_signup_bonus('ce000000-0000-0000-0000-000000000000');
  if v->>'reason' <> 'still_anonymous' then raise exception 'FAILED T12a grant=%', v->>'reason'; end if;
  v := public.billing_grant_signup_bonus('cc000000-0000-0000-0000-000000000000');
  if v->>'decision' <> 'merged_closed' then raise exception 'FAILED T12b grant=%', v->>'decision'; end if;
  v := public.billing_mark_signup_eligible('cc000000-0000-0000-0000-000000000000');
  if v->>'reason' <> 'not_anonymous' then raise exception 'FAILED T12b mark=%', v->>'reason'; end if;
  select count(*) into n from public.ledger_entries where user_id in
    ('cc000000-0000-0000-0000-000000000000','ce000000-0000-0000-0000-000000000000');
  if n <> 0 then raise exception 'FAILED T12: % lignes ledger ce+cc (attendu 0)', n; end if;
  raise notice 'PASS T12 merged_closed refusé (anon→merged_closed/still_anonymous · perm→merged_closed/not_anonymous)';

  -- T13 — FT1a ne contient AUCUN pg_advisory_xact_lock (verrou interdit).
  --   On cible le TOKEN D'APPEL EXACT 'pg_advisory_xact_lock' (pas le mot
  --   'advisory'/'pg_advisory' d'un commentaire : pg_get_functiondef renvoie
  --   aussi les commentaires du corps).
  if position('pg_advisory_xact_lock' in pg_get_functiondef('public.billing_grant_signup_bonus(uuid)'::regprocedure)) > 0
    then raise exception 'FAILED T13: advisory lock dans billing_grant_signup_bonus'; end if;
  if position('pg_advisory_xact_lock' in pg_get_functiondef('public.billing_mark_signup_eligible(uuid)'::regprocedure)) > 0
    then raise exception 'FAILED T13: advisory lock dans billing_mark_signup_eligible'; end if;
  raise notice 'PASS T13 aucun pg_advisory_xact_lock dans FT1a';

  -- ═══ GARDES ANONYMAT / COMPTE EXISTANT / MARK ═══
  -- Tex — compte existant jamais marqué → not_eligible, aucune écriture
  v := public.billing_grant_signup_bonus('e0000000-0000-0000-0000-000000000000');
  if v->>'decision' <> 'not_eligible' or v->>'reason' <> 'not_marked_eligible' then raise exception 'FAILED Tex: %', v; end if;
  select count(*) into n from public.ledger_entries where user_id='e0000000-0000-0000-0000-000000000000';
  if n <> 0 then raise exception 'FAILED Tex: écriture ledger'; end if;
  raise notice 'PASS Tex compte existant → aucun bonus';

  -- Tan — encore anonyme → still_anonymous, aucune écriture
  v := public.billing_grant_signup_bonus('a0000000-0000-0000-0000-000000000000');
  if v->>'reason' <> 'still_anonymous' then raise exception 'FAILED Tan: %', v; end if;
  select count(*) into n from public.ledger_entries where user_id='a0000000-0000-0000-0000-000000000000';
  if n <> 0 then raise exception 'FAILED Tan: écriture ledger'; end if;
  raise notice 'PASS Tan encore anonyme → refus';

  -- Tmka — mark anonyme frais → marked, eligible=true
  v := public.billing_mark_signup_eligible('aa000000-0000-0000-0000-000000000000');
  if (v->>'eligible')::boolean is not true or v->>'reason' <> 'marked' then raise exception 'FAILED Tmka: %', v; end if;
  perform 1 from public.account_state where user_id='aa000000-0000-0000-0000-000000000000' and signup_bonus_eligible=true;
  if not found then raise exception 'FAILED Tmka: non marqué'; end if;
  raise notice 'PASS Tmka mark anonyme → eligible';

  -- Tmkp — mark permanent → not_anonymous, aucune ligne créée
  v := public.billing_mark_signup_eligible('ab000000-0000-0000-0000-000000000000');
  if v->>'reason' <> 'not_anonymous' then raise exception 'FAILED Tmkp: %', v; end if;
  select count(*) into n from public.account_state where user_id='ab000000-0000-0000-0000-000000000000';
  if n <> 0 then raise exception 'FAILED Tmkp: ligne créée'; end if;
  raise notice 'PASS Tmkp mark permanent → refus';

  -- (Le flip trial 3→1 de billing_try_hold est testé, réversiblement, par
  --  _TEST_ft1b_flip_rollback.sql — PAS ici : ce fichier ne touche pas ft1b.)

  raise notice '=== FT1a : TOUS LES TESTS PASS (legacy+3 sans sur-crédit, aucun verrou) ===';
end $$;

rollback;
