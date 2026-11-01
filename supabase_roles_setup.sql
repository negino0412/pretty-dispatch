-- Pretty Dispatch role separation (phase 1)
-- Run only after the initial administrator has completed SMS phone authentication.
-- Japan phone number 07024632256 is stored in Supabase Auth in E.164 form: +817024632256.
-- IMPORTANT: Back up dispatch_jobs before running this migration.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'pending' check (role in ('pending','admin','staff','driver')),
  display_name text not null default '',
  phone text,
  approved boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

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

-- Promote ONLY the verified phone account supplied by the owner.
-- If this updates 0 rows, do not proceed: first complete SMS authentication
-- with that phone number, then rerun this UPDATE.
update public.profiles p
set role = 'admin', approved = true, phone = u.phone, updated_at = now()
from auth.users u
where p.user_id = u.id
  and u.phone = '+817024632256';

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
using (
  user_id = (select auth.uid())
  or exists (
    select 1 from public.profiles me
    where me.user_id = (select auth.uid())
      and me.role = 'admin' and me.approved = true
  )
);

-- Profiles are provisioned by a trusted server/admin process, never by clients.
create policy profiles_update_admin_only
on public.profiles for update to authenticated
using (
  exists (
    select 1 from public.profiles me
    where me.user_id = (select auth.uid())
      and me.role = 'admin' and me.approved = true
  )
)
with check (
  exists (
    select 1 from public.profiles me
    where me.user_id = (select auth.uid())
      and me.role = 'admin' and me.approved = true
  )
);

create policy dispatch_select_by_role
on public.dispatch_jobs for select to authenticated
using (
  exists (
    select 1 from public.profiles me
    where me.user_id = (select auth.uid())
      and me.approved = true
      and me.role in ('admin','staff')
  )
  or driver_user_id = (select auth.uid())
);

create policy dispatch_insert_by_role
on public.dispatch_jobs for insert to authenticated
with check (
  exists (
    select 1 from public.profiles me
    where me.user_id = (select auth.uid())
      and me.approved = true
      and me.role in ('admin','staff')
  )
);

create policy dispatch_update_by_role
on public.dispatch_jobs for update to authenticated
using (
  exists (
    select 1 from public.profiles me
    where me.user_id = (select auth.uid())
      and me.approved = true
      and me.role in ('admin','staff')
  )
)
with check (
  exists (
    select 1 from public.profiles me
    where me.user_id = (select auth.uid())
      and me.approved = true
      and me.role in ('admin','staff')
  )
);

create policy dispatch_delete_by_role
on public.dispatch_jobs for delete to authenticated
using (
  exists (
    select 1 from public.profiles me
    where me.user_id = (select auth.uid())
      and me.role = 'admin' and me.approved = true
  )
);

-- Existing text-only driver assignments must be linked to driver_user_id
-- after driver accounts have been provisioned. Do not guess the mapping.
