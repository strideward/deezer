-- Parrallery schema + abuse prevention — run in SQL Editor → Run (safe to re-run)

-- =========================================================
-- CORE TABLES
-- =========================================================
create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users(id) on delete cascade,
  handle text unique not null,
  name text,
  role text,
  preferred_genres text[] not null default '{}',
  country text,
  hometown text,
  website_url text,
  profile_links jsonb not null default '{}'::jsonb,
  bio text,
  img text,
  public_profile boolean not null default true,
  allow_messages boolean not null default false,
  new_follower_notifications boolean not null default true,
  message_notifications boolean not null default true,
  followers text default '0',
  following text default '0',
  verified boolean default false,
  is_admin boolean default false,
  suspended boolean default false,
  created_at timestamptz default now()
);
alter table public.profiles add column if not exists hometown text;
alter table public.profiles add column if not exists website_url text;
alter table public.profiles add column if not exists profile_links jsonb not null default '{}'::jsonb;

create table if not exists public.user_roles (
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('listener', 'artist')),
  created_at timestamptz not null default now(),
  primary key (user_id, role)
);

create table if not exists public.artist_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  artist_name text not null,
  category text,
  creator_type text,
  bio text,
  genres text[] not null default '{}',
  image_url text,
  links jsonb not null default '{}'::jsonb,
  verification_status text not null default 'unverified'
    check (verification_status in ('unverified', 'verified')),
  created_at timestamptz not null default now()
);
alter table public.artist_profiles add column if not exists category text;
alter table public.artist_profiles add column if not exists creator_type text;

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  title text not null,
  creator text not null,
  role text,
  type text default 'Project',
  release_type text,
  featured_users uuid[] default '{}',
  featured_artist_names text[] default '{}',
  description text,
  lyrics text,
  release_metadata jsonb not null default '{}'::jsonb,
  bpm text,
  "key" text,
  tags text[] default '{}',
  cover text,
  price numeric,
  license text,
  file_name text,
  file_url text,
  views text default '0',
  likes text default '0',
  shares text default '0',
  downloads text default '0',
  plays text default '0',
  date text,
  created_at timestamptz default now()
);

-- upgrades for databases created before these columns existed
alter table public.profiles add column if not exists following text default '0';
alter table public.profiles add column if not exists preferred_genres text[] not null default '{}';
alter table public.profiles add column if not exists verified boolean default false;
alter table public.profiles add column if not exists is_admin boolean default false;
alter table public.profiles add column if not exists suspended boolean default false;
alter table public.profiles add column if not exists public_profile boolean not null default true;
alter table public.profiles add column if not exists allow_messages boolean not null default false;
alter table public.profiles add column if not exists new_follower_notifications boolean not null default true;
alter table public.profiles add column if not exists message_notifications boolean not null default true;
alter table public.projects add column if not exists type text default 'Project';
alter table public.projects add column if not exists release_type text;
alter table public.projects add column if not exists featured_users uuid[] default '{}';
alter table public.projects add column if not exists featured_artist_names text[] default '{}';
alter table public.projects add column if not exists description text;
alter table public.projects add column if not exists lyrics text;
alter table public.projects add column if not exists release_metadata jsonb not null default '{}'::jsonb;
alter table public.projects add column if not exists price numeric;
alter table public.projects add column if not exists license text;
alter table public.projects add column if not exists file_name text;
alter table public.projects add column if not exists file_url text;
alter table public.projects add column if not exists plays text default '0';

-- Existing accounts retain listening access; legacy creator profiles also receive artist access.
insert into public.user_roles (user_id, role)
select u.id, 'listener'
from auth.users u
on conflict (user_id, role) do nothing;

insert into public.user_roles (user_id, role)
select p.user_id, 'artist'
from public.profiles p
where p.role is not null
  and (
    lower(p.role) = 'artist'
    or lower(p.role) in (
      'beatmaker', 'producer', 'sound designer', 'project creator', 'kit maker',
      'skin designer', 'remixer', 'sample pack creator', 'loop creator',
      'tutorial creator', 'other'
    )
  )
on conflict (user_id, role) do nothing;

insert into public.user_roles (user_id, role)
select distinct p.user_id, 'artist'
from public.projects p
where p.user_id is not null
on conflict (user_id, role) do nothing;

insert into public.artist_profiles (user_id, artist_name, category, bio, image_url)
select p.user_id, coalesce(nullif(btrim(p.name), ''), p.handle), p.role, p.bio, p.img
from public.profiles p
join public.user_roles r on r.user_id = p.user_id and r.role = 'artist'
on conflict (user_id) do nothing;

update public.artist_profiles
set creator_type = category
where creator_type is null
  and category in (
    'Beatmaker', 'Producer', 'Sound Designer', 'Project Creator', 'Kit Maker',
    'Skin Designer', 'Remixer', 'Sample Pack Creator', 'Loop Creator',
    'Tutorial Creator', 'Other'
  );

update public.profiles p
set preferred_genres = array(
  select normalized.genre
  from (
    select case
      when g.value in ('Afro', 'House') then 'Afro House'
      when lower(g.value) = 'rnb' then 'R&B'
      else g.value
    end as genre, min(g.ordinality) as first_position
    from unnest(coalesce(p.preferred_genres, '{}')) with ordinality as g(value, ordinality)
    group by 1
  ) normalized
  order by normalized.first_position
);

update public.artist_profiles ap
set genres = array(
  select normalized.genre
  from (
    select case
      when g.value in ('Afro', 'House') then 'Afro House'
      when lower(g.value) = 'rnb' then 'R&B'
      else g.value
    end as genre, min(g.ordinality) as first_position
    from unnest(coalesce(ap.genres, '{}')) with ordinality as g(value, ordinality)
    group by 1
  ) normalized
  order by normalized.first_position
);

update public.projects p
set tags = array(
  select normalized.tag
  from (
    select case
      when g.value in ('Afro', 'House') then 'Afro House'
      when lower(g.value) = 'rnb' then 'R&B'
      else g.value
    end as tag, min(g.ordinality) as first_position
    from unnest(coalesce(p.tags, '{}')) with ordinality as g(value, ordinality)
    group by 1
  ) normalized
  order by normalized.first_position
)
where p.tags && array['Afro', 'House', 'Rnb', 'RNB'];

update public.profiles p
set role = case
  when p.is_admin then 'Admin'
  when exists (
    select 1 from public.user_roles r
    where r.user_id = p.user_id and r.role = 'artist'
  ) then 'Artist'
  else 'Listener'
end;

-- =========================================================
-- SOCIAL TABLES
-- =========================================================
create table if not exists public.follows (
  follower_id uuid not null references auth.users(id) on delete cascade,
  following_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (follower_id, following_id),
  check (follower_id <> following_id)
);

create table if not exists public.project_likes (
  user_id uuid not null references auth.users(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, project_id)
);

create table if not exists public.project_downloads (
  user_id uuid not null references auth.users(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, project_id)
);

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

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  read boolean default false,
  created_at timestamptz default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete cascade,
  kind text not null,
  project_id uuid references public.projects(id) on delete cascade,
  body text,
  read boolean default false,
  created_at timestamptz default now()
);

