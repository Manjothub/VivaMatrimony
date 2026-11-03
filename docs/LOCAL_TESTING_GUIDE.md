# Viva Matrimony — Local Setup & Testing Guide (Windows)

A step-by-step guide from scratch: install the requirements, run the app locally,
and test it. Written for Windows, but the same steps work on macOS/Linux with
minor path changes.

---

## 1. Requirements

| Tool | Version | What it's for | Download / Docs |
|------|---------|---------------|-----------------|
| Flutter SDK | 3.47.9 stable (project needs ≥ 3.22.0) | Runs the mobile app (`viva_app`) | https://docs.flutter.dev/get-started/install |
| Git | any recent | Clone the repo / Flutter requirement | https://git-scm.com/downloads |
| Node.js + npm | 18+ (24 used in testing) | Runs the admin panel (`viva-admin`) | https://nodejs.org/en/download |
| Python | 3.11+ | Runs the FastAPI backend (native mode) | https://www.python.org/downloads/ |
| Docker Desktop | any recent | Runs the backend in a container (easiest way to get PDF generation working) | https://docs.docker.com/desktop/setup/install/windows-install/ |
| Supabase account | free tier works | Database, auth, storage | https://supabase.com/dashboard |
| Android Studio (only if running the app on an emulator/device) | — | Android SDK, emulator | https://developer.android.com/studio/install |

> **Don't have everything at once?** You can test backend + admin panel without
> Flutter, and the Flutter app alone with just the Flutter SDK + a Supabase project.

---

## 2. From scratch — step by step

### Step 1 — Get the code

```bash
git clone <your-repo-url>
cd VivaMatrimony
```

### Step 2 — Install the Flutter SDK (skip if already installed)

1. Download the Flutter stable zip for Windows from
   https://docs.flutter.dev/get-started/install/windows
2. Extract it to a short path such as `C:\flutter`
   (not inside `Program Files` — Flutter docs recommend a path without spaces/permissions issues)
3. Add `C:\flutter\bin` to your user **PATH**:
   - Search Windows for "Edit environment variables for your account"
   - Edit `Path` → add `C:\flutter\bin`
4. Open a **new** terminal (so the PATH change takes effect) and verify:

```bash
flutter --version
flutter doctor
```

`flutter doctor` tells you exactly what is still missing (Android SDK, Chrome,
Developer Mode, etc.). Follow the red/yellow lines it prints.

### Step 3 — Set up Supabase (the project's database)

1. Create a project at https://supabase.com/dashboard (free tier is enough).
2. Apply the database migrations from the `supabase/` folder — open the Supabase
   **SQL Editor** and run the migration files, or use the Supabase CLI.
   Full details: `docs/SUPABASE_SETUP.md` in this repo.
