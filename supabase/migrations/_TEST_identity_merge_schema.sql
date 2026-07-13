-- ─────────────────────────────────────────────────────────────────────────────
-- _TEST_identity_merge_schema.sql — VALIDATION du Commit 1 (Unified Identity)
-- ─────────────────────────────────────────────────────────────────────────────
-- SQL PUR — exécutable dans le Supabase SQL Editor ou psql (aucune méta-commande
-- psql, que du SQL standard). À exécuter sur une BASE DE TEST / STAGING / LOCALE.
-- JAMAIS en production (les sections C et D écrivent dans un BEGIN…ROLLBACK).
-- Le préfixe "_TEST_" exclut ce fichier de l'application normale des migrations.
-- Prérequis : la migration 20260713_identity_merge_schema.sql est appliquée.
-- ─────────────────────────────────────────────────────────────────────────────

-- ======================= A. Existence des objets =======================

-- A1. Tables (attendu : 3 lignes)
select table_name
  from information_schema.tables
 where table_schema = 'public'
   and table_name in ('account_state','identity_merge_tickets','identity_merges')
 order by table_name;

-- A2. Index nommés (attendu : les 4)
select indexname
  from pg_indexes
 where schemaname = 'public'
   and indexname in (
     'identity_merge_tickets_from_user_idx',
     'identity_merges_one_blocking_attempt_per_source',
     'identity_merges_to_user_idx',
     'identity_merges_resume_idx'
   )
 order by indexname;

-- A3. L'index unique partiel doit couvrir EXACTEMENT les 7 statuts bloquants (inspection du prédicat)
select indexdef
  from pg_indexes
 where schemaname = 'public'
   and indexname = 'identity_merges_one_blocking_attempt_per_source';

-- A4. CHECK des 10 statuts (inspection de la définition)
select pg_get_constraintdef(c.oid) as status_check
  from pg_constraint c
 where c.conrelid = 'public.identity_merges'::regclass and c.contype = 'c';

-- A5. Fonction : stable (provolatile='s') + security definer (prosecdef=true)
select p.proname, p.provolatile, p.prosecdef
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'is_current_identity_active';

-- A6. Grants EXECUTE de la fonction (attendu : authenticated + service_role uniquement)
select grantee, privilege_type
  from information_schema.role_routine_grants
 where routine_schema = 'public' and routine_name = 'is_current_identity_active'
 order by grantee;

-- A7. Grants tables : anon/authenticated NE doivent avoir AUCUN privilège sur les 3 tables
--     (attendu : 0 ligne)
select grantee, table_name, privilege_type
  from information_schema.role_table_grants
 where table_schema = 'public'
   and table_name in ('account_state','identity_merge_tickets','identity_merges')
   and grantee in ('anon','authenticated')
 order by table_name, grantee;

-- A8. Policies RESTRICTIVE ajoutées (attendu : 3 lignes, permissive = 'RESTRICTIVE')
select tablename, policyname, permissive
  from pg_policies
 where schemaname = 'public'
   and policyname in (
     'sessions: active identity only',
     'messages: active identity only',
     'assets: active identity only'
   )
 order by tablename;

-- A9. Policies "owner access" existantes TOUJOURS présentes et INCHANGÉES (attendu : 3 lignes)
select tablename, policyname, permissive
  from pg_policies
 where schemaname = 'public'
   and policyname in ('sessions: owner access','messages: owner access','assets: owner access')
 order by tablename;

-- ======================= B. Backfill + dormance =======================

-- B1. CRITÈRE ROBUSTE : le backfill égale exactement la source (attendu : true ;
--     sur le live actuel les deux valent 19 ; sur une base locale vide : 0=0 → true aussi)
select
  (select count(*) from public.account_state where trial_ever_granted is true)
  =
  (select count(distinct user_id) from public.ledger_entries
    where idempotency_key like 'trial:%' and available_delta > 0)
  as backfill_matches_source;

-- B2. DORMANCE : aucune fermeture, aucune fusion, aucun ticket (attendu : 0 / 0 / 0)
select
  (select count(*) from public.account_state where merged_closed is true) as merged_closed_rows,
  (select count(*) from public.identity_merges)                            as merge_rows,
  (select count(*) from public.identity_merge_tickets)                     as ticket_rows;

