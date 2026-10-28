# Backend & release setup

Everything the app needs server-side, in order. Commands assume the Supabase
CLI (`supabase`) and Flutter are on `PATH`.

## 1. Supabase project

Create a project, note:

- **Project URL** — `https://<ref>.supabase.co`
- **anon (publishable) key** — shipped in the APK
- **service_role key** — server-side only, never in the app or the repo

```bash
supabase login
supabase link --project-ref <ref>
```

## 2. Apply migrations

```bash
supabase db push
```

Four migrations run in order:

| File | Contents |
|---|---|
| `20261028090000_schema.sql` | tables, constraints, RLS, storage buckets, realtime publication |
| `20261028090100_functions.sql` | RPCs (chat, calls, admin, invites), push enqueue triggers, rate limits |
| `20261028090200_push_dispatch.sql` | `claim_outbound_jobs` / `complete_outbound_job` for the dispatcher |
| `20261028090300_reactions_reports.sql` | message reactions, user reports, report review RPCs, realtime publication entry |
| `20261028090400_group_push.sql` | pushes a new message to every active member of the conversation, not just one peer |

The buckets `avatars` and `attachments` are created with their policies; sizes
are capped at 5 MB and 200 MB respectively — adjust the migration if you need
different limits, and keep the client checks in `lib/core/config/env.dart` in
step.

## 3. Auth settings

`supabase/config.toml` pins the important ones (sign-ups disabled, minimum
password 12, no email confirmation: registration is invite-gated and the Edge
Function creates the user already confirmed).

If you changed them in the dashboard instead, make sure these hold:

- Email provider **enabled**, sign-ups **disabled**
- Confirm email **off**
- Minimum password length **12**
- JWT expiry **3600 s**, refresh token rotation **on**

## 4. Deploy the Edge Functions

```bash
supabase functions deploy redeem-invite-register --no-verify-jwt
supabase functions deploy login-identifier     --no-verify-jwt
supabase functions deploy username-availability --no-verify-jwt
supabase functions deploy dispatch-push        --no-verify-jwt
```

`verify_jwt` is off for all four by design: registration and username sign-in
happen before a session exists, and the dispatcher is authenticated by a shared
secret instead of a user token. `supabase/config.toml` records the same flags.

### Function secrets

```bash
# Firebase service account JSON, one line, from Google Cloud / Firebase console
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(tr -d '\n' < service-account.json)"

# Shared secret the scheduler sends as x-dispatch-secret
supabase secrets set PUSH_DISPATCH_SECRET="$(openssl rand -hex 32)"
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are injected
by the platform; do not set them yourself.

## 5. Firebase / FCM

1. Firebase console → add an **Android** app with package
   `com.adoetzchat.messenger`.
2. Download `google-services.json` into `android/app/`.
3. Cloud Messaging API must be enabled in the Google Cloud project.
4. Create a service account with the **Firebase Cloud Messaging API** role,
   download its JSON key, and set it as `FIREBASE_SERVICE_ACCOUNT` above.

Notification channels (`messages`, `calls`) are created by the app on first
launch; the FCM payloads target them by id.

## 6. Schedule the push dispatcher

Enable `pg_cron` and `pg_net` in the dashboard (Database → Extensions), then in
the SQL editor:

```sql
select cron.schedule(
  'adoetz-dispatch-push',
  '* * * * *',
  $$
  select net.http_post(
    url     := 'https://<ref>.supabase.co/functions/v1/dispatch-push',
    headers := jsonb_build_object(
                 'content-type', 'application/json',
                 'x-dispatch-secret', '<PUSH_DISPATCH_SECRET>'
               ),
    body    := '{}'::jsonb
  );
  $$
);
```

The dispatcher claims up to 50 due jobs per run, sends them through FCM HTTP
v1, retries failures with exponential backoff (30 s → 15 min, 5 attempts), and
revokes tokens FCM reports as unregistered. Jobs for users whose notification
privacy is `none` are never queued.

Message pushes carry a `notification` block, so Android draws the tray
notification itself. Call pushes are **data-only**: the app's FCM background
handler raises the native CallKit screen, which is the only way a call can ring
and be answered while the app is closed. They also expire after 45 s, matching
the server's ring window.

Because a minute of cron delay would eat most of that window, self-hosted
instances that run their own timer should dispatch more often. This instance
uses a systemd timer at 10 s:

```ini
# /etc/systemd/system/adoetz-push-dispatch.service
[Unit]
Description=Adoetz Chat push dispatch
After=network-online.target docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/adoetz-push-dispatch
TimeoutStartSec=60
```

```ini
# /etc/systemd/system/adoetz-push-dispatch.timer
[Unit]
Description=Run the Adoetz Chat push dispatcher every 10 seconds

[Timer]
OnBootSec=30s
OnUnitActiveSec=10s
AccuracySec=1s
Unit=adoetz-push-dispatch.service

[Install]
WantedBy=timers.target
```

`adoetz-push-dispatch` is a two-line script that reads `PUSH_DISPATCH_SECRET`
from the instance `.env` and POSTs to `http://127.0.0.1:8000/functions/v1/adoetz-push`.
Enable it with `systemctl enable --now adoetz-push-dispatch.timer`.

