-- Push fan-out for every conversation member.
--
-- The first version resolved a single peer, which is right for a direct chat
-- but notified only one member of a group (conversation_peer returns one row).
-- Queue a job per active member instead; the dispatcher expands each target's
-- own devices.

create or replace function private.enqueue_message_push()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_recipient uuid;
  v_token record;
begin
  for v_recipient in
    select m.user_id
      from public.conversation_members m
     where m.conversation_id = new.conversation_id
       and m.user_id <> new.sender_id
       and m.state = 'active'
  loop
    if public.is_blocked_between(new.sender_id, v_recipient) then
      continue;
    end if;
    if exists (
      select 1 from public.user_preferences
       where user_id = v_recipient and notification_privacy = 'none'
    ) then
      continue;
    end if;
    for v_token in
      select pt.device_id
        from public.push_tokens pt
       where pt.user_id = v_recipient and pt.revoked_at is null
    loop
      insert into public.outbound_jobs
        (event_type, recipient_user_id, recipient_device_id, payload)
      values (
        'message', v_recipient, v_token.device_id,
        jsonb_build_object(
          'message_id', new.id,
          'conversation_id', new.conversation_id,
          'sender_id', new.sender_id,
          'message_type', new.message_type
        )
      );
    end loop;
  end loop;
  return new;
end;
$$;
revoke all on function private.enqueue_message_push() from public, anon, authenticated;