create index if not exists idx_follows_following on public.follows(following_id);
create index if not exists idx_likes_project on public.project_likes(project_id);
create index if not exists idx_downloads_project on public.project_downloads(project_id);
create index if not exists idx_views_project on public.project_views(project_id);
create index if not exists idx_plays_project on public.project_plays(project_id);
create index if not exists idx_plays_user_created on public.project_plays(user_id, created_at desc);
create index if not exists idx_shares_project on public.project_shares(project_id);
create index if not exists idx_comments_project on public.project_comments(project_id, created_at desc);
create index if not exists idx_comments_parent on public.project_comments(parent_id);
create index if not exists idx_messages_sender on public.messages(sender_id, created_at desc);
create index if not exists idx_messages_recipient on public.messages(recipient_id, created_at desc);
create index if not exists idx_notifications_user on public.notifications(user_id, created_at desc);
create index if not exists idx_projects_creator on public.projects(user_id, created_at desc);

-- =========================================================
-- ABUSE PREVENTION TABLES
-- =========================================================
create table if not exists public.username_changes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  old_handle text not null,
  new_handle text not null,
  reserved_until timestamptz default (now() + interval '30 days'),
  created_at timestamptz default now()
);

create table if not exists public.account_deletions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique not null,
  status text default 'pending' check (status in ('pending','cancelled','deleted')),
  reason text,
  requested_at timestamptz default now(),
  delete_after timestamptz not null
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null,
  reported_user_id uuid not null,
  project_id uuid,
  reason text not null,
  details text,
  status text default 'open' check (status in ('open','reviewing','action_taken','dismissed','duplicate')),
  created_at timestamptz default now()
);

-- actor_id/target_id deliberately have no FK so logs survive account deletion
create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid,
  action text not null,
  target_id uuid,
  details jsonb,
  ip_address inet,
  user_agent text,
  created_at timestamptz default now()
);

create index if not exists idx_username_changes_user on public.username_changes(user_id, created_at desc);
create index if not exists idx_username_changes_reserved on public.username_changes(lower(old_handle), reserved_until);
create index if not exists idx_reports_reporter on public.reports(reporter_id, created_at desc);
create index if not exists idx_reports_target on public.reports(reported_user_id, status);
create index if not exists idx_audit_actor on public.audit_logs(actor_id, action, created_at desc);
create index if not exists idx_account_deletions_status on public.account_deletions(status, delete_after);

-- =========================================================
-- RLS
-- =========================================================
alter table public.profiles enable row level security;
alter table public.projects enable row level security;
alter table public.username_changes enable row level security;
alter table public.account_deletions enable row level security;
alter table public.reports enable row level security;
alter table public.audit_logs enable row level security;
alter table public.follows enable row level security;
alter table public.project_likes enable row level security;
alter table public.project_downloads enable row level security;
alter table public.project_views enable row level security;
alter table public.project_plays enable row level security;
alter table public.project_shares enable row level security;
alter table public.project_comments enable row level security;
alter table public.messages enable row level security;
alter table public.notifications enable row level security;
alter table public.user_roles enable row level security;
alter table public.artist_profiles enable row level security;

create or replace function public.has_role(p_role text)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.user_roles r
    where r.user_id = auth.uid() and r.role = p_role
  );
$$;

revoke all on function public.has_role(text) from public;
grant execute on function public.has_role(text) to authenticated;

create or replace function public.assign_default_listener_role()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_roles (user_id, role)
  values (new.id, 'listener')
  on conflict (user_id, role) do nothing;
  return new;
end;
$$;

drop trigger if exists auth_user_default_listener_role on auth.users;
create trigger auth_user_default_listener_role
  after insert on auth.users
  for each row execute function public.assign_default_listener_role();

revoke all on function public.assign_default_listener_role() from public, anon, authenticated;

drop function if exists public.become_artist(text, text[], text, text, jsonb);
drop function if exists public.become_artist(text, text[], text, text, jsonb, text);

create function public.become_artist(
  p_artist_name text,
  p_genres text[] default '{}',
  p_bio text default null,
  p_image_url text default null,
  p_links jsonb default '{}'::jsonb,
  p_creator_type text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  allowed_genres text[] := array[
    'Hip-Hop', 'Gqom', 'Amapiano', 'Afro House', 'Maskandi', 'Gwijo',
    '3-Step', 'Lekompo', 'Kwaito', 'Bacardi House', 'Bolo House',
    'Gospel', 'Boeremusiek', 'Pop', 'R&B', 'Soul'
  ];
  allowed_creator_types text[] := array[
    'Beatmaker', 'Producer', 'Sound Designer', 'Project Creator', 'Kit Maker',
    'Skin Designer', 'Remixer', 'Sample Pack Creator', 'Loop Creator',
    'Tutorial Creator', 'Other'
  ];
  clean_name text := nullif(btrim(p_artist_name), '');
  clean_genres text[] := coalesce(p_genres, '{}');
  clean_creator_type text := nullif(btrim(p_creator_type), '');
begin
  if uid is null then
    raise exception 'Sign in to become a creator' using errcode = '42501';
  end if;
  if clean_name is null or char_length(clean_name) > 60 then
    raise exception 'Creator name must be between 1 and 60 characters' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles p where p.user_id = uid) then
    raise exception 'Complete your profile before becoming a creator' using errcode = '42501';
  end if;
  if coalesce(array_length(clean_genres, 1), 0) > 16
     or exists (
       select 1 from unnest(clean_genres) as genre(value)
       where value is null or value <> all (allowed_genres)
     ) then
    raise exception 'Choose genres from the supported genre list' using errcode = '22023';
  end if;
  if clean_creator_type is not null and clean_creator_type <> all (allowed_creator_types) then
    raise exception 'Choose a supported creator type' using errcode = '22023';
  end if;
  if p_bio is not null and char_length(p_bio) > 160 then
    raise exception 'Creator bio must be 160 characters or fewer' using errcode = '22023';
  end if;
  if p_links is null or jsonb_typeof(p_links) <> 'object' then
    raise exception 'Artist links must be a JSON object' using errcode = '22023';
  end if;
  if pg_column_size(p_links) > 4000 then
    raise exception 'Artist links are too large' using errcode = '22023';
  end if;

  insert into public.user_roles (user_id, role)
  values (uid, 'listener'), (uid, 'artist')
  on conflict (user_id, role) do nothing;

  insert into public.artist_profiles (
    user_id, artist_name, creator_type, bio, genres, image_url, links, verification_status
  )
  values (
    uid, clean_name, clean_creator_type, nullif(btrim(p_bio), ''), clean_genres,
    nullif(btrim(p_image_url), ''), p_links, 'unverified'
  )
  on conflict (user_id) do update set
    artist_name = excluded.artist_name,
    creator_type = coalesce(excluded.creator_type, artist_profiles.creator_type),
    bio = excluded.bio,
    genres = excluded.genres,
    image_url = excluded.image_url,
    links = excluded.links;

  update public.profiles
  set role = 'Artist', preferred_genres = clean_genres
  where user_id = uid;
end;
$$;

revoke all on function public.become_artist(text, text[], text, text, jsonb, text) from public;
grant execute on function public.become_artist(text, text[], text, text, jsonb, text) to authenticated;

revoke all on public.user_roles, public.artist_profiles from anon, authenticated;
grant select on public.user_roles, public.artist_profiles to anon, authenticated;

-- admin helper (security definer avoids RLS recursion)
create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select coalesce((select is_admin from profiles where user_id = auth.uid()), false);
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;

drop policy if exists "user_roles_read_own" on public.user_roles;
create policy "user_roles_read_own"
  on public.user_roles for select
  using (auth.uid() = user_id or public.is_admin());

