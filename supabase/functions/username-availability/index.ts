// Pre-flight username check for the sign-up form.
//
// Returns only `{ valid, available }`; it never lists accounts, so it cannot
// be used to enumerate users beyond the name you already guessed.

import { adminClient } from '../_shared/admin.ts';
import { clientIp, fail, json, limited, preflight, readJson, str } from '../_shared/respond.ts';

const USERNAME_RE = /^[a-z][a-z0-9_]{2,23}$/;
// Keep in sync with Validators.reservedUsernames in the Flutter client.
const RESERVED = new Set([
  'admin',
  'administrator',
  'root',
  'support',
  'system',
  'adoetz',
  'adoetzchat',
  'help',
  'security',
  'moderator',
  'official',
]);

Deno.serve(async (req) => {
  const options = preflight(req);
  if (options) return options;
  if (req.method !== 'POST') return fail('METHOD_NOT_ALLOWED', 'Gunakan POST.', 405);

  const username = str((await readJson(req)).username).toLowerCase();
  if (!USERNAME_RE.test(username)) {
    return json({ valid: false, available: false });
  }
  if (RESERVED.has(username)) {
    return json({ valid: true, available: false });
  }

  const admin = adminClient();
  if (await limited(admin, `username:ip:${clientIp(req)}`, 60, 60)) {
    return fail('RATE_LIMITED', 'Terlalu banyak percobaan. Coba lagi nanti.', 429);
  }

  const { data, error } = await admin
    .from('profiles')
    .select('user_id')
    .eq('username', username)
    .maybeSingle();
  if (error) {
    console.error('username lookup failed', error);
    return fail('SERVER_ERROR', 'Terjadi kesalahan. Coba lagi.', 500);
  }

  return json({ valid: true, available: data === null });
});