3. Collect these 5 values (you'll need them in Step 5):

| Value | Where in the Supabase dashboard |
|-------|--------------------------------|
| Project URL | Project Settings → Data API → Project URL |
| ANON key | Project Settings → Data API → anon/publishable key |
| Service Role key | Project Settings → Data API → service_role/secret key (click Reveal) |
| Database URL | Project Settings → Database → Connection string (URI) → prefer the **Transaction pooler** URI (port `6543`) |
| JWT Secret | Project Settings → API → JWT Settings |

### Step 4 — Configure environment files

```bash
# backend
cp .env.example backend/.env
# admin panel
cp viva-admin/.env.example viva-admin/.env
```

Now edit:

**`backend/.env`** — paste your 5 Supabase values from Step 3, then set the
secrets to long random strings (min 32 chars each):

```env
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_ANON_KEY=...
SUPABASE_SERVICE_ROLE_KEY=...
DATABASE_URL=postgresql://postgres.xxxx:PASSWORD@aws-0-region.pooler.supabase.com:6543/postgres
SUPABASE_JWT_SECRET=...
APP_SECRET_KEY=<random 32+ chars>
JWT_SECRET_KEY=<random 64+ chars>
```

Generate random secrets easily:

```powershell
# PowerShell — run twice for the two keys (APP_SECRET_KEY, JWT_SECRET_KEY)
$secret = -join ((1..64) | ForEach-Object { "{0:x}" -f (Get-Random -Max 16) })
$secret
```

Also set/confirm:
- `APP_ENV=development`, `APP_DEBUG=true`
- `ALLOWED_ORIGINS=http://localhost:5173` (admin panel's port)
- `SECURE_COOKIES=false` (local only)

**`viva-admin/.env`**:

```env
VITE_API_BASE_URL=http://localhost:8000/api/v1
```

> **Never commit `.env` files** — they're already in `.gitignore`.

### Step 5 — Start the backend

Pick **one** of the two options:

**Option A — Docker (recommended; WeasyPrint/PDF needs Linux-only libs):**

```bash
docker compose up -d backend
```

The API is now at `http://localhost:8000` — open http://localhost:8000/docs to
see the interactive API docs. Health check: http://localhost:8000/health

**Option B — Native Python (fine for API testing; PDF generation may fail on
Windows without GTK):**

```bash
cd backend
pip install -r requirements.txt
python -m uvicorn app.main:app --reload
```

### Step 6 — Run the admin panel

```bash
cd viva-admin
npm install
npm run dev
```

Open http://localhost:5173 in a browser.

> **PowerShell note:** if `npm` fails with "running scripts is disabled",
> run `cmd /c npm run dev` instead, or run:
> `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

### Step 7 — Run the Flutter app

```bash
cd viva_app
flutter pub get
```

Then pick a target:

| Target | Command | Pre-req |
|--------|---------|---------|
| Android emulator | `flutter run` / `flutter run -d emulator-5554` | Android Studio + emulator (see flutter doctor) |
| Physical Android device | enable USB debugging, `flutter run` | USB debugging |
| Windows desktop | `flutter run -d windows` | **Developer Mode on** (Windows Settings → Privacy & security → For developers → Developer Mode) |
| Chrome / web | `flutter run -d chrome` | Chrome installed |

`flutter devices` lists what's available on your machine.

---

## 3. Testing checklist

### 3.1 Automated checks

Run from `viva_app/`:

```bash
# static analysis — should report no NEW issues
flutter analyze

# logout behaviour contract tests
flutter test test/logout_guard_test.dart
```

Expected: all logout tests pass. (`test/widget_test.dart` is a known-failing
stub — see "Known issues" below.)

### 3.2 Manual test — logout must NOT show a black screen

This was the fixed bug; verify it on every device type you can:

1. Run the app, log in with a real account.
2. Go to **Profile tab → Log Out icon → confirm** → ✅ expect: instant
   transition to the **Login screen** (off-white background), never a black flash.
3. Log in again → **Settings → Danger Zone → Delete My Account** → ✅ same
   expectation (delete account also logs out).
4. Go deep first: open **Onboarding → tap Back / Log Out** → ✅ must land on Login.
5. Leave the app idle > 60 min (token expiry) or revoke the session from the
   Supabase dashboard → resume the app → ✅ must land on Login, not a black screen.
6. If anything looks black: run the app with logs (`flutter run`) and look for
   `[Auth] GoRouter refreshed after auth flip` after the logout tap. If the line
   is missing, the safeguard didn't fire — check `auth_provider.dart` →
   `_forceRouterRedirect()`.

### 3.3 Backend smoke test

```bash
# health
curl http://localhost:8000/health

# API docs in browser
start http://localhost:8000/docs
```

### 3.4 Admin panel smoke test

Open http://localhost:5173, try logging in with the admin credentials
(`ADMIN_EMAIL` / `ADMIN_DEFAULT_PASSWORD` from `backend/.env` — the backend must
be running).

---

## 4. Known issues / gotchas

| Issue | Note |
|-------|------|
| `test/widget_test.dart` fails | Pre-existing: the stub mounts `VivaApp` without Supabase/Firebase init, so the splash's 8s safety timer trips the test framework. Unrelated to app code. |
| `npm` blocked in PowerShell | Execution policy. Use `cmd /c npm run dev` or `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| PDF generation fails on native Windows | WeasyPrint needs Pango/Cairo native libs. Use the **Docker backend** (Option A) — the Dockerfile installs everything |
| `pub get` says "enable Developer Mode" | Only matters for building plugins on Windows desktop; not needed for `flutter analyze/test` or Android runs |
| Plugin-registrant files keep changing | `viva_app/{linux,windows,macos}/flutter/generated_*` are auto-generated. Don't commit their diffs unless you rebuild with a new Flutter SDK |
| Login flow needs WhatsApp OTP | Dev setup uses OpenWA (Node.js 18+). See `docs/WHATSAPP.md` in this repo |

---

## 5. Reference links

**Project docs (in this repo):**

- `README.md` — overview + quick start
- `docs/SUPABASE_SETUP.md` — database migrations & RLS
- `docs/ARCHITECTURE.md` — how the 3 apps fit together
- `docs/API.md` / `docs/DEPLOYMENT.md` — API & deployment details
- `docs/WHATSAPP.md` — OTP login setup
- `QUICK_START_TESTING.md` — original testing checklist

**External documentation:**

- Flutter install (Windows): https://docs.flutter.dev/get-started/install/windows
- Flutter doctor / setup troubleshooting: https://docs.flutter.dev/get-started/install/help
- Dart & Flutter CLI commands: https://dart.dev/tools/sdk
- Supabase dashboard: https://supabase.com/dashboard
- Supabase self-hosting / setup docs: https://supabase.com/docs/guides/local-development
- FastAPI docs: https://fastapi.tiangolo.com
- Docker Desktop (Windows): https://docs.docker.com/desktop/
- Node.js downloads: https://nodejs.org/en/download
- Vite (admin panel): https://vite.dev/guide/
- Riverpod (state management used in the app): https://riverpod.dev
- GoRouter (navigation used in the app): https://pub.dev/packages/go_router
- Android Studio install: https://developer.android.com/studio/install