// Firebase Cloud Messaging HTTP v1 sender.
//
// Authenticates with the service-account JSON in `FIREBASE_SERVICE_ACCOUNT`
// (a function secret). The service account key stays inside the Edge Function
// runtime; it is never part of the APK, the repo, or any client.

export interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

export function serviceAccount(): ServiceAccount | null {
  // Self-hosted runtimes often inject the JSON base64-encoded to survive env
  // parsing, so accept either form.
  const encoded = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_B64');
  const raw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ??
    (encoded ? new TextDecoder().decode(Uint8Array.from(atob(encoded), (c) => c.charCodeAt(0))) : '');
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as Partial<ServiceAccount>;
    if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
      return null;
    }
    return {
      project_id: parsed.project_id,
      client_email: parsed.client_email,
      private_key: parsed.private_key,
    };
  } catch {
    return null;
  }
}

let cachedToken: { token: string; expiresAt: number } | null = null;

const encoder = new TextEncoder();

function base64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64UrlJson(value: unknown): string {
  return base64Url(encoder.encode(JSON.stringify(value)));
}

async function importKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const raw = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    'pkcs8',
    raw,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

async function accessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt - 120 > now) return cachedToken.token;

  const unsigned = `${base64UrlJson({ alg: 'RS256', typ: 'JWT' })}.${base64UrlJson({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  })}`;

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    await importKey(sa.private_key),
    encoder.encode(unsigned),
  );
  const assertion = `${unsigned}.${base64Url(new Uint8Array(signature))}`;

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!response.ok) {
    throw new Error(`oauth ${response.status}: ${await response.text()}`);
  }
  const payload = (await response.json()) as { access_token?: string; expires_in?: number };
  if (!payload.access_token) throw new Error('oauth: no access_token');

  cachedToken = {
    token: payload.access_token,
    expiresAt: now + (payload.expires_in ?? 3600),
  };
  return cachedToken.token;
}

export interface PushMessage {
  token: string;
  title: string;
  body: string;
  data: Record<string, string>;
  /** Ringing calls must wake the device immediately. */
  highPriority?: boolean;
  /**
   * Send without a `notification` block so Android hands the payload to the
   * app's background handler instead of drawing a tray notification. Used for
   * calls, where the app raises the native CallKit screen itself.
   */
  dataOnly?: boolean;
  /** How long FCM may keep trying to deliver, in seconds. */
  ttlSeconds?: number;
}

export interface PushResult {
  ok: boolean;
  status: number;
  /** Token is no longer registered with FCM. */
  unregistered: boolean;
  detail: string;
}

export async function sendPush(sa: ServiceAccount, message: PushMessage): Promise<PushResult> {
  const token = await accessToken(sa);
  const android: Record<string, unknown> = {
    priority: message.highPriority ? 'high' : 'normal',
  };
  if (message.ttlSeconds) android.ttl = `${message.ttlSeconds}s`;
  if (!message.dataOnly) {
    android.notification = {
      // Must match the channels created in lib/core/services/push_service.dart.
      channel_id: message.highPriority ? 'calls' : 'messages',
      sound: 'default',
      default_vibrate_timings: true,
    };
  }
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
    {
      method: 'POST',
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token: message.token,
          ...(message.dataOnly
            ? {}
            : { notification: { title: message.title, body: message.body } }),
          data: message.data,
          android,
        },
      }),
    },
  );

  const detail = await response.text();
  return {
    ok: response.ok,
    status: response.status,
    // FCM answers 404 UNREGISTERED / 400 INVALID_ARGUMENT for stale tokens.
    unregistered:
      response.status === 404 ||
      detail.includes('UNREGISTERED') ||
      detail.includes('INVALID_ARGUMENT'),
    detail,
  };
}
