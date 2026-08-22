-- Farket: delete_account, restore_account, export_my_data,
-- purge_deleted_accounts (brifing v3, bölüm 9 adım 10 — silme akışı;
-- v2 bölüm 7'deki akış esas alınmıştır, v3 onu değiştirmeden miras aldı)
--
-- Kapsam notu: bu geçişte Storage entegrasyonu henüz yok (adım 4'ün bir
-- parçası, ertelendi). purge_deleted_accounts() veritabanı satırlarını
-- temizliyor ama fotoğrafların Storage bucket'ından FİZİKSEL silinmesini
-- YAPMIYOR — bu, Storage kurulunca eklenmesi gereken ayrı bir adım.
-- Ayrıca bu fonksiyonun "30 gün sonra otomatik çalışması" bir zamanlayıcı
-- (pg_cron ya da periyodik bir Edge Function çağrısı) gerektirir; o
-- zamanlayıcı burada KURULMADI — fonksiyon var ama hiçbir şey onu
-- otomatik tetiklemiyor. authenticated'a hiç EXECUTE verilmedi (yalnızca
-- service role/manuel çalıştırma).

-- profiles.birth_date ve city_id, purge sırasında anonimleştirme
-- yapabilmek için nullable'a çevrildi. Normal akışta (kayıt, set_city)
-- her ikisi de her zaman doldurulur; yalnızca purge sonrası "silinmiş"
-- bir profilde null olurlar.
alter table public.profiles alter column birth_date drop not null;
alter table public.profiles alter column city_id drop not null;

-- =========================================================================
-- delete_account — yumuşak silme, 30 günlük geri alma penceresi başlatır.
-- =========================================================================
create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id uuid := (select auth.uid());
begin
  if v_viewer_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  update public.profiles
    set status = 'deleted', deleted_at = now()
    where id = v_viewer_id and status <> 'deleted';

  if not found then
    raise exception 'Profil bulunamadı ya da zaten silinmiş';
  end if;

  update public.conversations
    set status = 'closed'
    where status in ('pending', 'accepted')
      and (participant_a = v_viewer_id or participant_b = v_viewer_id);
end;
$$;

revoke execute on function public.delete_account() from public;
grant execute on function public.delete_account() to authenticated;

-- =========================================================================
-- restore_account — 30 gün dolmadan geri alma.
-- =========================================================================
create or replace function public.restore_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id uuid := (select auth.uid());
  v_profile   record;
begin
  if v_viewer_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  select status, deleted_at into v_profile
    from public.profiles where id = v_viewer_id;

  if not found or v_profile.status <> 'deleted' then
    raise exception 'Hesap silinmiş durumda değil';
  end if;

  if v_profile.deleted_at < now() - interval '30 days' then
    raise exception 'Geri alma süresi (30 gün) dolmuş';
  end if;

  update public.profiles
    set status = 'published', deleted_at = null
    where id = v_viewer_id;
end;
$$;

revoke execute on function public.restore_account() from public;
grant execute on function public.restore_account() to authenticated;

-- =========================================================================
-- export_my_data — veri taşınabilirliği.
-- =========================================================================
create or replace function public.export_my_data()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id uuid := (select auth.uid());
begin
  if v_viewer_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  return jsonb_build_object(
    'profile', (select to_jsonb(p) from public.profiles p where p.id = v_viewer_id),
    'identity_card', (select to_jsonb(ic) from public.identity_card ic where ic.profile_id = v_viewer_id),
    'photos', (select coalesce(jsonb_agg(to_jsonb(ph)), '[]'::jsonb) from public.photos ph where ph.profile_id = v_viewer_id),
    'custom_questions', (
      select coalesce(jsonb_agg(jsonb_build_object('id', cq.id, 'body', cq.body, 'is_active', cq.is_active)), '[]'::jsonb)
      from public.custom_questions cq where cq.profile_id = v_viewer_id
    ),
    'quiz_attempts_as_viewer', (
      select coalesce(jsonb_agg(to_jsonb(qa)), '[]'::jsonb)
      from public.quiz_attempts qa where qa.viewer_id = v_viewer_id
    ),
    'messages_sent', (
      select coalesce(jsonb_agg(to_jsonb(m)), '[]'::jsonb)
      from public.messages m where m.sender_id = v_viewer_id
    ),
    'reports_filed', (
      select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
      from public.reports r where r.reporter_id = v_viewer_id
    )
  );
end;
$$;

revoke execute on function public.export_my_data() from public;
grant execute on function public.export_my_data() to authenticated;

-- =========================================================================
-- purge_deleted_accounts — kalıcı silme (yalnızca manuel/service role
-- çalıştırması için; authenticated'a hiç açık değil).
-- =========================================================================
create or replace function public.purge_deleted_accounts()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id  uuid;
  v_count       int := 0;
begin
  for v_profile_id in
    select id from public.profiles
    where status = 'deleted' and deleted_at < now() - interval '30 days'
  loop
    -- Mesajlar KASITLI OLARAK silinmiyor — karşı tarafın konuşma
    -- geçmişinde kalmalı. messages.sender_id, profiles satırı silinmediği
    -- (yalnızca anonimleştirildiği) için zaten dokunulmadan korunuyor.
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

  return v_count;
end;
$$;

revoke execute on function public.purge_deleted_accounts() from public;