drop policy if exists "artist_profiles_public_read" on public.artist_profiles;
create policy "artist_profiles_public_read"
  on public.artist_profiles for select
  using (
    public.is_admin()
    or user_id = auth.uid()
    or exists (
      select 1 from public.profiles p
      where p.user_id = artist_profiles.user_id and p.public_profile
    )
  );

-- profiles: hide accounts pending deletion from everyone except self and admin
drop policy if exists "profiles_public_read" on public.profiles;
create policy "profiles_public_read"
  on public.profiles for select
  using (
    user_id = auth.uid()
    or public.is_admin()
    or (
      public_profile
      and not exists (
        select 1 from public.account_deletions d
        where d.user_id = profiles.user_id
          and d.status = 'pending'
          and d.delete_after > now()
      )
    )
  );

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles for insert
  with check (auth.uid() = user_id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "profiles_admin_update" on public.profiles;
create policy "profiles_admin_update"
  on public.profiles for update
  using (public.is_admin())
  with check (public.is_admin());

-- projects
drop policy if exists "projects_public_read" on public.projects;
create policy "projects_public_read"
  on public.projects for select
  using (true);

drop policy if exists "projects_insert_own" on public.projects;
create policy "projects_insert_own"
  on public.projects for insert
  with check (auth.uid() = user_id and public.has_role('artist'));

drop policy if exists "projects_update_own" on public.projects;
create policy "projects_update_own"
  on public.projects for update
  using (auth.uid() = user_id and public.has_role('artist'))
  with check (auth.uid() = user_id and public.has_role('artist'));

drop policy if exists "projects_delete_own" on public.projects;
create policy "projects_delete_own"
  on public.projects for delete
  using (auth.uid() = user_id and public.has_role('artist'));

-- follows: signed-in users can see the graph; you can only edit your own edges
drop policy if exists "follows_read" on public.follows;
create policy "follows_read"
  on public.follows for select
  using (
    auth.uid() is not null
    and (
      auth.uid() = follower_id
      or auth.uid() = following_id
      or (
        exists (
          select 1 from public.profiles follower
          where follower.user_id = follows.follower_id
            and follower.public_profile
        )
        and exists (
          select 1 from public.profiles followed
          where followed.user_id = follows.following_id
            and followed.public_profile
        )
      )
    )
  );

drop policy if exists "follows_insert_own" on public.follows;
create policy "follows_insert_own"
  on public.follows for insert
  with check (auth.uid() = follower_id);

drop policy if exists "follows_delete_own" on public.follows;
create policy "follows_delete_own"
  on public.follows for delete
  using (auth.uid() = follower_id);

-- likes / downloads: public counts, own rows
drop policy if exists "likes_read" on public.project_likes;
create policy "likes_read"
  on public.project_likes for select
  using (
    exists (
      select 1 from public.projects p
      where p.id = project_likes.project_id
    )
  );

drop policy if exists "likes_insert_own" on public.project_likes;
create policy "likes_insert_own"
  on public.project_likes for insert
  with check (auth.uid() = user_id);

drop policy if exists "likes_delete_own" on public.project_likes;
create policy "likes_delete_own"
  on public.project_likes for delete
  using (auth.uid() = user_id);

drop policy if exists "downloads_read_own" on public.project_downloads;
create policy "downloads_read_own"
  on public.project_downloads for select
  using (auth.uid() = user_id);

drop policy if exists "downloads_insert_own" on public.project_downloads;
create policy "downloads_insert_own"
  on public.project_downloads for insert
  with check (auth.uid() = user_id);

drop policy if exists "downloads_delete_own" on public.project_downloads;
create policy "downloads_delete_own"
  on public.project_downloads for delete
  using (auth.uid() = user_id);

-- views / shares: private ledger for the counter RPCs
revoke all on public.project_views from anon, authenticated;
revoke all on public.project_plays from anon, authenticated;
revoke all on public.project_shares from anon, authenticated;

-- comments: everyone reads, signed-in users write and remove their own
drop policy if exists "project_comments_public_read" on public.project_comments;
create policy "project_comments_public_read"
  on public.project_comments for select
  using (
    exists (
      select 1 from public.projects p
      where p.id = project_comments.project_id
    )
  );

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

-- messages: only sender and recipient
drop policy if exists "messages_read_own" on public.messages;
create policy "messages_read_own"
  on public.messages for select
  using (auth.uid() = sender_id or auth.uid() = recipient_id);

drop policy if exists "messages_insert_own" on public.messages;
create policy "messages_insert_own"
  on public.messages for insert
  with check (auth.uid() = sender_id);

drop policy if exists "messages_mark_read" on public.messages;
create policy "messages_mark_read"
  on public.messages for update
  using (auth.uid() = recipient_id)
  with check (auth.uid() = recipient_id);

-- notifications: recipient reads/marks; actor creates
drop policy if exists "notifications_read_own" on public.notifications;
create policy "notifications_read_own"
  on public.notifications for select
  using (auth.uid() = user_id);

drop policy if exists "notifications_insert_actor" on public.notifications;
create policy "notifications_insert_actor"
  on public.notifications for insert
  with check (auth.uid() = actor_id);

drop policy if exists "notifications_mark_read" on public.notifications;
create policy "notifications_mark_read"
  on public.notifications for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- username_changes: own rows readable; writes go through RPC only
drop policy if exists "username_changes_read_own" on public.username_changes;
create policy "username_changes_read_own"
  on public.username_changes for select
  using (auth.uid() = user_id);

-- account_deletions: own rows only (writes via RPC)
drop policy if exists "account_deletions_read_own" on public.account_deletions;
create policy "account_deletions_read_own"
  on public.account_deletions for select
  using (auth.uid() = user_id or public.is_admin());

-- reports: reporter sees own; admin sees all; inserts via RPC only
drop policy if exists "reports_read_own" on public.reports;
create policy "reports_read_own"
  on public.reports for select
  using (auth.uid() = reporter_id or public.is_admin());

drop policy if exists "reports_admin_update" on public.reports;
create policy "reports_admin_update"
  on public.reports for update
  using (public.is_admin())
  with check (public.is_admin());

-- audit_logs: own actor rows + admin
drop policy if exists "audit_read_own" on public.audit_logs;
create policy "audit_read_own"
  on public.audit_logs for select
  using (auth.uid() = actor_id or public.is_admin());

-- =========================================================
-- RPC · USERNAME CHANGE  (1 free, then 1 per 30 days, max 3/year)
-- =========================================================
create or replace function public.change_username(new_handle text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  cur_handle text;
  last_change timestamptz;
  year_count int;
begin
  if uid is null then
    return jsonb_build_object('error', 'Not signed in');
  end if;

  new_handle := lower(trim(coalesce(new_handle, '')));
  if new_handle !~ '^[a-z0-9._]{3,24}$' then
    return jsonb_build_object('error', '3-24 characters. Letters, numbers, dots and underscores only.');
  end if;

  select handle into cur_handle from profiles where user_id = uid;
  if cur_handle is null then
    return jsonb_build_object('error', 'No profile found');
  end if;
  if lower(cur_handle) = new_handle then
    return jsonb_build_object('error', 'That is already your username');
  end if;

  if exists (select 1 from profiles where lower(handle) = new_handle) then
    return jsonb_build_object('error', 'That username is already taken');
  end if;

  if exists (
    select 1 from username_changes
    where lower(old_handle) = new_handle and reserved_until > now()
  ) then
    return jsonb_build_object('error', 'That username is reserved for 30 days after a previous owner changed it');
  end if;

  select max(created_at) into last_change
  from username_changes where user_id = uid;

  if last_change is not null and last_change > now() - interval '30 days' then
    return jsonb_build_object(
      'error',
      'You can change your username once every 30 days. Your previous username will be reserved for 30 days to prevent impersonation.'
    );
  end if;

  select count(*) into year_count
  from username_changes
  where user_id = uid and created_at > now() - interval '1 year';
  if year_count >= 3 then
    return jsonb_build_object('error', 'Maximum 3 username changes per year');
  end if;

  update profiles set handle = new_handle where user_id = uid;

  insert into username_changes (user_id, old_handle, new_handle, reserved_until)
  values (uid, cur_handle, new_handle, now() + interval '30 days');

  insert into audit_logs (actor_id, action, target_id, details)
  values (uid, 'username_changed', uid,
          jsonb_build_object('old_handle', cur_handle, 'new_handle', new_handle));

  return jsonb_build_object('ok', true, 'handle', new_handle);
end;
$$;

-- =========================================================
-- RPC · DISPLAY NAME  (1/day, 3/month, 2-40 chars)
-- =========================================================
create or replace function public.change_display_name(new_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  day_count int;
  month_count int;
  clean_name text;
begin
  if uid is null then
    return jsonb_build_object('error', 'Not signed in');
  end if;

  clean_name := trim(coalesce(new_name, ''));
  if length(clean_name) < 2 or length(clean_name) > 40 then
    return jsonb_build_object('error', 'Display name must be 2-40 characters');
  end if;

  select count(*) into day_count
  from audit_logs
  where actor_id = uid and action = 'display_name_changed'
    and created_at > now() - interval '1 day';
  if day_count >= 1 then
    return jsonb_build_object('error', 'You can change your display name once per day');
  end if;

  select count(*) into month_count
  from audit_logs
  where actor_id = uid and action = 'display_name_changed'
    and created_at > now() - interval '1 month';
  if month_count >= 3 then
    return jsonb_build_object('error', 'Maximum 3 display-name changes per month');
  end if;

  update profiles set name = clean_name where user_id = uid;

  insert into audit_logs (actor_id, action, target_id, details)
  values (uid, 'display_name_changed', uid, jsonb_build_object('name', clean_name));

  return jsonb_build_object('ok', true, 'name', clean_name);
end;
$$;

-- =========================================================
-- RPC · BASIC PROFILE DETAILS
-- =========================================================
create or replace function public.update_basic_profile(
  p_name text,
  p_hometown text default null,
  p_website_url text default null,
  p_bio text default null,
  p_genre text default null,
  p_links jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  clean_name text := nullif(btrim(coalesce(p_name, '')), '');
  clean_hometown text := nullif(btrim(coalesce(p_hometown, '')), '');
  clean_website text := nullif(btrim(coalesce(p_website_url, '')), '');
  clean_bio text := nullif(btrim(coalesce(p_bio, '')), '');
  clean_genre text := nullif(btrim(coalesce(p_genre, '')), '');
  clean_links jsonb := coalesce(p_links, '{}'::jsonb);
  current_name text;
  day_count int;
  month_count int;
  link_entry record;
begin
  if uid is null then
    return jsonb_build_object('error', 'Not signed in');
  end if;
  if clean_name is null or char_length(clean_name) < 2 or char_length(clean_name) > 40 then
    return jsonb_build_object('error', 'Name must be between 2 and 40 characters');
  end if;
  if char_length(coalesce(clean_hometown, '')) > 120 then
    return jsonb_build_object('error', 'Hometown must be 120 characters or fewer');
  end if;
  if char_length(coalesce(clean_website, '')) > 300 then
    return jsonb_build_object('error', 'Website URL must be 300 characters or fewer');
  end if;
  if char_length(coalesce(clean_bio, '')) > 800 then
    return jsonb_build_object('error', 'Biography must be 800 characters or fewer');
  end if;
  if clean_genre is not null and clean_genre <> all(array[
    'Hip-Hop', 'Gqom', 'Amapiano', 'Afro House', 'Maskandi', 'Gwijo',
    '3-Step', 'Lekompo', 'Kwaito', 'Bacardi House', 'Bolo House',
    'Gospel', 'Boeremusiek', 'Pop', 'R&B', 'Soul'
  ]) then
    return jsonb_build_object('error', 'Choose a supported genre');
  end if;
  if jsonb_typeof(clean_links) is distinct from 'object' then
    return jsonb_build_object('error', 'Social links must be an object');
  end if;
  for link_entry in select key, value from jsonb_each_text(clean_links) loop
    if link_entry.key not in ('twitter', 'instagram', 'facebook', 'youtube', 'tiktok', 'linktree')
       or char_length(coalesce(link_entry.value, '')) > 300
       or (link_entry.key <> 'instagram' and link_entry.value <> ''
           and link_entry.value !~* '^https?://') then
      return jsonb_build_object('error', 'A social profile link is invalid or too long');
    end if;
  end loop;
  if clean_website is not null and clean_website !~* '^https?://' then
    return jsonb_build_object('error', 'Website URL must start with http:// or https://');
  end if;

  select name into current_name
  from public.profiles
  where user_id = uid
  for update;
  if not found then
    return jsonb_build_object('error', 'Profile not found');
  end if;

  if current_name is distinct from clean_name then
    select count(*) into day_count
    from public.audit_logs
    where actor_id = uid and action = 'display_name_changed'
      and created_at > now() - interval '1 day';
    if day_count >= 1 then
      return jsonb_build_object('error', 'You can change your display name once per day');
    end if;
    select count(*) into month_count
    from public.audit_logs
    where actor_id = uid and action = 'display_name_changed'
      and created_at > now() - interval '1 month';
    if month_count >= 3 then
      return jsonb_build_object('error', 'Maximum 3 display-name changes per month');
    end if;
  end if;

  update public.profiles
  set name = clean_name,
      hometown = clean_hometown,
      website_url = clean_website,
      bio = clean_bio,
      preferred_genres = case when clean_genre is null then '{}' else array[clean_genre] end,
      profile_links = clean_links
  where user_id = uid;

  if current_name is distinct from clean_name then
    insert into public.audit_logs (actor_id, action, target_id, details)
    values (uid, 'display_name_changed', uid, jsonb_build_object('name', clean_name));
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.update_basic_profile(text, text, text, text, text, jsonb) from public, anon;
grant execute on function public.update_basic_profile(text, text, text, text, text, jsonb) to authenticated;

-- =========================================================
-- RPC · ACCOUNT DELETION  (soft delete, 14-day grace, 1 per 30 days)
-- =========================================================
create or replace function public.request_account_deletion(p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    return jsonb_build_object('error', 'Not signed in');
  end if;

  if exists (
    select 1 from account_deletions
    where user_id = uid and status = 'pending' and delete_after > now()
  ) then
    return jsonb_build_object('error', 'Deletion already pending');
  end if;

  if exists (
    select 1 from account_deletions
    where user_id = uid and requested_at > now() - interval '30 days'
  ) then
    return jsonb_build_object('error', 'You can request account deletion once every 30 days');
  end if;

  insert into account_deletions (user_id, status, reason, delete_after)
  values (uid, 'pending', nullif(trim(coalesce(p_reason, '')), ''), now() + interval '14 days')
  on conflict (user_id) do update
    set status = 'pending',
        reason = excluded.reason,
        requested_at = now(),
        delete_after = excluded.delete_after;

  insert into audit_logs (actor_id, action, target_id, details)
  values (uid, 'account_deletion_requested', uid,
          jsonb_build_object('reason', nullif(trim(coalesce(p_reason, '')), '')));

  return jsonb_build_object('ok', true, 'delete_after', (now() + interval '14 days')::text);
end;
$$;

create or replace function public.cancel_account_deletion()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    return jsonb_build_object('error', 'Not signed in');
  end if;

  update account_deletions
  set status = 'cancelled'
  where user_id = uid and status = 'pending' and delete_after > now();

  if not found then
    return jsonb_build_object('error', 'No pending deletion found');
  end if;

  insert into audit_logs (actor_id, action, target_id)
  values (uid, 'account_deletion_cancelled', uid);

  return jsonb_build_object('ok', true);
end;
$$;

-- purge after grace period (run manually or via pg_cron: select public.purge_expired_deletions();
-- deletes auth user → cascades profile/uploads; audit_logs kept)
create or replace function public.purge_expired_deletions()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  rec record;
  n integer := 0;
begin
  for rec in
    select user_id, reason from account_deletions
    where status = 'pending' and delete_after <= now()
  loop
    insert into audit_logs (actor_id, action, target_id, details)
    values (rec.user_id, 'account_deleted', rec.user_id,
            jsonb_build_object('reason', rec.reason));

    delete from auth.users where id = rec.user_id;
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- =========================================================
-- RPC · ADMIN — resolve a report
-- =========================================================
create or replace function public.resolve_report(p_report_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null or not exists (select 1 from profiles where user_id = uid and is_admin) then
    return jsonb_build_object('error', 'Admin only');
  end if;
  if p_status not in ('open','reviewing','action_taken','dismissed','duplicate') then
    return jsonb_build_object('error', 'Invalid status');
  end if;

  update reports set status = p_status where id = p_report_id;

  insert into audit_logs (actor_id, action, target_id, details)
  values (uid, 'report_resolved', p_report_id, jsonb_build_object('status', p_status));

  return jsonb_build_object('ok', true);
end;
$$;

-- =========================================================
-- RPC · ADMIN — suspend / unsuspend
-- =========================================================
create or replace function public.set_user_suspended(p_user_id uuid, p_suspended boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null or not exists (select 1 from profiles where user_id = uid and is_admin) then
    return jsonb_build_object('error', 'Admin only');
  end if;

  update profiles set suspended = p_suspended where user_id = p_user_id;

  insert into audit_logs (actor_id, action, target_id, details)
  values (uid, case when p_suspended then 'user_suspended' else 'user_unsuspended' end,
          p_user_id, jsonb_build_object('suspended', p_suspended));

  return jsonb_build_object('ok', true);
end;
$$;

-- =========================================================
-- RPC · FOLLOW / UNFOLLOW  (keeps profiles.followers accurate)
-- =========================================================
create or replace function public.toggle_follow(p_target uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  is_following boolean;
  follower_count int;
  following_count int;
begin
  if uid is null then
    return jsonb_build_object('error', 'Not signed in');
  end if;
  if p_target is null or p_target = uid then
    return jsonb_build_object('error', 'Invalid follow target');
  end if;

  if exists (select 1 from follows where follower_id = uid and following_id = p_target) then
    delete from follows where follower_id = uid and following_id = p_target;
    delete from notifications
      where user_id = p_target and actor_id = uid and kind = 'follow';
    is_following := false;
  else
    insert into follows (follower_id, following_id) values (uid, p_target)
      on conflict do nothing;
    if coalesce((
      select new_follower_notifications
      from profiles
      where user_id = p_target
    ), true) then
      insert into notifications (user_id, actor_id, kind)
        values (p_target, uid, 'follow');
    end if;
    is_following := true;
  end if;

  select count(*) into follower_count from follows where following_id = p_target;
  update profiles set followers = follower_count::text where user_id = p_target;

  select count(*) into following_count from follows where follower_id = uid;
  update profiles set following = following_count::text where user_id = uid;

  return jsonb_build_object('ok', true, 'following', is_following, 'followers', follower_count);
end;
$$;

revoke all on function public.toggle_follow(uuid) from public;
grant execute on function public.toggle_follow(uuid) to authenticated;

-- =========================================================
-- RPC · LIKE / UNLIKE  (keeps projects.likes accurate)
-- =========================================================
create or replace function public.toggle_project_like(p_project uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  owner uuid;
  liked boolean;
  like_count int;
begin
  if uid is null then
    return jsonb_build_object('error', 'Not signed in');
  end if;

  select user_id into owner from projects where id = p_project;
  if owner is null then
    return jsonb_build_object('error', 'Project not found');
  end if;

  if exists (select 1 from project_likes where user_id = uid and project_id = p_project) then
    delete from project_likes where user_id = uid and project_id = p_project;
    liked := false;
  else
    insert into project_likes (user_id, project_id) values (uid, p_project)
      on conflict do nothing;
    liked := true;
    if owner <> uid then
      insert into notifications (user_id, actor_id, kind, project_id)
        values (owner, uid, 'like', p_project);
    end if;
  end if;

  select count(*) into like_count from project_likes where project_id = p_project;
  update projects set likes = like_count::text where id = p_project;

  return jsonb_build_object('ok', true, 'liked', liked, 'likes', like_count);
end;
$$;

revoke all on function public.toggle_project_like(uuid) from public;
grant execute on function public.toggle_project_like(uuid) to authenticated;

-- =========================================================
-- RPC · RECORD DOWNLOAD  (adds to library once, counts once)
-- =========================================================
create or replace function public.record_project_download(p_project uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  owner uuid;
  already boolean;
  dl_count int;
begin
  if uid is null then
    return jsonb_build_object('error', 'Not signed in');
  end if;

  select user_id into owner from projects where id = p_project;
  if owner is null then
    return jsonb_build_object('error', 'Project not found');
  end if;

  already := exists (
    select 1 from project_downloads where user_id = uid and project_id = p_project
  );

  if not already then
    insert into project_downloads (user_id, project_id) values (uid, p_project)
      on conflict do nothing;
    if owner <> uid then
      insert into notifications (user_id, actor_id, kind, project_id)
        values (owner, uid, 'download', p_project);
    end if;
  end if;

  select count(*) into dl_count from project_downloads where project_id = p_project;
  update projects set downloads = dl_count::text where id = p_project;

  return jsonb_build_object('ok', true, 'already', already, 'downloads', dl_count);
end;
$$;

revoke all on function public.record_project_download(uuid) from public;
grant execute on function public.record_project_download(uuid) to authenticated;

-- =========================================================
-- RPC · VIEWS  (counts each signed-in visitor once per project)
-- =========================================================
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

-- =========================================================
-- RPC · SHARES  (counts each signed-in sharer once per project)
-- =========================================================
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

-- =========================================================
-- RPC · PLAYS  (one per listener/project, capped at 100 distinct plays per day)
-- =========================================================
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

drop function if exists public.creator_play_earnings();


-- =========================================================
-- MESSAGE NOTIFICATIONS
-- =========================================================
create or replace function public.notify_on_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce((
    select message_notifications
    from profiles
    where user_id = new.recipient_id
  ), true) then
    insert into notifications (user_id, actor_id, kind, body)
    values (new.recipient_id, new.sender_id, 'message', left(new.body, 120));
  end if;
  return new;
end;
$$;

drop trigger if exists messages_notify on public.messages;
create trigger messages_notify
  after insert on public.messages
  for each row execute function public.notify_on_message();

-- =========================================================
-- RPC · OFFICIAL @app AUTO-REPLIES
-- =========================================================
create or replace function public.persona_reply(
  p_user uuid,
  p_body text,
  p_persona text default 'app',
  p_transfer boolean default false,
  p_context text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  persona_id uuid;
  team_id uuid;
  member_handle text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if p_user is distinct from auth.uid() then
    raise exception 'recipient must be the caller';
  end if;

  if p_persona is distinct from 'app' then
    raise exception 'only @app can send automated replies';
  end if;

  if coalesce(btrim(p_body), '') = '' then
    raise exception 'empty reply';
  end if;

  select user_id into persona_id from public.profiles where handle = p_persona limit 1;
  if persona_id is null then
    raise exception '@% account is missing', p_persona;
  end if;

  if persona_id = p_user then
    raise exception 'a persona cannot message itself';
  end if;

  insert into public.messages (sender_id, recipient_id, body)
  values (persona_id, p_user, left(btrim(p_body), 2000));

  if coalesce(p_transfer, false) and p_persona = 'app' then
    select handle into member_handle from public.profiles where user_id = p_user;
    select user_id into team_id from public.profiles where handle = 'ntuthuko' limit 1;
    if team_id is not null then
      insert into public.notifications (user_id, actor_id, kind, body)
      values (
        team_id,
        p_user,
        'message',
        'Support request from @' || coalesce(member_handle, 'member') || ': ' ||
          left(coalesce(p_context, p_body), 180)
      );
    end if;
  end if;

  return jsonb_build_object('ok', true, 'persona', p_persona, 'transfer', coalesce(p_transfer, false) and p_persona = 'app');
end;
$$;

revoke all on function public.persona_reply(uuid, text, text, boolean, text) from public;
grant execute on function public.persona_reply(uuid, text, text, boolean, text) to authenticated;

-- =========================================================
-- COMMENT NOTIFICATIONS
-- =========================================================
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

-- =========================================================
-- RPC · OFFICIAL @app COMMENT on a member's new upload
-- =========================================================
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

-- =========================================================
-- STORAGE · uploads bucket (project/preset/sample files + covers)
-- =========================================================
insert into storage.buckets (id, name, public)
values ('uploads', 'uploads', true)
on conflict (id) do update set public = true;

drop policy if exists "uploads_public_read" on storage.objects;
create policy "uploads_public_read"
  on storage.objects for select
  using (bucket_id = 'uploads');

drop policy if exists "uploads_insert_own" on storage.objects;
create policy "uploads_insert_own"
  on storage.objects for insert
  with check (
    bucket_id = 'uploads'
    and auth.role() = 'authenticated'
    and public.has_role('artist')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "uploads_update_own" on storage.objects;
create policy "uploads_update_own"
  on storage.objects for update
  using (bucket_id = 'uploads' and owner = auth.uid() and public.has_role('artist'))
  with check (
    bucket_id = 'uploads'
    and owner = auth.uid()
    and public.has_role('artist')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "uploads_delete_own" on storage.objects;
create policy "uploads_delete_own"
  on storage.objects for delete
  using (
    bucket_id = 'uploads'
    and owner = auth.uid()
    and public.has_role('artist')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- =========================================================
-- BACKFILL PUBLIC COUNTS (safe to re-run)
-- =========================================================
update public.profiles p
set followers = coalesce((select count(*) from public.follows f where f.following_id = p.user_id), 0)::text,
    following = coalesce((select count(*) from public.follows f where f.follower_id = p.user_id), 0)::text;


-- =========================================================
-- MODERATION + VERIFICATION (mirrored from moderation.sql)
-- =========================================================
-- Parrallery moderation + verification — run in SQL Editor → Run (safe to re-run)
-- Adds: verification tiers, quieter message notifications, deletable messages
-- and notifications, content states (active/frozen/banned), AI report triage,
-- moderation audit trail and account bans.

-- =========================================================
-- PROFILE: VERIFICATION TIERS + ACCOUNT STATE
-- =========================================================
alter table public.profiles add column if not exists verification_tier text;
alter table public.profiles add column if not exists state text default 'active';
alter table public.profiles add column if not exists banned_reason text;
alter table public.profiles add column if not exists banned_until timestamptz;
alter table public.profiles add column if not exists banned_at timestamptz;

-- keep the legacy verified flag true for every tier
update public.profiles
   set verification_tier = 'basic'
 where verified = true and verification_tier is null;

-- backfill by follower count (trusted wins over basic)
update public.profiles p
   set verification_tier = 'basic', verified = true
 where p.verification_tier is null
   and (select count(*) from public.follows f where f.following_id = p.user_id) >= 25;

update public.profiles p
   set verification_tier = 'trusted', verified = true
 where p.verification_tier = 'basic'
   and (select count(*) from public.follows f where f.following_id = p.user_id) >= 100;

create or replace function public.sync_artist_profile_verification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.profiles p
    where p.user_id = new.user_id
      and (p.verified is true or p.verification_tier in ('basic', 'trusted'))
  ) then
    new.verification_status := 'verified';
  else
    new.verification_status := 'unverified';
  end if;
  return new;
end;
$$;

create or replace function public.sync_artist_verification_from_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.artist_profiles
     set verification_status = case
       when new.verified is true or new.verification_tier in ('basic', 'trusted') then 'verified'
       else 'unverified'
     end
   where user_id = new.user_id;
  return new;
end;
$$;

revoke all on function public.sync_artist_profile_verification() from public, anon, authenticated;
revoke all on function public.sync_artist_verification_from_profile() from public, anon, authenticated;

drop trigger if exists artist_profiles_sync_verification on public.artist_profiles;
create trigger artist_profiles_sync_verification
  before insert or update on public.artist_profiles
  for each row execute function public.sync_artist_profile_verification();

drop trigger if exists profiles_sync_artist_verification on public.profiles;
create trigger profiles_sync_artist_verification
  after update of verified, verification_tier on public.profiles
  for each row execute function public.sync_artist_verification_from_profile();

update public.artist_profiles ap
   set verification_status = case
     when p.verified is true or p.verification_tier in ('basic', 'trusted') then 'verified'
     else 'unverified'
   end
  from public.profiles p
 where p.user_id = ap.user_id;

-- =========================================================
-- CONTENT STATE (projects + presets + samples share this table)
-- =========================================================
alter table public.projects add column if not exists state text default 'active';
alter table public.projects add column if not exists frozen_until timestamptz;
alter table public.projects add column if not exists moderation_reason text;
alter table public.projects add column if not exists banned_at timestamptz;

create index if not exists idx_projects_state on public.projects(state, created_at desc);

-- =========================================================
-- REPORTS + MODERATION AUDIT
-- =========================================================
alter table public.reports add column if not exists target_type text default 'account';
alter table public.reports add column if not exists target_id uuid;
alter table public.reports add column if not exists ai_confidence numeric;
alter table public.reports add column if not exists ai_severity text;
alter table public.reports add column if not exists reporter_reliability numeric;

create table if not exists public.moderation_actions (
  id uuid primary key default gen_random_uuid(),
  target_type text not null,
  target_id uuid not null,
  action text not null,
  reason text,
  performed_by uuid,
  ai_evidence jsonb,
  created_at timestamptz default now(),
  reverted_at timestamptz
);

create index if not exists idx_moderation_target on public.moderation_actions(target_type, target_id, created_at desc);

alter table public.moderation_actions enable row level security;

drop policy if exists "moderation_read" on public.moderation_actions;
create policy "moderation_read"
  on public.moderation_actions for select
  using (
    public.is_admin()
    or performed_by = auth.uid()
    or (target_type = 'account' and target_id = auth.uid())
  );

revoke all on public.moderation_actions from anon, authenticated;
grant select on public.moderation_actions to authenticated;

-- =========================================================
-- RLS · CONTENT VISIBILITY + DELETES
-- =========================================================
drop policy if exists "projects_public_read" on public.projects;
create policy "projects_public_read"
  on public.projects for select
  using (
    user_id = auth.uid()
    or public.is_admin()
    or (
      exists (
        select 1
        from public.profiles p
        where p.user_id = projects.user_id
          and p.public_profile
      )
      and (
        state is null
        or state = 'active'
        or (state = 'frozen' and frozen_until is not null and frozen_until <= now())
      )
    )
  );

drop policy if exists "projects_insert_own" on public.projects;
create policy "projects_insert_own"
  on public.projects for insert
  with check (
    auth.uid() = user_id
    and public.has_role('artist')
    and not exists (
      select 1 from public.profiles p
      where p.user_id = auth.uid()
        and p.state = 'banned'
        and (p.banned_until is null or p.banned_until > now())
    )
  );

-- messages + notifications: owners/participants can delete
drop policy if exists "projects_admin_delete" on public.projects;
create policy "projects_admin_delete"
  on public.projects for delete
  using (public.is_admin());

drop policy if exists "messages_insert_own" on public.messages;
create or replace function public.can_send_message(p_recipient uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select auth.uid() is not null
    and auth.uid() <> p_recipient
    and exists (
      select 1
      from public.profiles p
      where p.user_id = p_recipient
        and (
          p.handle in ('app', 'caustic')
          or
          p.allow_messages
          or exists (
            select 1
            from public.follows f
            where f.follower_id = p_recipient
              and f.following_id = auth.uid()
          )
        )
    );
$$;

revoke all on function public.can_send_message(uuid) from public;
grant execute on function public.can_send_message(uuid) to authenticated;

create policy "messages_insert_own"
  on public.messages for insert
  with check (
    auth.uid() = sender_id
    and public.can_send_message(recipient_id)
    and not exists (
      select 1 from public.profiles p
      where p.user_id = auth.uid()
        and p.state = 'banned'
        and (p.banned_until is null or p.banned_until > now())
    )
  );

drop policy if exists "messages_delete_participant" on public.messages;
create policy "messages_delete_participant"
  on public.messages for delete
  using (auth.uid() = sender_id or auth.uid() = recipient_id);

drop policy if exists "notifications_delete_own" on public.notifications;
create policy "notifications_delete_own"
  on public.notifications for delete
  using (auth.uid() = user_id);

-- comments: banned accounts cannot post
drop policy if exists "project_comments_own_insert" on public.project_comments;
create policy "project_comments_own_insert"
  on public.project_comments for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and not exists (
      select 1 from public.profiles p
      where p.user_id = auth.uid()
        and p.state = 'banned'
        and (p.banned_until is null or p.banned_until > now())
    )
  );

grant select, insert, update, delete on public.messages to authenticated;
grant select, insert, update, delete on public.notifications to authenticated;

-- =========================================================
-- TRIGGER · PROTECT PRIVILEGED PROFILE COLUMNS
-- Members can edit their profile, but not badge/admin/ban fields.
-- =========================================================
create or replace function public.guard_profile_privileges()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(current_setting('parrallery.privileged', true), '') = 'on' then
    return new;
  end if;

  if auth.uid() is not null and not public.is_admin() then
    if tg_op = 'INSERT' then
      new.verified := false;
      new.verification_tier := null;
      new.is_admin := false;
      new.state := 'active';
      new.banned_until := null;
      new.banned_reason := null;
      new.banned_at := null;
      new.suspended := false;
    else
      new.verified := old.verified;
      new.verification_tier := old.verification_tier;
      new.is_admin := old.is_admin;
      new.state := old.state;
      new.banned_until := old.banned_until;
      new.banned_reason := old.banned_reason;
      new.banned_at := old.banned_at;
      new.suspended := old.suspended;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_guard_privileges on public.profiles;
create trigger profiles_guard_privileges
  before insert or update on public.profiles
  for each row execute function public.guard_profile_privileges();

create or replace function public.guard_project_state()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(current_setting('parrallery.privileged', true), '') = 'on' or public.is_admin() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.state := 'active';
    new.frozen_until := null;
    new.moderation_reason := null;
    new.banned_at := null;
  else
    new.state := old.state;
    new.frozen_until := old.frozen_until;
    new.moderation_reason := old.moderation_reason;
    new.banned_at := old.banned_at;
  end if;
  return new;
end;
$$;

drop trigger if exists projects_guard_state on public.projects;
create trigger projects_guard_state
  before insert or update on public.projects
  for each row execute function public.guard_project_state();

-- =========================================================
-- VERIFICATION · 25 followers = basic, 100 = trusted
-- =========================================================
create or replace function public.check_verification(p_user uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  tier text;
  follower_count int;
begin
  if p_user is null then return null; end if;

  perform set_config('parrallery.privileged', 'on', true);

  select verification_tier into tier from public.profiles where user_id = p_user;
  select count(*) into follower_count from public.follows where following_id = p_user;

  if follower_count >= 100 and coalesce(tier, '') <> 'trusted' then
    update public.profiles
       set verification_tier = 'trusted', verified = true
     where user_id = p_user;
    insert into public.notifications (user_id, actor_id, kind, body)
    values (p_user, null, 'verified', 'You are now Trusted Verified!');
    return 'trusted';
  end if;

  if follower_count >= 25 and tier is null then
    update public.profiles
       set verification_tier = 'basic', verified = true
     where user_id = p_user;
    return 'basic';
  end if;

  return tier;
end;
$$;

revoke all on function public.check_verification(uuid) from public;
revoke all on function public.check_verification(uuid) from anon, authenticated;

create or replace function public.verify_on_follow()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.check_verification(new.following_id);
  return new;
end;
$$;

drop trigger if exists follows_verify on public.follows;
create trigger follows_verify
  after insert on public.follows
  for each row execute function public.verify_on_follow();

-- =========================================================
-- MESSAGE NOTIFICATIONS · one unread row per conversation,
-- refreshed instead of stacking; persona replies stay silent.
-- =========================================================
create or replace function public.notify_on_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  sender_handle text;
  existing uuid;
begin
  select handle into sender_handle from public.profiles where user_id = new.sender_id;

  if sender_handle in ('app', 'caustic') then
    return new;
  end if;

  if not coalesce((
    select message_notifications
    from public.profiles
    where user_id = new.recipient_id
  ), true) then
    return new;
  end if;

  select id into existing
    from public.notifications
   where user_id = new.recipient_id
     and actor_id = new.sender_id
     and kind = 'message'
     and read = false
   order by created_at desc
   limit 1;

  if existing is not null then
    update public.notifications
       set body = left(new.body, 120), created_at = now()
     where id = existing;
  else
    insert into public.notifications (user_id, actor_id, kind, body)
    values (new.recipient_id, new.sender_id, 'message', left(new.body, 120));
  end if;

  return new;
end;
$$;

drop trigger if exists messages_notify on public.messages;
create trigger messages_notify
  after insert on public.messages
  for each row execute function public.notify_on_message();

-- =========================================================
-- RPC · FILE REPORT  (AI triage result → moderation action)
--  * 5 reports/day, 1 per target/24h
--  * 3+ reports on one target in 24h = queue for review
--  * 3+ severe reports in 24h = account ban
--  * confidence > .8 = freeze 7 days, > .5 = freeze 3 days
-- =========================================================
create or replace function public.file_report(
  p_target_type text,
  p_target_id uuid,
  p_reason text,
  p_details text default null,
  p_confidence numeric default 0,
  p_severity text default 'low',
  p_days int default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  owner uuid;
  clean_reason text;
  severity text;
  confidence numeric;
  window_start timestamptz := now() - interval '24 hours';
  day_count int;
  target_count int;
  report_count int;
  severe_count int;
  freeze_days int;
  new_report uuid;
  action_taken text := 'none';
  report_status text;
  reporter_banned boolean;
begin
  if uid is null then
    return jsonb_build_object('error', 'Not signed in');
  end if;

  perform set_config('parrallery.privileged', 'on', true);

  if p_target_type not in ('account', 'project', 'preset', 'sample') then
    return jsonb_build_object('error', 'Invalid report type');
  end if;
  if p_target_id is null then
    return jsonb_build_object('error', 'Invalid report target');
  end if;

  select (state = 'banned' and (banned_until is null or banned_until > now()))
    into reporter_banned
    from public.profiles where user_id = uid;
  if coalesce(reporter_banned, false) then
    return jsonb_build_object('error', 'Your account cannot submit reports');
  end if;

  clean_reason := trim(coalesce(p_reason, ''));
  if clean_reason = '' then
    return jsonb_build_object('error', 'Choose a reason');
  end if;

  severity := lower(coalesce(p_severity, 'low'));
  if severity not in ('none', 'low', 'medium', 'high', 'severe') then
    severity := 'low';
  end if;
  confidence := greatest(0, least(1, coalesce(p_confidence, 0)));
  freeze_days := greatest(1, least(30, coalesce(p_days, 3)));

  if p_target_type = 'account' then
    select user_id into owner from public.profiles where user_id = p_target_id;
  else
    select user_id into owner from public.projects where id = p_target_id;
  end if;
  if owner is null then
    return jsonb_build_object('error', 'Report target not found');
  end if;
  if owner = uid then
    return jsonb_build_object('error', 'You cannot report your own content');
  end if;

  select count(*) into day_count
    from public.reports
   where reporter_id = uid and created_at > now() - interval '1 day';
  if day_count >= 5 then
    return jsonb_build_object('error', 'Daily report limit reached (5 per day)');
  end if;

  select count(*) into target_count
    from public.reports
   where reporter_id = uid
     and target_id = p_target_id
     and created_at > window_start;
  if target_count >= 1 then
    return jsonb_build_object('error', 'You already reported this in the last 24 hours');
  end if;

  insert into public.reports (
    reporter_id, reported_user_id, project_id, reason, details,
    target_type, target_id, ai_confidence, ai_severity, status
  ) values (
    uid, owner,
    case when p_target_type = 'account' then null else p_target_id end,
    clean_reason,
    nullif(trim(coalesce(p_details, '')), ''),
    p_target_type, p_target_id, confidence, severity, 'reviewing'
  ) returning id into new_report;

  select count(distinct reporter_id) into report_count
    from public.reports
   where target_id = p_target_id and created_at > window_start;

  select count(distinct reporter_id) into severe_count
    from public.reports
   where target_id = p_target_id
     and ai_severity = 'severe'
     and created_at > window_start;

  if severe_count >= 3 or (severity = 'severe' and confidence >= 0.9 and report_count >= 3) then
    update public.profiles
       set state = 'banned',
           banned_reason = clean_reason,
           banned_at = now(),
           banned_until = null
     where user_id = owner;

    update public.projects
       set state = 'frozen',
           frozen_until = now() + interval '10 years',
           moderation_reason = 'account banned'
     where user_id = owner and state <> 'banned';

    insert into public.moderation_actions (target_type, target_id, action, reason, performed_by, ai_evidence)
    values ('account', owner, 'ban_account', clean_reason, null,
            jsonb_build_object('report_id', new_report, 'confidence', confidence,
                               'severity', severity, 'reports', report_count));

    insert into public.notifications (user_id, actor_id, kind, body)
    values (owner, null, 'moderation',
            'Your account was restricted: ' || clean_reason || '. Appeal in Messages.');

    report_status := 'action_taken';
    action_taken := 'ban_account';

  elsif report_count >= 3 and severe_count < 3 then
    report_status := 'reviewing';
    action_taken := 'queued_for_review';

  elsif confidence > 0.8 then
    update public.projects
       set state = 'frozen',
           frozen_until = now() + make_interval(days => freeze_days),
           moderation_reason = clean_reason
     where state <> 'banned'
       and (id = p_target_id or (p_target_type = 'account' and user_id = owner));

    insert into public.moderation_actions (target_type, target_id, action, reason, performed_by, ai_evidence)
    values (p_target_type, p_target_id, 'freeze_content', clean_reason, null,
            jsonb_build_object('report_id', new_report, 'confidence', confidence,
                               'severity', severity, 'days', freeze_days));

    insert into public.notifications (user_id, actor_id, kind, body)
    values (owner, null, 'moderation',
            'Your upload is under review for ' || freeze_days || ' days: ' || clean_reason);

    report_status := 'action_taken';
    action_taken := 'freeze_content';

  elsif confidence > 0.5 then
    update public.projects
       set state = 'frozen',
           frozen_until = now() + interval '3 days',
           moderation_reason = clean_reason
     where state <> 'banned'
       and (id = p_target_id or (p_target_type = 'account' and user_id = owner));

    insert into public.moderation_actions (target_type, target_id, action, reason, performed_by, ai_evidence)
    values (p_target_type, p_target_id, 'freeze_content', clean_reason, null,
            jsonb_build_object('report_id', new_report, 'confidence', confidence,
                               'severity', severity, 'days', 3));

    insert into public.notifications (user_id, actor_id, kind, body)
    values (owner, null, 'moderation',
            'Your upload is under review for 3 days: ' || clean_reason);

    report_status := 'action_taken';
    action_taken := 'freeze_content';

  else
    report_status := 'dismissed';
    action_taken := 'dismissed';
  end if;

  update public.reports set status = report_status where id = new_report;

  insert into public.audit_logs (actor_id, action, target_id, details)
  values (uid, 'report_submitted', owner,
          jsonb_build_object('reason', clean_reason, 'target_type', p_target_type,
                             'target_id', p_target_id, 'severity', severity,
                             'confidence', confidence, 'action', action_taken));

  return jsonb_build_object(
    'ok', true,
    'status', report_status,
    'action', action_taken,
    'report_id', new_report
  );
end;
$$;

revoke all on function public.file_report(text, uuid, text, text, numeric, text, int) from public;
grant execute on function public.file_report(text, uuid, text, text, numeric, text, int) to authenticated;

-- =========================================================
-- RPC · SWEEP  (auto-unfreeze expired reviews)
-- =========================================================
create or replace function public.sweep_moderation()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare n int;
begin
  update public.projects
     set state = 'active', frozen_until = null, moderation_reason = null
   where state = 'frozen'
     and frozen_until is not null
     and frozen_until <= now();
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke all on function public.sweep_moderation() from public;
grant execute on function public.sweep_moderation() to authenticated;
