-- =========================================================
-- Parrallery · one-per-user counters + project comments
-- Run in Supabase → SQL Editor. Safe to run more than once.
-- =========================================================

-- ---------------------------------------------------------
-- Per-user counter tables
-- ---------------------------------------------------------
alter table public.projects add column if not exists lyrics text;
alter table public.projects add column if not exists release_type text;
alter table public.projects add column if not exists release_metadata jsonb not null default '{}'::jsonb;
alter table public.projects add column if not exists featured_users uuid[] default '{}';
alter table public.projects add column if not exists featured_artist_names text[] default '{}';

create table if not exists public.project_views (
  user_id uuid not null references auth.users(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, project_id)
);

create table if not exists public.project_plays (
  user_id uuid not null references auth.users(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, project_id)
);

create table if not exists public.project_shares (
  user_id uuid not null references auth.users(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, project_id)
);

create index if not exists idx_views_project on public.project_views(project_id);
create index if not exists idx_plays_project on public.project_plays(project_id);
create index if not exists idx_plays_user_created on public.project_plays(user_id, created_at desc);
create index if not exists idx_shares_project on public.project_shares(project_id);

alter table public.project_views enable row level security;
alter table public.project_plays enable row level security;
alter table public.project_shares enable row level security;

-- these tables are only touched by the security-definer RPCs below
revoke all on public.project_views from anon, authenticated;
revoke all on public.project_plays from anon, authenticated;
revoke all on public.project_shares from anon, authenticated;

