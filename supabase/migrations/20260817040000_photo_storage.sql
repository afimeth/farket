-- Farket: Storage entegrasyonu (Sonraki Adımlar Görev 4)
--
-- Mimari karar (kullanıcıyla netleştirildi): imzalı URL üretimi saf SQL ile
-- yapılamaz — Storage servisinin JWT secret'ı Postgres'e açık değil, pg_net
-- da bu iş için (senkron tek-istek/tek-cevap) uygun değil (asenkron/webhook
-- amaçlı). Bu yüzden "get_photo_urls() SECURITY DEFINER" fikri yerine,
-- görüntüleme hakkı doğrudan storage.objects üzerindeki bir RLS policy'sine
-- taşındı: istemci supabase.storage.from('profile-photos').createSignedUrl(path)
-- çağırır, Storage servisi bu SELECT policy'sini kimliklenmiş kullanıcı adına
-- otomatik uygular ve hak yoksa imzalama isteğini reddeder. Aynı sonucu
-- (yetkisiz kullanıcı asla imzalı URL alamaz) daha az hareketli parçayla
-- sağlıyor.
--
-- Yol biçimi: '{profile_id}/{random_uuid}_thumb.<ext>' veya
-- '..._full.<ext>' — hem sahiplik kontrolünü (ilk klasör = auth.uid())
-- hem "tahmin edilemez ad" kuralını (brifing madde 5) tek yapıda karşılar.

-- =========================================================================
-- 1) Bucket — private.
-- =========================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profile-photos', 'profile-photos', false, 5242880, array['image/webp', 'image/jpeg', 'image/png'])
on conflict (id) do nothing;

-- =========================================================================
-- 2) photos tablosu — tek storage_path yerine iki boyut.
-- Küçük (feed kapak/thumbnail) + tam çözünürlük (quiz sırasında gösterilen).
-- =========================================================================
alter table public.photos rename column storage_path to storage_path_full;
alter table public.photos add column storage_path_thumb text;
update public.photos set storage_path_thumb = storage_path_full where storage_path_thumb is null;
alter table public.photos alter column storage_path_thumb set not null;
alter table public.photos add constraint photos_storage_path_thumb_key unique (storage_path_thumb);

-- =========================================================================
-- 3) storage.objects RLS — bucket 'profile-photos' için.
-- =========================================================================
create policy profile_photos_insert_own
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and name ~ ('^' || (select auth.uid())::text || '/[0-9a-f-]{36}_(thumb|full)\.(webp|jpe?g|png)$')
  );

create policy profile_photos_update_own
  on storage.objects for update
  to authenticated
  using (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy profile_photos_delete_own
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- Görüntüleme (ve dolayısıyla imzalı URL alma) hakkı: sahibi HER ZAMAN
-- kendi fotoğrafını görebilir; başkası yalnızca fotoğrafın ait olduğu
-- profil AYNI ŞEHİRDE + yayınlanmış + onaylanmış + karşılıklı engelli
-- değil + gizli (3 ay) değilse görebilir. discover_profiles'ın kendi
-- filtre kümesiyle birebir aynı kurallar (madde bazlı tutarlılık için).
--
-- Bu kontrol bir SECURITY DEFINER fonksiyona taşındı: RLS policy'sinin
-- USING ifadesi çağıran rolün (authenticated) bağlamında çalışır, yani
-- inline bir exists() burada photos/profiles üzerindeki KENDİ RLS'lerine
-- (yalnızca kendi satırın) takılıp her zaman false dönerdi. SECURITY
-- DEFINER + postgres sahipliği (BYPASSRLS), get_public_profile'ın zaten
-- yaptığı gibi bu iç kontrolü RLS'ten muaf tutuyor.
create or replace function public.can_view_profile_photo_object(p_object_name text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id uuid := (select auth.uid());
begin
  if v_viewer_id is null then
    return false;
  end if;

  return exists (
    select 1
    from public.photos ph
    join public.profiles target on target.id = ph.profile_id
    join public.profiles viewer on viewer.id = v_viewer_id
    where (ph.storage_path_thumb = p_object_name or ph.storage_path_full = p_object_name)
      and ph.moderation_status = 'approved'
      and target.status = 'published'
      and target.city_id = viewer.city_id
      and not exists (
        select 1 from public.blocks b
        where (b.blocker_id = viewer.id and b.blocked_id = target.id)
           or (b.blocker_id = target.id and b.blocked_id = viewer.id)
      )
      and not exists (
        select 1 from public.hidden_profiles h
        where h.viewer_id = viewer.id and h.target_profile_id = target.id and h.hidden_until > now()
      )
  );
end;
$$;

revoke execute on function public.can_view_profile_photo_object(text) from public;
grant execute on function public.can_view_profile_photo_object(text) to authenticated;

create policy profile_photos_select_authorized
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'profile-photos'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or public.can_view_profile_photo_object(name)
    )
  );

