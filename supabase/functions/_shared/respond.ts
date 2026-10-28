// Shared HTTP helpers for the Adoetz Chat Edge Functions.
//
// Every function answers JSON, never HTML, so the Flutter client can read
// `code` / `message` on failure and `success` on success.

import type { SupabaseClient } from 'npm:@supabase/supabase-js@2.45.4';

export const corsHeaders: Record<string, string> = {
  'access-control-allow-origin': '*',
  'access-control-allow-headers':
    'authorization, x-client-info, apikey, content-type, x-dispatch-secret',
  'access-control-allow-methods': 'POST, OPTIONS',
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'content-type': 'application/json; charset=utf-8' },
  });
}

export function fail(code: string, message: string, status = 400): Response {
  return json({ success: false, code, message }, status);
}

export function preflight(req: Request): Response | null {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  return null;
}

export async function readJson(req: Request): Promise<Record<string, unknown>> {
  try {
    const value = await req.json();
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      return value as Record<string, unknown>;
    }
  } catch {
    // fall through
  }
  return {};
}

export function str(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

/** First IP in `x-forwarded-for`, used only as a rate-limit bucket key. */
export function clientIp(req: Request): string {
  const forwarded = req.headers.get('x-forwarded-for') ?? '';
  const first = forwarded.split(',')[0]?.trim();
  return first && first.length > 0 ? first : 'unknown';
}

/** Per-bucket limiter backed by `public.hit_rate_limit` (service role only). */
export async function limited(
  admin: SupabaseClient,
  bucket: string,
  limit: number,
  windowSeconds: number,
): Promise<boolean> {
  const { data, error } = await admin.rpc('hit_rate_limit', {
    p_bucket: bucket,
    p_limit: limit,
    p_window_seconds: windowSeconds,
  });
  if (error) {
    console.error('hit_rate_limit failed', error);
    return false; // never lock users out because the limiter itself broke
  }
  return data === true;
}
