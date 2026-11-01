# Pretty Dispatch account setup (password-only)

## Login identifiers
- Admin: phone number + password. The phone number is used as a login ID alias; no SMS is sent.
- Operations staff: staff ID + password.
- Driver: driver name/login ID + password.
- Admin issues staff and driver accounts. No self-registration.

## Step 1 — create the initial administrator
In Supabase Dashboard > Authentication > Users, create a user with:
- Email: `admin_07024632256@pretty-dispatch.invalid`
- Password: choose a unique password of at least 12 characters.
- Confirm the email/user if the dashboard asks.

This is an internal login alias, not a real mailbox. The app's phone login screen converts 07024632256 to this alias. Do not enable Phone/SMS authentication or enter Twilio credentials.

## Step 2 — database migration
Back up the database first. Run `supabase_roles_setup.sql` in Supabase SQL Editor. Then verify that the profile for the user above has role=admin and approved=true. If the promotion update affected zero rows, stop and check the exact Auth email.

## Step 3 — deploy account provisioning
Deploy `supabase/functions/admin-create-account/index.ts` as Edge Function `admin-create-account`.
Set Edge Function secrets:
- SUPABASE_URL
- SUPABASE_SERVICE_ROLE_KEY

The service-role key must remain a server secret and must never be put in index.html or shared in chat.

The function permits only an authenticated, approved admin to issue staff or driver accounts. It requires passwords of at least 12 characters. Login IDs are unique.

## Remaining app work
The existing index.html has not yet been changed to role-specific login forms, role-aware controls, filtered driver lists, or driver assignment IDs. Until that frontend update is deployed and tested, do not issue accounts or run the new RLS migration on a live production database. The current app is not yet compatible with the new login scheme.
