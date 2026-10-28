-- Adoetz Chat - RPCs, server-side enforcement, admin operations, invites.

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------

create or replace function private.write_audit(
  p_actor_id uuid,
  p_target_id uuid,
  p_action text,
  p_reason text,
  p_result text default 'success',
  p_request_id text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_id uuid;
begin
  insert into public.admin_audit_logs
    (actor_id, target_id, action, reason, result, request_id, metadata)
  values
    (p_actor_id, p_target_id, p_action, p_reason, p_result, p_request_id, p_metadata)
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function private.write_audit(uuid, uuid, text, text, text, text, jsonb)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Account / profile
-- ---------------------------------------------------------------------------

create or replace function public.get_my_account()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  select jsonb_build_object(
           'user_id', p.user_id,
           'username', p.username::text,
           'display_name', p.display_name,
           'avatar_path', p.avatar_path,
           'bio', p.bio,
           'discoverable', p.discoverable,
           'role', coalesce(r.role, 'user'),
           'status', coalesce(s.status, 'active'),
           'created_at', p.created_at,
           'email', u.email,
           'last_sign_in_at', u.last_sign_in_at
         )
    into v
    from public.profiles p
    join auth.users u on u.id = p.user_id
    left join public.user_roles r on r.user_id = p.user_id
    left join public.account_status s on s.user_id = p.user_id
   where p.user_id = auth.uid();
  if v is null then
    raise exception 'PROFILE_MISSING' using errcode = 'P0002';
  end if;
  return v;
end;
$$;
revoke all on function public.get_my_account() from public, anon;
grant execute on function public.get_my_account() to authenticated;

create or replace function public.search_users(p_query text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  q text := lower(trim(coalesce(p_query, '')));
  v jsonb;
begin
  if auth.uid() is null or not public.is_active_account() then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if char_length(q) < 2 then
    return '[]'::jsonb;
  end if;
  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb)
    into v
    from (
      select p.user_id, p.username::text as username, p.display_name,
             p.avatar_path, p.bio
        from public.profiles p
        join public.account_status s on s.user_id = p.user_id
       where p.discoverable = true
         and s.status = 'active'
         and p.user_id <> auth.uid()
         and (p.username::text ilike '%' || q || '%'
              or p.display_name ilike '%' || q || '%')
         and not public.is_blocked_between(p.user_id, auth.uid())
       order by (p.username::text = q) desc, p.username
       limit 20
    ) t;
  return v;
end;
$$;
revoke all on function public.search_users(text) from public, anon;
grant execute on function public.search_users(text) to authenticated;

create or replace function public.get_peer_profile(p_peer_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if auth.uid() is null or not public.is_active_account() then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if p_peer_id = auth.uid() then
    raise exception 'INVALID_TARGET' using errcode = '22023';
  end if;
  select jsonb_build_object(
           'user_id', p.user_id,
           'username', p.username::text,
           'display_name', p.display_name,
           'avatar_path', p.avatar_path,
           'bio', p.bio,
           'discoverable', p.discoverable,
           'status', s.status,
           'last_seen_at', null
         )
    into v
    from public.profiles p
    left join public.account_status s on s.user_id = p.user_id
   where p.user_id = p_peer_id
     and (p.discoverable = true or public.shares_conversation(p.user_id, auth.uid()));
  if v is null then
    raise exception 'NOT_FOUND' using errcode = 'P0002';
  end if;
  return v;
end;
$$;
revoke all on function public.get_peer_profile(uuid) from public, anon;
grant execute on function public.get_peer_profile(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Conversations
-- ---------------------------------------------------------------------------

create or replace function public.get_or_create_direct_conversation(p_peer_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text;
  v_id uuid;
begin
  if auth.uid() is null or not public.is_active_account() then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if p_peer_id = auth.uid() then
    raise exception 'INVALID_TARGET' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.account_status
     where user_id = p_peer_id and status = 'active'
  ) then
    raise exception 'PEER_UNAVAILABLE' using errcode = 'P0002';
  end if;
  if public.is_blocked_between(auth.uid(), p_peer_id) then
    raise exception 'BLOCKED' using errcode = '42501';
  end if;

  v_key := least(auth.uid()::text, p_peer_id::text)
        || ':' || greatest(auth.uid()::text, p_peer_id::text);

  insert into public.conversations (kind, direct_key, created_by)
  values ('direct', v_key, auth.uid())
  on conflict (direct_key) do nothing;

  select id into v_id from public.conversations where direct_key = v_key;

  insert into public.conversation_members (conversation_id, user_id)
  values (v_id, auth.uid()), (v_id, p_peer_id)
  on conflict (conversation_id, user_id)
  do update set state = 'active';

  return v_id;
end;
$$;
revoke all on function public.get_or_create_direct_conversation(uuid) from public, anon;
grant execute on function public.get_or_create_direct_conversation(uuid) to authenticated;

create or replace function public.get_my_conversations()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if auth.uid() is null or not public.is_active_account() then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(row_to_json(t) order by t.pinned desc, t.last_sort desc), '[]'::jsonb)
    into v
    from (
      select
        c.id as conversation_id,
        peer.user_id as peer_id,
        peer.username::text as peer_username,
        peer.display_name as peer_display_name,
        peer.avatar_path as peer_avatar_path,
        lm.id as last_message_id,
        lm.sender_id as last_message_sender_id,
        lm.ciphertext as last_message_ciphertext,
        lm.protocol_version as last_message_protocol_version,
        lm.message_type as last_message_type,
        lm.created_at as last_message_at,
        null::text as last_message_preview,
        coalesce(unread.count, 0)::int as unread_count,
        m.pinned,
        m.muted,
        coalesce(lm.created_at, c.created_at) as last_sort
      from public.conversation_members m
      join public.conversations c
        on c.id = m.conversation_id and c.kind = 'direct'
      join public.conversation_members pm
        on pm.conversation_id = c.id and pm.user_id <> m.user_id
       and pm.state = 'active'
      join public.profiles peer on peer.user_id = pm.user_id
      left join lateral (
        select msg.*
          from public.messages msg
         where msg.conversation_id = c.id
         order by msg.created_at desc, msg.id desc
         limit 1
      ) lm on true
      left join lateral (
        select count(*) as count
          from public.messages msg
         where msg.conversation_id = c.id
           and msg.sender_id <> m.user_id
           and msg.deleted_at is null
           and msg.created_at > m.last_read_at
      ) unread on true
      where m.user_id = auth.uid()
        and m.state = 'active'
    ) t;
  return v;
end;
$$;
revoke all on function public.get_my_conversations() from public, anon;
grant execute on function public.get_my_conversations() to authenticated;

create or replace function public.mark_conversation_read(p_conversation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ids uuid[];
  v_receipts boolean := true;
begin
  if auth.uid() is null or not public.is_conversation_member(p_conversation_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select coalesce(read_receipts, true) into v_receipts
    from public.user_preferences where user_id = auth.uid();
  v_receipts := coalesce(v_receipts, true);

  if v_receipts then
    with inserted as (
      insert into public.message_receipts (message_id, recipient_id, type)
      select msg.id, auth.uid(), 'read'
        from public.messages msg
       where msg.conversation_id = p_conversation_id
         and msg.sender_id <> auth.uid()
         and msg.deleted_at is null
      on conflict do nothing
      returning message_id
    )
    select coalesce(array_agg(message_id), '{}') into v_ids from inserted;
  else
    v_ids := '{}';
  end if;

  update public.conversation_members
     set last_read_at = now()
   where conversation_id = p_conversation_id and user_id = auth.uid();

  return jsonb_build_object(
    'message_ids', to_jsonb(v_ids),
    'receipts_sent', v_receipts
  );
end;
$$;
revoke all on function public.mark_conversation_read(uuid) from public, anon;
grant execute on function public.mark_conversation_read(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Messages
-- ---------------------------------------------------------------------------

create or replace function public.send_message(
  p_conversation_id uuid,
  p_client_message_id uuid,
  p_ciphertext text,
  p_protocol_version integer default 1,
  p_message_type text default 'text'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_peer uuid;
  v_row public.messages;
begin
  if auth.uid() is null or not public.is_active_account() then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if not public.is_conversation_member(p_conversation_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  v_peer := public.conversation_peer(p_conversation_id);
  if v_peer is null then
    raise exception 'CONVERSATION_INVALID' using errcode = 'P0002';
  end if;
  if public.is_blocked_between(auth.uid(), v_peer) then
    raise exception 'BLOCKED' using errcode = '42501';
  end if;
  if p_client_message_id is null then
    raise exception 'CLIENT_ID_REQUIRED' using errcode = '22023';
  end if;
  if char_length(coalesce(p_ciphertext, '')) not between 3 and 262144 then
    raise exception 'PAYLOAD_INVALID' using errcode = '22023';
  end if;
  if p_ciphertext not like 'p:%' and p_ciphertext not like 's:%' then
    raise exception 'PAYLOAD_INVALID' using errcode = '22023';
  end if;
  if p_protocol_version not in (1, 2, 3) then
    raise exception 'PROTOCOL_UNSUPPORTED' using errcode = '22023';
  end if;
  if p_message_type not in ('text', 'image', 'video', 'document', 'audio', 'system') then
    raise exception 'PAYLOAD_INVALID' using errcode = '22023';
  end if;

  select * into v_row
    from public.messages
   where sender_id = auth.uid()
     and client_message_id = p_client_message_id;

  if found then
    return jsonb_build_object('message', to_jsonb(v_row), 'duplicate', true);
  end if;

  insert into public.messages
    (client_message_id, conversation_id, sender_id, ciphertext,
     protocol_version, message_type)
  values
    (p_client_message_id, p_conversation_id, auth.uid(), p_ciphertext,
     p_protocol_version, p_message_type)
  returning * into v_row;

  return jsonb_build_object('message', to_jsonb(v_row), 'duplicate', false);
end;
$$;
revoke all on function public.send_message(uuid, uuid, text, integer, text)
  from public, anon;
grant execute on function public.send_message(uuid, uuid, text, integer, text)
  to authenticated;

create or replace function public.edit_message(
  p_message_id uuid,
  p_ciphertext text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.messages;
begin
  if auth.uid() is null or not public.is_active_account() then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  select * into v_row from public.messages where id = p_message_id;
  if not found then
    raise exception 'NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_row.sender_id <> auth.uid() or v_row.deleted_at is not null then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if v_row.created_at < now() - interval '15 minutes' then
    raise exception 'EDIT_WINDOW_EXPIRED' using errcode = '22023';
  end if;
  if p_ciphertext not like 'p:%' and p_ciphertext not like 's:%' then
    raise exception 'PAYLOAD_INVALID' using errcode = '22023';
  end if;
  update public.messages
     set ciphertext = p_ciphertext, edited_at = now()
   where id = p_message_id
  returning * into v_row;
  return jsonb_build_object('message', to_jsonb(v_row));
end;
$$;
revoke all on function public.edit_message(uuid, text) from public, anon;
grant execute on function public.edit_message(uuid, text) to authenticated;

create or replace function public.delete_message(p_message_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.messages;
begin
  if auth.uid() is null or not public.is_active_account() then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  select * into v_row from public.messages where id = p_message_id;
  if not found then
    raise exception 'NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_row.sender_id <> auth.uid() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  update public.messages
     set deleted_at = now()
   where id = p_message_id
  returning * into v_row;
  return jsonb_build_object('message', to_jsonb(v_row));
end;
$$;
revoke all on function public.delete_message(uuid) from public, anon;
grant execute on function public.delete_message(uuid) to authenticated;

create or replace function public.get_message_by_client_id(
  p_conversation_id uuid,
  p_client_message_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if auth.uid() is null or not public.is_conversation_member(p_conversation_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  select to_jsonb(m) into v
    from public.messages m
   where m.conversation_id = p_conversation_id
     and m.sender_id = auth.uid()
     and m.client_message_id = p_client_message_id;
  return v;
end;
$$;
revoke all on function public.get_message_by_client_id(uuid, uuid) from public, anon;
grant execute on function public.get_message_by_client_id(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Attachments
-- ---------------------------------------------------------------------------

create or replace function public.create_attachment_object(
  p_conversation_id uuid,
  p_storage_path text,
  p_size_bytes bigint,
  p_mime_hint text,
  p_sha256 text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_limit bigint;
begin
  if auth.uid() is null or not public.is_active_account() then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if not public.is_conversation_member(p_conversation_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_storage_path not like p_conversation_id::text || '/%' then
    raise exception 'PATH_INVALID' using errcode = '22023';
  end if;
  if p_mime_hint like 'image/%' then
    v_limit := 15 * 1024 * 1024;
  elsif p_mime_hint like 'video/%' then
    v_limit := 100 * 1024 * 1024;
  else
    v_limit := 25 * 1024 * 1024;
  end if;
  if p_size_bytes <= 0 or p_size_bytes > v_limit then
    raise exception 'FILE_TOO_LARGE' using errcode = '22023';
  end if;

  insert into public.attachment_objects
    (owner_id, conversation_id, storage_path, size_bytes, mime_hint, sha256,
     upload_state)
  values
    (auth.uid(), p_conversation_id, p_storage_path, p_size_bytes, p_mime_hint,
     p_sha256, 'uploaded')
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'storage_path', p_storage_path);
end;
$$;
revoke all on function public.create_attachment_object(uuid, text, bigint, text, text)
  from public, anon;
grant execute on function public.create_attachment_object(uuid, text, bigint, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Identity / device keys
-- ---------------------------------------------------------------------------

create or replace function public.register_device_keys(
  p_device_id uuid,
  p_identity_key text,
  p_registration_id integer,
  p_signed_prekey jsonb,
  p_prekeys jsonb,
  p_replace boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing uuid;
  v_count int;
  v_item jsonb;
begin
  if auth.uid() is null or not public.is_active_account() then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if p_device_id is null
     or char_length(coalesce(p_identity_key, '')) not between 20 and 1024 then
    raise exception 'KEYS_INVALID' using errcode = '22023';
  end if;
  if jsonb_typeof(p_signed_prekey) <> 'object' then
    raise exception 'KEYS_INVALID' using errcode = '22023';
  end if;
  if jsonb_typeof(p_prekeys) <> 'array'
     or jsonb_array_length(p_prekeys) > 200 then
    raise exception 'KEYS_INVALID' using errcode = '22023';
  end if;

  select id into v_existing
    from public.devices
   where user_id = auth.uid() and status = 'active';

  if v_existing is not null and v_existing <> p_device_id then
    if not p_replace then
      raise exception 'DEVICE_EXISTS' using errcode = 'P0001';
    end if;
    update public.devices
       set status = 'replaced'
     where id = v_existing;
    update public.push_tokens
       set revoked_at = now()
     where device_id = v_existing and revoked_at is null;
  end if;

  insert into public.devices
    (id, user_id, identity_key, registration_id, status, last_seen_at)
  values
    (p_device_id, auth.uid(), p_identity_key, p_registration_id, 'active', now())
  on conflict (id) do update
    set identity_key = excluded.identity_key,
        registration_id = excluded.registration_id,
        status = 'active',
        last_seen_at = now()
  where public.devices.user_id = auth.uid();

  insert into public.signed_prekeys (device_id, key_id, public_key, signature)
  values (
    p_device_id,
    (p_signed_prekey->>'key_id')::int,
    p_signed_prekey->>'public_key',
    p_signed_prekey->>'signature'
  )
  on conflict (device_id, key_id) do update
    set public_key = excluded.public_key,
        signature = excluded.signature;

  for v_item in select * from jsonb_array_elements(p_prekeys) loop
    insert into public.one_time_prekeys (device_id, key_id, public_key)
    values (p_device_id, (v_item->>'key_id')::int, v_item->>'public_key')
    on conflict (device_id, key_id) do nothing;
  end loop;

  select count(*) into v_count
    from public.one_time_prekeys
   where device_id = p_device_id and consumed_at is null;

  return jsonb_build_object(
    'device_id', p_device_id,
    'prekey_count', v_count,
    'replaced', v_existing is not null and v_existing <> p_device_id
  );
end;
$$;
revoke all on function public.register_device_keys(uuid, text, integer, jsonb, jsonb, boolean)
  from public, anon;
grant execute on function public.register_device_keys(uuid, text, integer, jsonb, jsonb, boolean)
  to authenticated;

create or replace function public.replenish_prekeys(
  p_device_id uuid,
  p_prekeys jsonb
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item jsonb;
  v_count int;
begin
  if auth.uid() is null or not public.is_active_account() then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.devices
     where id = p_device_id and user_id = auth.uid() and status = 'active'
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if jsonb_typeof(p_prekeys) <> 'array' or jsonb_array_length(p_prekeys) > 200 then
    raise exception 'KEYS_INVALID' using errcode = '22023';
  end if;
  for v_item in select * from jsonb_array_elements(p_prekeys) loop
    insert into public.one_time_prekeys (device_id, key_id, public_key)
    values (p_device_id, (v_item->>'key_id')::int, v_item->>'public_key')
    on conflict (device_id, key_id) do nothing;
  end loop;
  select count(*) into v_count
    from public.one_time_prekeys
   where device_id = p_device_id and consumed_at is null;
  return v_count;
end;
$$;
revoke all on function public.replenish_prekeys(uuid, jsonb) from public, anon;
grant execute on function public.replenish_prekeys(uuid, jsonb) to authenticated;

create or replace function public.get_prekey_bundle(p_conversation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_peer uuid;
  v_device public.devices;
  v_spk public.signed_prekeys;
  v_prekey public.one_time_prekeys;
begin
  if auth.uid() is null or not public.is_active_account() then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if not public.is_conversation_member(p_conversation_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  v_peer := public.conversation_peer(p_conversation_id);
  if v_peer is null then
    raise exception 'CONVERSATION_INVALID' using errcode = 'P0002';
  end if;

  select * into v_device
    from public.devices
   where user_id = v_peer and status = 'active'
   limit 1;
  if not found then
    raise exception 'NO_DEVICE' using errcode = 'P0002';
  end if;

  select * into v_spk
    from public.signed_prekeys
   where device_id = v_device.id
   order by key_id desc
   limit 1;
  if not found then
    raise exception 'NO_DEVICE' using errcode = 'P0002';
  end if;

  select * into v_prekey
    from public.one_time_prekeys
   where device_id = v_device.id and consumed_at is null
   order by key_id
   limit 1
   for update skip locked;

  if found then
    update public.one_time_prekeys
       set consumed_at = now()
     where device_id = v_device.id and key_id = v_prekey.key_id;
  end if;

  return jsonb_build_object(
    'device_id', v_device.id,
    'identity_key', v_device.identity_key,
    'registration_id', v_device.registration_id,
    'signed_prekey_id', v_spk.key_id,
    'signed_prekey_public', v_spk.public_key,
    'signed_prekey_signature', v_spk.signature,
    'prekey_id', v_prekey.key_id,
    'prekey_public', v_prekey.public_key
  );
end;
$$;
revoke all on function public.get_prekey_bundle(uuid) from public, anon;
grant execute on function public.get_prekey_bundle(uuid) to authenticated;

create or replace function public.get_peer_identity(p_peer_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if not public.shares_conversation(p_peer_id, auth.uid()) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  select jsonb_build_object(
           'identity_key', d.identity_key,
           'device_id', d.id
         )
    into v
    from public.devices d
   where d.user_id = p_peer_id and d.status = 'active'
   limit 1;
  return v;
end;
$$;
revoke all on function public.get_peer_identity(uuid) from public, anon;
grant execute on function public.get_peer_identity(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Push tokens
-- ---------------------------------------------------------------------------

create or replace function public.register_push_token(
  p_token text,
  p_device_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_active_account() then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if p_token is null or char_length(p_token) < 20 then
    raise exception 'TOKEN_INVALID' using errcode = '22023';
  end if;
  insert into public.push_tokens (user_id, device_id, token, platform)
  values (auth.uid(), p_device_id, p_token, 'android')
  on conflict (token) do update
    set user_id = auth.uid(),
        device_id = excluded.device_id,
        updated_at = now(),
        revoked_at = null;
end;
$$;
revoke all on function public.register_push_token(text, uuid) from public, anon;
grant execute on function public.register_push_token(text, uuid) to authenticated;

create or replace function public.unregister_push_token(p_token text)
returns void
language sql
security definer
set search_path = public
as $$
  update public.push_tokens
     set revoked_at = now()
   where token = p_token and user_id = auth.uid();
$$;
revoke all on function public.unregister_push_token(text) from public, anon;
grant execute on function public.unregister_push_token(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Blocking
-- ---------------------------------------------------------------------------

create or replace function public.block_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if p_user_id = auth.uid() or p_user_id is null then
    raise exception 'INVALID_TARGET' using errcode = '22023';
  end if;
  insert into public.blocked_users (blocker_id, blocked_id)
  values (auth.uid(), p_user_id)
  on conflict do nothing;
end;
$$;
revoke all on function public.block_user(uuid) from public, anon;
grant execute on function public.block_user(uuid) to authenticated;

create or replace function public.unblock_user(p_user_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.blocked_users
   where blocker_id = auth.uid() and blocked_id = p_user_id;
$$;
revoke all on function public.unblock_user(uuid) from public, anon;
grant execute on function public.unblock_user(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Calls
-- ---------------------------------------------------------------------------

create or replace function public.initiate_call(
  p_receiver_id uuid,
  p_kind text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.calls;
begin
  if auth.uid() is null or not public.is_active_account() then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if p_kind not in ('voice', 'video') then
    raise exception 'CALL_KIND_INVALID' using errcode = '22023';
  end if;
  if p_receiver_id = auth.uid() or p_receiver_id is null then
    raise exception 'INVALID_TARGET' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.account_status
     where user_id = p_receiver_id and status = 'active'
  ) then
    raise exception 'PEER_UNAVAILABLE' using errcode = 'P0002';
  end if;
  if public.is_blocked_between(auth.uid(), p_receiver_id) then
    raise exception 'BLOCKED' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.calls
     where status in ('ringing', 'connecting', 'active')
       and expires_at > now()
       and (initiator_id in (auth.uid(), p_receiver_id)
            or receiver_id in (auth.uid(), p_receiver_id))
  ) then
    raise exception 'BUSY' using errcode = 'P0001';
  end if;

  insert into public.calls (initiator_id, receiver_id, kind, status, expires_at)
  values (auth.uid(), p_receiver_id, p_kind, 'ringing', now() + interval '45 seconds')
  returning * into v_row;

  return to_jsonb(v_row);
end;
$$;
revoke all on function public.initiate_call(uuid, text) from public, anon;
grant execute on function public.initiate_call(uuid, text) to authenticated;

create or replace function public.call_action(
  p_call_id uuid,
  p_action text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.calls;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  select * into v_row from public.calls where id = p_call_id for update;
  if not found then
    raise exception 'NOT_FOUND' using errcode = 'P0002';
  end if;
  if auth.uid() not in (v_row.initiator_id, v_row.receiver_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if p_action = 'accept' then
    if auth.uid() <> v_row.receiver_id or v_row.status <> 'ringing' then
      raise exception 'CALL_STATE_INVALID' using errcode = 'P0001';
    end if;
    update public.calls
       set status = 'active', started_at = now(),
           expires_at = now() + interval '2 hours'
     where id = p_call_id
    returning * into v_row;
  elsif p_action = 'decline' then
    if auth.uid() <> v_row.receiver_id or v_row.status <> 'ringing' then
      raise exception 'CALL_STATE_INVALID' using errcode = 'P0001';
    end if;
    update public.calls
       set status = 'declined', ended_at = now()
     where id = p_call_id
    returning * into v_row;
  elsif p_action = 'cancel' then
    if auth.uid() <> v_row.initiator_id or v_row.status <> 'ringing' then
      raise exception 'CALL_STATE_INVALID' using errcode = 'P0001';
    end if;
    update public.calls
       set status = 'cancelled', ended_at = now()
     where id = p_call_id
    returning * into v_row;
  elsif p_action = 'end' then
    if v_row.status not in ('active', 'connecting', 'ringing') then
      raise exception 'CALL_STATE_INVALID' using errcode = 'P0001';
    end if;
    update public.calls
       set status = 'ended', ended_at = now()
     where id = p_call_id
    returning * into v_row;
  elsif p_action = 'missed' then
    if v_row.status <> 'ringing' or v_row.expires_at > now() then
      raise exception 'CALL_STATE_INVALID' using errcode = 'P0001';
    end if;
    update public.calls
       set status = 'missed', ended_at = now()
     where id = p_call_id
    returning * into v_row;
  else
    raise exception 'CALL_ACTION_INVALID' using errcode = '22023';
  end if;

  return to_jsonb(v_row);
end;
$$;
revoke all on function public.call_action(uuid, text) from public, anon;
grant execute on function public.call_action(uuid, text) to authenticated;

create or replace function public.send_call_signal(
  p_call_id uuid,
  p_payload jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id bigint;
  v_call public.calls;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  select * into v_call from public.calls where id = p_call_id;
  if not found or auth.uid() not in (v_call.initiator_id, v_call.receiver_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_payload is null or length(p_payload::text) > 65536 then
    raise exception 'PAYLOAD_INVALID' using errcode = '22023';
  end if;
  insert into public.call_signaling_events (call_id, sender_id, payload)
  values (p_call_id, auth.uid(), p_payload)
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.send_call_signal(uuid, jsonb) from public, anon;
grant execute on function public.send_call_signal(uuid, jsonb) to authenticated;

create or replace function public.get_call_signals(
  p_call_id uuid,
  p_after bigint default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.calls c
     where c.id = p_call_id
       and auth.uid() in (c.initiator_id, c.receiver_id)
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(to_jsonb(e) order by e.id), '[]'::jsonb)
    into v
    from public.call_signaling_events e
   where e.call_id = p_call_id and e.id > p_after and e.expires_at > now();
  return v;
end;
$$;
revoke all on function public.get_call_signals(uuid, bigint) from public, anon;
grant execute on function public.get_call_signals(uuid, bigint) to authenticated;

create or replace function public.get_call_history(
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb)
    into v
    from (
      select c.id, c.initiator_id, c.receiver_id, c.kind, c.status,
             c.created_at, c.started_at, c.ended_at,
             case when c.initiator_id = auth.uid() then 'outgoing' else 'incoming' end as direction,
             peer.user_id as peer_id, peer.username::text as peer_username,
             peer.display_name as peer_display_name, peer.avatar_path as peer_avatar_path
        from public.calls c
        join public.profiles peer
          on peer.user_id = case when c.initiator_id = auth.uid()
                                 then c.receiver_id else c.initiator_id end
       where auth.uid() in (c.initiator_id, c.receiver_id)
       order by c.created_at desc
       limit least(greatest(coalesce(p_limit, 50), 1), 100)
      offset greatest(coalesce(p_offset, 0), 0)
    ) t;
  return v;
end;
$$;
revoke all on function public.get_call_history(integer, integer) from public, anon;
grant execute on function public.get_call_history(integer, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Admin
-- ---------------------------------------------------------------------------

create or replace function public.admin_dashboard_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'total_users', (select count(*) from public.profiles),
    'active_users', (select count(*) from public.account_status where status = 'active'),
    'suspended_users', (select count(*) from public.account_status where status = 'suspended'),
    'pending_invites', (select count(*) from public.invitations
                         where status = 'active' and expires_at > now()
                           and used_count < max_uses),
    'active_invites', (select count(*) from public.invitations
                        where status = 'active'),
    'recent_actions', coalesce((
      select jsonb_agg(to_jsonb(a) order by a.created_at desc)
        from (
          select l.id, l.action, l.reason, l.result, l.created_at,
                 l.actor_id, actor.username::text as actor_username,
                 l.target_id, target.username::text as target_username
            from public.admin_audit_logs l
            left join public.profiles actor on actor.user_id = l.actor_id
            left join public.profiles target on target.user_id = l.target_id
           order by l.created_at desc
           limit 8
        ) a
    ), '[]'::jsonb)
  ) into v;
  return v;
end;
$$;
revoke all on function public.admin_dashboard_stats() from public, anon;
grant execute on function public.admin_dashboard_stats() to authenticated;

create or replace function public.admin_list_users(
  p_query text default null,
  p_role text default null,
  p_status text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit int := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset int := greatest(coalesce(p_offset, 0), 0);
  v_total int;
  v_users jsonb;
  q text := lower(trim(coalesce(p_query, '')));
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select count(*) into v_total
    from public.profiles p
    join auth.users u on u.id = p.user_id
    left join public.user_roles r on r.user_id = p.user_id
    left join public.account_status s on s.user_id = p.user_id
   where (q = '' or p.username::text ilike '%' || q || '%'
          or u.email ilike '%' || q || '%'
          or p.user_id::text = q)
     and (p_role is null or coalesce(r.role, 'user') = p_role)
     and (p_status is null or coalesce(s.status, 'active') = p_status);

  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb)
    into v_users
    from (
      select p.user_id, p.username::text as username, p.display_name,
             p.avatar_path, p.bio, p.discoverable, p.created_at,
             coalesce(r.role, 'user') as role,
             coalesce(s.status, 'active') as status,
             u.email, u.last_sign_in_at,
             (select count(*) from public.devices d
               where d.user_id = p.user_id and d.status = 'active') as device_count
        from public.profiles p
        join auth.users u on u.id = p.user_id
        left join public.user_roles r on r.user_id = p.user_id
        left join public.account_status s on s.user_id = p.user_id
       where (q = '' or p.username::text ilike '%' || q || '%'
              or u.email ilike '%' || q || '%'
              or p.user_id::text = q)
         and (p_role is null or coalesce(r.role, 'user') = p_role)
         and (p_status is null or coalesce(s.status, 'active') = p_status)
       order by p.created_at desc
       limit v_limit offset v_offset
    ) t;

  return jsonb_build_object(
    'users', v_users,
    'total', v_total,
    'has_more', v_offset + v_limit < v_total
  );
end;
$$;
revoke all on function public.admin_list_users(text, text, text, integer, integer)
  from public, anon;
grant execute on function public.admin_list_users(text, text, text, integer, integer)
  to authenticated;

create or replace function public.admin_get_user(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'user_id', p.user_id,
    'username', p.username::text,
    'display_name', p.display_name,
    'avatar_path', p.avatar_path,
    'bio', p.bio,
    'discoverable', p.discoverable,
    'created_at', p.created_at,
    'role', coalesce(r.role, 'user'),
    'status', coalesce(s.status, 'active'),
    'suspended_at', s.suspended_at,
    'reason_code', s.reason_code,
    'email', u.email,
    'last_sign_in_at', u.last_sign_in_at,
    'devices', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'status', d.status,
        'created_at', d.created_at, 'last_seen_at', d.last_seen_at
      ) order by d.created_at desc)
        from public.devices d where d.user_id = p.user_id
    ), '[]'::jsonb)
  ) into v
    from public.profiles p
    join auth.users u on u.id = p.user_id
    left join public.user_roles r on r.user_id = p.user_id
    left join public.account_status s on s.user_id = p.user_id
   where p.user_id = p_user_id;
  if v is null then
    raise exception 'NOT_FOUND' using errcode = 'P0002';
  end if;
  return v;
end;
$$;
revoke all on function public.admin_get_user(uuid) from public, anon;
grant execute on function public.admin_get_user(uuid) to authenticated;

create or replace function public.admin_set_user_role(
  p_target_id uuid,
  p_role text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_role not in ('user', 'admin') then
    raise exception 'ROLE_INVALID' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where user_id = p_target_id) then
    raise exception 'NOT_FOUND' using errcode = 'P0002';
  end if;

  if p_role <> 'admin' and exists (
    select 1 from public.user_roles where user_id = p_target_id and role = 'admin'
  ) then
    if (select count(*) from public.user_roles where role = 'admin') <= 1 then
      raise exception 'LAST_ADMIN' using errcode = 'P0001';
    end if;
  end if;

  insert into public.user_roles (user_id, role)
  values (p_target_id, p_role)
  on conflict (user_id) do update set role = excluded.role;

  perform private.write_audit(
    auth.uid(), p_target_id, 'role_change', p_reason, 'success', null,
    jsonb_build_object('role', p_role)
  );
end;
$$;
revoke all on function public.admin_set_user_role(uuid, text, text) from public, anon;
grant execute on function public.admin_set_user_role(uuid, text, text) to authenticated;

create or replace function public.admin_set_user_status(
  p_target_id uuid,
  p_status text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_status not in ('active', 'suspended') then
    raise exception 'STATUS_INVALID' using errcode = '22023';
  end if;
  if p_target_id = auth.uid() then
    raise exception 'SELF_ACTION' using errcode = 'P0001';
  end if;
  if p_reason is null or char_length(trim(p_reason)) < 5 then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;
  if p_status = 'suspended' and exists (
    select 1 from public.user_roles where user_id = p_target_id and role = 'admin'
  ) and (select count(*) from public.user_roles where role = 'admin') <= 1 then
    raise exception 'LAST_ADMIN' using errcode = 'P0001';
  end if;

  update public.account_status
     set status = p_status,
         suspended_at = case when p_status = 'suspended' then now() else null end,
         reason_code = case when p_status = 'suspended' then 'admin_action' else null end,
         reason_note = case when p_status = 'suspended' then p_reason else null end
   where user_id = p_target_id;

  if p_status = 'suspended' then
    update public.push_tokens
       set revoked_at = now()
     where user_id = p_target_id and revoked_at is null;
    delete from auth.refresh_tokens where user_id = p_target_id::text;
  end if;

  perform private.write_audit(
    auth.uid(), p_target_id,
    case when p_status = 'suspended' then 'user_suspend' else 'user_reactivate' end,
    p_reason, 'success', null, '{}'::jsonb
  );
end;
$$;
revoke all on function public.admin_set_user_status(uuid, text, text) from public, anon;
grant execute on function public.admin_set_user_status(uuid, text, text) to authenticated;

create or replace function public.admin_list_invitations(p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb)
    into v
    from (
      select i.id, i.status, i.max_uses, i.used_count, i.expires_at,
             i.created_at, i.label, i.intended_for,
             creator.username::text as created_by_username
        from public.invitations i
        left join public.profiles creator on creator.user_id = i.created_by
       where p_status is null or i.status = p_status
       order by i.created_at desc
       limit 100
    ) t;
  return v;
end;
$$;
revoke all on function public.admin_list_invitations(text) from public, anon;
grant execute on function public.admin_list_invitations(text) to authenticated;

create or replace function public.admin_create_invitation(
  p_label text default null,
  p_max_uses integer default 1,
  p_expires_at timestamptz default null,
  p_intended_for text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text;
  v_id uuid;
  v_expires timestamptz := coalesce(p_expires_at, now() + interval '7 days');
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if coalesce(p_max_uses, 1) not between 1 and 100 then
    raise exception 'USES_INVALID' using errcode = '22023';
  end if;
  if v_expires <= now() then
    raise exception 'EXPIRY_INVALID' using errcode = '22023';
  end if;

  v_token := encode(gen_random_bytes(16), 'hex');
  insert into public.invitations
    (token_hash, max_uses, expires_at, created_by, label, intended_for)
  values
    (encode(digest(v_token, 'sha256'), 'hex'), p_max_uses, v_expires,
     auth.uid(), p_label, p_intended_for)
  returning id into v_id;

  perform private.write_audit(
    auth.uid(), null, 'invite_create', null, 'success', null,
    jsonb_build_object('invitation_id', v_id, 'max_uses', p_max_uses)
  );

  return jsonb_build_object(
    'id', v_id, 'raw_code', v_token, 'max_uses', p_max_uses,
    'expires_at', v_expires
  );
end;
$$;
revoke all on function public.admin_create_invitation(text, integer, timestamptz, text)
  from public, anon;
grant execute on function public.admin_create_invitation(text, integer, timestamptz, text)
  to authenticated;

create or replace function public.admin_revoke_invitation(
  p_invitation_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  update public.invitations set status = 'revoked' where id = p_invitation_id;
  if not found then
    raise exception 'NOT_FOUND' using errcode = 'P0002';
  end if;
  perform private.write_audit(
    auth.uid(), null, 'invite_revoke', p_reason, 'success', null,
    jsonb_build_object('invitation_id', p_invitation_id)
  );
end;
$$;
revoke all on function public.admin_revoke_invitation(uuid, text) from public, anon;
grant execute on function public.admin_revoke_invitation(uuid, text) to authenticated;

create or replace function public.admin_list_audit_logs(
  p_limit integer default 50,
  p_offset integer default 0,
  p_action text default null,
  p_query text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit int := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_offset int := greatest(coalesce(p_offset, 0), 0);
  q text := lower(trim(coalesce(p_query, '')));
  v jsonb;
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb)
    into v
    from (
      select l.id, l.action, l.reason, l.result, l.request_id, l.created_at,
             l.actor_id, actor.username::text as actor_username,
             l.target_id, target.username::text as target_username,
             l.metadata
        from public.admin_audit_logs l
        left join public.profiles actor on actor.user_id = l.actor_id
        left join public.profiles target on target.user_id = l.target_id
       where (p_action is null or l.action = p_action)
         and (q = '' or l.action ilike '%' || q || '%'
              or coalesce(l.reason, '') ilike '%' || q || '%'
              or coalesce(actor.username::text, '') ilike '%' || q || '%'
              or coalesce(target.username::text, '') ilike '%' || q || '%')
       order by l.created_at desc
       limit v_limit offset v_offset
    ) t;
  return v;
end;
$$;
revoke all on function public.admin_list_audit_logs(integer, integer, text, text)
  from public, anon;
grant execute on function public.admin_list_audit_logs(integer, integer, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Invite redemption + registration (service role / Edge Functions only)
-- ---------------------------------------------------------------------------

create table if not exists private.auth_rate_limits (
  bucket text not null,
  window_start timestamptz not null,
  count integer not null default 0,
  primary key (bucket, window_start)
);

create or replace function public.hit_rate_limit(
  p_bucket text,
  p_limit integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_window timestamptz;
  v_count int;
begin
  if p_bucket is null or p_limit < 1 or p_window_seconds < 1 then
    return true;
  end if;
  v_window := to_timestamp(
    floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds
  );
  insert into private.auth_rate_limits (bucket, window_start, count)
  values (p_bucket, v_window, 1)
  on conflict (bucket, window_start) do update
    set count = private.auth_rate_limits.count + 1
  returning count into v_count;

  delete from private.auth_rate_limits where window_start < now() - interval '1 day';
  return v_count > p_limit;
end;
$$;
revoke all on function public.hit_rate_limit(text, integer, integer) from public, anon, authenticated;
grant execute on function public.hit_rate_limit(text, integer, integer) to service_role;

create or replace function public.redeem_invite_token(
  p_token text,
  p_email citext
)
returns uuid
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_inv public.invitations;
begin
  if p_token is null or char_length(p_token) < 8 then
    raise exception 'INVITE_INVALID' using errcode = 'P0001';
  end if;
  select * into v_inv
    from public.invitations
   where token_hash = encode(digest(p_token, 'sha256'), 'hex')
   for update;
  if not found then
    raise exception 'INVITE_INVALID' using errcode = 'P0001';
  end if;
  if v_inv.status <> 'active' then
    raise exception 'INVITE_REVOKED' using errcode = 'P0001';
  end if;
  if v_inv.expires_at <= now() then
    raise exception 'INVITE_EXPIRED' using errcode = 'P0001';
  end if;
  if v_inv.used_count >= v_inv.max_uses then
    raise exception 'INVITE_USED' using errcode = 'P0001';
  end if;

  update public.invitations
     set used_count = used_count + 1
   where id = v_inv.id;

  insert into private.invite_reservations (invitation_id, email)
  values (v_inv.id, p_email);

  return v_inv.id;
end;
$$;
revoke all on function public.redeem_invite_token(text, citext)
  from public, anon, authenticated;
grant execute on function public.redeem_invite_token(text, citext) to service_role;

create or replace function public.release_invite_token(
  p_invitation_id uuid,
  p_email citext
)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
begin
  update public.invitations
     set used_count = greatest(used_count - 1, 0)
   where id = p_invitation_id;
  delete from private.invite_reservations
   where invitation_id = p_invitation_id and email = p_email;
end;
$$;
revoke all on function public.release_invite_token(uuid, citext)
  from public, anon, authenticated;
grant execute on function public.release_invite_token(uuid, citext) to service_role;

create or replace function public.finalize_registration(
  p_user_id uuid,
  p_username text,
  p_display_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_invite_id uuid;
  v_profile public.profiles;
begin
  select nullif(raw_app_meta_data->>'adoetz_invite_id', '')::uuid
    into v_invite_id
    from auth.users where id = p_user_id;

  if v_invite_id is null then
    raise exception 'INVITE_REQUIRED' using errcode = '42501';
  end if;
  if not exists (
    select 1 from private.invite_reservations
     where invitation_id = v_invite_id
  ) then
    raise exception 'INVITE_REQUIRED' using errcode = '42501';
  end if;
  if p_username !~ '^[a-z][a-z0-9_]{2,23}$' then
    raise exception 'USERNAME_INVALID' using errcode = '22023';
  end if;
  if char_length(trim(coalesce(p_display_name, ''))) not between 1 and 40 then
    raise exception 'NAME_INVALID' using errcode = '22023';
  end if;

  insert into public.profiles (user_id, username, display_name)
  values (p_user_id, lower(p_username), trim(p_display_name))
  returning * into v_profile;

  insert into public.user_roles (user_id, role) values (p_user_id, 'user')
  on conflict (user_id) do nothing;

  insert into public.account_status (user_id, status) values (p_user_id, 'active')
  on conflict (user_id) do nothing;

  insert into public.user_preferences (user_id) values (p_user_id)
  on conflict (user_id) do nothing;

  insert into public.invitation_redemptions (invitation_id, user_id)
  values (v_invite_id, p_user_id)
  on conflict do nothing;

  delete from private.invite_reservations
   where invitation_id = v_invite_id
     and email = (select email from auth.users where id = p_user_id);

  return jsonb_build_object(
    'user_id', v_profile.user_id,
    'username', v_profile.username::text,
    'display_name', v_profile.display_name
  );
end;
$$;
revoke all on function public.finalize_registration(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.finalize_registration(uuid, text, text) to service_role;

create or replace function public.lookup_login_email(p_identifier text)
returns text
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_email text;
  v_identifier text := lower(trim(coalesce(p_identifier, '')));
begin
  if v_identifier = '' then
    return null;
  end if;
  select u.email into v_email
    from public.profiles p
    join auth.users u on u.id = p.user_id
   where p.username::text = v_identifier
   limit 1;
  if v_email is null and v_identifier like '%@%' then
    select email into v_email from auth.users
     where lower(email) = v_identifier limit 1;
  end if;
  return v_email;
end;
$$;
revoke all on function public.lookup_login_email(text)
  from public, anon, authenticated;
grant execute on function public.lookup_login_email(text) to service_role;

-- ---------------------------------------------------------------------------
-- Push job enqueueing
-- ---------------------------------------------------------------------------

create or replace function private.enqueue_message_push()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_peer uuid;
  v_token record;
begin
  v_peer := public.conversation_peer(new.conversation_id);
  if v_peer is null or v_peer = new.sender_id then
    return new;
  end if;
  if public.is_blocked_between(new.sender_id, v_peer) then
    return new;
  end if;
  if exists (
    select 1 from public.user_preferences
     where user_id = v_peer and notification_privacy = 'none'
  ) then
    return new;
  end if;
  for v_token in
    select pt.device_id
      from public.push_tokens pt
     where pt.user_id = v_peer and pt.revoked_at is null
  loop
    insert into public.outbound_jobs
      (event_type, recipient_user_id, recipient_device_id, payload)
    values (
      'message', v_peer, v_token.device_id,
      jsonb_build_object(
        'message_id', new.id,
        'conversation_id', new.conversation_id,
        'sender_id', new.sender_id,
        'message_type', new.message_type
      )
    );
  end loop;
  return new;
end;
$$;
revoke all on function private.enqueue_message_push() from public, anon, authenticated;

drop trigger if exists messages_enqueue_push on public.messages;
create trigger messages_enqueue_push after insert on public.messages
  for each row execute function private.enqueue_message_push();

create or replace function private.enqueue_call_push()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_token record;
begin
  if new.status <> 'ringing' then
    return new;
  end if;
  if public.is_blocked_between(new.initiator_id, new.receiver_id) then
    return new;
  end if;
  for v_token in
    select pt.device_id
      from public.push_tokens pt
     where pt.user_id = new.receiver_id and pt.revoked_at is null
  loop
    insert into public.outbound_jobs
      (event_type, recipient_user_id, recipient_device_id, payload)
    values (
      'call', new.receiver_id, v_token.device_id,
      jsonb_build_object(
        'call_id', new.id,
        'kind', new.kind,
        'initiator_id', new.initiator_id,
        'expires_at', new.expires_at
      )
    );
  end loop;
  return new;
end;
$$;
revoke all on function private.enqueue_call_push() from public, anon, authenticated;

drop trigger if exists calls_enqueue_push on public.calls;
create trigger calls_enqueue_push after insert on public.calls
  for each row execute function private.enqueue_call_push();
