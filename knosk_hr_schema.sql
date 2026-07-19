-- ============================================================================
-- KNOSK HR SYSTEM — SUPABASE SCHEMA
-- Covers: NGO track (KNOSK Charity Education Initiative) &
--         Academic track (KNOSK N100-A-Day Charity Secondary School)
-- Built from: Offer Letter SOP, Onboarding SOP, NGO organogram, School organogram
-- Run this once, top to bottom, in the Supabase SQL editor.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. EXTENSIONS
-- ----------------------------------------------------------------------------
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- ----------------------------------------------------------------------------
-- 1. ENUM TYPES
-- ----------------------------------------------------------------------------
create type track_type          as enum ('ngo', 'academic');
create type employment_status   as enum ('probation','active','on_leave','reassigning','offboarding','terminated','resigned','archived');
create type staff_category      as enum ('fulltime','part_time','volunteer','nysc','intern');
create type doc_status          as enum ('missing','draft','pending_signature','signed','filed','expired');
create type access_status       as enum ('requested','active','pending_revocation','revoked');
create type task_status         as enum ('pending','in_progress','completed','overdue','waived');
create type alert_severity      as enum ('info','warning','critical');
create type org_node_type       as enum ('board','leadership','department','unit','role');
create type app_role            as enum ('super_admin','hr_admin','head_of_ops','principal','vice_principal','department_head','manager','staff_viewer');

-- ----------------------------------------------------------------------------
-- 2. CORE REFERENCE TABLES
-- ----------------------------------------------------------------------------

-- The two legal employing entities
create table entities (
  id            uuid primary key default uuid_generate_v4(),
  name          text not null unique,       -- 'KNOSK Charity Education Initiative' | 'KNOSK N100-A-Day Charity Secondary School'
  track         track_type not null,
  created_at    timestamptz not null default now()
);

-- Organogram nodes — self-referencing tree, drives BOTH the org chart UI
-- and the 3D navigable version (x/y/z are optional manual overrides;
-- if null the frontend auto-lays-out based on depth/siblings).
create table org_nodes (
  id             uuid primary key default uuid_generate_v4(),
  entity_id      uuid not null references entities(id) on delete cascade,
  parent_id      uuid references org_nodes(id) on delete cascade,
  title          text not null,              -- e.g. 'Head of Operations and Systems'
  subtitle       text,                       -- e.g. 'Reports to Co-Founders'
  node_type      org_node_type not null,
  track          track_type not null,
  sort_order     int not null default 0,
  pos_x          numeric,
  pos_y          numeric,
  pos_z          numeric,
  created_at     timestamptz not null default now()
);
create index idx_org_nodes_parent on org_nodes(parent_id);
create index idx_org_nodes_entity on org_nodes(entity_id);

