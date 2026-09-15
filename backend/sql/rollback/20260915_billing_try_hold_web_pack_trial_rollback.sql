-- ============================================================================
-- ROLLBACK de 20260915_billing_try_hold_web_pack_trial.
-- Restaure la definition EXACTE d'avant le correctif (md5 a1aa52c0b152295c8828cb46451be2ba).
-- Effet du retour arriere : un acheteur de pack web reperd la projection de son
-- droit gratuit. Les lignes TRIAL deja materialisees NE sont PAS retirees (ledger
-- append-only) : elles restent un credit acquis, ce qui est le comportement sur.
-- RevenueCat / iOS ne sont concernes ni par le correctif ni par son retrait.
-- ============================================================================
begin;
CREATE OR REPLACE FUNCTION public.billing_try_hold(p_user_id uuid, p_intent_id text, p_tier text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_hold_key text := 'hold:' || p_intent_id;
  v_trial_key text := 'trial:' || p_user_id::text;
  v_active_pass uuid; v_pass int := 0; v_free_raw int := 0; v_free int := 0;
  v_trial_granted boolean := false; v_target_pass uuid; v_bucket text;
  v_total_before int; v_total_after int;
begin
  if exists (select 1 from public.ledger_entries where idempotency_key = v_hold_key) then
    return jsonb_build_object('granted', true, 'reason', '', 'idempotent', true, 'bucket', 'existing');
  end if;
  if p_tier in ('admin', 'promo_unlimited', 'promo_limited') then
    return jsonb_build_object('granted', true, 'reason', 'bypass', 'bucket', 'none');
  end if;
  perform pg_advisory_xact_lock(hashtext(p_user_id::text));
  select id into v_active_pass from public.passes
   where user_id = p_user_id and status = 'ACTIVE' and now() between starts_at and ends_at
   order by ends_at desc limit 1;
  if v_active_pass is not null then
    select coalesce(sum(available_delta), 0) into v_pass
      from public.ledger_entries where user_id = p_user_id and pass_id = v_active_pass;
  end if;
  select coalesce(sum(available_delta), 0), coalesce(bool_or(entry_type = 'TRIAL'), false)
    into v_free_raw, v_trial_granted
    from public.ledger_entries where user_id = p_user_id and pass_id is null;
  v_free := greatest(v_free_raw, 0);
  v_total_before := v_pass + v_free;
  if v_pass >= 1 then
    v_bucket := 'pass'; v_target_pass := v_active_pass;
  elsif v_free >= 1 then
    v_bucket := 'free'; v_target_pass := null;
  elsif p_tier = 'free' and v_active_pass is null and not v_trial_granted then
    insert into public.ledger_entries
      (user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
    values (p_user_id, 'TRIAL', 3, null, 'PROMO', 'trial', v_trial_key)
    on conflict (idempotency_key) do nothing;
    v_bucket := 'free'; v_target_pass := null;
  else
    return jsonb_build_object('granted', false,
      'reason', case when v_active_pass is not null then 'pass_exhausted'
                     when p_tier <> 'free' then 'no_active_pass'
                     else 'insufficient_credits' end,
      'total_before', v_total_before, 'total_after', v_total_before);
  end if;
  insert into public.ledger_entries
    (user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
  values (p_user_id, 'HOLD', -1, v_target_pass, 'GENERATION_INTENT', p_intent_id, v_hold_key)
  on conflict (idempotency_key) do nothing;
  perform public.billing_reproject_wallet(p_user_id);
  select available_credits into v_total_after from public.wallets where user_id = p_user_id;
  return jsonb_build_object('granted', true, 'reason', '', 'bucket', v_bucket, 'pass_id', v_target_pass,
    'total_before', v_total_before, 'total_after', coalesce(v_total_after, v_total_before - 1));
end; $function$
;
do $g$ begin
  if md5(pg_get_functiondef('public.billing_try_hold(uuid,text,text)'::regprocedure))
     <> 'a1aa52c0b152295c8828cb46451be2ba' then
    raise exception 'le retour arriere n a pas reproduit la definition d origine';
  end if;
end $g$;
commit;