-- ======= C. is_current_identity_active() : true (absent) puis false (fermé) — ROLLBACK =======
-- UUID synthétique (account_state n'a PAS de FK) → aucun compte réel requis.
begin;
  -- utilisateur inconnu ⇒ ACTIF par défaut
  select set_config('request.jwt.claims',
    json_build_object('sub','00000000-0000-4000-8000-000000000001','role','authenticated')::text, true);
  set local role authenticated;
  select public.is_current_identity_active() as expect_true;   -- attendu : t

  -- repasser superuser pour écrire l'état de test
  reset role;
  insert into public.account_state(user_id, merged_closed)
  values ('00000000-0000-4000-8000-000000000001', true)
  on conflict (user_id) do update set merged_closed = true;

  -- rejouer en tant que ce user : fermé
  select set_config('request.jwt.claims',
    json_build_object('sub','00000000-0000-4000-8000-000000000001','role','authenticated')::text, true);
  set local role authenticated;
  select public.is_current_identity_active() as expect_false;  -- attendu : f
rollback;   -- AUCUNE donnée modifiée

-- ======= D. RLS : un user merged_closed est bloqué sur sessions/messages/assets — ROLLBACK =======
-- SELF-ASSERTING : lève une exception si (a) le placeholder n'a pas été remplacé, (b) la baseline
-- n'a pas >=1 ligne visible dans CHACUNE des 3 tables, ou (c) l'après-fermeture n'est pas 0/0/0.
-- Fixtures session/message/asset créées DANS la transaction pour le vrai user staging, puis ROLLBACK.
-- ⚠ Exécuter en tant que rôle privilégié (postgres/service_role, bypass RLS pour créer les fixtures).
-- ⚠ REMPLACER v_user par un UUID de compte STAGING réel (existe dans auth.users).
begin;
do $$
declare
  v_user   uuid := '00000000-0000-0000-0000-000000000000';   -- ⟵ REMPLACER par un vrai user staging
  v_claims text;
  v_sid    uuid;
  v_s int; v_m int; v_a int;
begin
  -- (a) interdire un faux test avec le placeholder
  if v_user = '00000000-0000-0000-0000-000000000000' then
    raise exception 'Section D : remplace v_user par un UUID de compte STAGING réel avant exécution';
  end if;
  v_claims := json_build_object('sub', v_user::text, 'role', 'authenticated')::text;

  -- fixtures (en tant que rôle privilégié → insertion directe)
  insert into public.sessions(user_id) values (v_user) returning id into v_sid;
  insert into public.messages(session_id, role, content) values (v_sid, 'user', 'rls-test');
  insert into public.assets(session_id, type, url)        values (v_sid, 'upload', 'https://rls-test.invalid/x');

  -- (b) baseline en tant que user ACTIF : chaque table doit voir >= 1 ligne
  perform set_config('request.jwt.claims', v_claims, true);
  set local role authenticated;
  select count(*) into v_s from public.sessions;
  select count(*) into v_m from public.messages;
  select count(*) into v_a from public.assets;
  reset role;
  if v_s < 1 or v_m < 1 or v_a < 1 then
    raise exception 'Section D baseline : attendu >=1 partout, obtenu sessions=% messages=% assets=%', v_s, v_m, v_a;
  end if;

  -- fermer l'identité
  insert into public.account_state(user_id, merged_closed) values (v_user, true)
  on conflict (user_id) do update set merged_closed = true;

  -- (c) après fermeture : les 3 tables doivent être EXACTEMENT à 0
  perform set_config('request.jwt.claims', v_claims, true);
  set local role authenticated;
  select count(*) into v_s from public.sessions;
  select count(*) into v_m from public.messages;
  select count(*) into v_a from public.assets;
  reset role;
  if v_s <> 0 or v_m <> 0 or v_a <> 0 then
    raise exception 'Section D après merged_closed : attendu 0/0/0, obtenu sessions=% messages=% assets=%', v_s, v_m, v_a;
  end if;

  raise notice 'Section D OK : baseline>=1 sur sessions/messages/assets, puis 0/0/0 après merged_closed';
end $$;
rollback;   -- AUCUNE fixture ni fermeture ne persiste

-- ── Critères : A tous présents · B1 = true (live 19=19) · B2 = 0/0/0 ·
--    C = t puis f · D = NOTICE "Section D OK" (sinon une EXCEPTION est levée).
