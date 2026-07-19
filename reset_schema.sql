-- ============================================================================
-- KNOSK HR SYSTEM — RESET SCRIPT
-- Run this FIRST if you're re-running knosk_hr_schema.sql on a project where
-- it (or an earlier version of it) already partially ran. This removes
-- every table, view, function, type, and storage policy the schema creates,
-- so the main script can run again from a clean slate.
--
-- Safe notes:
-- - This does NOT delete your Supabase auth users (including any bootstrap
--   admin login you already created) — only this app's own data/schema.
-- - Run this, then immediately run knosk_hr_schema.sql again in full.
-- ============================================================================

-- Views (drop first — they depend on the tables below)
drop view if exists v_org_chart;
drop view if exists v_offboarding_progress;
drop view if exists v_onboarding_progress;
drop view if exists v_leadership_dashboard;

-- Tables (cascade removes their indexes, triggers, and policies automatically)
drop table if exists notification_log cascade;
drop table if exists notification_preferences cascade;
drop table if exists audit_log cascade;
drop table if exists alerts cascade;
drop table if exists reassignments cascade;
drop table if exists offboarding_tasks cascade;
drop table if exists offboarding_templates cascade;
drop table if exists onboarding_tasks cascade;
drop table if exists onboarding_templates cascade;
drop table if exists staff_access cascade;
drop table if exists access_systems cascade;
drop table if exists staff_documents cascade;
drop table if exists document_types cascade;
drop table if exists offer_letters cascade;
drop table if exists staff cascade;
drop table if exists job_descriptions cascade;
drop table if exists profiles cascade;
drop table if exists org_nodes cascade;
drop table if exists entities cascade;

-- Functions (cascade also drops any triggers still referencing them)
drop function if exists audit_trigger_fn() cascade;
drop function if exists enforce_offboarding_before_exit() cascade;
drop function if exists auto_generate_offboarding_on_status_change() cascade;
drop function if exists generate_offboarding_tasks(uuid) cascade;
drop function if exists auto_provision_new_staff() cascade;
drop function if exists generate_onboarding_tasks(uuid) cascade;
drop function if exists generate_staff_documents(uuid) cascade;
drop function if exists enforce_offer_letter_clauses() cascade;
drop function if exists enforce_job_title_matches_jd() cascade;
drop function if exists current_app_role() cascade;
drop function if exists queue_alert_notifications() cascade;

-- Storage: remove this app's policies (leaves other buckets/objects alone).
-- Note: we deliberately do NOT delete from storage.objects/storage.buckets
-- directly — Supabase blocks direct deletes on those tables by design
-- ("Use the Storage API instead"), and it's unnecessary anyway: the main
-- schema's bucket insert uses ON CONFLICT DO NOTHING, so an existing
-- staff-documents bucket is simply left as-is on re-run. If you genuinely
-- want the bucket gone, delete it manually via Supabase Dashboard →
-- Storage → staff-documents → delete.
drop policy if exists staff_documents_storage_read on storage.objects;
drop policy if exists staff_documents_storage_write on storage.objects;
drop policy if exists staff_documents_storage_update on storage.objects;
drop policy if exists staff_documents_storage_delete on storage.objects;

-- Enum types (must drop last — tables above referenced these)
drop type if exists app_role;
drop type if exists org_node_type;
drop type if exists alert_severity;
drop type if exists task_status;
drop type if exists access_status;
drop type if exists doc_status;
drop type if exists staff_category;
drop type if exists employment_status;
drop type if exists track_type;

-- Done. Now run knosk_hr_schema.sql in full.
