// Username-or-email sign-in.
//
// The app posts `{ identifier, password }`; this function resolves a username
// to its auth email server-side (the email is never exposed to the caller) and
// returns a session the app installs with `setSession`.
//
// verify_jwt = false: the caller has no session yet.

import { adminClient, anonClient } from '../_shared/admin.ts';
import { clientIp, fail, json, limited, preflight, readJson, str } from '../_shared/respond.ts';

const GENERIC = 'Username/email atau password tidak sesuai.';

Deno.serve(async (req) => {
  const options = preflight(req);
  if (options) return options;
  if (req.method !== 'POST') return fail('METHOD_NOT_ALLOWED', 'Gunakan POST.', 405);

  const body = await readJson(req);
  const identifier = str(body.identifier).toLowerCase();
  const password = typeof body.password === 'string' ? body.password : '';

  if (identifier.length < 3 || identifier.length > 254 || password.length === 0) {
    return fail('AUTH_FAILED', GENERIC, 401);
  }

  const admin = adminClient();
  const ip = clientIp(req);

  const [ipLimited, identifierLimited] = await Promise.all([
    limited(admin, `login:ip:${ip}`, 20, 600),
    limited(admin, `login:id:${identifier}`, 10, 600),
  ]);
  if (ipLimited || identifierLimited) {
    return fail('RATE_LIMITED', 'Terlalu banyak percobaan masuk. Coba lagi nanti.', 429);
  }

  const { data: email, error: lookupError } = await admin.rpc('lookup_login_email', {
    p_identifier: identifier,
  });
  if (lookupError) {
    console.error('lookup_login_email failed', lookupError);
    return fail('SERVER_ERROR', 'Terjadi kesalahan. Coba lagi.', 500);
  }
  if (!email) {
    return fail('AUTH_FAILED', GENERIC, 401);
  }

  const { data, error } = await anonClient().auth.signInWithPassword({
    email: email as string,
    password,
  });
  if (error || !data.session) {
    return fail('AUTH_FAILED', GENERIC, 401);
  }

  return json({
    success: true,
    access_token: data.session.access_token,
    refresh_token: data.session.refresh_token,
    expires_at: data.session.expires_at,
    user_id: data.session.user.id,
  });
});
