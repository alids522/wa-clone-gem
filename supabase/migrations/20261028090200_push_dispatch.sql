-- Adoetz Chat - outbound job claiming for the dispatch-push Edge Function.
--
-- Triggers enqueue a row in public.outbound_jobs for every message and ringing
-- call. The dispatch-push function claims a batch, sends it through FCM, then
-- reports the outcome. Claiming uses SKIP LOCKED so concurrent runs never send
-- the same notification twice.

create or replace function public.claim_outbound_jobs(p_limit integer default 50)
returns setof public.outbound_jobs
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with claimed as (
    select id
      from public.outbound_jobs
     where status = 'queued'
       and next_attempt_at <= now()
     order by next_attempt_at
     limit greatest(1, least(coalesce(p_limit, 50), 200))
     for update skip locked
  )
  update public.outbound_jobs j
     set status = 'sending',
         retry_count = j.retry_count + 1,
         updated_at = now()
    from claimed c
   where j.id = c.id
  returning j.*;
end;
$$;
revoke all on function public.claim_outbound_jobs(integer) from public, anon, authenticated;
grant execute on function public.claim_outbound_jobs(integer) to service_role;

create or replace function public.complete_outbound_job(
  p_id uuid,
  p_status text,
  p_error text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_retry integer;
begin
  if p_status not in ('sent', 'failed', 'dead') then
    raise exception 'INVALID_STATUS' using errcode = '22023';
  end if;

  select retry_count into v_retry from public.outbound_jobs where id = p_id;
  if not found then
    return;
  end if;

  update public.outbound_jobs
     set status = p_status,
         updated_at = now(),
         next_attempt_at = case
           when p_status = 'failed'
             then now() + make_interval(secs => least(30 * power(2, v_retry), 900))
           else next_attempt_at
         end
   where id = p_id;

  if p_status = 'dead' and p_error is not null then
    raise log 'outbound job % died: %', p_id, p_error;
  end if;
end;
$$;
revoke all on function public.complete_outbound_job(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.complete_outbound_job(uuid, text, text) to service_role;

create index if not exists outbound_jobs_due
  on public.outbound_jobs (next_attempt_at)
  where status = 'queued';

create index if not exists outbound_jobs_sending
  on public.outbound_jobs (updated_at)
  where status = 'sending';
