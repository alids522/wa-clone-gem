// Invite-only registration.
//
// Validates the invite code, reserves one use, creates the auth user with the
// invite id in `raw_app_meta_data`, then finalizes the profile through the
// database RPC. Any failure after the reservation releases the invite so a
// broken sign-up never burns a code.
//
// verify_jwt = false: the caller is not signed in yet.

import { adminClient } from '../_shared/admin.ts';
import { clientIp, fail, json, limited, preflight, readJson, str } from '../_shared/respond.ts';

const USERNAME_RE = /^[a-z][a-z0-9_]{2,23}$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MIN_PASSWORD = 12; // matches Validators.password in the client
const MAX_PASSWORD = 72;

Deno.serve(async (req) => {
  const options = preflight(req);
  if (options) return options;
  if (req.method !== 'POST') return fail('METHOD_NOT_ALLOWED', 'Gunakan POST.', 405);

  const body = await readJson(req);
  const inviteCode = str(body.invite_code);
  const username = str(body.username).toLowerCase();
  const email = str(body.email).toLowerCase();
  const password = typeof body.password === 'string' ? body.password : '';
  const displayName = str(body.display_name);

  if (inviteCode.length < 8) {
    return fail('INVITE_INVALID', 'Kode undangan tidak valid.');
  }
  if (!USERNAME_RE.test(username)) {
    return fail(
      'USERNAME_INVALID',
      'Username harus 3–24 karakter, diawali huruf, hanya huruf kecil, angka, dan garis bawah.',
    );
  }
  if (!EMAIL_RE.test(email)) {
    return fail('EMAIL_INVALID', 'Alamat email tidak valid.');
  }
  if (password.length < MIN_PASSWORD || password.length > MAX_PASSWORD) {
    return fail('PASSWORD_WEAK', 'Kata sandi minimal 12 karakter.');
  }
  if (displayName.length < 1 || displayName.length > 40) {
    return fail('NAME_INVALID', 'Nama tampilan harus 1–40 karakter.');
  }

  const admin = adminClient();

  const ip = clientIp(req);
  if (await limited(admin, `register:ip:${ip}`, 10, 3600)) {
    return fail('RATE_LIMITED', 'Terlalu banyak percobaan. Coba lagi nanti.', 429);
  }

  const { data: taken, error: takenError } = await admin
    .from('profiles')
    .select('user_id')
    .eq('username', username)
    .maybeSingle();
  if (takenError) {
    console.error('username lookup failed', takenError);
    return fail('SERVER_ERROR', 'Terjadi kesalahan. Coba lagi.', 500);
  }
  if (taken) {
    return fail('USERNAME_TAKEN', 'Username sudah dipakai.');
  }

  const { data: invitationId, error: redeemError } = await admin.rpc('redeem_invite_token', {
    p_token: inviteCode,
    p_email: email,
  });
  if (redeemError) {
    const raw = String(redeemError.message ?? '');
    if (raw.includes('INVITE_EXPIRED')) {
      return fail('INVITE_EXPIRED', 'Kode undangan sudah kedaluwarsa.');
    }
    if (raw.includes('INVITE_REVOKED')) {
      return fail('INVITE_REVOKED', 'Kode undangan sudah dicabut.');
    }
    if (raw.includes('INVITE_USED')) {
      return fail('INVITE_USED', 'Kode undangan sudah habis dipakai.');
    }
    return fail('INVITE_INVALID', 'Kode undangan tidak valid.');
  }

  const release = async () => {
    await admin
      .rpc('release_invite_token', { p_invitation_id: invitationId, p_email: email })
      .then(({ error }) => {
        if (error) console.error('release_invite_token failed', error);
      });
  };

  const created = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true, // invite-only: the code is the proof, there is no mailer
    app_metadata: { adoetz_invite_id: invitationId },
    user_metadata: { display_name: displayName, username },
  });
  if (created.error || !created.data.user) {
    await release();
    const raw = String(created.error?.message ?? '');
    if (/already|registered|exists/i.test(raw)) {
      return fail('EMAIL_TAKEN', 'Email sudah terdaftar.');
    }
    console.error('createUser failed', created.error);
    return fail('REGISTER_FAILED', 'Pendaftaran gagal. Coba lagi.', 500);
  }

  const userId = created.data.user.id;
  const { data: profile, error: finalizeError } = await admin.rpc('finalize_registration', {
    p_user_id: userId,
    p_username: username,
    p_display_name: displayName,
  });

  if (finalizeError) {
    await admin.auth.admin.deleteUser(userId).catch((error) => {
      console.error('deleteUser rollback failed', error);
    });
    await release();
    const raw = String(finalizeError.message ?? '');
    if (raw.includes('23505') || raw.includes('duplicate key')) {
      return fail('USERNAME_TAKEN', 'Username sudah dipakai.');
    }
    console.error('finalize_registration failed', finalizeError);
    return fail('REGISTER_FAILED', 'Pendaftaran gagal. Coba lagi.', 500);
  }

  return json({
    success: true,
    user_id: userId,
    username,
    display_name: profile?.display_name ?? displayName,
  });
});
