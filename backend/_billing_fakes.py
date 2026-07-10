"""P0 Billing Integrity — FilterSupa : mock Supabase in-memory qui FILTRE réellement
(eq / neq / is_ null / lte / lt / gt / gte), modélise l'idempotence ledger (upsert
on_conflict=idempotency_key ignore_duplicates) et la reprojection wallet ADDITIVE
(miroir du SQL billing_reproject_wallet). Sert à tester la logique billing Python
(reserve_decision, apply_billing) sans DB. Le SQL/RPC réel est couvert en E2E DB.

NON auto-exécutant : importable par les validateurs (`from _billing_fakes import FilterSupa`).
"""
from datetime import datetime, timezone


class _Res:
    def __init__(self, data): self.data = data


class _Query:
    def __init__(self, fake, table):
        self._f = fake
        self._t = table
        self._filters = []
        self._limit = None
        self._insert = None
        self._update = None
        self._upsert = None
        self._on_conflict = None
        self._ignore_dup = False

    # ── builders (chaînables) ──
    def select(self, *a, **k): return self
    def order(self, *a, **k): return self
    def limit(self, n=None, *a, **k): self._limit = n; return self
    def eq(self, col, val): self._filters.append(("eq", col, val)); return self
    def neq(self, col, val): self._filters.append(("neq", col, val)); return self
    def is_(self, col, val): self._filters.append(("is", col, val)); return self
    def lte(self, col, val): self._filters.append(("lte", col, val)); return self
    def lt(self, col, val): self._filters.append(("lt", col, val)); return self
    def gt(self, col, val): self._filters.append(("gt", col, val)); return self
    def gte(self, col, val): self._filters.append(("gte", col, val)); return self
    def insert(self, row): self._insert = row; return self
    def update(self, row): self._update = row; return self
    def upsert(self, row, **k):
        self._upsert = row
        self._on_conflict = k.get("on_conflict")
        self._ignore_dup = bool(k.get("ignore_duplicates"))
        return self

    def _match(self, row):
        for op, col, val in self._filters:
            cell = row.get(col)
            if op == "eq" and cell != val:
                return False
            if op == "neq" and cell == val:
                return False
            if op == "is":
                if str(val).lower() == "null":
                    if cell is not None:
                        return False
                elif cell != val:
                    return False
            if op == "lte" and not (cell is not None and cell <= val):
                return False
            if op == "lt" and not (cell is not None and cell < val):
                return False
            if op == "gt" and not (cell is not None and cell > val):
                return False
            if op == "gte" and not (cell is not None and cell >= val):
                return False
        return True

    def execute(self):
        self._f.query_log.append((self._t, [f[0] + ":" + str(f[1]) for f in self._filters]))
        if self._t == "passes":
            self._f.passes_queries += 1
        if self._t == "ledger_entries":
            self._f.ledger_queries += 1
        rows = self._f.tables.setdefault(self._t, [])
        if self._insert is not None:
            return self._f._do_insert(self._t, self._insert)
        if self._upsert is not None:
            return self._f._do_upsert(self._t, self._upsert, self._on_conflict, self._ignore_dup)
        if self._update is not None:
            matched = [r for r in rows if self._match(r)]
            for r in matched:
                r.update(self._update)
            return _Res([dict(r) for r in matched])
        matched = [r for r in rows if self._match(r)]
        if self._limit:
            matched = matched[: self._limit]
        return _Res([dict(r) for r in matched])


