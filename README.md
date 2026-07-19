# KNOSK HR System

Internal HR platform for KNOSK Charity Education Initiative (NGO track) and
KNOSK N100-A-Day Charity Secondary School (Academic track).

Frontend: React + Vite + Tailwind v4. Backend: Supabase (Postgres + Auth +
Storage + RLS). Notifications: a Supabase Edge Function you connect to your
own email/WhatsApp provider.

---

## Beginner walkthrough: going live on GitHub Pages + Supabase

This assumes you've never done this before. Follow it in order.

### Step 1 — Create your Supabase project

1. Go to [supabase.com](https://supabase.com), sign in, click **New project**.
2. Pick a name (e.g. `knosk-hr`), set a database password (save it somewhere
   safe), pick a region close to Nigeria, and click **Create project**. Wait
   ~2 minutes for it to finish provisioning.

### Step 2 — Run the one SQL file that sets everything up

1. In your Supabase project, open **SQL Editor** (left sidebar).
2. Click **New query**.
3. Open `knosk_hr_schema.sql` (included alongside this project) on your
   computer, copy the *entire* contents, paste into the SQL editor.
4. Scroll to the very bottom, find the block under **"OPTIONAL: BOOTSTRAP
   YOUR FIRST LOGIN"**, and edit these three lines to your real details:
   ```sql
   v_admin_email    text := 'admin@knosk.org';        -- <-- change this
   v_admin_password text := 'ChangeMe123!';            -- <-- change this
   v_admin_name     text := 'KNOSK Admin';             -- <-- change this
   ```
5. Click **Run**. This one script creates every table, security rule,
   automation trigger, seeds both org charts and SOP checklists, sets up
   file storage, *and* creates your first working login — all in one pass.
6. If it succeeds you'll see `Success. No rows returned` plus a notice
   confirming your admin account was created. **Now log into the app with
   that email/password and immediately change the password** (Supabase
   dashboard → Authentication → Users → your account → "..." → Send
   password recovery, or just change it from within a future in-app
   settings flow) — it currently exists in your SQL editor history in
   plain text.

### Step 3 — Get your API keys

1. In Supabase: **Project Settings → API**.
2. Copy the **Project URL** and the **anon public** key. You'll need both
   in Step 5.

### Step 4 — Put the code on GitHub

1. Create a new **empty** repository on GitHub (no README/license — you're
   uploading an existing project). If you want the site at
   `https://<your-username>.github.io` directly, name the repo exactly
   `<your-username>.github.io`. Otherwise any name works and the site will
   be at `https://<your-username>.github.io/<repo-name>/`.
2. On your computer, inside this project folder:
   ```bash
   git init
   git add .
   git commit -m "Initial commit"
   git branch -M main
   git remote add origin https://github.com/<your-username>/<repo-name>.git
   git push -u origin main
   ```

### Step 5 — Give GitHub your Supabase keys (as secrets, never committed)

1. On GitHub, open your repo → **Settings → Secrets and variables →
   Actions**.
2. Click **New repository secret** twice, adding:
   - `VITE_SUPABASE_URL` → the Project URL from Step 3
   - `VITE_SUPABASE_ANON_KEY` → the anon public key from Step 3

### Step 6 — Turn on GitHub Pages

1. Repo → **Settings → Pages**.
2. Under **Build and deployment → Source**, choose **GitHub Actions**
   (not "Deploy from a branch" — that's what caused the white-screen/404
   you saw, because it serves your raw source files instead of a built app).
3. That's it — a workflow file is already included
   (`.github/workflows/deploy.yml`). Go to the **Actions** tab, you should
   see it running automatically from your Step 4 push. Wait for the green
   checkmark (~1–2 minutes).
4. Your site is now live at the URL shown in the workflow's summary (or
   Settings → Pages will show it).

### Why the white screen happened, for reference

The screenshot showed a 404 on `/src/main.jsx`. That file is *unbuilt React
source* — browsers can't execute it directly, only Vite's dev server can.
What was deployed was the raw repository instead of the *built* output
(the `dist/` folder Vite produces via `npm run build`). The GitHub Actions
workflow above builds it properly and deploys only the built output, so
this can't happen again as long as Pages' source is set to "GitHub Actions"
per Step 6.

### Making future changes

Every time you `git push` to `main`, the site rebuilds and redeploys
automatically — no manual steps.

---

## Local development (optional, if you want to run it on your own machine)

```bash
cp .env.example .env
# fill in VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY
npm install
npm run dev
```

## Enabling email / WhatsApp notifications (optional)

The database already queues a notification the moment a critical or
warning alert is created (see `notification_log` in the schema) — that part
needs no setup. Actually *sending* it requires your own provider:

1. **Email (via [Resend](https://resend.com))** — free tier available.
   Get an API key, then:
   ```bash
   supabase secrets set RESEND_API_KEY=your_key
   supabase secrets set RESEND_FROM="KNOSK HR <hr@yourdomain.org>"
   ```
2. **WhatsApp (via [Twilio](https://www.twilio.com/whatsapp))** — requires
   a Twilio account with WhatsApp enabled:
   ```bash
   supabase secrets set TWILIO_ACCOUNT_SID=your_sid
   supabase secrets set TWILIO_AUTH_TOKEN=your_token
   supabase secrets set TWILIO_WHATSAPP_FROM="whatsapp:+1415XXXXXXX"
   ```
3. Deploy the function: `supabase functions deploy dispatch-notifications`
4. Schedule it to run every few minutes: Supabase Dashboard → Edge
   Functions → `dispatch-notifications` → add a Cron trigger (e.g. every
   5 minutes).

Until you do this, alerts still work fully inside the app (Alerts tab,
dashboard feed) — this only adds the "also ping me by email/WhatsApp" layer.

## File storage

Offer letters and other staff documents can be uploaded directly from the
**Documents** tab. Files go into a private Supabase Storage bucket
(`staff-documents`, created automatically by the schema) and are only ever
served via short-lived signed links — never a public URL.

## Project status

All 12 planned modules are wired end-to-end against the schema, plus:

- File upload/storage for staff documents (private bucket, signed URLs)
- Bulk CSV import for staff (Staff Registry → Import CSV)
- Single "Add staff" flow, auto-generating onboarding + document checklists
- Notification queueing (database side) + a ready-to-deploy Edge Function
  for actually sending email/WhatsApp once you add your provider keys
- One-shot Supabase bootstrap: schema + seed data + your first working login,
  all from a single SQL script

The schema has been run end-to-end against a real Postgres instance during
development — every table, trigger, and RLS policy verified to actually
execute, plus targeted tests confirming: the job-title mismatch guard, the
offboarding mandatory-task gate, the offer-letter clause enforcement, the
auto-provisioning triggers (onboarding tasks + document checklist on staff
creation, offboarding tasks on exit), the notification queueing trigger, and
the bootstrap admin block (including that its password hash actually
verifies and that re-running it is safe). The Edge Function has been
type-checked and linted with a real Deno toolchain. The built frontend has
been served locally and every asset request confirmed to resolve.

## What's still worth deciding together

- **Role scoping for `department_head` vs `manager`** — currently both see
  the same operational tables. Tightening this depends on the organogram
  being finalized.
- **Custom domain** — GitHub Pages supports one for free if you'd rather
  not use the `github.io` address.