-- ---------------------------------------------------------
-- VIEWS · counts each signed-in visitor once per project
-- ---------------------------------------------------------
create or replace function public.record_project_view(p_project uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  view_count int;
  inserted boolean := false;
begin
  if not exists (select 1 from projects where id = p_project) then
    return jsonb_build_object('error', 'Project not found');
  end if;

  if uid is not null then
    insert into project_views (user_id, project_id) values (uid, p_project)
      on conflict (user_id, project_id) do nothing;
    inserted := found;
  end if;

  if inserted then
    update projects
    set views = (coalesce(nullif(views, '')::int, 0) + 1)::text
    where id = p_project
    returning coalesce(nullif(views, '')::int, 0) into view_count;
  else
    select coalesce(nullif(views, '')::int, 0) into view_count
    from projects where id = p_project;
  end if;

  return jsonb_build_object('ok', true, 'views', view_count, 'counted', inserted);
end;
$$;

revoke all on function public.record_project_view(uuid) from public;
grant execute on function public.record_project_view(uuid) to anon, authenticated;

-- ---------------------------------------------------------
-- PLAYS · one per listener/project, capped at 100 distinct plays per day
-- ---------------------------------------------------------
create or replace function public.record_project_play(p_project uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  play_count int;
  inserted boolean := false;
  daily_count int;
begin
  if uid is null then
    return jsonb_build_object('error', 'Sign in to record a play');
  end if;

  if not exists (select 1 from projects where id = p_project) then
    return jsonb_build_object('error', 'Project not found');
  end if;

  -- Serialize this user's counter updates so concurrent RPC calls cannot evade the cap.
  perform 1 from auth.users where id = uid for update;

  if exists (
    select 1 from project_plays where user_id = uid and project_id = p_project
  ) then
    select coalesce(nullif(plays, '')::int, 0) into play_count
    from projects where id = p_project;
    return jsonb_build_object('ok', true, 'plays', play_count, 'counted', false);
  end if;

  select count(*) into daily_count
  from project_plays
  where user_id = uid and created_at >= now() - interval '24 hours';

  if daily_count >= 100 then
    select coalesce(nullif(plays, '')::int, 0) into play_count
    from projects where id = p_project;
    return jsonb_build_object('ok', true, 'plays', play_count, 'counted', false, 'reason', 'daily_limit');
  end if;

  insert into project_plays (user_id, project_id)
    select uid, p_project
    from projects
    where id = p_project and user_id is distinct from uid
    on conflict (user_id, project_id) do nothing;
  inserted := found;

  if inserted then
    update projects
    set plays = (coalesce(nullif(plays, '')::int, 0) + 1)::text
    where id = p_project
    returning coalesce(nullif(plays, '')::int, 0) into play_count;
  else
    select coalesce(nullif(plays, '')::int, 0) into play_count
    from projects where id = p_project;
  end if;

  return jsonb_build_object('ok', true, 'plays', play_count, 'counted', inserted);
end;
$$;

revoke all on function public.record_project_play(uuid) from public;
grant execute on function public.record_project_play(uuid) to authenticated;

-- Remove the former fixed-rate estimate; Parrallery has no active payout program.
drop function if exists public.creator_play_earnings();

-- ---------------------------------------------------------
-- SHARES · counts each signed-in sharer once per project
-- ---------------------------------------------------------
create or replace function public.record_project_share(p_project uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  share_count int;
  inserted boolean := false;
begin
  if not exists (select 1 from projects where id = p_project) then
    return jsonb_build_object('error', 'Project not found');
  end if;

  if uid is not null then
    insert into project_shares (user_id, project_id) values (uid, p_project)
      on conflict (user_id, project_id) do nothing;
    inserted := found;
  end if;

  if inserted then
    update projects
    set shares = (coalesce(nullif(shares, '')::int, 0) + 1)::text
    where id = p_project
    returning coalesce(nullif(shares, '')::int, 0) into share_count;
  else
    select coalesce(nullif(shares, '')::int, 0) into share_count
    from projects where id = p_project;
  end if;

  return jsonb_build_object('ok', true, 'shares', share_count, 'counted', inserted);
end;
$$;

revoke all on function public.record_project_share(uuid) from public;
grant execute on function public.record_project_share(uuid) to anon, authenticated;

-- ---------------------------------------------------------
-- COMMENTS
-- ---------------------------------------------------------
create table if not exists public.project_comments (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  parent_id uuid references public.project_comments(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 280),
  created_at timestamptz default now()
);

-- table may already exist from an earlier run
alter table public.project_comments
  add column if not exists parent_id uuid references public.project_comments(id) on delete cascade;

create index if not exists idx_comments_project
  on public.project_comments(project_id, created_at desc);

create index if not exists idx_comments_parent
  on public.project_comments(parent_id);

alter table public.project_comments enable row level security;

drop policy if exists "project_comments_public_read" on public.project_comments;
create policy "project_comments_public_read"
  on public.project_comments for select
  using (true);

drop policy if exists "project_comments_own_insert" on public.project_comments;
create policy "project_comments_own_insert"
  on public.project_comments for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "project_comments_own_delete" on public.project_comments;
create policy "project_comments_own_delete"
  on public.project_comments for delete
  to authenticated
  using (user_id = auth.uid() or public.is_admin());

grant select on public.project_comments to anon, authenticated;
grant insert, delete on public.project_comments to authenticated;

-- ---------------------------------------------------------
-- Comment notifications
-- Top-level comment  → the project owner.
-- Reply              → the author of the comment being replied to.
-- ---------------------------------------------------------
create or replace function public.notify_on_comment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  owner uuid;
  parent_author uuid;
begin
  if new.parent_id is not null then
    select user_id into parent_author
    from project_comments where id = new.parent_id;

    if parent_author is not null and parent_author <> new.user_id then
      insert into notifications (user_id, actor_id, kind, project_id, body)
      values (parent_author, new.user_id, 'reply', new.project_id, left(new.body, 140));
    end if;
    return new;
  end if;

  select user_id into owner from projects where id = new.project_id;
  if owner is not null and owner <> new.user_id then
    insert into notifications (user_id, actor_id, kind, project_id, body)
    values (owner, new.user_id, 'comment', new.project_id, left(new.body, 140));
  end if;
  return new;
end;
$$;

drop trigger if exists on_project_comment_notify on public.project_comments;
create trigger on_project_comment_notify
  after insert on public.project_comments
  for each row execute function public.notify_on_comment();

-- ---------------------------------------------------------
-- Official @app comment on a member's new upload.
-- Only the uploader can invite @app, and only once per upload.
-- ---------------------------------------------------------
create or replace function public.persona_comment(
  p_project uuid,
  p_body text,
  p_persona text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_id uuid;
  persona_id uuid;
  already boolean;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if p_persona is distinct from 'app' then
    raise exception 'only @app can post automated upload comments';
  end if;

  select user_id into owner_id from public.projects where id = p_project;
  if owner_id is null then
    raise exception 'project not found';
  end if;

  if owner_id <> auth.uid() then
    raise exception 'only the uploader can invite persona comments';
  end if;

  if coalesce(btrim(p_body), '') = '' then
    raise exception 'empty comment';
  end if;

  select user_id into persona_id from public.profiles where handle = p_persona limit 1;
  if persona_id is null then
    raise exception '@% account is missing', p_persona;
  end if;

  if persona_id = owner_id then
    return jsonb_build_object('ok', true, 'skipped', true);
  end if;

  select exists (
    select 1 from public.project_comments
    where project_id = p_project and user_id = persona_id
  ) into already;
  if already then
    return jsonb_build_object('ok', true, 'skipped', true);
  end if;

  insert into public.project_comments (project_id, user_id, body)
  values (p_project, persona_id, left(btrim(p_body), 280));

  return jsonb_build_object('ok', true, 'skipped', false);
end;
$$;

revoke all on function public.persona_comment(uuid, text, text) from public;
grant execute on function public.persona_comment(uuid, text, text) to authenticated;
