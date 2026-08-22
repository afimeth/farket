-- Bulgu (backend, kritik → düzeltildi): request_verification() RPC'si ve
-- verification-selfies bucket'ı zaten kuruluydu (20260818120544_v41_verification.sql),
-- ama Android tarafında bunu çağıran hiçbir ekran yoktu — kullanıcı için doğrulama
-- talep etmenin fiilen bir yolu yoktu. verification_requests tablosunun hiç GRANT'ı
-- olmadığı için (kasıtlı, bkz. o migration) istemci kendi başvurusunun durumunu da
-- okuyamıyordu. Bu RPC, get_my_template_progress ile aynı desende, yalnızca "benim
-- durumum ne" sorusuna cevap veriyor.

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

  return 'none';
end;
$$;

grant execute on function public.get_my_verification_status() to authenticated;
