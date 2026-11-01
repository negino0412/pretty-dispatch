# Pretty Dispatch: role separation setup

## Current status
This repository change prepares the database schema and row-level security (RLS). It does not by itself configure your Supabase project, send SMS, create Auth users, or deploy Edge Functions.

Initial administrator phone: 07024632256 (E.164: +817024632256).

## Required order

1. In Supabase Dashboard, open Authentication > Providers > Phone and enable phone authentication.
2. Configure an SMS provider (for example Twilio) and its credentials in Supabase. Never put provider secrets or the service-role key in this repository or in the browser.
3. Authenticate the initial administrator using SMS with +817024632256. Confirm that the user appears under Authentication > Users and that the phone is verified.
4. Back up the current database, especially public.dispatch_jobs.
5. Open SQL Editor and run supabase_roles_setup.sql.
6. Check the SQL result. The promotion UPDATE must affect exactly one profile. If it affects zero rows, stop and verify the phone-auth user and E.164 phone. Do not proceed as if admin setup succeeded.
7. Confirm the profile row has role=admin and approved=true.
8. Do not use the current app's old email/password login after enabling strict RLS until the role-aware client update is deployed.

## Role rules prepared by the migration

- admin: all jobs; can delete jobs; can administer profiles.
- staff: all jobs; can create/update jobs; cannot delete jobs.
- driver: can read only rows whose driver_user_id equals their own Auth user ID; no job writes.
- pending/unapproved: no job access.
- New Auth users default to pending. A user cannot assign themselves a role from the browser.

## Important unfinished work

The current browser app still uses a shared email/password login and free-text driver field. It has not yet been converted to phone/SMS staff login, username/password driver login, admin-issued accounts, or per-driver job filtering. Do not onboard drivers or staff until that client and trusted account-provisioning function are implemented and deployed.

The driver username/password flow requires a server-side Supabase Edge Function using SUPABASE_SERVICE_ROLE_KEY stored as a server secret. Never expose that key in index.html. Staff phone invitations and account approval also require a server-side provisioning flow. Web Push notifications require a separate VAPID configuration and push-sending function; Supabase Realtime is not push while the app is closed.

## Existing data
The migration intentionally keeps the existing text driver column and adds driver_user_id. Existing assignments need explicit mapping to the correct driver profile. No automatic name matching is performed, because that could expose a job to the wrong driver.

## Rollback
Do not drop profiles or driver_user_id as a casual rollback. Restore from your database backup or have the migration reviewed before changing RLS policies.
