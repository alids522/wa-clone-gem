// Service-role Supabase client for the Edge Functions.
//
// The service role key is injected by the Supabase platform into the function
// runtime only. It must never be shipped in the Flutter app or committed.

import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2.45.4';

function required(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`missing env: ${name}`);
  return value;
}

export function adminClient(): SupabaseClient {
  return createClient(required('SUPABASE_URL'), required('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

/** Anon client, used only to verify a password the way the app would. */
export function anonClient(): SupabaseClient {
  return createClient(required('SUPABASE_URL'), required('SUPABASE_ANON_KEY'), {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
