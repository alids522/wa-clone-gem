// Short-lived TURN credentials for the caller's own WebRTC session.
//
// coturn runs with `static-auth-secret`, so credentials are minted the REST
// way: the username is `<expiry>:<user id>` and the password is
// base64(HMAC-SHA1(secret, username)). Handing every signed-in user its own
// hour-long pair keeps a long-lived TURN password out of the APK, and coturn
// stops honouring the pair once the timestamp passes.
//
// verify_jwt = false in this deployment (the runtime checks functions
// globally), so the bearer token is validated here instead.

import { adminClient, anonClient } from '../_shared/admin.ts';
import { fail, json, preflight } from '../_shared/respond.ts';

// Publishable: the relay's address is not a secret, only the shared key is.
const DEFAULT_URLS =
  'turn:turn.adoetz52.my.id:3478?transport=udp,turn:turn.adoetz52.my.id:3478?transport=tcp';
const TTL_SECONDS = 3600;

interface TurnConfig {
  secret: string;
  urls: string[];
}

function decodeBase64(value: string): string {
  try {
    const bytes = Uint8Array.from(atob(value), (char) => char.charCodeAt(0));
    return new TextDecoder().decode(bytes);
  } catch {
    return '';
  }
}

/** The deployment keeps the coturn JSON (secret + urls) base64-encoded in one
 *  env var so the compose file stays readable; a plain secret wins if set. */
function turnConfig(): TurnConfig {
  const urls = (Deno.env.get('TURN_URLS') ?? DEFAULT_URLS)
    .split(',')
    .map((url) => url.trim())
    .filter((url) => url.length > 0);

  const direct = Deno.env.get('TURN_STATIC_AUTH_SECRET');
  if (direct) return { secret: direct, urls };

  const encoded = Deno.env.get('ADOETZ_TURN_CONFIG_B64');
  if (encoded) {
    try {
      const parsed = JSON.parse(decodeBase64(encoded)) as {
        secret?: string;
        urls?: string[];
      };
      if (parsed.secret) {
        return { secret: parsed.secret, urls: parsed.urls?.length ? parsed.urls : urls };
      }
    } catch {
      // fall through to the error below
    }
  }
  throw new Error('missing env: TURN_STATIC_AUTH_SECRET / ADOETZ_TURN_CONFIG_B64');
}

function base64(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

async function credentialFor(secret: string, username: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-1' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(username));
  return base64(new Uint8Array(signature));
}

Deno.serve(async (req) => {
  const options = preflight(req);
  if (options) return options;
  if (req.method !== 'POST' && req.method !== 'GET') {
    return fail('METHOD_NOT_ALLOWED', 'Gunakan GET atau POST.', 405);
  }

  const token = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!token) return fail('AUTH_REQUIRED', 'Masuk terlebih dahulu.', 401);

  const { data: userData, error: userError } = await anonClient().auth.getUser(token);
  if (userError || !userData.user) {
    return fail('AUTH_REQUIRED', 'Sesi tidak valid. Masuk ulang.', 401);
  }

  // A suspended account must not be handed relay credentials either.
  const { data: status, error: statusError } = await adminClient()
    .from('account_status')
    .select('status')
    .eq('user_id', userData.user.id)
    .maybeSingle();
  if (statusError) {
    console.error('account_status lookup failed', statusError);
    return fail('SERVER_ERROR', 'Terjadi kesalahan. Coba lagi.', 500);
  }
  if (status && status.status !== 'active') {
    return fail('FORBIDDEN', 'Akun ini sedang dibatasi.', 403);
  }

  try {
    const config = turnConfig();
    const username = `${Math.floor(Date.now() / 1000) + TTL_SECONDS}:${userData.user.id}`;
    return json({
      urls: config.urls,
      username,
      credential: await credentialFor(config.secret, username),
      ttl: TTL_SECONDS,
    });
  } catch (error) {
    console.error('turn credential minting failed', error);
    return fail('TURN_UNAVAILABLE', 'Server relay tidak tersedia.', 503);
  }
});
