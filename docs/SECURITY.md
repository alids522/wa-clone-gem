# Security notes & threat model

## What the server can see

- Account identity: username, email (auth schema), display name, avatar, bio.
- Conversation membership, message timestamps, sender, message type, sizes.
- Ciphertext of every message, attachment and edit; per-file attachment keys
  are inside the encrypted message body.
- Call metadata: participants, start/end, kind, state transitions.
- Push tokens and outbound job rows.

The server **cannot** read message text, attachment contents, or call media.
There is no plaintext logging of message content in the client (error paths log
codes, not bodies).

## Keys

| Key | Where it lives | Who has it |
|---|---|---|
| Supabase anon key | APK (`--dart-define`) | publishable; RLS is the boundary |
| Supabase service_role key | Edge Function runtime only | platform |
| Firebase service account | Edge Function secret | platform |
| TURN credentials | build define (publishable) or your own endpoint | app |
| Signal identity/prekeys | SQLCipher DB + Keystore-wrapped key | device |
| Local DB password | Android Keystore via `flutter_secure_storage` | device |
| App-lock PIN | salted, iterated SHA-256 hash in secure storage | device |
| Release keystore | CI secret / local file, git-ignored | release manager |

Consequences enforced in the repo:

- No `service_role`, service-account JSON, TURN secret or keystore is ever
  passed through `--dart-define` or committed.
- `android/key.properties`, `*.jks`, `*.keystore` and local secrets are
  git-ignored; the release workflow deletes signing material after the build.
- The app never talks to `auth.admin`; every privileged operation is a
  `SECURITY DEFINER` RPC that re-checks the caller's role and status.

## Authorization

- RLS is enabled on every table. Policies are membership-based: a user can read
  a conversation's rows only if `conversation_members` lists them.
- Admin RPCs (`admin_*`), invite RPCs and login helpers are granted to
  `service_role` only, or to `authenticated` with an internal `is_admin()`
  check; `public`/`anon` are revoked.
- Suspended/banned accounts are rejected server-side, not just in the UI.
- One active device per account: registering keys from a new device flags a
  conflict and requires the transfer flow, which prevents silent device
  cloning.

## Invite-only sign-up

- Codes are random 128-bit values; only their SHA-256 hash is stored.
- A code has max uses, expiry, optional intended recipient and an audit trail.
- Redemption reserves a use before the user is created; any failure releases
  it, so a failed sign-up cannot burn a code.
- Registration and login are rate-limited per IP and per identifier through
  `hit_rate_limit` (server-side, service role only).
- Login by username resolves the email server-side and answers a generic error
  for unknown identifiers, missing accounts and wrong passwords alike.

## Privacy features

- Notification privacy: `full` (sender + type), `sender` (name only), `none`
  (no job is queued at all).
- Read receipts and typing indicators are user-toggled; servers honour the
  stored preference.
- Blocking is enforced in the send path and in push enqueueing.
- Admin dashboard shows account metadata only — never chat content. Reports are
  the only path by which an admin can see content, and the reporter explicitly
  chooses which message to share.
- Safe number verification (QR/fingerprint) surfaces identity-key changes; a
  changed key raises a warning before sending.

## Device hardening

- `FLAG_SECURE` on the main activity: screenshots and screen recording blocked.
- `allowBackup=false` plus data-extraction rules: no cloud backup of the
  database, preferences or cached files.
- SQLCipher database, key stored in the Android Keystore; the raw key never
  appears in preferences or logs.
- App lock: 4-digit PIN (salted, 24 000 SHA-256 iterations, constant-time
  compare) with biometric unlock, auto-lock timeout, and a 5-attempt cooldown.
- Release builds are minified/shrunk with R8 rules that keep SQLCipher, WebRTC
  and Firebase classes; debug symbols are uploaded as a separate artifact.

## Known gaps / accepted risks for v1.0

- Message timestamps, message types and metadata are visible to the server —
  unavoidable for delivery and push.
- Push notifications cannot include message text: the server has no plaintext.
  Generic bodies are the deliberate trade-off.
- A compromised device with an unlocked screen holds the messages; the app lock
  is a barrier, not a defense against a rooted attacker.
- TURN credentials passed as build defines are extractable from the APK. Use
  short-lived credentials from your own endpoint if that matters to you.
- 1:1 only: no group key management in v1.0.
- No independent security audit yet. Treat this as a solid baseline, not a
  certification.
