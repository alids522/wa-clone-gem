// Push dispatcher.
//
// Called on a schedule (pg_cron / Supabase scheduled function, every minute).
// Claims a batch of queued `outbound_jobs`, resolves the recipient's device
// token, sends one FCM HTTP v1 message per job, and records the outcome.
//
// Not a user-facing endpoint: `verify_jwt` is off because the caller is the
// scheduler, and every request must carry `x-dispatch-secret` matching the
// PUSH_DISPATCH_SECRET function secret.

import { adminClient } from '../_shared/admin.ts';
import { sendPush, serviceAccount, type PushMessage } from '../_shared/fcm.ts';
import { fail, json, preflight } from '../_shared/respond.ts';

interface Job {
  id: string;
  event_type: string;
  recipient_user_id: string | null;
  recipient_device_id: string | null;
  payload: Record<string, unknown>;
  retry_count: number;
}

interface TokenRow {
  token: string;
  device_id: string | null;
}

const MAX_ATTEMPTS = 5;

Deno.serve(async (req) => {
  const options = preflight(req);
  if (options) return options;
  if (req.method !== 'POST') return fail('METHOD_NOT_ALLOWED', 'Gunakan POST.', 405);

  const secret = Deno.env.get('PUSH_DISPATCH_SECRET');
  if (!secret || req.headers.get('x-dispatch-secret') !== secret) {
    return fail('UNAUTHORIZED', 'Tidak diizinkan.', 401);
  }

  const sa = serviceAccount();
  if (!sa) {
    return fail('CONFIG_ERROR', 'FIREBASE_SERVICE_ACCOUNT belum diset.', 500);
  }

  const admin = adminClient();
  const { data: jobs, error: claimError } = await admin.rpc('claim_outbound_jobs', {
    p_limit: 50,
  });
  if (claimError) {
    console.error('claim_outbound_jobs failed', claimError);
    return fail('SERVER_ERROR', 'Gagal mengambil antrean.', 500);
  }

  const batch = (jobs ?? []) as Job[];
  if (batch.length === 0) return json({ success: true, processed: 0 });

  const results: Array<{ id: string; status: string }> = [];

  for (const job of batch) {
    const finish = async (status: 'sent' | 'failed' | 'dead', error?: string) => {
      await admin
        .rpc('complete_outbound_job', { p_id: job.id, p_status: status, p_error: error ?? null })
        .then(({ error: rpcError }) => {
          if (rpcError) console.error('complete_outbound_job failed', rpcError);
        });
      results.push({ id: job.id, status });
    };

    if (!job.recipient_user_id) {
      await finish('dead', 'no recipient');
      continue;
    }

    const tokens = await tokensFor(admin, job.recipient_user_id, job.recipient_device_id);
    if (tokens.length === 0) {
      await finish('dead', 'no active push token');
      continue;
    }

    const message = await buildMessage(admin, job);
    if (!message) {
      await finish('dead', 'unknown event');
      continue;
    }

    let sent = 0;
    let unregistered = 0;
    let lastError = '';
    for (const row of tokens) {
      try {
        const result = await sendPush(sa, { ...message, token: row.token });
        if (result.ok) {
          sent += 1;
          continue;
        }
        lastError = `${result.status} ${result.detail}`.slice(0, 500);
        if (result.unregistered) {
          unregistered += 1;
          await admin
            .from('push_tokens')
            .update({ revoked_at: new Date().toISOString() })
            .eq('token', row.token)
            .then(({ error }) => {
              if (error) console.error('revoke push token failed', error);
            });
        }
      } catch (error) {
        lastError = String(error).slice(0, 500);
        console.error('sendPush threw', error);
      }
    }

    if (sent > 0) {
      await finish('sent');
    } else if (unregistered === tokens.length) {
      // Every device FCM knows about is gone; retrying cannot ever succeed and
      // would keep dead jobs in the queue for five minutes.
      await finish('dead', lastError || 'all push tokens unregistered');
    } else if (job.retry_count + 1 >= MAX_ATTEMPTS) {
      await finish('dead', lastError);
    } else {
      await finish('failed', lastError);
    }
  }

  return json({ success: true, processed: batch.length, results });
});

async function tokensFor(
  admin: ReturnType<typeof adminClient>,
  userId: string,
  deviceId: string | null,
): Promise<TokenRow[]> {
  let query = admin
    .from('push_tokens')
    .select('token, device_id')
    .eq('user_id', userId)
    .is('revoked_at', null);
  if (deviceId) query = query.eq('device_id', deviceId);
  const { data, error } = await query;
  if (error) {
    console.error('push token lookup failed', error);
    return [];
  }
  return (data ?? []) as TokenRow[];
}

async function buildMessage(
  admin: ReturnType<typeof adminClient>,
  job: Job,
): Promise<Omit<PushMessage, 'token'> | null> {
  if (job.event_type !== 'message' && job.event_type !== 'call') return null;

  const actorId =
    job.event_type === 'message' ? job.payload.sender_id : job.payload.initiator_id;
  const title = await displayName(admin, typeof actorId === 'string' ? actorId : null);

  if (job.event_type === 'call') {
    const kind = String(job.payload.kind ?? 'audio');
    // Data-only: the app's background handler raises the native CallKit
    // screen, which is the only thing that can ring and be answered while the
    // app is closed. A `notification` block would just draw a silent tray row.
    return {
      title,
      body: 'Panggilan masuk',
      highPriority: true,
      dataOnly: true,
      ttlSeconds: 45,
      data: {
        type: 'call',
        call_id: String(job.payload.call_id ?? ''),
        kind,
        initiator_name: title,
        initiator_id: String(job.payload.initiator_id ?? ''),
      },
    };
  }

  // Message bodies are end-to-end encrypted, so the notification can only
  // carry the sender, never the text. Privacy 'none' is filtered by the DB
  // trigger before a job is even queued.
  const privacy = await notificationPrivacy(admin, job.recipient_user_id);
  return {
    title,
    body: privacy === 'full' ? bodyForType(String(job.payload.message_type ?? 'text')) : 'Pesan baru',
    data: {
      type: 'message',
      conversation_id: String(job.payload.conversation_id ?? ''),
      message_id: String(job.payload.message_id ?? ''),
    },
  };
}

function bodyForType(type: string): string {
  switch (type) {
    case 'image':
      return 'Mengirim foto';
    case 'video':
      return 'Mengirim video';
    case 'audio':
      return 'Mengirim pesan suara';
    case 'document':
      return 'Mengirim dokumen';
    default:
      return 'Pesan baru';
  }
}

async function displayName(
  admin: ReturnType<typeof adminClient>,
  userId: string | null,
): Promise<string> {
  if (!userId) return 'Adoetz Chat';
  const { data } = await admin
    .from('profiles')
    .select('display_name')
    .eq('user_id', userId)
    .maybeSingle();
  return (data?.display_name as string | undefined) ?? 'Adoetz Chat';
}

async function notificationPrivacy(
  admin: ReturnType<typeof adminClient>,
  userId: string | null,
): Promise<string> {
  if (!userId) return 'sender';
  const { data } = await admin
    .from('user_preferences')
    .select('notification_privacy')
    .eq('user_id', userId)
    .maybeSingle();
  return (data?.notification_privacy as string | undefined) ?? 'sender';
}
