-- get_my_verification_status() never distinguished "rejected" from "never applied" — a
-- rejected verification_requests row (status check already allows 'rejected', see
-- 20260818110732_v41_additive_columns.sql) fell through to 'none' with no way for the
-- user to see their application was reviewed and declined. Add a rejected branch: most
-- recent request (by created_at) is rejected and there is no newer pending request.

create or replace function public.get_my_verification_status()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_verified_at timestamptz;
  v_pending boolean;
  v_latest_status text;
begin
  if v_uid is null then
    raise exception 'Oturum açılmamış';
  end if;

  select verified_at into v_verified_at from public.profiles where id = v_uid;
  if v_verified_at is not null then
    return 'verified';
  end if;

  select exists (
    select 1 from public.verification_requests
    where profile_id = v_uid and status = 'pending'
  ) into v_pending;

  if v_pending then
    return 'pending';
  end if;

  select status into v_latest_status
    from public.verification_requests
    where profile_id = v_uid
    order by created_at desc
    limit 1;

  if v_latest_status = 'rejected' then
    return 'rejected';
  end if;

  return 'none';
end;
$$;

grant execute on function public.get_my_verification_status() to authenticated;