class FilterSupa:
    """tables = {name: [rows]}. Reproject additif appelé via rpc('billing_reproject_wallet')."""

    def __init__(self, tables=None):
        self.tables = {k: [dict(r) for r in v] for k, v in (tables or {}).items()}
        self.query_log = []
        self.rpc_calls = []
        self.passes_queries = 0
        self.ledger_queries = 0

    def table(self, name):
        return _Query(self, name)

    def rpc(self, name, params):
        # Réel : supa.rpc(name, params).execute() → renvoie un builder ; le side-effect
        # et le résultat sont produits dans .execute() (bon timing).
        self.rpc_calls.append((name, params))
        fake = self

        class _RpcCall:
            def execute(self):
                if name == "billing_reproject_wallet":
                    fake._reproject(params.get("p_user_id"))
                    return _Res(None)
                if name == "billing_try_hold":
                    return _Res(fake._try_hold(
                        params.get("p_user_id"), params.get("p_intent_id"), params.get("p_tier")))
                return _Res(None)

        return _RpcCall()

    def _try_hold(self, uid, intent_id, tier):
        """Miroir FIDÈLE du SQL billing_try_hold (séquentiel = effet de l'advisory-lock).
        Prouve la LOGIQUE (pass-first, deny, trial, idempotence, drain → min(N,bucket)).
        L'atomicité RÉELLE (advisory lock sous concurrence HTTP) = E2E DB post-apply."""
        now = datetime.now(timezone.utc).isoformat()
        hold_key = "hold:" + str(intent_id)
        led = self.tables.setdefault("ledger_entries", [])
        # 0) idempotence
        if any(r.get("idempotency_key") == hold_key for r in led):
            return {"granted": True, "reason": "", "idempotent": True, "bucket": "existing"}
        # 1) bypass
        if tier in ("admin", "promo_unlimited", "promo_limited"):
            return {"granted": True, "reason": "bypass", "bucket": "none"}
        # 3) recalc (sous "verrou")
        passes = [p for p in self.tables.get("passes", []) if p.get("user_id") == uid]
        active = None
        for p in passes:
            if (p.get("status") == "ACTIVE"
                    and (p.get("starts_at") is None or p["starts_at"] <= now)
                    and p.get("ends_at") is not None and p["ends_at"] > now):
                if active is None or p["ends_at"] > active["ends_at"]:
                    active = p
        uled = [r for r in led if r.get("user_id") == uid]
        v_pass = (sum(int(r.get("available_delta") or 0) for r in uled if r.get("pass_id") == active["id"])
                  if active else 0)
        free_raw = sum(int(r.get("available_delta") or 0) for r in uled if r.get("pass_id") is None)
        trial_granted = any(r.get("entry_type") == "TRIAL" for r in uled if r.get("pass_id") is None)
        v_free = max(0, free_raw)
        total_before = v_pass + v_free
        # 4) pass-first puis free ; sinon trial free-tier ; sinon deny
        if v_pass >= 1:
            bucket, target = "pass", active["id"]
        elif v_free >= 1:
            bucket, target = "free", None
        elif tier == "free" and active is None and not trial_granted:
            led.append({"user_id": uid, "entry_type": "TRIAL", "available_delta": 3,
                        "pass_id": None, "idempotency_key": "trial:" + str(uid)})
            bucket, target = "free", None
        else:
            reason = ("pass_exhausted" if active is not None
                      else ("no_active_pass" if tier != "free" else "insufficient_credits"))
            return {"granted": False, "reason": reason,
                    "total_before": total_before, "total_after": total_before}
        # 5) HOLD(-1) idempotent
        led.append({"user_id": uid, "entry_type": "HOLD", "available_delta": -1,
                    "pass_id": target, "idempotency_key": hold_key})
        # 6) reproject
        self._reproject(uid)
        return {"granted": True, "reason": "", "bucket": bucket, "pass_id": target,
                "total_before": total_before,
                "total_after": self.wallet(uid).get("available_credits", total_before - 1)}

    # ── writes ──
    def _do_insert(self, table, row):
        rows = self.tables.setdefault(table, [])
        rows.append(dict(row))
        return _Res([{"id": len(rows)}])

    def _do_upsert(self, table, row, on_conflict, ignore_dup):
        rows = self.tables.setdefault(table, [])
        keys = [k.strip() for k in (on_conflict or "").split(",")] if on_conflict else []
        existing = None
        if keys:
            for r in rows:
                if all(r.get(k) == row.get(k) for k in keys):
                    existing = r
                    break
        if existing is not None:
            if ignore_dup:
                return _Res([])              # conflit → no-op (idempotence ledger)
            existing.update(row)
            return _Res([dict(existing)])
        rows.append(dict(row))
        return _Res([dict(row)])

    # ── reprojection ADDITIVE (miroir SQL billing_reproject_wallet) ──
    def _reproject(self, uid):
        now = datetime.now(timezone.utc).isoformat()
        led = [r for r in self.tables.get("ledger_entries", []) if r.get("user_id") == uid]
        passes = [r for r in self.tables.get("passes", []) if r.get("user_id") == uid]
        active = None
        for p in passes:
            if (p.get("status") == "ACTIVE"
                    and (p.get("starts_at") is None or p["starts_at"] <= now)
                    and p.get("ends_at") is not None and p["ends_at"] > now):
                if active is None or p["ends_at"] > active["ends_at"]:
                    active = p
        free = max(0, sum(int(r.get("available_delta") or 0) for r in led if r.get("pass_id") is None))
        pass_b = 0
        if active is not None:
            pass_b = sum(int(r.get("available_delta") or 0) for r in led if r.get("pass_id") == active.get("id"))
        avail = pass_b + free
        w = self.tables.setdefault("wallets", [])
        row = next((r for r in w if r.get("user_id") == uid), None)
        active_id = active.get("id") if active else None
        if row is None:
            w.append({"user_id": uid, "available_credits": avail, "active_pass_id": active_id})
        else:
            row["available_credits"] = avail
            row["active_pass_id"] = active_id

    def wallet(self, uid):
        return next((r for r in self.tables.get("wallets", []) if r.get("user_id") == uid), {})

    def ledger_by_key(self, key):
        return [r for r in self.tables.get("ledger_entries", []) if r.get("idempotency_key") == key]
