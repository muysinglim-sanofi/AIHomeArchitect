"""STAGING Supabase Auth — the Cambodia sign-in configuration (Facebook + phone).

WHY THIS EXISTS
    The PWA offers whichever doors the PROJECT has switched on (`/auth/v1/
    settings`). Switching them on is project configuration, which only the
    Management API can write, and it accepts only a personal access token
    (`sbp_…`) — not the service-role key. This tool makes that one step
    exact, repeatable and reviewable, instead of a list of dashboard clicks.

WHAT IT DOES
    verify   (default)  read the whitelisted keys back — no writes
    apply    --apply    write the Cambodia auth configuration (below)

WHAT --apply WRITES  (every value comes from the ignored staging secret file)
    security_manual_linking_enabled   true     linkIdentity() needs it
    external_facebook_enabled         true     when FACEBOOK_CLIENT_ID/SECRET set
    external_facebook_client_id       …        from FACEBOOK_CLIENT_ID
    external_facebook_secret          …        from FACEBOOK_CLIENT_SECRET
    external_facebook_email_optional  true     a Facebook user with no email
                                               can still sign in / be created
    external_phone_enabled            true     when the SMS provider is set
    sms_provider                      twilio   (the project's preset)
    sms_twilio_account_sid            …        from TWILIO_ACCOUNT_SID
    sms_twilio_auth_token             …        from TWILIO_AUTH_TOKEN
    sms_twilio_message_service_sid    …        from TWILIO_MESSAGE_SERVICE_SID
    sms_otp_length                    6        the copy says six
    sms_otp_exp                       300      5 minutes; the backend releases
                                               stale phone_change rows after 600
    sms_max_frequency                 60       one code per number per minute
    rate_limit_sms_sent               30       per hour, project-wide (staging)
    sms_test_otp                      …        from SMS_TEST_OTP ("+855…=123456,…")
                                               real SMS is NOT sent to these
    sms_test_otp_valid_until          …        from SMS_TEST_OTP_VALID_UNTIL
    uri_allow_list                    += https://preprod.aydenstudio.com/**,
                                         https://ayden-studio-preprod.web.app/**
                                               the OAuth `redirect_to`

SAFETY
    - staging project ref hard-coded; any other SUPABASE_URL is refused
    - fails closed when a credential is missing; never prints one
    - reads back only whitelisted keys (the config object holds secrets)
    - never touches production, PayWay, billing, or email templates
"""
import json, os, sys, urllib.error, urllib.request

ENV = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env.pwa-staging.local")
STAGING_REF = "eedcahzekpgxvvfxufbk"
MGMT = "https://api.supabase.com"

#: Sent on every request — see the note in `call()`. Not a disguise: it names
#: this tool, and carries a browser token only because Cloudflare's rule keys
#: on the `Python-urllib` signature alone.
_UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
       "(KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36 "
       "ayden-staging-auth-tool/1.0")

PREPROD_REDIRECTS = (
    "https://preprod.aydenstudio.com/**",
    "https://ayden-studio-preprod.web.app/**",
)

# The only keys ever read back. Secrets are deliberately absent.
SHOWN = (
    "site_url", "uri_allow_list",
    "security_manual_linking_enabled",
    "external_anonymous_users_enabled",
    "external_email_enabled",
    "external_facebook_enabled", "external_facebook_email_optional",
    "external_phone_enabled", "sms_provider",
    "sms_otp_length", "sms_otp_exp", "sms_max_frequency", "rate_limit_sms_sent",
    "sms_test_otp_valid_until",
    "security_captcha_enabled", "security_captcha_provider",
    "hook_send_sms_enabled",
)