-- ----------------------------------------------------------------------------
-- 3. IDENTITY / PROFILES (linked to Supabase auth.users)
-- ----------------------------------------------------------------------------
create table profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  full_name     text not null,
  email         text not null unique,
  role          app_role not null default 'staff_viewer',
  staff_id      uuid,                        -- fk added after staff table exists
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 4. JOB DESCRIPTIONS (SOP step 1 — nothing else can exist without this)
-- ----------------------------------------------------------------------------
create table job_descriptions (
  id                uuid primary key default uuid_generate_v4(),
  title             text not null,                     -- exact title, e.g. 'Learning Resource Officer — Agriculture'
  track             track_type not null,
  org_node_id       uuid references org_nodes(id),      -- department/role this JD belongs to
  reports_to_node_id uuid references org_nodes(id),
  role_summary      text not null,                      -- pasted verbatim into offer letters
  kpis              jsonb not null default '[]'::jsonb, -- [{ "metric": "videos produced", "target": "2/month" }]
  duties            text,
  is_approved       boolean not null default false,
  approved_by       uuid references profiles(id),
  approved_at       timestamptz,
  version           int not null default 1,
  file_url          text,
  created_at        timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 5. STAFF REGISTRY (the spine of the whole system)
-- ----------------------------------------------------------------------------
create table staff (
  id                    uuid primary key default uuid_generate_v4(),
  staff_code            text unique,                    -- e.g. KNK-2026-001
  full_name             text not null,
  preferred_name        text,
  email                 text,
  phone                 text,
  photo_url             text,
  entity_id             uuid not null references entities(id),
  track                 track_type not null,
  org_node_id           uuid references org_nodes(id),   -- current seat in the org chart
  job_description_id    uuid references job_descriptions(id),
  job_title             text not null,                   -- must match JD exactly (enforced by trigger below)
  staff_category        staff_category not null default 'fulltime',
  employment_status     employment_status not null default 'probation',
  reports_to_staff_id   uuid references staff(id),
  start_date            date not null,
  probation_end_date    date,
  exit_date             date,
  guarantor_on_file     boolean not null default false,
  safeguarding_cleared  boolean not null default false,  -- academic track only, must be true before offer per SOP Annex A
  trc_registration      text,                             -- Teachers Registration Council no. (academic track)
  created_by            uuid references profiles(id),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index idx_staff_org_node on staff(org_node_id);
create index idx_staff_status on staff(employment_status);

alter table profiles add constraint fk_profiles_staff foreign key (staff_id) references staff(id);

-- Job title must match the linked JD exactly — enforced in a trigger, not just convention
create or replace function enforce_job_title_matches_jd()
returns trigger as $$
begin
  if new.job_description_id is not null then
    if new.job_title <> (select title from job_descriptions where id = new.job_description_id) then
      raise exception 'job_title on staff (%) does not match linked job_description title', new.job_title;
    end if;
  end if;
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger trg_staff_title_check
before insert or update on staff
for each row execute function enforce_job_title_matches_jd();

-- ----------------------------------------------------------------------------
-- 6. OFFER LETTERS (mirrors the SOP field-for-field)
-- ----------------------------------------------------------------------------
create table offer_letters (
  id                      uuid primary key default uuid_generate_v4(),
  staff_id                uuid not null references staff(id) on delete cascade,
  job_description_id      uuid not null references job_descriptions(id),
  entity_id               uuid not null references entities(id),
  reports_to_title        text not null,
  role_summary            text not null,           -- copied from JD at time of issue, immutable snapshot
  kpis                    jsonb not null default '[]'::jsonb,
  monthly_salary          numeric(12,2) not null,
  annual_leave_note       text not null default 'As set out in the KNOSK staff handbook, as may be updated from time to time.',
  health_insurance        boolean not null default false,
  health_insurance_note   text,
  accommodation           text not null check (accommodation in ('none','free','subsidized')),
  accommodation_note      text,
  salary_escalation_clause text,                    -- only filled if genuinely intended for this hire
  probation_indicators    text[] not null default array['attitude to work','honesty','resourcefulness'],
  working_hours           text not null,
  policy_ack_included     boolean not null default true,
  offboarding_clause_included boolean not null default true,
  public_visibility_clause_included boolean,        -- required true if track = ngo
  safeguarding_clause_included boolean,             -- required true if track = academic
  signatory               text not null,
  co_signatory            text,
  status                  doc_status not null default 'draft',
  sent_at                 timestamptz,
  signed_at               timestamptz,
  filed_at                timestamptz,
  file_url                text,
  created_by              uuid references profiles(id),
  created_at              timestamptz not null default now()
);

-- Track-specific mandatory clauses, enforced at write time
create or replace function enforce_offer_letter_clauses()
returns trigger as $$
declare v_track track_type;
begin
  select track into v_track from entities where id = new.entity_id;
  if v_track = 'ngo' and coalesce(new.public_visibility_clause_included,false) is not true then
    raise exception 'NGO-track offer letters must include the public visibility / fundraising clause';
  end if;
  if v_track = 'academic' and coalesce(new.safeguarding_clause_included,false) is not true then
    raise exception 'Academic-track offer letters must include the safeguarding clause';
  end if;
  if new.offboarding_clause_included is not true then
    raise exception 'Offboarding & handover clause is compulsory on every offer letter';
  end if;
  return new;
end;
$$ language plpgsql;

create trigger trg_offer_letter_clauses
before insert or update on offer_letters
for each row execute function enforce_offer_letter_clauses();

-- ----------------------------------------------------------------------------
-- 7. DOCUMENT INVENTORY
-- ----------------------------------------------------------------------------
create table document_types (
  id            uuid primary key default uuid_generate_v4(),
  name          text not null unique,   -- 'Offer Letter','Contract','Job Description','Safeguarding Declaration','Guarantor Form', etc.
  track         track_type,             -- null = applies to both
  is_mandatory  boolean not null default true
);

create table staff_documents (
  id                uuid primary key default uuid_generate_v4(),
  staff_id          uuid not null references staff(id) on delete cascade,
  document_type_id  uuid not null references document_types(id),
  status            doc_status not null default 'missing',
  file_url          text,
  expiry_date       date,
  notes             text,
  uploaded_by       uuid references profiles(id),
  uploaded_at       timestamptz,
  unique (staff_id, document_type_id)
);

-- ----------------------------------------------------------------------------
-- 8. ACCESS INVENTORY (with offboarding removal tracking)
-- ----------------------------------------------------------------------------
create table access_systems (
  id            uuid primary key default uuid_generate_v4(),
  name          text not null unique,      -- 'Official Email','Ops WhatsApp Group','Shared Drive - Programs', etc.
  category      text not null,             -- 'email','drive','whatsapp','platform','physical'
  owner_note    text
);

create table staff_access (
  id               uuid primary key default uuid_generate_v4(),
  staff_id         uuid not null references staff(id) on delete cascade,
  access_system_id uuid not null references access_systems(id),
  status           access_status not null default 'requested',
  granted_at       timestamptz,
  granted_by       uuid references profiles(id),
  revoked_at       timestamptz,
  revoked_by       uuid references profiles(id),
  notes            text
);
create index idx_staff_access_staff on staff_access(staff_id);

-- ----------------------------------------------------------------------------
-- 9. ONBOARDING TRACKER (role/track specific)
-- ----------------------------------------------------------------------------
create table onboarding_templates (
  id            uuid primary key default uuid_generate_v4(),
  track         track_type,                -- null = both tracks
  staff_category staff_category,           -- null = all categories
  task_name     text not null,
  description   text,
  sequence      int not null default 0,
  is_mandatory  boolean not null default true
);

create table onboarding_tasks (
  id            uuid primary key default uuid_generate_v4(),
  staff_id      uuid not null references staff(id) on delete cascade,
  template_id   uuid references onboarding_templates(id),
  task_name     text not null,
  status        task_status not null default 'pending',
  due_date      date,
  completed_at  timestamptz,
  completed_by  uuid references profiles(id),
  notes         text
);

-- Auto-generate onboarding tasks for a staff member from the templates
-- matching their track + category. Call after inserting a staff row.
create or replace function generate_onboarding_tasks(p_staff_id uuid)
returns void as $$
declare v_track track_type; v_cat staff_category;
begin
  select track, staff_category into v_track, v_cat from staff where id = p_staff_id;
  insert into onboarding_tasks (staff_id, template_id, task_name, due_date)
  select p_staff_id, id, task_name, current_date + 14
  from onboarding_templates
  where (track is null or track = v_track)
    and (staff_category is null or staff_category = v_cat)
  order by sequence;
end;
$$ language plpgsql;

-- ----------------------------------------------------------------------------
-- 10. OFFBOARDING TRACKER — mandatory completion enforcement
-- ----------------------------------------------------------------------------
create table offboarding_templates (
  id            uuid primary key default uuid_generate_v4(),
  track         track_type,
  task_name     text not null,
  description   text,
  sequence      int not null default 0,
  is_mandatory  boolean not null default true
);

create table offboarding_tasks (
  id            uuid primary key default uuid_generate_v4(),
  staff_id      uuid not null references staff(id) on delete cascade,
  template_id   uuid references offboarding_templates(id),
  task_name     text not null,
  status        task_status not null default 'pending',
  is_mandatory  boolean not null default true,
  due_date      date,
  completed_at  timestamptz,
  completed_by  uuid references profiles(id),
  notes         text
);

create or replace function generate_offboarding_tasks(p_staff_id uuid)
returns void as $$
declare v_track track_type;
begin
  select track into v_track from staff where id = p_staff_id;
  insert into offboarding_tasks (staff_id, template_id, task_name, is_mandatory, due_date)
  select p_staff_id, id, task_name, is_mandatory, current_date + 14
  from offboarding_templates
  where track is null or track = v_track
  order by sequence;
end;
$$ language plpgsql;

-- HARD ENFORCEMENT: a staff record cannot move to 'terminated'/'resigned'/'archived'
-- while any mandatory offboarding task is still incomplete.
create or replace function enforce_offboarding_before_exit()
returns trigger as $$
declare v_incomplete int;
begin
  if new.employment_status in ('terminated','resigned','archived')
     and old.employment_status is distinct from new.employment_status then
    select count(*) into v_incomplete
    from offboarding_tasks
    where staff_id = new.id and is_mandatory = true and status not in ('completed','waived');
    if v_incomplete > 0 then
      raise exception 'Cannot finalize exit for % — % mandatory offboarding task(s) incomplete', new.full_name, v_incomplete;
    end if;
  end if;
  return new;
end;
$$ language plpgsql;

create trigger trg_offboarding_gate
before update on staff
for each row execute function enforce_offboarding_before_exit();

-- ----------------------------------------------------------------------------
-- 11. INTERNAL REASSIGNMENT TRACKER
-- ----------------------------------------------------------------------------
create table reassignments (
  id                     uuid primary key default uuid_generate_v4(),
  staff_id               uuid not null references staff(id) on delete cascade,
  from_org_node_id       uuid references org_nodes(id),
  to_org_node_id         uuid references org_nodes(id),
  from_job_description_id uuid references job_descriptions(id),
  to_job_description_id   uuid references job_descriptions(id),
  effective_date         date not null,
  reason                 text,
  approved_by            uuid references profiles(id),
  handover_completed     boolean not null default false,  -- reassignment also triggers a handover per SOP step 13
  created_at             timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 12. ALERTS & FLAGS DASHBOARD
-- ----------------------------------------------------------------------------
create table alerts (
  id            uuid primary key default uuid_generate_v4(),
  staff_id      uuid references staff(id) on delete cascade,
  org_node_id   uuid references org_nodes(id),
  alert_type    text not null,      -- 'missing_jd','offer_letter_unsigned','probation_ending','offboarding_incomplete','access_not_revoked', etc.
  severity      alert_severity not null default 'warning',
  message       text not null,
  is_resolved   boolean not null default false,
  resolved_by   uuid references profiles(id),
  resolved_at   timestamptz,
  created_at    timestamptz not null default now()
);
create index idx_alerts_open on alerts(is_resolved) where is_resolved = false;

-- ----------------------------------------------------------------------------
-- 13. AUDIT LOG (generic, attaches to any table)
-- ----------------------------------------------------------------------------
create table audit_log (
  id            uuid primary key default uuid_generate_v4(),
  table_name    text not null,
  record_id     uuid not null,
  action        text not null,        -- INSERT/UPDATE/DELETE
  changed_by    uuid references profiles(id),
  old_data      jsonb,
  new_data      jsonb,
  created_at    timestamptz not null default now()
);

create or replace function audit_trigger_fn()
returns trigger as $$
begin
  insert into audit_log(table_name, record_id, action, changed_by, old_data, new_data)
  values (
    tg_table_name,
    coalesce(new.id, old.id),
    tg_op,
    nullif(current_setting('request.jwt.claim.sub', true), '')::uuid,
    case when tg_op = 'DELETE' then to_jsonb(old) else null end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end
  );
  return coalesce(new, old);
end;
$$ language plpgsql;

create trigger trg_audit_staff after insert or update or delete on staff
  for each row execute function audit_trigger_fn();
create trigger trg_audit_offer_letters after insert or update or delete on offer_letters
  for each row execute function audit_trigger_fn();
create trigger trg_audit_staff_access after insert or update or delete on staff_access
  for each row execute function audit_trigger_fn();
create trigger trg_audit_offboarding after insert or update or delete on offboarding_tasks
  for each row execute function audit_trigger_fn();
create trigger trg_audit_reassignments after insert or update or delete on reassignments
  for each row execute function audit_trigger_fn();

-- ----------------------------------------------------------------------------
-- 14. ROW LEVEL SECURITY (role-based permissions)
-- ----------------------------------------------------------------------------
alter table staff enable row level security;
alter table offer_letters enable row level security;
alter table staff_documents enable row level security;
alter table staff_access enable row level security;
alter table onboarding_tasks enable row level security;
alter table offboarding_tasks enable row level security;
alter table reassignments enable row level security;
alter table alerts enable row level security;
alter table audit_log enable row level security;
alter table profiles enable row level security;

create or replace function current_app_role() returns app_role as $$
  select role from profiles where id = auth.uid();
$$ language sql stable;

-- Full read/write for admin roles; managers see their own reports; staff see themselves
create policy staff_admin_all on staff for all
  using (current_app_role() in ('super_admin','hr_admin','head_of_ops','principal'))
  with check (current_app_role() in ('super_admin','hr_admin','head_of_ops','principal'));

create policy staff_manager_read on staff for select
  using (
    current_app_role() in ('vice_principal','department_head','manager')
    or id = (select staff_id from profiles where id = auth.uid())
  );

create policy offer_letters_admin_only on offer_letters for all
  using (current_app_role() in ('super_admin','hr_admin','head_of_ops','principal'))
  with check (current_app_role() in ('super_admin','hr_admin','head_of_ops','principal'));

create policy audit_log_admin_read on audit_log for select
  using (current_app_role() in ('super_admin','hr_admin'));

create policy alerts_admin_and_managers on alerts for select
  using (current_app_role() in ('super_admin','hr_admin','head_of_ops','principal','vice_principal','department_head','manager'));

create policy profiles_self_or_admin on profiles for select
  using (id = auth.uid() or current_app_role() in ('super_admin','hr_admin'));

-- ---------------------------------------------------------------------------
-- 14b. RLS for the operational tables the app writes to day-to-day.
--      Split into "admin manages the record" vs "any signed-in staff member
--      can tick off their own operational tasks" — matches how the SOP
--      actually expects this to be used day-to-day, not just by HR.
-- ---------------------------------------------------------------------------

create policy profiles_admin_update on profiles for update
  using (current_app_role() in ('super_admin','hr_admin'))
  with check (current_app_role() in ('super_admin','hr_admin'));

alter table job_descriptions enable row level security;
create policy jd_read_all on job_descriptions for select using (true);
create policy jd_write_admin on job_descriptions for insert
  with check (current_app_role() in ('super_admin','hr_admin','head_of_ops','principal'));
create policy jd_update_admin on job_descriptions for update
  using (current_app_role() in ('super_admin','hr_admin','head_of_ops','principal'))
  with check (current_app_role() in ('super_admin','hr_admin','head_of_ops','principal'));

alter table org_nodes enable row level security;
create policy org_nodes_read_all on org_nodes for select using (true);
create policy org_nodes_write_admin on org_nodes for all
  using (current_app_role() in ('super_admin','hr_admin','head_of_ops'))
  with check (current_app_role() in ('super_admin','hr_admin','head_of_ops'));

create policy onboarding_tasks_read_all on onboarding_tasks for select using (true);
create policy onboarding_tasks_update_operational on onboarding_tasks for update
  using (current_app_role() <> 'staff_viewer')
  with check (current_app_role() <> 'staff_viewer');

create policy offboarding_tasks_read_all on offboarding_tasks for select using (true);
create policy offboarding_tasks_update_operational on offboarding_tasks for update
  using (current_app_role() <> 'staff_viewer')
  with check (current_app_role() <> 'staff_viewer');

alter table staff_documents enable row level security;
create policy staff_documents_read_all on staff_documents for select using (true);
create policy staff_documents_write_operational on staff_documents for all
  using (current_app_role() <> 'staff_viewer')
  with check (current_app_role() <> 'staff_viewer');

alter table access_systems enable row level security;
create policy access_systems_read_all on access_systems for select using (true);

create policy staff_access_read_all on staff_access for select using (true);
create policy staff_access_write_operational on staff_access for all
  using (current_app_role() <> 'staff_viewer')
  with check (current_app_role() <> 'staff_viewer');

create policy reassignments_read_all on reassignments for select using (true);
create policy reassignments_write_admin on reassignments for all
  using (current_app_role() in ('super_admin','hr_admin','head_of_ops','principal','vice_principal','department_head','manager'))
  with check (current_app_role() in ('super_admin','hr_admin','head_of_ops','principal','vice_principal','department_head','manager'));

create policy alerts_write_admin on alerts for update
  using (current_app_role() <> 'staff_viewer')
  with check (current_app_role() <> 'staff_viewer');

-- Every profile with a real role (not the default 'staff_viewer') can also
-- update the exit gate on staff records via the offboarding UI — the
-- enforce_offboarding_before_exit() trigger is still the real gatekeeper.
create policy staff_operational_update on staff for update
  using (current_app_role() not in ('staff_viewer'))
  with check (current_app_role() not in ('staff_viewer'));

-- (Apply the same admin-all / scoped-read pattern to remaining tables as roles are finalized —
--  left deliberately simple here so you and I can tune scoping together, since department_head
--  vs manager visibility will depend on the final organogram sign-off.)

-- ----------------------------------------------------------------------------
-- 15. REPORTING VIEWS
-- ----------------------------------------------------------------------------
create view v_leadership_dashboard as
select
  e.name as entity,
  s.track,
  count(*) filter (where s.employment_status = 'active') as active_staff,
  count(*) filter (where s.employment_status = 'probation') as on_probation,
  count(*) filter (where s.employment_status = 'offboarding') as offboarding,
  count(*) filter (where s.probation_end_date <= current_date + 14 and s.employment_status = 'probation') as probation_ending_soon
from staff s
join entities e on e.id = s.entity_id
group by e.name, s.track;

create view v_onboarding_progress as
select
  s.id as staff_id, s.full_name, s.track,
  count(*) as total_tasks,
  count(*) filter (where ot.status = 'completed') as completed_tasks,
  round(100.0 * count(*) filter (where ot.status = 'completed') / nullif(count(*),0), 1) as pct_complete
from staff s
left join onboarding_tasks ot on ot.staff_id = s.id
group by s.id, s.full_name, s.track;

create view v_offboarding_progress as
select
  s.id as staff_id, s.full_name,
  count(*) filter (where ft.is_mandatory) as mandatory_tasks,
  count(*) filter (where ft.is_mandatory and ft.status = 'completed') as mandatory_completed,
  (count(*) filter (where ft.is_mandatory and ft.status not in ('completed','waived')) = 0) as cleared_to_exit
from staff s
join offboarding_tasks ft on ft.staff_id = s.id
group by s.id, s.full_name;

create view v_org_chart as
select id, entity_id, parent_id, title, subtitle, node_type, track, pos_x, pos_y, pos_z,
  (select s.full_name from staff s where s.org_node_id = org_nodes.id and s.employment_status in ('active','probation') limit 1) as current_holder
from org_nodes;

-- ============================================================================
-- 16. SEED DATA — entities, org charts (from both organogram images),
--     document types, access systems, onboarding/offboarding templates (SOP)
-- ============================================================================

insert into entities (name, track) values
  ('KNOSK Charity Education Initiative', 'ngo'),
  ('KNOSK N100-A-Day Charity Secondary School', 'academic');

-- ---- NGO organogram ----
do $$
declare
  v_ngo_entity uuid := (select id from entities where track = 'ngo');
  v_board uuid; v_king uuid; v_irene uuid; v_headops uuid;
  v_operations uuid; v_finance uuid; v_ict uuid; v_sponsorship uuid;
begin
  insert into org_nodes (entity_id, title, node_type, track, sort_order) values
    (v_ngo_entity, 'Board of Trustees', 'board', 'ngo', 0) returning id into v_board;

  insert into org_nodes (entity_id, parent_id, title, subtitle, node_type, track, sort_order) values
    (v_ngo_entity, v_board, 'Kingsley Bangwell', 'Co-founder, Strategy & Funding', 'leadership', 'ngo', 0) returning id into v_king;
  insert into org_nodes (entity_id, parent_id, title, subtitle, node_type, track, sort_order) values
    (v_ngo_entity, v_board, 'Irene Bangwell', 'Co-founder, Learning/Academics', 'leadership', 'ngo', 1) returning id into v_irene;

  insert into org_nodes (entity_id, parent_id, title, subtitle, node_type, track, sort_order) values
    (v_ngo_entity, v_king, 'Head of Operations and Systems', 'Reports to Co-Founders', 'leadership', 'ngo', 0) returning id into v_headops;

  insert into org_nodes (entity_id, parent_id, title, subtitle, node_type, track, sort_order) values
    (v_ngo_entity, v_headops, 'Operations', 'Program lead', 'department', 'ngo', 0) returning id into v_operations;
  insert into org_nodes (entity_id, parent_id, title, node_type, track, sort_order) values
    (v_ngo_entity, v_headops, 'Finance', 'department', 'ngo', 1) returning id into v_finance;
  insert into org_nodes (entity_id, parent_id, title, node_type, track, sort_order) values
    (v_ngo_entity, v_headops, 'ICT', 'department', 'ngo', 2) returning id into v_ict;
  insert into org_nodes (entity_id, parent_id, title, node_type, track, sort_order) values
    (v_ngo_entity, v_headops, 'Child Sponsorship', 'department', 'ngo', 3) returning id into v_sponsorship;

  insert into org_nodes (entity_id, parent_id, title, node_type, track, sort_order) values
    (v_ngo_entity, v_operations, 'Resource', 'unit', 'ngo', 0),
    (v_ngo_entity, v_operations, 'Programs', 'unit', 'ngo', 1),
    (v_ngo_entity, v_operations, 'Comms & Media Lead', 'unit', 'ngo', 2);
end $$;

-- ---- School organogram ----
do $$
declare
  v_school_entity uuid := (select id from entities where track = 'academic');
  v_board uuid; v_irene uuid; v_king uuid; v_headops uuid; v_principal uuid;
  v_vpa uuid; v_vpad uuid; v_teachsup uuid; v_adminassist uuid;
begin
  insert into org_nodes (entity_id, title, node_type, track, sort_order) values
    (v_school_entity, 'Board of Trustees', 'board', 'academic', 0) returning id into v_board;

  insert into org_nodes (entity_id, parent_id, title, subtitle, node_type, track, sort_order) values
    (v_school_entity, v_board, 'Irene Bangwell', 'Co-Founder, Head of Learning Design', 'leadership', 'academic', 0) returning id into v_irene;
  insert into org_nodes (entity_id, parent_id, title, subtitle, node_type, track, sort_order) values
    (v_school_entity, v_board, 'Kingsley Bangwell', 'Co-Founder, Strategy & Fundraising', 'leadership', 'academic', 1) returning id into v_king;

  insert into org_nodes (entity_id, parent_id, title, subtitle, node_type, track, sort_order) values
    (v_school_entity, v_king, 'Head of Operations and Systems', 'Reports to Co-Founders', 'leadership', 'academic', 0) returning id into v_headops;

  insert into org_nodes (entity_id, parent_id, title, subtitle, node_type, track, sort_order) values
    (v_school_entity, v_headops, 'Principal', 'Head of School (academic line also to Irene — see notes)', 'leadership', 'academic', 0) returning id into v_principal;

  insert into org_nodes (entity_id, parent_id, title, subtitle, node_type, track, sort_order) values
    (v_school_entity, v_principal, 'Vice Principal Academics', 'Reports to Principal', 'department', 'academic', 0) returning id into v_vpa;
  insert into org_nodes (entity_id, parent_id, title, subtitle, node_type, track, sort_order) values
    (v_school_entity, v_principal, 'Vice Principal Administration', 'Reports to Principal', 'department', 'academic', 1) returning id into v_vpad;

  insert into org_nodes (entity_id, parent_id, title, node_type, track, sort_order) values
    (v_school_entity, v_vpa, 'Teaching Supervisors', 'unit', 'academic', 0) returning id into v_teachsup;
  insert into org_nodes (entity_id, parent_id, title, node_type, track, sort_order) values
    (v_school_entity, v_vpad, 'Administrative Assistants', 'unit', 'academic', 0) returning id into v_adminassist;

  insert into org_nodes (entity_id, parent_id, title, subtitle, node_type, track, sort_order) values
    (v_school_entity, v_teachsup, 'Teaching Staff', 'Fulltime | Part-time | Volunteers | NYSC', 'unit', 'academic', 0),
    (v_school_entity, v_adminassist, 'Non-Teaching Staff', null, 'unit', 'academic', 0);
end $$;

-- ---- Document types (SOP-driven) ----
insert into document_types (name, track, is_mandatory) values
  ('Job Description', null, true),
  ('Offer Letter', null, true),
  ('Signed Contract', null, true),
  ('Guarantor Form', null, true),
  ('Safeguarding Declaration', 'academic', true),
  ('Qualification / TRC Registration', 'academic', true),
  ('Handover Note (previous role)', null, false);

-- ---- Access systems (generic starter set — expand per real inventory) ----
insert into access_systems (name, category) values
  ('Official KNOSK Email', 'email'),
  ('Ops WhatsApp Group', 'whatsapp'),
  ('Shared Drive — General', 'drive'),
  ('Shared Drive — Track-Specific', 'drive'),
  ('Finance/Payroll Platform', 'platform'),
  ('Social Media Accounts', 'platform');

-- ---- Onboarding templates (per SOP + Annex A/B) ----
insert into onboarding_templates (track, task_name, sequence, is_mandatory) values
  (null, 'Collect signed offer letter', 1, true),
  (null, 'Issue official email + core access', 2, true),
  (null, 'HR policy & handbook walkthrough', 3, true),
  (null, 'Confirm guarantor form on file', 4, true),
  ('academic', 'Verify safeguarding declaration signed', 5, true),
  ('academic', 'Verify TRC registration / in-progress status', 6, true),
  ('academic', 'Introduce to Teaching Supervisor + hand over CERMATCC pack for subject', 7, true),
  ('ngo', 'Brief on public visibility / fundraising expectations', 5, true),
  ('ngo', 'Grant relevant shared drive + platform access', 6, true);

-- ---- Offboarding templates (per SOP + Annex A/B — mandatory, enforced by trigger) ----
insert into offboarding_templates (track, task_name, sequence, is_mandatory) values
  (null, 'Structured handover document submitted', 1, true),
  (null, 'All access revoked (email, drives, WhatsApp, platforms)', 2, true),
  (null, 'Exit interview conducted', 3, false),
  (null, 'Final settlement processed', 4, true),
  ('academic', 'CERMATCC breakdown, lesson aliases & materials handed over', 5, true),
  ('academic', 'Student progress records transferred', 6, true),
  ('ngo', 'External contacts (donors/vendors/media) transferred with live details', 5, true),
  ('ngo', 'Ongoing project/campaign/grant status documented', 6, true),
  ('ngo', 'Login/social access transferred out of personal name', 7, true);

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================
