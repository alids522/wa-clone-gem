# Adoetz Chat

Private, invite-only messenger for Android, built to the Adoetz Chat PRD v1.0.
Flutter client + Supabase backend (Auth, PostgREST, Realtime, Storage, Edge
Functions) + Firebase Cloud Messaging + WebRTC calls.

| | |
|---|---|
| Package | `com.adoetzchat.messenger` |
| Platform | Android 10+ (SDK 29), Flutter 3.44 |
| Backend | Self-hosted or hosted Supabase |
| Messages | End-to-end encrypted (Signal Protocol, X25519 + AES-GCM) |
| Theme | Midnight Blue (dark) / Ice Blue (light), Bahasa Indonesia UI |
| Distribution | Signed APK from GitHub Actions releases |

## Features

**Accounts**
- Invite-only sign-up: a one-time (or limited-use) invite code is required; each
  code has a label, intended recipient, max uses and expiry.
- Sign in with **username or email** plus password; username is resolved to the
  auth email by an Edge Function, so the email is never shown in the app.
- Profile: display name, bio, avatar (Storage), username change audit trail.
- Account states: active / suspended / banned, with a blocking screen, plus
  device-conflict detection (one active device per account, transfer flows).
- App lock: 4-digit PIN (SHA-256, salted, iterated) with biometric unlock,
  configurable auto-lock timeout, 5-attempt cooldown.

**Chat**
- 1:1 conversations, realtime delivery and typing indicators.
- Text, images, video, voice notes, documents; image compression, upload
  progress, per-attachment encryption.
- Reply, edit, delete-for-everyone, delete-for-me, copy, forward, message
  reactions (6 emoji), read receipts, unread counters, in-chat search,
  pagination, shared-media browser.
- Offline-first: SQLCipher database keyed from the Android Keystore, message
  queue with retry, cached conversations and media.
- Presence, block/unblock, and reporting of a contact or a single message;
  message content is attached to a report only when the reporter opts in.
  Disappearing-message support exists in the data model.
- Privacy: read receipts and typing indicators toggles, notification privacy
  (full / sender only / none).

**Calls**
- Audio and video calls over WebRTC with Supabase Realtime signaling.
- Ringing/answered/declined/timeout state machine, mute, camera flip,
  speaker, call timer, in-app incoming-call overlay, call history.
- STUN by default; TURN configurable at build time for NAT-restricted networks.

**Notifications**
- FCM push for messages and incoming calls, dispatched from an Edge Function
  that reads `outbound_jobs`; deep links into the right chat or call.
- Local notifications, Android channels (`messages`, `calls`), per-user privacy.

**Admin**
- In-app dashboard (admin role only): totals, recent audit trail, user search
  and filters, role and status changes with mandatory reasons, invitation
  creation/revocation, report queue with status transitions, audit log search.
- Every privileged action is a `SECURITY DEFINER` RPC that re-checks the admin
  role server-side and writes to `admin_audit_logs`.

**Security**
- End-to-end encryption for message bodies and media; the server stores
  ciphertext only (`p:` / `s:` prefixed blobs).
- Row Level Security on every table; the app ships only the publishable anon
  key.
- `FLAG_SECURE` (screenshots blocked), backups disabled, R8 shrinking,
  certificate-pinned-by-policy network client.

## Repository layout

```
lib/
  app/            app shell, routing gate, theme, providers
  core/
    config/       build-time env (publishable values only)
    crypto/       Signal E2EE, media encryption, key store
    models/       profile, conversation, message, admin DTOs
    services/     auth, chat, call, admin, media, push, realtime
    storage/      SQLCipher local DB, secure key storage
    ui/ utils/    shared widgets, formatters, error mapping
  features/       auth, chats, calls, settings, admin, home, splash
supabase/
  migrations/     schema, RPCs, RLS, push enqueueing, job claiming
  functions/      redeem-invite-register, login-identifier,
                  username-availability, dispatch-push
android/          manifest, signing config, R8 rules, Firebase config
.github/workflows ci, signed APK release, Supabase deploy
docs/             setup, architecture, security
```

## Quick start

Prerequisites: Flutter 3.44+, Java 17, an Android device or emulator, and a
Supabase project with the migrations applied.

```bash
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://<project>.supabase.co \
            --dart-define=SUPABASE_ANON_KEY=<anon key>
```

`android/app/google-services.json` must belong to the Firebase Android app
`com.adoetzchat.messenger`.

Backend setup (migrations, Edge Functions, FCM service account, push cron,
first admin, TURN): see [docs/SETUP.md](docs/SETUP.md).
Design and threat model: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md),
[docs/SECURITY.md](docs/SECURITY.md).

## Build a signed APK

Locally:

```bash
cp android/key.properties.example android/key.properties   # fill in
flutter build apk --release
```

In CI, push a tag:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

The `Android release` workflow decodes the keystore from repository secrets,
builds an obfuscated universal APK, uploads it as an artifact and attaches it
(plus `SHA256SUMS.txt`) to the GitHub Release.

## Known limitations

- Message text cannot appear in push notifications: the server cannot decrypt
  what it relays, so bodies are generic ("Pesan baru", "Mengirim foto").
- Video calls need a TURN server to traverse symmetric NAT; the default build
  only ships STUN.
- WebRTC call quality is device- and network-dependent; the call data channel
  falls back to signaling-only when a peer connection cannot be established.
- iOS is out of scope for v1.0 (Android-first, per the PRD).
- Backup/restore of message history across devices is not implemented; the
  local database is device-bound.
