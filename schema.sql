-- Sistema de tarefas: Jovem Aprendiz + Diretor de Secretaria
-- Execute UMA VEZ no SQL Editor de um projeto Supabase novo.
-- Ambos os cargos têm as mesmas permissões operacionais.
-- Não execute em produção sem revisar/testar primeiro.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text,
  role text not null default 'jovem_aprendiz'
    check (role in ('jovem_aprendiz', 'diretor_secretaria')),
  created_at timestamptz not null default now()
);

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(trim(title)) between 1 and 180),
  description text not null default '',
  task_date date not null default current_date,
  due_date date,
  priority text not null default 'normal'
    check (priority in ('baixa', 'normal', 'alta', 'urgente')),
  status text not null default 'pendente'
    check (status in ('pendente', 'em_andamento', 'concluida', 'cancelada')),
  assigned_to uuid references public.profiles(id) on delete set null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.extra_activities (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(trim(title)) between 1 and 180),
  description text not null default '',
  due_date date,
  priority text not null default 'normal'
    check (priority in ('baixa', 'normal', 'alta', 'urgente')),
  status text not null default 'pendente'
    check (status in ('pendente', 'em_andamento', 'concluida', 'cancelada')),
  assigned_to uuid references public.profiles(id) on delete set null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_table text not null,
  entity_id text,
  occurred_at timestamptz not null default now(),
  old_data jsonb,
  new_data jsonb
);

create index if not exists tasks_task_date_idx on public.tasks(task_date);
create index if not exists tasks_status_idx on public.tasks(status);
create index if not exists tasks_assigned_to_idx on public.tasks(assigned_to);
create index if not exists extra_activities_due_date_idx on public.extra_activities(due_date);
create index if not exists audit_logs_occurred_at_idx on public.audit_logs(occurred_at desc);

alter table public.profiles enable row level security;
alter table public.tasks enable row level security;
alter table public.extra_activities enable row level security;
alter table public.audit_logs enable row level security;

-- Profile creation trigger: role always defaults to apprentice.
-- A user cannot assign themselves director role through signup metadata.
create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, full_name, role)
  values (
    new.id,
    new.email,
    nullif(new.raw_user_meta_data ->> 'full_name', ''),
    'jovem_aprendiz'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
after insert on auth.users
for each row execute procedure public.create_profile_for_new_user();

-- updated_at maintained in database
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists tasks_set_updated_at on public.tasks;
create trigger tasks_set_updated_at before update on public.tasks
for each row execute procedure public.set_updated_at();

drop trigger if exists extra_activities_set_updated_at on public.extra_activities;
create trigger extra_activities_set_updated_at before update on public.extra_activities
for each row execute procedure public.set_updated_at();

-- Audit log is written by database triggers, not by frontend claims.
create or replace function public.write_audit_log()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_id text;
begin
  if TG_OP = 'INSERT' then
    row_id := to_jsonb(NEW) ->> 'id';
    insert into public.audit_logs(actor_id, action, entity_table, entity_id, new_data)
    values (auth.uid(), 'criou', TG_TABLE_NAME, row_id, to_jsonb(NEW));
    return NEW;
  elsif TG_OP = 'UPDATE' then
    row_id := to_jsonb(NEW) ->> 'id';
    insert into public.audit_logs(actor_id, action, entity_table, entity_id, old_data, new_data)
    values (auth.uid(), 'alterou', TG_TABLE_NAME, row_id, to_jsonb(OLD), to_jsonb(NEW));
    return NEW;
  elsif TG_OP = 'DELETE' then
    row_id := to_jsonb(OLD) ->> 'id';
    insert into public.audit_logs(actor_id, action, entity_table, entity_id, old_data)
    values (auth.uid(), 'excluiu', TG_TABLE_NAME, row_id, to_jsonb(OLD));
    return OLD;
  end if;
  return null;
end;
$$;

drop trigger if exists tasks_audit on public.tasks;
create trigger tasks_audit after insert or update or delete on public.tasks
for each row execute procedure public.write_audit_log();

drop trigger if exists extra_activities_audit on public.extra_activities;
create trigger extra_activities_audit after insert or update or delete on public.extra_activities
for each row execute procedure public.write_audit_log();

-- Authenticated users can read profiles; profile role is not editable from frontend.
create policy "authenticated read profiles"
on public.profiles for select to authenticated using (true);

create policy "users update own name"
on public.profiles for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

-- Both cargos can manage all tasks. Inserts must be attributed to the signed-in user.
create policy "authenticated read tasks"
on public.tasks for select to authenticated using (true);

create policy "authenticated create tasks"
on public.tasks for insert to authenticated
with check (created_by = (select auth.uid()));

create policy "authenticated update tasks"
on public.tasks for update to authenticated
using (true) with check (true);

create policy "authenticated delete tasks"
on public.tasks for delete to authenticated using (true);

-- Same permissions for extra activities.
create policy "authenticated read extra activities"
on public.extra_activities for select to authenticated using (true);

create policy "authenticated create extra activities"
on public.extra_activities for insert to authenticated
with check (created_by = (select auth.uid()));

create policy "authenticated update extra activities"
on public.extra_activities for update to authenticated
using (true) with check (true);

create policy "authenticated delete extra activities"
on public.extra_activities for delete to authenticated using (true);

-- Any authenticated user can consult the full log; nobody can edit/delete it via API.
create policy "authenticated read audit logs"
on public.audit_logs for select to authenticated using (true);

revoke all on public.profiles from anon;
revoke all on public.tasks from anon;
revoke all on public.extra_activities from anon;
revoke all on public.audit_logs from anon;

grant select, update (full_name) on public.profiles to authenticated;
grant select, insert, update, delete on public.tasks to authenticated;
grant select, insert, update, delete on public.extra_activities to authenticated;
grant select on public.audit_logs to authenticated;
grant usage, select on sequence public.audit_logs_id_seq to authenticated;

-- Role changes are intentionally performed by trusted project owner in SQL Editor.
-- Example (replace UUID): update public.profiles set role='diretor_secretaria'
-- where id='UUID-DO-USUARIO';