-- =========================================================================
-- 4) get_public_profile / discover_profiles — iki yol da dönsün.
-- =========================================================================
create or replace function public.get_public_profile(p_profile_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id   uuid := (select auth.uid());
  v_profile     record;
  v_photos      jsonb;
  v_solve_rate  numeric;
begin
  if v_viewer_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  select p.id, p.username, c.name as city_name
    into v_profile
    from public.profiles p
    join public.cities c on c.id = p.city_id
    where p.id = p_profile_id and p.status = 'published';

  if not found then
    raise exception 'Profil bulunamadı veya yayınlanmamış';
  end if;

  if exists (
    select 1 from public.blocks
    where (blocker_id = v_viewer_id and blocked_id = p_profile_id)
       or (blocker_id = p_profile_id and blocked_id = v_viewer_id)
  ) then
    raise exception 'Bu profille etkileşim engellenmiş';
  end if;

  select jsonb_agg(
           jsonb_build_object(
             'id', ph.id, 'position', ph.position,
             'storage_path_thumb', ph.storage_path_thumb,
             'storage_path_full', ph.storage_path_full
           )
           order by ph.position
         )
    into v_photos
    from public.photos ph
    where ph.profile_id = p_profile_id and ph.moderation_status = 'approved';

  select case
           when count(*) filter (where qa.status in ('completed', 'failed_checkpoint')) = 0 then null
           else round(
             100.0 * count(*) filter (where qa.unlocked_tier > 0)
             / count(*) filter (where qa.status in ('completed', 'failed_checkpoint'))
           )
         end
    into v_solve_rate
    from public.quiz_attempts qa
    where qa.target_profile_id = p_profile_id;

  return jsonb_build_object(
    'id', v_profile.id,
    'username', v_profile.username,
    'city', v_profile.city_name,
    'photos', coalesce(v_photos, '[]'::jsonb),
    'solve_rate', v_solve_rate
  );
end;
$$;

create or replace function public.discover_profiles(p_limit int default 20)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id     uuid := (select auth.uid());
  v_viewer_city   int;
  v_calls_used    int;
  v_result        jsonb;
begin
  if v_viewer_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  select city_id into v_viewer_city from public.profiles where id = v_viewer_id;
  if v_viewer_city is null then
    raise exception 'Profilin bulunamadı';
  end if;

  select discover_calls_used into v_calls_used
    from public.daily_quotas
    where user_id = v_viewer_id and date = current_date;
  if coalesce(v_calls_used, 0) >= 200 then
    raise exception 'Günlük keşif çağrı kotan doldu';
  end if;

  insert into public.daily_quotas as dq (user_id, date, discover_calls_used)
    values (v_viewer_id, current_date, 1)
    on conflict (user_id, date)
    do update set discover_calls_used = dq.discover_calls_used + 1;

  select jsonb_agg(
           jsonb_build_object(
             'id', p.id,
             'username', p.username,
             'cover_photo_thumb', (
               select ph.storage_path_thumb from public.photos ph
               where ph.profile_id = p.id and ph.position = 1 and ph.moderation_status = 'approved'
             ),
             'photo_count', (
               select count(*) from public.photos ph2
               where ph2.profile_id = p.id and ph2.moderation_status = 'approved'
             ),
             'solve_rate', (
               select case
                        when count(*) filter (where qa.status in ('completed', 'failed_checkpoint')) = 0 then null
                        else round(
                          100.0 * count(*) filter (where qa.unlocked_tier > 0)
                          / count(*) filter (where qa.status in ('completed', 'failed_checkpoint'))
                        )
                      end
               from public.quiz_attempts qa
               where qa.target_profile_id = p.id
             )
           ) order by random()
         )
    into v_result
    from public.profiles p
    where p.id <> v_viewer_id
      and p.status = 'published'
      and p.city_id = v_viewer_city
      and p.username is not null
      and exists (
        select 1 from public.photos ph3
        where ph3.profile_id = p.id and ph3.position = 1 and ph3.moderation_status = 'approved'
      )
      and not exists (
        select 1 from public.blocks b
        where (b.blocker_id = v_viewer_id and b.blocked_id = p.id)
           or (b.blocker_id = p.id and b.blocked_id = v_viewer_id)
      )
      and not exists (
        select 1 from public.hidden_profiles h
        where h.viewer_id = v_viewer_id and h.target_profile_id = p.id and h.hidden_until > now()
      )
      and not exists (
        select 1 from public.skipped_profiles s
        where s.viewer_id = v_viewer_id and s.target_profile_id = p.id
      )
      and not exists (
        select 1 from public.quiz_attempts qa2
        where qa2.viewer_id = v_viewer_id and qa2.target_profile_id = p.id
      )
    limit p_limit;

  return coalesce(v_result, '[]'::jsonb);
end;
$$;

-- =========================================================================
-- 5) purge_deleted_accounts — fotoğraf yollarını, DB satırlarını silmeden
-- ÖNCE, dönüş değerine ekliyoruz. Storage'daki gerçek dosyaları silmek
-- storage-api'ye (service-role ile DELETE /storage/v1/object/...) bir HTTP
-- çağrısı gerektiriyor — bu da Postgres'in tek başına yapamadığı bir şey
-- (storage.objects üzerinde doğrudan DELETE, protect_objects_delete
-- trigger'ı tarafından engelleniyor). Bu yüzden fiziksel silme, bu
-- fonksiyonu çağıracak dış orkestratöre (henüz kurulmamış pg_cron/Edge
-- Function, bkz. bölüm 8 "Bilinen boşluklar") devrediliyor: o çağrı,
-- dönen 'deleted_photo_paths' listesini alıp Storage API'den siler.
-- =========================================================================
drop function if exists public.purge_deleted_accounts();

create function public.purge_deleted_accounts()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id        uuid;
  v_count             int := 0;
  v_all_paths         text[] := '{}';
  v_profile_paths     text[];
begin
  for v_profile_id in
    select id from public.profiles
    where status = 'deleted' and deleted_at < now() - interval '30 days'
  loop
    select coalesce(array_agg(storage_path_thumb), '{}') || coalesce(array_agg(storage_path_full), '{}')
      into v_profile_paths
      from public.photos where profile_id = v_profile_id;
    v_all_paths := v_all_paths || v_profile_paths;

    delete from public.photos where profile_id = v_profile_id;
    delete from public.custom_questions where profile_id = v_profile_id;
    delete from public.profile_template_answers where profile_id = v_profile_id;
    delete from public.identity_card where profile_id = v_profile_id;
    delete from public.quiz_attempts where viewer_id = v_profile_id or target_profile_id = v_profile_id;
    delete from public.hidden_profiles where viewer_id = v_profile_id or target_profile_id = v_profile_id;
    delete from public.skipped_profiles where viewer_id = v_profile_id or target_profile_id = v_profile_id;
    delete from public.identity_reveals where viewer_id = v_profile_id or target_profile_id = v_profile_id;

    update public.profiles
      set display_name = '[silinmiş kullanıcı]',
          birth_date = null,
          username = null,
          city_id = null,
          district_id = null
      where id = v_profile_id;

    v_count := v_count + 1;
  end loop;

  return jsonb_build_object('purged_count', v_count, 'deleted_photo_paths', to_jsonb(v_all_paths));
end;
$$;

revoke execute on function public.purge_deleted_accounts() from public;