## 7. First admin

Users are always created as `user`. Bootstrap the first administrator in the
SQL editor (service role):

```sql
update public.user_roles
   set role = 'admin'
 where user_id = (select id from auth.users where email = 'owner@example.com');

insert into public.admin_audit_logs (actor_id, action, reason, result, metadata)
values (null, 'bootstrap_admin', 'initial owner bootstrap', 'success', '{}'::jsonb);
```

From then on, role changes happen in the in-app admin panel and are audited.
The panel can create the first invitation and show its one-time code.

## 8. TURN for calls

STUN alone works on most home networks; symmetric NAT / mobile carriers need
TURN. Run coturn with TLS and static-auth credentials, then build with:

```
--dart-define=TURN_URL=turn:turn.example.com:3478
--dart-define=TURN_USERNAME=...
--dart-define=TURN_CREDENTIAL=...
```

Only publishable TURN credentials belong in the APK. If you issue ephemeral
credentials server-side, hand them to the app through your own authenticated
endpoint instead of these defines.

## 9. Build and sign locally

```bash
keytool -genkey -v -keystore android/app/upload-keystore.jks \
        -keyalg RSA -keysize 2048 -validity 10000 -alias adoetz
cp android/key.properties.example android/key.properties   # fill in
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon key>
```

Without `android/key.properties` the release build falls back to debug signing
(fine for local testing, never for distribution).

## 10. CI secrets

| Secret | Used by |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `android-release.yml` — `base64 -w0 upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | release signing |
| `ANDROID_KEY_ALIAS` | release signing |
| `ANDROID_KEY_PASSWORD` | release signing |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | build-time `--dart-define` |
| `STUN_URL`, `TURN_URL`, `TURN_USERNAME`, `TURN_CREDENTIAL` | optional call config |
| `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD` | `supabase.yml` deploy workflow |

Tag a release with `git tag v1.0.0 && git push origin v1.0.0`; the workflow
attaches the APK and `SHA256SUMS.txt` to the GitHub Release.

## 11. Smoke test

1. Create an invitation as admin, copy the code.
2. Register a second account with it; confirm the code is now used.
3. Sign in with the **username** (not the email) on another device.
4. Send text, photo, voice note and document both ways; check receipts.
5. Background the receiver: push arrives with sender name only.
6. Long-press a message to react, forward it, and search for its text inside
   the chat; the reaction must appear on the other device within a second.
7. Report a message without checking consent, then with it checked; confirm the
   report appears under **Admin → Laporan** and that only the consented report
   carries `shared_content`.
8. Start an audio call, answer, hang up; verify history on both devices.
9. Suspend the account from the admin panel; the app should show the blocked
   screen on next foreground.

## 12. Running next to another application

The production instance (`supabase.adoetz52.my.id`) already hosts another app in
`public`, so this deployment isolates everything it can:

| Thing | Where |
|---|---|
| Tables, RPCs | schema `waclonegem`, helpers in `waclonegem_private` |
| PostgREST | `PGRST_DB_SCHEMAS` includes `waclonegem`; the app pins it with `PostgrestClientOptions(schema: Env.dbSchema)` |
| Realtime | tables published on `supabase_realtime`; every `onPostgresChanges` subscription passes `schema: Env.dbSchema` — the argument does not follow the PostgREST client's schema |
| Edge Functions | `adoetz-login`, `adoetz-register`, `adoetz-username`, `adoetz-push`, `adoetz-turn` |
| Storage | `avatars`, `attachments` (global by nature, but policies are app-specific) |

Migrations stay the source of truth in `public`/`private`; the SQL applied to
this instance is generated:

```bash
bash supabase/scripts/to-schema.sh waclonegem build/sql-waclonegem
for f in build/sql-waclonegem/*.sql; do
  psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f "$f"
done
```

The generated `zz-role-grants.sql` mirrors the API-role grants Supabase normally
gives `public`, and drops the invite-only trigger the migrations put on
`auth.users` — `auth.users` is shared, and that trigger would reject the other
app's sign-ups. Registration stays invite-only because `adoetz-register` and
`finalize_registration` are the only paths into the app.

The other app installs its own `private.on_signup` trigger that rejects any
user without its `invite_code` marker. Adoetz Chat users are recognised by the
invite reservation `redeem_invite_token` writes just before `createUser`, so a
one-time shim lets them through:

```sql
-- see the deployment notes; the check is
--   exists (select 1 from waclonegem_private.invite_reservations r
--            where r.email = new.email and r.created_at > now() - interval '1 hour')
```

### TURN

coturn (`adoetz-turn`) runs with `static-auth-secret`, so the APK carries no TURN
password. `adoetz-turn` mints `<expiry>:<user id>` / base64(HMAC-SHA1) pairs for
signed-in users; the client asks for one before each call and falls back to
`--dart-define=TURN_USERNAME/TURN_CREDENTIAL` only when those are supplied
explicitly. The coturn secret lives in the functions runtime
(`ADOETZ_TURN_CONFIG_B64`), never in the app.
