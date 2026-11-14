-- @app official account reply writer.
-- Run once in the Supabase SQL editor (whole file, no selection).
-- Lets a signed-in member save an automated @app reply in their own
-- conversation, and hands the request to the team when a human is needed.

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
