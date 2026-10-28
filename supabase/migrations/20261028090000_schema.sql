-- Adoetz Chat - core schema, RLS, helper functions
-- Apply this migration to the Supabase project before deploying Edge Functions.

create extension if not exists "pgcrypto";
create extension if not exists "citext";

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username citext not null unique,
  display_name text not null,
  avatar_path text,
  bio text,
  discoverable boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_format
    check (username ~ '^[a-z][a-z0-9_]{2,23}$'),
  constraint profiles_display_name_length
    check (char_length(display_name) between 1 and 40),
  constraint profiles_bio_length check (bio is null or char_length(bio) <= 160)
);

create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'user' check (role in ('user', 'admin')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.account_status (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null default 'active'
    check (status in ('active', 'suspended')),
  suspended_at timestamptz,
  reason_code text,
  reason_note text,
  updated_at timestamptz not null default now()
);

create table if not exists public.devices (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  identity_key text not null,
  registration_id integer not null check (registration_id between 1 and 2147483646),
  status text not null default 'active'
    check (status in ('active', 'replaced', 'revoked')),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create unique index if not exists devices_one_active_per_user
  on public.devices (user_id) where status = 'active';

create table if not exists public.signed_prekeys (
  device_id uuid not null references public.devices(id) on delete cascade,
  key_id integer not null,
  public_key text not null,
  signature text not null,
  created_at timestamptz not null default now(),
  primary key (device_id, key_id)
);

create table if not exists public.one_time_prekeys (
  device_id uuid not null references public.devices(id) on delete cascade,
  key_id integer not null,
  public_key text not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (device_id, key_id)
);

create index if not exists one_time_prekeys_available
  on public.one_time_prekeys (device_id, key_id) where consumed_at is null;

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  kind text not null default 'direct' check (kind in ('direct')),
  direct_key text unique,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  last_event_at timestamptz not null default now()
);

create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  state text not null default 'active'
    check (state in ('active', 'left', 'removed')),
  last_read_at timestamptz not null default 'epoch',
  last_read_cursor uuid,
  pinned boolean not null default false,
  muted boolean not null default false,
  primary key (conversation_id, user_id)
);

create index if not exists conversation_members_user
  on public.conversation_members (user_id, state);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  client_message_id uuid not null,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  ciphertext text not null,
  protocol_version integer not null default 1,
  message_type text not null default 'text'
    check (message_type in ('text', 'image', 'video', 'document', 'audio', 'system')),
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted_at timestamptz,
  unique (sender_id, client_message_id),
  constraint messages_ciphertext_size
    check (char_length(ciphertext) between 1 and 262144)
);

create index if not exists messages_conversation_cursor
  on public.messages (conversation_id, created_at desc, id desc);

