-- ============================================================================
-- ROLLBACK of 20260911_billing_grant_perpetual_pack. NOT APPLIED.
--
-- Restores the production definition of public.billing_grant_purchase exactly
-- as it was read on 2026-09-11 (md5 of pg_get_functiondef = b42b47cb68773f11b02875d685d4e2f9).
--
-- The original definition is embedded as BASE64, not as SQL text. Its body
-- contains CRLF line endings, and a text file loses them to any editor or git
-- line-ending normalisation — the first version of this rollback restored a
-- body that differed only by those characters, and its own md5 check refused
-- it (dry run on production, 2026-09-11). Base64 survives any of that.
--
-- Two checks: the embedded payload must hash to the original BEFORE it is
-- executed, and the live definition must hash to it AFTER.
--
-- public.billing_perpetual_ends_at() is LEFT in place on purpose: passes already
-- granted as perpetual carry its value (a date), nothing else references it,
-- and removing it is optional (commented below).
-- After this rollback, a perpetual pack can no longer be granted (it fails as
-- before) — do not roll back while the Web rail is open for sale.
-- ============================================================================

begin;

do $restore$
declare
  v_def text := convert_from(decode('Q1JFQVRFIE9SIFJFUExBQ0UgRlVOQ1RJT04gcHVibGljLmJpbGxpbmdfZ3JhbnRfcHVyY2hhc2UocF91c2VyX2lkIHV1aWQsIHBfcHJvdmlkZXIgdGV4dCwgcF9wcm92aWRlcl90cmFuc2FjdGlvbl9pZCB0ZXh0LCBwX3Byb2R1Y3RfaWQgdXVpZCwgcF9jcmVkaXRzIGludGVnZXIsIHBfZHVyYXRpb25fZGF5cyBpbnRlZ2VyLCBwX2Ftb3VudCBudW1lcmljLCBwX2N1cnJlbmN5IHRleHQsIHBfZW5kc19hdCB0aW1lc3RhbXAgd2l0aCB0aW1lIHpvbmUsIHBfcmF3X3BheWxvYWQganNvbmIpCiBSRVRVUk5TIGpzb25iCiBMQU5HVUFHRSBwbHBnc3FsCkFTICRmdW5jdGlvbiQNCmRlY2xhcmUNCiAgdl9vcmRlcl9pZCB1dWlkOyB2X3Bhc3NfaWQgdXVpZDsgdl9wYXltZW50X25ldyBib29sZWFuIDo9IGZhbHNlOyB2X2dyYW50X25ldyBib29sZWFuIDo9IGZhbHNlOw0KICB2X29yZGVyX2tleSB0ZXh0IDo9ICdvcmRlcjonIHx8IHBfcHJvdmlkZXIgfHwgJzonIHx8IHBfcHJvdmlkZXJfdHJhbnNhY3Rpb25faWQ7DQogIHZfZ3JhbnRfa2V5IHRleHQ7IHZfZW5kc19hdCB0aW1lc3RhbXB0ejsgdl9hdmFpbGFibGUgaW50Ow0KYmVnaW4NCiAgdl9lbmRzX2F0IDo9IGNvYWxlc2NlKHBfZW5kc19hdCwgbm93KCkgKyBtYWtlX2ludGVydmFsKGRheXMgPT4gcF9kdXJhdGlvbl9kYXlzKSk7DQoNCiAgaW5zZXJ0IGludG8gcHVibGljLm9yZGVycyAodXNlcl9pZCwgcHJvZHVjdF9pZCwgc3RhdHVzLCBwcm92aWRlciwgYW1vdW50LCBjdXJyZW5jeSwgaWRlbXBvdGVuY3lfa2V5KQ0KICB2YWx1ZXMgKHBfdXNlcl9pZCwgcF9wcm9kdWN0X2lkLCAnUEFJRCcsIHBfcHJvdmlkZXIsIHBfYW1vdW50LCBjb2FsZXNjZShwX2N1cnJlbmN5LCdVU0QnKSwgdl9vcmRlcl9rZXkpDQogIG9uIGNvbmZsaWN0IChpZGVtcG90ZW5jeV9rZXkpIGRvIHVwZGF0ZSBzZXQgc3RhdHVzPSdQQUlEJywgdXBkYXRlZF9hdD1ub3coKQ0KICByZXR1cm5pbmcgaWQgaW50byB2X29yZGVyX2lkOw0KDQogIHZfZ3JhbnRfa2V5IDo9ICdncmFudDpvcmRlcjonIHx8IHZfb3JkZXJfaWQ6OnRleHQ7DQoNCiAgaW5zZXJ0IGludG8gcHVibGljLnBheW1lbnRzIChvcmRlcl9pZCwgcHJvdmlkZXIsIHByb3ZpZGVyX3RyYW5zYWN0aW9uX2lkLCBzdGF0dXMsIGFtb3VudCwgY3VycmVuY3ksIHJhd19wYXlsb2FkKQ0KICB2YWx1ZXMgKHZfb3JkZXJfaWQsIHBfcHJvdmlkZXIsIHBfcHJvdmlkZXJfdHJhbnNhY3Rpb25faWQsICdTVUNDRVNTJywgcF9hbW91bnQsIHBfY3VycmVuY3ksIHBfcmF3X3BheWxvYWQpDQogIG9uIGNvbmZsaWN0IChwcm92aWRlciwgcHJvdmlkZXJfdHJhbnNhY3Rpb25faWQpIGRvIG5vdGhpbmc7DQogIHZfcGF5bWVudF9uZXcgOj0gZm91bmQ7DQoNCiAgaW5zZXJ0IGludG8gcHVibGljLnBhc3NlcyAodXNlcl9pZCwgcHJvZHVjdF9pZCwgc291cmNlX29yZGVyX2lkLCBzdGFydHNfYXQsIGVuZHNfYXQsIHN0YXR1cykNCiAgdmFsdWVzIChwX3VzZXJfaWQsIHBfcHJvZHVjdF9pZCwgdl9vcmRlcl9pZCwgbm93KCksIHZfZW5kc19hdCwgJ0FDVElWRScpDQogIG9uIGNvbmZsaWN0IChzb3VyY2Vfb3JkZXJfaWQpIGRvIG5vdGhpbmc7DQogIHNlbGVjdCBpZCBpbnRvIHZfcGFzc19pZCBmcm9tIHB1YmxpYy5wYXNzZXMgd2hlcmUgc291cmNlX29yZGVyX2lkID0gdl9vcmRlcl9pZDsNCg0KICBpbnNlcnQgaW50byBwdWJsaWMubGVkZ2VyX2VudHJpZXMNCiAgICAodXNlcl9pZCwgZW50cnlfdHlwZSwgYXZhaWxhYmxlX2RlbHRhLCBwYXNzX2lkLCByZWZlcmVuY2VfdHlwZSwgcmVmZXJlbmNlX2lkLCBpZGVtcG90ZW5jeV9rZXkpDQogIHZhbHVlcyAocF91c2VyX2lkLCAnR1JBTlQnLCBwX2NyZWRpdHMsIHZfcGFzc19pZCwgJ09SREVSJywgdl9vcmRlcl9pZDo6dGV4dCwgdl9ncmFudF9rZXkpDQogIG9uIGNvbmZsaWN0IChpZGVtcG90ZW5jeV9rZXkpIGRvIG5vdGhpbmc7DQogIHZfZ3JhbnRfbmV3IDo9IGZvdW5kOw0KDQogIHBlcmZvcm0gcHVibGljLmJpbGxpbmdfcmVwcm9qZWN0X3dhbGxldChwX3VzZXJfaWQpOyAgIC0tIHByb2plY3Rpb24gUEFTUy1BV0FSRQ0KICBzZWxlY3QgYXZhaWxhYmxlX2NyZWRpdHMgaW50byB2X2F2YWlsYWJsZSBmcm9tIHB1YmxpYy53YWxsZXRzIHdoZXJlIHVzZXJfaWQgPSBwX3VzZXJfaWQ7DQoNCiAgcmV0dXJuIGpzb25iX2J1aWxkX29iamVjdCgNCiAgICAnb2snLCB0cnVlLA0KICAgICdzdGF0dXMnLCBjYXNlIHdoZW4gdl9ncmFudF9uZXcgdGhlbiAnZ3JhbnRlZCcgZWxzZSAnYWxyZWFkeV9wcm9jZXNzZWQnIGVuZCwNCiAgICAnb3JkZXJfaWQnLCB2X29yZGVyX2lkLCAncGFzc19pZCcsIHZfcGFzc19pZCwgJ3BheW1lbnRfbmV3Jywgdl9wYXltZW50X25ldywNCiAgICAnY3JlZGl0ZWQnLCB2X2dyYW50X25ldywNCiAgICAnY3JlZGl0cycsIGNhc2Ugd2hlbiB2X2dyYW50X25ldyB0aGVuIHBfY3JlZGl0cyBlbHNlIDAgZW5kLA0KICAgICdhdmFpbGFibGVfY3JlZGl0cycsIHZfYXZhaWxhYmxlKTsNCmVuZDsgJGZ1bmN0aW9uJAo=', 'base64'), 'UTF8');
begin
  if md5(v_def) <> 'b42b47cb68773f11b02875d685d4e2f9' then
    raise exception 'embedded original definition is corrupted - aborting.';
  end if;
  execute v_def;
end
$restore$;

do $check$
begin
  if md5(pg_get_functiondef('public.billing_grant_purchase(uuid,text,text,uuid,integer,integer,numeric,text,timestamptz,jsonb)'::regprocedure)) <> 'b42b47cb68773f11b02875d685d4e2f9' then
    raise exception 'restore did not reproduce the original definition - aborting.';
  end if;
end
$check$;

-- drop function if exists public.billing_perpetual_ends_at();

commit;
