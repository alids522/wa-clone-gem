# Architecture

## Layers

```
UI (features/)            screens, widgets, Riverpod controllers
        │
Services (core/services)  auth, chat, calls, media, admin, push, realtime
        │
Crypto (core/crypto)      Signal sessions, media keys, key store
Storage (core/storage)    SQLCipher database, secure key storage
        │
Supabase                  PostgREST RPCs · Realtime · Storage · Edge Functions
```

There is no business logic in screens: a screen watches a provider, the
provider calls a service, the service talks to Supabase and the local database.

`lib/app/dependencies.dart` wires the services once at startup; `providers.dart`
exposes them (and the controllers) to the widget tree.

## Startup

1. `main.dart` initializes date formatting (Bahasa Indonesia), secure storage,
   preferences, the SQLCipher database (key from the Android Keystore), the
   E2EE service, push and realtime.
2. `RootGate` switches on `AuthController.stage`:
   splash → welcome/sign-in → (device conflict | blocked) → home shell.
3. `AppLockGate` wraps the whole tree; when enabled and locked, it covers the
   app with the PIN/biometric screen and never routes away from it.

## Sending a message

1. `ChatController.send` creates a `ChatMessage` (local id, `pending`) and
   writes it to SQLCipher plus the `outbox` table, so it survives a crash.
2. `ChatRepository._queueAndSend` encrypts the body (and any attachment key)
   with the Signal session for the peer, producing `p:<base64>` (prekey) or
   `s:<base64>` (session) ciphertext.
3. It calls `rpc('send_message', ...)` with the opaque `client_message_id`.
   The RPC is idempotent: a retry returns the existing row instead of a
   duplicate.
4. On success the local row is replaced by the server row and the outbox entry
   is removed. Failures stay queued with exponential backoff and a manual retry.
5. Attachments: the file is encrypted client-side, uploaded to Storage under a
   path owned by the conversation, and an `attachment_objects` row records the
   metadata. The message body carries the per-file key, encrypted.

## Receiving

- `RealtimeService` subscribes to one channel, `adoetz:inbox`, listening to
  `messages`, `message_receipts`, `conversations`, `calls` and call-signaling
  inserts for the signed-in user. Events are broadcast to controllers.
- A new message is decrypted with the ratchet session, written to SQLCipher and
  triggers a delivered receipt; when the chat is open, a read receipt follows
  and the unread counter is reset.
- Catch-up: on reconnect and on foreground, `syncConversations` and
  `syncMessages` page over anything missed; the local database is the source of
  truth for the UI.

## Calls

`call_session.dart` owns the `RTCPeerConnection` and the local/remote
renderers:

1. `initiate_call` inserts a `calls` row (`ringing`, 40 s expiry).
2. Signaling uses `send_call_signal` / `get_call_signals` rows plus Realtime;
   offers, answers and ICE candidates are exchanged as opaque JSON.
3. The receiver can answer, decline or let it time out; `call_action` moves the
   state machine (`ringing → active → ended | missed | declined`).
4. `flutter_webrtc` renders audio/video; the session tears down the peer
   connection, tracks and renderers on every exit path (hang up, error,
   background timeout, widget disposal).

## Push

```
insert into messages/calls
        │  trigger (SECURITY DEFINER)
        ▼
public.outbound_jobs  ──(pg_cron every minute)──▶ dispatch-push (Deno)
        │                                              │
        │                                              ▼
        └───────────────────────────────────────▶  FCM HTTP v1
                                                       │
                                                       ▼
                                              device notification
```

The trigger skips blocked pairs and users with notification privacy `none`.
The dispatcher claims jobs with `FOR UPDATE SKIP LOCKED`, so overlapping runs
cannot double-send. Message notifications carry the sender's display name and a
generic body: the payload never contains plaintext the server does not have.

## Data model (public schema)

| Table | Purpose |
|---|---|
| `profiles`, `user_roles`, `account_status`, `user_preferences` | identity, role, status, privacy |
| `devices`, `signed_prekeys`, `one_time_prekeys` | Signal key material |
| `conversations`, `conversation_members`, `messages`, `message_receipts` | chat |
| `message_reactions` | per-user emoji reactions on a message |
| `attachment_objects` | storage metadata per uploaded file |
| `calls`, `call_signaling_events` | call state and WebRTC signaling |
| `invitations`, `invitation_redemptions`, `private.invite_reservations` | invite-only onboarding |
| `push_tokens`, `outbound_jobs` | notification delivery |
| `blocked_users`, `reports`, `admin_audit_logs` | safety and accountability |

Every table has RLS enabled. Mutations that need cross-row checks (sending,
receipts, calls, admin actions, invites) go through `SECURITY DEFINER` RPCs
that resolve `auth.uid()` themselves rather than trusting the client.

## Client state

Riverpod `StateNotifier` controllers per feature: auth, chat list, one chat,
call, settings, admin. Controllers never hold `BuildContext`; screens translate
errors with `mapError` and show them through `showAppSnack`.