create table if not exists public.message_receipts (
  message_id uuid not null references public.messages(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  type text not null check (type in ('delivered', 'read')),
  created_at timestamptz not null default now(),
  primary key (message_id, recipient_id, type)
);

create index if not exists message_receipts_recipient
  on public.message_receipts (recipient_id, created_at desc);

create table if not exists public.attachment_objects (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  storage_path text not null unique,
  size_bytes bigint not null check (size_bytes between 0 and 209715200),
  mime_hint text,
  sha256 text,
  upload_state text not null default 'pending'
    check (upload_state in ('pending', 'uploaded', 'failed')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days'
);

create table if not exists public.calls (
  id uuid primary key default gen_random_uuid(),
  initiator_id uuid not null references auth.users(id) on delete cascade,
  receiver_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('voice', 'video')),
  status text not null default 'ringing'
    check (status in ('ringing', 'connecting', 'active', 'ended', 'declined',
                      'missed', 'failed', 'busy', 'cancelled')),
  created_at timestamptz not null default now(),
  started_at timestamptz,
  ended_at timestamptz,
  expires_at timestamptz not null default now() + interval '45 seconds'
);

create index if not exists calls_initiator on public.calls (initiator_id, created_at desc);
create index if not exists calls_receiver on public.calls (receiver_id, created_at desc);

create table if not exists public.call_signaling_events (
  id bigserial primary key,
  call_id uuid not null references public.calls(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '5 minutes'
);

create index if not exists call_events_call on public.call_signaling_events (call_id, id);

create table if not exists public.invitations (
  id uuid primary key default gen_random_uuid(),
  token_hash text not null unique,
  status text not null default 'active'
    check (status in ('active', 'revoked')),
  max_uses integer not null default 1 check (max_uses between 1 and 100),
  used_count integer not null default 0 check (used_count >= 0),
  expires_at timestamptz not null,
  created_by uuid not null references auth.users(id),
  label text,
  intended_for text,
  created_at timestamptz not null default now()
);

create table if not exists public.invitation_redemptions (
  invitation_id uuid not null references public.invitations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  redeemed_at timestamptz not null default now(),
  primary key (invitation_id, user_id)
);

create table if not exists public.push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id uuid references public.devices(id) on delete cascade,
  token text not null unique,
  platform text not null default 'android',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revoked_at timestamptz
);

create table if not exists public.blocked_users (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table if not exists public.user_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  theme text not null default 'system' check (theme in ('system', 'dark', 'light')),
  read_receipts boolean not null default true,
  typing_indicators boolean not null default true,
  notification_privacy text not null default 'sender'
    check (notification_privacy in ('full', 'sender', 'none')),
  language text not null default 'id',
  updated_at timestamptz not null default now()
);

create table if not exists public.admin_audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users(id) on delete set null,
  target_id uuid references auth.users(id) on delete set null,
  action text not null,
  reason text,
  result text not null default 'success' check (result in ('success', 'failure')),
  request_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists admin_audit_created
  on public.admin_audit_logs (created_at desc);

create table if not exists public.outbound_jobs (
  id uuid primary key default gen_random_uuid(),
  event_type text not null,
  recipient_user_id uuid references auth.users(id) on delete cascade,
  recipient_device_id uuid references public.devices(id) on delete cascade,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'queued'
    check (status in ('queued', 'sending', 'sent', 'failed', 'dead')),
  retry_count integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Pending invite reservations, only touched by the Edge Function (service role).
create table if not exists private.invite_reservations (
  id uuid primary key default gen_random_uuid(),
  invitation_id uuid not null references public.invitations(id) on delete cascade,
  email citext not null,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Constraints / triggers
-- ---------------------------------------------------------------------------

drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

drop trigger if exists user_roles_touch on public.user_roles;
create trigger user_roles_touch before update on public.user_roles
  for each row execute function public.touch_updated_at();

drop trigger if exists preferences_touch on public.user_preferences;
create trigger preferences_touch before update on public.user_preferences
  for each row execute function public.touch_updated_at();

create or replace function public.bump_conversation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.conversations
     set last_event_at = greatest(last_event_at, new.created_at)
   where id = new.conversation_id;
  return new;
end;
$$;

drop trigger if exists messages_bump_conversation on public.messages;
create trigger messages_bump_conversation after insert on public.messages
  for each row execute function public.bump_conversation();

-- Invite-only gate: even if public email signup is accidentally enabled in
-- GoTrue, auth.users inserts without our app_metadata marker are rejected.
create or replace function private.enforce_invite_only()
returns trigger
language plpgsql
security definer
set search_path = auth, public, private
as $$
begin
  if coalesce(new.raw_app_meta_data->>'adoetz_invite_id', '') = '' then
    raise exception 'INVITE_REQUIRED';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_invite_only on auth.users;
create trigger enforce_invite_only before insert on auth.users
  for each row execute function private.enforce_invite_only();

-- ---------------------------------------------------------------------------
-- Authorization helpers
-- ---------------------------------------------------------------------------

create or replace function public.is_admin(uid uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.user_roles r
      join public.account_status s on s.user_id = r.user_id
     where r.user_id = uid and r.role = 'admin' and s.status = 'active'
  );
$$;

create or replace function public.is_active_account(uid uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.account_status
     where user_id = uid and status = 'active'
  );
$$;

create or replace function public.is_conversation_member(
  p_conversation_id uuid,
  uid uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.conversation_members
     where conversation_id = p_conversation_id
       and user_id = uid
       and state = 'active'
  );
$$;

create or replace function public.shares_conversation(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.conversation_members m1
      join public.conversation_members m2
        on m1.conversation_id = m2.conversation_id
     where m1.user_id = a and m2.user_id = b
       and m1.state = 'active' and m2.state = 'active'
  );
$$;

create or replace function public.is_blocked_between(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.blocked_users
     where (blocker_id = a and blocked_id = b)
        or (blocker_id = b and blocked_id = a)
  );
$$;

create or replace function public.conversation_peer(p_conversation_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select m.user_id
    from public.conversation_members m
   where m.conversation_id = p_conversation_id
     and m.user_id <> auth.uid()
     and m.state = 'active'
   limit 1;
$$;

revoke all on function public.conversation_peer(uuid) from public, anon;
grant execute on function public.conversation_peer(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.account_status enable row level security;
alter table public.devices enable row level security;
alter table public.signed_prekeys enable row level security;
alter table public.one_time_prekeys enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.message_receipts enable row level security;
alter table public.attachment_objects enable row level security;
alter table public.calls enable row level security;
alter table public.call_signaling_events enable row level security;
alter table public.invitations enable row level security;
alter table public.invitation_redemptions enable row level security;
alter table public.push_tokens enable row level security;
alter table public.blocked_users enable row level security;
alter table public.user_preferences enable row level security;
alter table public.admin_audit_logs enable row level security;
alter table public.outbound_jobs enable row level security;

-- Start from deny-all for client roles.
revoke all on all tables in schema public from anon, authenticated;

grant usage on schema public to anon, authenticated;
grant select on public.profiles to authenticated;
grant update (display_name, avatar_path, bio, discoverable) on public.profiles to authenticated;

grant select on public.user_roles to authenticated;
grant select on public.account_status to authenticated;
grant select on public.devices to authenticated;
grant select on public.conversations to authenticated;
grant select on public.conversation_members to authenticated;
grant update (pinned, muted) on public.conversation_members to authenticated;
grant select on public.messages to authenticated;
grant select on public.message_receipts to authenticated;
grant insert on public.message_receipts to authenticated;
grant select, insert, update, delete on public.attachment_objects to authenticated;
grant select on public.calls to authenticated;
grant select on public.call_signaling_events to authenticated;
grant select on public.push_tokens to authenticated;
grant insert, update, delete on public.push_tokens to authenticated;
grant select, insert, delete on public.blocked_users to authenticated;
grant select, insert, update on public.user_preferences to authenticated;

-- profiles
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    discoverable = true
    or user_id = auth.uid()
    or public.shares_conversation(user_id, auth.uid())
    or public.is_admin()
  );

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and public.is_active_account());

-- roles: read own or admin; no direct writes ever
drop policy if exists roles_select on public.user_roles;
create policy roles_select on public.user_roles
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists status_select on public.account_status;
create policy status_select on public.account_status
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- devices: owner can read only
drop policy if exists devices_select on public.devices;
create policy devices_select on public.devices
  for select to authenticated
  using (user_id = auth.uid());

-- conversations / members
drop policy if exists conversations_select on public.conversations;
create policy conversations_select on public.conversations
  for select to authenticated
  using (public.is_conversation_member(id));

drop policy if exists members_select on public.conversation_members;
create policy members_select on public.conversation_members
  for select to authenticated
  using (public.is_conversation_member(conversation_id));

drop policy if exists members_update_own on public.conversation_members;
create policy members_update_own on public.conversation_members
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- messages
drop policy if exists messages_select on public.messages;
create policy messages_select on public.messages
  for select to authenticated
  using (public.is_conversation_member(conversation_id));

-- Inserts normally go through send_message();
-- this policy keeps direct REST inserts safe too.
drop policy if exists messages_insert on public.messages;
create policy messages_insert on public.messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and public.is_active_account()
    and public.is_conversation_member(conversation_id)
  );

-- receipts
drop policy if exists receipts_select on public.message_receipts;
create policy receipts_select on public.message_receipts
  for select to authenticated
  using (
    recipient_id = auth.uid()
    or exists (
      select 1 from public.messages m
       where m.id = message_id
         and m.sender_id = auth.uid()
         and public.is_conversation_member(m.conversation_id)
    )
  );

drop policy if exists receipts_insert on public.message_receipts;
create policy receipts_insert on public.message_receipts
  for insert to authenticated
  with check (
    recipient_id = auth.uid()
    and exists (
      select 1 from public.messages m
       where m.id = message_id
         and public.is_conversation_member(m.conversation_id)
    )
  );

-- attachments metadata
drop policy if exists attachments_select on public.attachment_objects;
create policy attachments_select on public.attachment_objects
  for select to authenticated
  using (public.is_conversation_member(conversation_id));

drop policy if exists attachments_insert on public.attachment_objects;
create policy attachments_insert on public.attachment_objects
  for insert to authenticated
  with check (owner_id = auth.uid() and public.is_conversation_member(conversation_id));

drop policy if exists attachments_update on public.attachment_objects;
create policy attachments_update on public.attachment_objects
  for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists attachments_delete on public.attachment_objects;
create policy attachments_delete on public.attachment_objects
  for delete to authenticated
  using (owner_id = auth.uid());

-- calls
drop policy if exists calls_select on public.calls;
create policy calls_select on public.calls
  for select to authenticated
  using (initiator_id = auth.uid() or receiver_id = auth.uid());

drop policy if exists call_events_select on public.call_signaling_events;
create policy call_events_select on public.call_signaling_events
  for select to authenticated
  using (
    exists (
      select 1 from public.calls c
       where c.id = call_id
         and (c.initiator_id = auth.uid() or c.receiver_id = auth.uid())
    )
  );

drop policy if exists call_events_insert on public.call_signaling_events;
create policy call_events_insert on public.call_signaling_events
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.calls c
       where c.id = call_id
         and (c.initiator_id = auth.uid() or c.receiver_id = auth.uid())
    )
  );

