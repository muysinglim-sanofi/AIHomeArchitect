# AYDEN Studio — Setup / Resume guide

Everything needed to pick the project back up on a fresh machine (or a cloud
IDE you can open from your phone). The **code** is in git; the **secrets** and
**toolchain** are not (by design) — this guide fills those gaps.

> Branches: main repo = `wave-4.9.3`, frontend submodule = `wave4-design-spine`.
> The Supabase database (promo tables, RPCs, user_roles, usage_log) is in the
> **cloud** — reachable from anywhere with the right `.env`. No DB re-setup.

---

## 📱 Working from a phone — use GitHub Codespaces

You **cannot** build/run a Flutter app or a Python server *on* a phone. The
realistic path is **GitHub Codespaces** — a cloud dev machine you open in your
phone's browser:

1. On GitHub → this repo → **Code ▸ Codespaces ▸ Create codespace on `wave-4.9.3`**.
2. The `.devcontainer/` auto-installs Python + backend deps and copies the
   `.env` templates. Wait for "setup done".
3. **Fill the secrets** (see below) into `backend/.env` and `frontend/.env`.
4. Run the backend / tests from the Codespaces terminal (see commands below).

In Codespaces you can: **edit all code**, **run the backend**, run
`flutter test` / `dart analyze`. You can **not** see the live Flutter UI from a
phone (no emulator) — for that, use a laptop.

---

## 💻 On a laptop / desktop (full setup)

### 1. Clone (with the submodule)
```bash
git clone --recursive https://github.com/muysinglim-sanofi/AIHomeArchitect.git
cd AIHomeArchitect
git checkout wave-4.9.3
git submodule update --init --recursive   # pulls the frontend (wave4-design-spine)
```

### 2. Secrets — create the two `.env` files (NOT in git)
Copy the templates and fill in the real values from your dashboards:
```bash
cp backend/.env.example  backend/.env
cp frontend/.env.example frontend/.env
```
- **backend/.env** — `OPENAI_API_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
  `SUPABASE_JWT_SECRET`, `REVENUECAT_WEBHOOK_AUTH`, `REVENUECAT_SECRET_API_KEY`.
- **frontend/.env** — `API_BASE_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`
  (+ RevenueCat public keys when you have them).
- Source: Supabase Dashboard → Project Settings → API · OpenAI dashboard · RevenueCat dashboard.

### 3. Backend
```bash
cd backend
python -m venv .venv && . .venv/Scripts/activate   # (Linux/Mac: source .venv/bin/activate)
pip install -r requirements.txt
# Launch — BIMODAL_ENABLED=1 is REQUIRED (TV anchor + DNA strips depend on it).
# Windows: single process, NO --reload. Linux/Codespaces: --reload is fine.
BIMODAL_ENABLED=1 uvicorn main:app --host 127.0.0.1 --port 8000
```

### 4. Frontend
```bash
cd frontend
flutter pub get
flutter run            # needs an emulator/device — laptop only
flutter test           # works anywhere with the SDK
dart analyze lib
```

---

## ✅ Quick validation (no UI needed)
```bash
# Backend — promo access resolver (pure, no DB)
cd backend && python _sprint_1b_promo_validation.py
# Backend — live RPC smoke (needs backend/.env with Supabase service key)
python _sprint_1b_promo_db_smoke.py
# Frontend
cd frontend && flutter test
```

---

## 🗄️ Database (Supabase) — already provisioned
The promo system SQL lives in `backend/sql/sprint_1b_promo.sql` and is **already
applied** to the live Supabase project. If you ever recreate the DB, run that
file once in the Supabase SQL editor.

## What is NOT in git (and why)
| Item | Why | How to restore |
|---|---|---|
| `backend/.env`, `frontend/.env` | secrets | copy from `.env.example`, fill values |
| `backend/.venv` | local deps | `pip install -r requirements.txt` |
| Flutter packages | local deps | `flutter pub get` |
| `backend/logs/` | 1 GB+ runtime logs | n/a (regenerated) |