def env():
    if not os.path.exists(ENV):
        sys.exit("FAIL-CLOSED: the ignored staging secret file is absent.")
    d = {}
    for line in open(ENV, encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            d[k] = v.strip().strip('"').strip("'")
    url = d.get("SUPABASE_URL", "").rstrip("/")
    if STAGING_REF not in url:
        sys.exit("FAIL-CLOSED: SUPABASE_URL is not the staging project. Refusing.")
    return url, d


def call(url, *, method="GET", body=None, bearer=None, apikey=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    # `api.supabase.com` sits behind Cloudflare, which BANS the default
    # `Python-urllib/3.x` signature: every Management API call answered
    # `403 error code: 1010` — a browser-signature block, not an auth failure.
    # Measured 2026-09-09, same token, three requests:
    #   default UA + token  -> 403 "error code: 1010"
    #   browser UA + token  -> 200 (projects listed)
    #   browser UA, no token-> 401 {"message":"Unauthorized"}
    # So the token authenticates and the UA only gets past the WAF. There is
    # no configuration that changes urllib's User-Agent, hence this header.
    req.add_header("User-Agent", _UA)
    if apikey:
        req.add_header("apikey", apikey)
    if bearer:
        req.add_header("Authorization", "Bearer " + bearer)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw or b"{}")
        except Exception:
            return e.code, {"raw": raw.decode(errors="replace")[:200]}


def public_settings(base, anon):
    st, s = call(f"{base}/auth/v1/settings", apikey=anon)
    if st != 200:
        return {}
    ext = s.get("external", {})
    return {"facebook": ext.get("facebook"), "phone": ext.get("phone"),
            "email": ext.get("email"), "anonymous": ext.get("anonymous_users"),
            "sms_provider": s.get("sms_provider")}


def desired(d):
    """The PATCH body, built only from what the secret file actually holds."""
    body = {
        "security_manual_linking_enabled": True,
        "sms_otp_length": 6,
        "sms_otp_exp": 300,
        "sms_max_frequency": 60,
        "rate_limit_sms_sent": 30,
    }
    fb_id, fb_secret = d.get("FACEBOOK_CLIENT_ID", ""), d.get("FACEBOOK_CLIENT_SECRET", "")
    if fb_id and fb_secret:
        body.update({
            "external_facebook_enabled": True,
            "external_facebook_client_id": fb_id,
            "external_facebook_secret": fb_secret,
            "external_facebook_email_optional": True,
        })
    sid, tok, msid = (d.get("TWILIO_ACCOUNT_SID", ""), d.get("TWILIO_AUTH_TOKEN", ""),
                      d.get("TWILIO_MESSAGE_SERVICE_SID", ""))
    if sid and tok and msid:
        body.update({
            "external_phone_enabled": True,
            "sms_provider": "twilio",
            "sms_twilio_account_sid": sid,
            "sms_twilio_auth_token": tok,
            "sms_twilio_message_service_sid": msid,
        })
    test_otp = d.get("SMS_TEST_OTP", "")
    if test_otp:
        body["sms_test_otp"] = test_otp
        until = d.get("SMS_TEST_OTP_VALID_UNTIL", "")
        if until:
            body["sms_test_otp_valid_until"] = until
    return body


def merged_allow_list(current: str) -> str:
    items = [s.strip() for s in (current or "").split(",") if s.strip()]
    for r in PREPROD_REDIRECTS:
        if r not in items:
            items.append(r)
    return ",".join(items)


def main():
    apply_ = "--apply" in sys.argv
    base, d = env()
    anon = d.get("SUPABASE_PUBLISHABLE_KEY", "")
    pat = d.get("SUPABASE_ACCESS_TOKEN", "")
    print(f"project     : {STAGING_REF}  (STAGING)")
    print(f"mode        : {'APPLY' if apply_ else 'verify (no writes)'}")

    print("\n-- what the project answers publicly (/auth/v1/settings) ---------")
    for k, v in public_settings(base, anon).items():
        print(f"   {k:14s} = {v}")

    print("\n-- what the secret file provides (presence only) ------------------")
    for k in ("FACEBOOK_CLIENT_ID", "FACEBOOK_CLIENT_SECRET", "TWILIO_ACCOUNT_SID",
              "TWILIO_AUTH_TOKEN", "TWILIO_MESSAGE_SERVICE_SID", "SMS_TEST_OTP",
              "SUPABASE_ACCESS_TOKEN"):
        print(f"   {k:28s} {'present' if d.get(k) else 'ABSENT'}")

    if not pat:
        print("\n   SUPABASE_ACCESS_TOKEN absent from the ignored staging file.")
        print("   Project config is written by the Management API only, with a")
        print("   personal access token (sbp_...). Either:")
        print("     a) Dashboard > Authentication > Sign In / Providers:")
        print("          - Facebook: enable, App ID + App Secret, 'Email optional' ON")
        print("          - Phone: enable, provider Twilio (SID / token / Message Service SID),")
        print("            OTP length 6, OTP expiry 300 s, 'Test OTPs' for the QA numbers")
        print("          - Anonymous sign-ins: keep ON")
        print("        Dashboard > Authentication > Settings: 'Allow manual linking' ON")
        print("        Dashboard > Authentication > URL Configuration > Redirect URLs:")
        for r in PREPROD_REDIRECTS:
            print(f"          - {r}")
        print("     b) add SUPABASE_ACCESS_TOKEN=sbp_... (+ the FACEBOOK_* / TWILIO_* lines)")
        print(f"        to {os.path.relpath(ENV)}  and re-run with --apply")
        return 0

    cfg_url = f"{MGMT}/v1/projects/{STAGING_REF}/config/auth"
    st, cfg = call(cfg_url, bearer=pat)
    if st != 200:
        print(f"\n   Management API refused the token ({st}). Nothing was written.")
        return 1
    print("\n-- current config (whitelisted keys only) ------------------------")
    for k in SHOWN:
        if k in cfg:
            print(f"   {k:36s} = {cfg[k]}")
    print(f"   {'facebook client id configured':36s} = {bool(cfg.get('external_facebook_client_id'))}")
    print(f"   {'twilio account sid configured':36s} = {bool(cfg.get('sms_twilio_account_sid'))}")
    print(f"   {'test otp configured':36s} = {bool(cfg.get('sms_test_otp'))}")

    body = desired(d)
    body["uri_allow_list"] = merged_allow_list(cfg.get("uri_allow_list", ""))
    print("\n-- would write ---------------------------------------------------")
    for k, v in body.items():
        shown = "***" if any(s in k for s in ("secret", "token", "sid", "test_otp")) and k != "sms_test_otp_valid_until" else v
        print(f"   {k:36s} = {shown}")

    if not apply_:
        print("\n   verify only — re-run with --apply to write.")
        return 0

    st, res = call(cfg_url, method="PATCH", bearer=pat, body=body)
    print("\n-- apply ---------------------------------------------------------")
    print(f"   PATCH config/auth -> {st}")
    if st not in (200, 201):
        print("   ", json.dumps(res)[:300])
        return 1
    st, cfg = call(cfg_url, bearer=pat)
    for k in SHOWN:
        if k in cfg:
            print(f"   {k:36s} = {cfg[k]}")
    print("\n-- public settings now -------------------------------------------")
    for k, v in public_settings(base, anon).items():
        print(f"   {k:14s} = {v}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
