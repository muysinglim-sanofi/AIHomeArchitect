-- ============================================================================
-- ROLLBACK of 20260911_pwa_prod_payment_rail_minimal. NOT APPLIED.
--
-- Removes the `pwa` schema created by the minimal payment rail. REFUSES if the
-- rail holds any row that records real money (paid, verified or granted): those
-- rows are the audit trail of a real payment and must never be dropped.
-- Removes nothing in public.*, auth.* or storage.*. Also remove `pwa` from
-- Settings -> API -> Exposed schemas afterwards (Dashboard).
-- ============================================================================
begin;

do $guard$
begin
  if to_regclass('pwa.payway_transactions') is not null and exists (
       select 1 from pwa.payway_transactions
        where state in ('PAID_PENDING_VERIFICATION', 'VERIFIED', 'GRANTED')) then
    raise exception 'pwa.payway_transactions records real payments - NOT dropping it.';
  end if;
  if exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
              where n.nspname = 'pwa' and c.relkind = 'r'
                and c.relname <> 'payway_transactions') then
    raise exception 'pwa holds more than the payment rail - this rollback is not for that schema.';
  end if;
end
$guard$;

drop schema pwa cascade;

commit;
