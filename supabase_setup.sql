create table if not exists public.dispatch_jobs (
 id uuid primary key, girl text not null, driver text not null default '',
 catcher text not null default '', start_time text not null default '',
 out_time text not null default '', note text not null default '',
 status text not null default '予定', updated_at timestamptz not null default now()
);

alter table public.dispatch_jobs
 add column if not exists panel text not null default '',
 add column if not exists place text not null default '',
 add column if not exists map_url text not null default '',
 add column if not exists duration text not null default '',
 add column if not exists price text not null default '',
 add column if not exists payment text not null default '',
 add column if not exists travel text not null default '',
 add column if not exists event text not null default '',
 add column if not exists options text not null default '',
 add column if not exists customer text not null default '',
 add column if not exists phone text not null default '',
 add column if not exists history text not null default '',
 add column if not exists catch_done boolean not null default false;
alter table public.dispatch_jobs enable row level security;
drop policy if exists dispatch_select_staff on public.dispatch_jobs;
drop policy if exists dispatch_insert_staff on public.dispatch_jobs;
drop policy if exists dispatch_update_staff on public.dispatch_jobs;
drop policy if exists dispatch_delete_staff on public.dispatch_jobs;
create policy dispatch_select_staff on public.dispatch_jobs for select to authenticated using (true);
create policy dispatch_insert_staff on public.dispatch_jobs for insert to authenticated with check (true);
create policy dispatch_update_staff on public.dispatch_jobs for update to authenticated using (true) with check (true);
create policy dispatch_delete_staff on public.dispatch_jobs for delete to authenticated using (true);
do $$ begin alter publication supabase_realtime add table public.dispatch_jobs;
exception when duplicate_object then null; when others then if sqlstate='42710' then null; else raise; end if; end $$;