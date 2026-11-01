-- Pretty Dispatch role separation (phase 1)
-- SMS is NOT used. The administrator signs in with a phone-number alias and password.
-- Create the initial Auth user in Dashboard using email admin_07024632256@pretty-dispatch.invalid,
-- then run this migration to promote that exact account.
-- IMPORTANT: Back up dispatch_jobs before running this migration.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'pending' check (role in ('pending','admin','staff','driver')),
  display_name text not null default '',
  phone text,
  login_id text unique,
  approved boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles add column if not exists login_id text unique;

alter table public.dispatch_jobs
  add column if not exists driver_user_id uuid references public.profiles(user_id) on delete set null;

-- Every new Auth user gets a non-privileged profile. No client can self-assign a role.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles(user_id, phone, display_name, role, approved)
  values (
    new.id,
    nullif(new.phone, ''),
    coalesce(new.raw_user_meta_data->>'display_name', ''),
    'pending',
    false
  )
  on conflict (user_id) do update
    set phone = excluded.phone,
        updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_pretty_dispatch on auth.users;
create trigger on_auth_user_created_pretty_dispatch
after insert or update of phone on auth.users
for each row execute function public.handle_new_auth_user();

-- Promote the exact initial administrator login created manually in Supabase Auth.
-- Create user with email admin_07024632256@pretty-dispatch.invalid first.
update public.profiles p
set role = 'admin', approved = true, phone = '07024632256',
    login_id = '07024632256', updated_at = now()
from auth.users u
where p.user_id = u.id
  and lower(u.email) = 'admin_07024632256@pretty-dispatch.invalid';

-- SECURITY DEFINER helpers avoid recursive RLS checks on profiles.
create or replace function public.current_user_is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $
  select exists (
    select 1 from public.profiles p
    where p.user_id = (select auth.uid())
      and p.role = 'admin' and p.approved = true
  );
$;

create or replace function public.current_user_is_staff_or_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $
  select exists (
    select 1 from public.profiles p
    where p.user_id = (select auth.uid())
      and p.role in ('admin','staff') and p.approved = true
  );
$;

revoke all on function public.current_user_is_admin() from public;
revoke all on function public.current_user_is_staff_or_admin() from public;
grant execute on function public.current_user_is_admin() to authenticated;
grant execute on function public.current_user_is_staff_or_admin() to authenticated;

alter table public.profiles enable row level security;
alter table public.dispatch_jobs enable row level security;

-- Remove the old broad policies that allowed every authenticated account
-- to read/write every dispatch job.
drop policy if exists dispatch_select_staff on public.dispatch_jobs;
drop policy if exists dispatch_insert_staff on public.dispatch_jobs;
drop policy if exists dispatch_update_staff on public.dispatch_jobs;
drop policy if exists dispatch_delete_staff on public.dispatch_jobs;
drop policy if exists dispatch_select_by_role on public.dispatch_jobs;
drop policy if exists dispatch_insert_by_role on public.dispatch_jobs;
drop policy if exists dispatch_update_by_role on public.dispatch_jobs;
drop policy if exists dispatch_delete_by_role on public.dispatch_jobs;

drop policy if exists profiles_select_self_or_admin on public.profiles;
drop policy if exists profiles_update_admin_only on public.profiles;

create policy profiles_select_self_or_admin
on public.profiles for select to authenticated
using (user_id = (select auth.uid()) or (select public.current_user_is_admin()));

-- Profiles are provisioned by a trusted server/admin process, never by clients.
create policy profiles_update_admin_only
on public.profiles for update to authenticated
using ((select public.current_user_is_admin()))
with check ((select public.current_user_is_admin()));

create policy dispatch_select_by_role
on public.dispatch_jobs for select to authenticated
using (
  (select public.current_user_is_staff_or_admin())
  or driver_user_id = (select auth.uid())
);

create policy dispatch_insert_by_role
on public.dispatch_jobs for insert to authenticated
with check ((select public.current_user_is_staff_or_admin()));

create policy dispatch_update_by_role
on public.dispatch_jobs for update to authenticated
using ((select public.current_user_is_staff_or_admin()))
with check ((select public.current_user_is_staff_or_admin()));

create policy dispatch_delete_by_role
on public.dispatch_jobs for delete to authenticated
using (
  (select public.current_user_is_admin())
);

-- Existing text-only driver assignments must be linked to driver_user_id
-- after driver accounts have been provisioned. Do not guess the mapping.
