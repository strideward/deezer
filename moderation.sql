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
    or state is null
    or state = 'active'
    or (state = 'frozen' and frozen_until is not null and frozen_until <= now())
  );

drop policy if exists "projects_insert_own" on public.projects;
create policy "projects_insert_own"
  on public.projects for insert
  with check (
    auth.uid() = user_id
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
create policy "messages_insert_own"
  on public.messages for insert
  with check (
    auth.uid() = sender_id
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
