-- Farket v4.1 — sonraki fazlar, Faz 4/6: doğrulama akışı.
--
-- v1'de onay/red ELLE yapılacak (Studio üzerinden doğrudan
-- `update verification_requests set status=..., reviewed_at=now()` +
-- onaylanıyorsa `update profiles set verified_at=now()`) — fotoğraf
-- moderasyonuyla aynı desen (Migration 1). Burada yalnızca başvuru
-- (request_verification) ve selfie'nin özel/kapalı Storage bucket'ı var;
-- bir onay/red RPC'si YOK, kasıtlı olarak.

-- =========================================================================
-- 1) Bucket — private, yalnızca sahibi kendi selfie'sini yükleyip
-- görebilir. profile-photos'tan AYRI: farklı hassasiyet sınıfı (kimlik
-- doğrulama amaçlı, hiçbir zaman başka bir kullanıcıya gösterilmeyecek),
-- farklı adlandırma kuralı gerektirmiyor (tek dosya, _thumb/_full yok).
-- =========================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('verification-selfies', 'verification-selfies', false, 5242880, array['image/webp', 'image/jpeg', 'image/png'])
on conflict (id) do nothing;

create policy verification_selfies_insert_own
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'verification-selfies'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy verification_selfies_select_own
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'verification-selfies'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- =========================================================================
-- 2) request_verification — yolu 'verification-selfies' bucket'ında,
-- '{auth.uid()}/...' ile başlamalı (RLS zaten bunu zorluyor, burada ayrıca
-- doğrulanmıyor — yükleme başarısız olmadan bu fonksiyona gelinemez).
-- =========================================================================
create or replace function public.request_verification(p_selfie_path text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'Oturum açılmamış';
  end if;

  if exists (select 1 from public.profiles where id = v_uid and verified_at is not null) then
    raise exception 'Zaten doğrulanmışsın';
  end if;

  if exists (select 1 from public.verification_requests where profile_id = v_uid and status = 'pending') then
    raise exception 'Zaten bekleyen bir doğrulama başvurun var';
  end if;

  insert into public.verification_requests (profile_id, selfie_path)
    values (v_uid, p_selfie_path);

  return jsonb_build_object('status', 'pending');
end;
$$;

revoke execute on function public.request_verification(text) from public;
grant execute on function public.request_verification(text) to authenticated;