-- invitations: admin read only (writes via RPC)
drop policy if exists invitations_select on public.invitations;
create policy invitations_select on public.invitations
  for select to authenticated
  using (public.is_admin());

drop policy if exists redemptions_select on public.invitation_redemptions;
create policy redemptions_select on public.invitation_redemptions
  for select to authenticated
  using (public.is_admin());

-- push tokens
drop policy if exists push_tokens_own on public.push_tokens;
create policy push_tokens_own on public.push_tokens
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- blocked users
drop policy if exists blocked_own on public.blocked_users;
create policy blocked_own on public.blocked_users
  for all to authenticated
  using (blocker_id = auth.uid())
  with check (blocker_id = auth.uid());

-- preferences
drop policy if exists preferences_own on public.user_preferences;
create policy preferences_own on public.user_preferences
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Realtime: durable changes for messages/receipts/calls.
do $$
begin
  begin
    alter publication supabase_realtime add table public.messages;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.message_receipts;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.calls;
  exception when duplicate_object then null;
  end;
end;
$$;

-- Private broadcast topics (typing/presence, call signaling).
do $$
begin
  if exists (select 1 from pg_tables where schemaname = 'realtime' and tablename = 'messages') then
    execute $p$
      drop policy if exists adoetz_conversation_read on realtime.messages;
      create policy adoetz_conversation_read on realtime.messages
        for select to authenticated
        using (
          realtime.topic() like 'conversation:%'
          and public.is_conversation_member(
            nullif(split_part(realtime.topic(), ':', 2), '')::uuid
          )
        );
      drop policy if exists adoetz_conversation_write on realtime.messages;
      create policy adoetz_conversation_write on realtime.messages
        for insert to authenticated
        with check (
          realtime.topic() like 'conversation:%'
          and public.is_conversation_member(
            nullif(split_part(realtime.topic(), ':', 2), '')::uuid
          )
        );
      drop policy if exists adoetz_user_topics on realtime.messages;
      create policy adoetz_user_topics on realtime.messages
        for select to authenticated
        using (
          realtime.topic() like 'user:%'
          and split_part(realtime.topic(), ':', 2) = auth.uid()::text
        );
      drop policy if exists adoetz_call_topics on realtime.messages;
      create policy adoetz_call_topics on realtime.messages
        for select to authenticated
        using (
          realtime.topic() like 'call:%'
          and exists (
            select 1 from public.calls c
             where c.id::text = split_part(realtime.topic(), ':', 2)
               and (c.initiator_id = auth.uid() or c.receiver_id = auth.uid())
          )
        );
      drop policy if exists adoetz_call_write on realtime.messages;
      create policy adoetz_call_write on realtime.messages
        for insert to authenticated
        with check (
          realtime.topic() like 'call:%'
          and exists (
            select 1 from public.calls c
             where c.id::text = split_part(realtime.topic(), ':', 2)
               and (c.initiator_id = auth.uid() or c.receiver_id = auth.uid())
          )
        );
    $p$;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Storage buckets + policies
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit)
values
  ('avatars', 'avatars', false, 5242880),
  ('attachments', 'attachments', false, 209715200)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit;

drop policy if exists avatars_read on storage.objects;
create policy avatars_read on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars');

drop policy if exists avatars_write on storage.objects;
create policy avatars_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists avatars_update on storage.objects;
create policy avatars_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists avatars_delete on storage.objects;
create policy avatars_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists attachments_read on storage.objects;
create policy attachments_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'attachments'
    and public.is_conversation_member(
      nullif(split_part(name, '/', 1), '')::uuid
    )
  );

drop policy if exists attachments_write on storage.objects;
create policy attachments_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'attachments'
    and public.is_conversation_member(
      nullif(split_part(name, '/', 1), '')::uuid
    )
  );

drop policy if exists attachments_delete on storage.objects;
create policy attachments_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'attachments'
    and exists (
      select 1 from public.attachment_objects a
       where a.storage_path = storage.objects.name
         and a.owner_id = auth.uid()
    )
  );
