-- Adoetz Chat - message reactions and user reports.
--
-- Reactions are cheap, per-user toggles on a message. Reports are the only
-- deliberate path by which a user may share plaintext with an administrator:
-- the client sends the decrypted text only when the reporter ticks the consent
-- box, and the server stores exactly what was sent.

-- ---------------------------------------------------------------------------
-- Reactions
-- ---------------------------------------------------------------------------

create table if not exists public.message_reactions (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  emoji text not null,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, emoji)
);

create index if not exists message_reactions_message
  on public.message_reactions (message_id);

alter table public.message_reactions enable row level security;

drop policy if exists reactions_select on public.message_reactions;
create policy reactions_select on public.message_reactions
  for select to authenticated
  using (
    exists (
      select 1 from public.messages m
       where m.id = message_id
         and public.is_conversation_member(m.conversation_id)
    )
  );
-- No write policies: toggling goes through set_message_reaction().

create or replace function public.set_message_reaction(
  p_message_id uuid,
  p_emoji text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_conversation uuid;
  v_result jsonb;
begin
  if v_me is null then
    raise exception 'UNAUTHENTICATED' using errcode = '42501';
  end if;
  if p_emoji is null
     or p_emoji not in ('👍', '❤️', '😂', '😮', '😢', '🙏') then
    raise exception 'REACTION_INVALID' using errcode = '22023';
  end if;

  select conversation_id into v_conversation
    from public.messages
   where id = p_message_id and deleted_at is null;
  if v_conversation is null or not public.is_conversation_member(v_conversation) then
    raise exception 'NOT_FOUND' using errcode = 'P0002';
  end if;

  if exists (
    select 1 from public.message_reactions
     where message_id = p_message_id and user_id = v_me and emoji = p_emoji
  ) then
    delete from public.message_reactions
     where message_id = p_message_id and user_id = v_me and emoji = p_emoji;
  else
    insert into public.message_reactions (message_id, user_id, emoji)
    values (p_message_id, v_me, p_emoji)
    on conflict do nothing;
  end if;

  select coalesce(jsonb_object_agg(emoji, ids), '{}'::jsonb)
    into v_result
    from (
      select emoji, jsonb_agg(user_id) as ids
        from public.message_reactions
       where message_id = p_message_id
       group by emoji
    ) grouped;

  return v_result;
end;
$$;
revoke all on function public.set_message_reaction(uuid, text) from public, anon;
grant execute on function public.set_message_reaction(uuid, text) to authenticated;

create or replace function public.get_conversation_reactions(
  p_conversation_id uuid
)
returns table (message_id uuid, emoji text, user_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select r.message_id, r.emoji, r.user_id
    from public.message_reactions r
    join public.messages m on m.id = r.message_id
   where m.conversation_id = p_conversation_id
     and public.is_conversation_member(p_conversation_id);
$$;
revoke all on function public.get_conversation_reactions(uuid) from public, anon;
grant execute on function public.get_conversation_reactions(uuid) to authenticated;

do $$
begin
  begin
    alter publication supabase_realtime add table public.message_reactions;
  exception when duplicate_object then null;
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- Reports
-- ---------------------------------------------------------------------------

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reported_user_id uuid not null references auth.users(id) on delete cascade,
  conversation_id uuid references public.conversations(id) on delete set null,
  message_id uuid references public.messages(id) on delete set null,
  reason text not null
    check (reason in ('spam', 'harassment', 'scam', 'illegal', 'other')),
  details text,
  -- Only filled when the reporter explicitly consents to sharing this message.
  shared_content text,
  status text not null default 'open'
    check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  resolution_note text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists reports_status_created
  on public.reports (status, created_at desc);
create index if not exists reports_reported
  on public.reports (reported_user_id, created_at desc);

alter table public.reports enable row level security;

drop policy if exists reports_select on public.reports;
create policy reports_select on public.reports
  for select to authenticated
  using (reporter_id = auth.uid() or public.is_admin());
-- Inserts/updates only through the RPCs below.

create or replace function public.submit_report(
  p_reported_user_id uuid,
  p_reason text,
  p_details text default null,
  p_message_id uuid default null,
  p_shared_content text default null,
  p_share_content boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_me uuid := auth.uid();
  v_message public.messages;
  v_id uuid;
begin
  if v_me is null then
    raise exception 'UNAUTHENTICATED' using errcode = '42501';
  end if;
  if p_reported_user_id = v_me then
    raise exception 'REPORT_SELF' using errcode = '22023';
  end if;
  if p_reason is null
     or p_reason not in ('spam', 'harassment', 'scam', 'illegal', 'other') then
    raise exception 'REASON_INVALID' using errcode = '22023';
  end if;

  if p_message_id is not null then
    select * into v_message from public.messages where id = p_message_id;
    if not found
       or v_message.sender_id <> p_reported_user_id
       or not public.is_conversation_member(v_message.conversation_id) then
      raise exception 'MESSAGE_INVALID' using errcode = '22023';
    end if;
  end if;

  insert into public.reports (
    reporter_id, reported_user_id, conversation_id, message_id,
    reason, details, shared_content
  )
  values (
    v_me, p_reported_user_id,
    v_message.conversation_id, p_message_id,
    p_reason,
    nullif(trim(coalesce(p_details, '')), ''),
    case
      when p_share_content and p_message_id is not null
        then left(coalesce(p_shared_content, ''), 4000)
      else null
    end
  )
  returning id into v_id;

  perform private.write_audit(
    v_me, p_reported_user_id, 'report_submit', p_reason, 'success', null,
    jsonb_build_object(
      'report_id', v_id,
      'message_id', p_message_id,
      'shared_content', (p_share_content and p_message_id is not null)
    )
  );

  return v_id;
end;
$$;
revoke all on function public.submit_report(uuid, text, text, uuid, text, boolean)
  from public, anon;
grant execute on function public.submit_report(uuid, text, text, uuid, text, boolean)
  to authenticated;

create or replace function public.admin_list_reports(
  p_status text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  id uuid,
  reporter_id uuid,
  reporter_username text,
  reported_user_id uuid,
  reported_username text,
  reported_display_name text,
  conversation_id uuid,
  message_id uuid,
  reason text,
  details text,
  shared_content text,
  status text,
  resolution_note text,
  created_at timestamptz,
  reviewed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  return query
  select r.id, r.reporter_id, rp.username::text,
         r.reported_user_id, tp.username::text, tp.display_name,
         r.conversation_id, r.message_id, r.reason, r.details,
         r.shared_content, r.status, r.resolution_note, r.created_at,
         r.reviewed_at
    from public.reports r
    left join public.profiles rp on rp.user_id = r.reporter_id
    left join public.profiles tp on tp.user_id = r.reported_user_id
   where p_status is null or r.status = p_status
   order by r.created_at desc
   limit least(greatest(coalesce(p_limit, 50), 1), 100)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;
revoke all on function public.admin_list_reports(text, integer, integer)
  from public, anon;
grant execute on function public.admin_list_reports(text, integer, integer)
  to authenticated;

create or replace function public.admin_update_report(
  p_report_id uuid,
  p_status text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_status not in ('open', 'reviewing', 'resolved', 'dismissed') then
    raise exception 'STATUS_INVALID' using errcode = '22023';
  end if;

  update public.reports
     set status = p_status,
         resolution_note = nullif(trim(coalesce(p_note, '')), ''),
         reviewed_by = auth.uid(),
         reviewed_at = now()
   where id = p_report_id;
  if not found then
    raise exception 'NOT_FOUND' using errcode = 'P0002';
  end if;

  perform private.write_audit(
    auth.uid(), null, 'report_update', null, 'success', null,
    jsonb_build_object('report_id', p_report_id, 'status', p_status)
  );
end;
$$;
revoke all on function public.admin_update_report(uuid, text, text)
  from public, anon;
grant execute on function public.admin_update_report(uuid, text, text)
  to authenticated;
