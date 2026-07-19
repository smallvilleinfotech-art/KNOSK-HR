# KNOSK HR System

Internal HR platform for KNOSK Charity Education Initiative (NGO track) and
KNOSK N100-A-Day Charity Secondary School (Academic track).

Frontend: React + Vite + Tailwind v4.
Backend: Supabase (Postgres + Auth + RLS).

## 1. Set up Supabase

1. Create a Supabase project.
2. Open the SQL editor and run `knosk_hr_schema.sql` (provided alongside this
   project) once, top to bottom. It creates every table, view, trigger, RLS
   policy, and seeds the two org charts, document types, access systems, and
   onboarding/offboarding templates from the SOPs.
3. In Supabase Auth, create your first user (e.g. yourself) — Authentication
   → Users → Add user.
4. Insert a matching row in `profiles` so the app knows your role:

   ```sql
   insert into profiles (id, full_name, email, role)
   values ('<auth-user-uuid>', 'Your Name', 'you@knosk.org', 'super_admin');
   ```

   There is no public sign-up screen by design — every account in an HR
   system should be provisioned deliberately by an admin.

## 2. Configure the app

```bash
cp .env.example .env
```

Fill in `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` from your Supabase
project's API settings.

## 3. Run it

```bash
npm install
npm run dev
```

Visit the printed local URL, sign in with the account you created above.

## 4. Build for production

```bash
npm run build
```

Outputs static files to `dist/` — deploy that anywhere you host static
sites (or serve it from your own server, since a "no third-party cloud
dependency" architecture only needs Supabase for data/auth, not for
hosting the frontend itself).

## Project status

All 12 planned modules are wired end-to-end against the schema:

- Auth (Supabase email/password) + role-aware session
- App shell (sidebar/topbar, KNOSK yellow/blue/white theme)
- Dashboard (leadership stats, open alerts, onboarding progress, blocked exits)
- Staff Registry (search, track filter, pagination)
- Job Descriptions (create/edit, KPI builder, approval gate)
- Onboarding tracker (role/track-specific checklists)
- Offboarding tracker (mandatory-completion gate, enforced by the database itself)
- Document inventory (per staff, inline status updates)
- Access inventory (grants, revocation, offboarding-exposure warning)
- Reassignment tracker (internal moves + handover flag)
- 3D org chart (rotate/pan/zoom, click a node to focus + reveal direct reports)
- Alerts & flags (full filterable feed, resolve/reopen)
- Audit log (filterable by table, field-level diff view)
- Settings (role-based permissions management, enforced via RLS)

The schema (`knosk_hr_schema.sql`) has been run end-to-end against a real
Postgres instance during development — every table, trigger, and RLS policy
verified to actually execute, plus targeted tests confirming the job-title
mismatch guard, the offboarding mandatory-task gate, and the offer-letter
clause enforcement all behave as specified in the SOPs.

## What's next / worth deciding together

- **Role scoping for `department_head` vs `manager`** — currently both see
  the same operational tables. Tightening this depends on the organogram
  being finalized.
- **File storage** — `file_url` columns exist throughout (offer letters,
  documents) but actual file upload/storage (Supabase Storage) isn't wired
  yet — worth a short conversation on retention/access rules first.
- **Bulk import** — loading your existing staff folder in one pass rather
  than one-by-one through the UI.
- **Notifications** — alerts currently live in-app only; email/WhatsApp
  delivery would need its own decision on which channel is authoritative.
