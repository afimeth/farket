-- Farket: DOCTOR.md'de "bekleyen ürün kararı" olarak açık bırakılan 3 madde
-- kullanıcı onayıyla kapatıldı.

-- =========================================================================
-- 1) identity_reveals — hedef taraf artık kendini quiz'leyen viewer'ın
--    UUID'sini doğrudan tablo okumasıyla göremiyor. Bildirim zaten kasıtlı
--    kimliksiz gönderiliyordu (bkz. notifications.sql); RLS bunu tutarlı
--    hale getiriyor. Hiçbir RPC/Android kodu target tarafının bu tabloyu
--    okumasına dayanmıyor (grep ile doğrulandı).
-- =========================================================================
drop policy identity_reveals_select_participant on public.identity_reveals;

create policy identity_reveals_select_own
  on public.identity_reveals for select
  to authenticated
  using (viewer_id = (select auth.uid()));

-- =========================================================================
-- 2) publish_profile — foto sayısının yanı sıra artık TÜM fotoğrafların
--    moderation_status='approved' olması da şart. Önceden yalnızca
--    'rejected' olanlar engelliyordu, 'pending' bir fotoyla da profil
--    yayına alınabiliyordu. Gövde 20260821080000_publish_profile_identity_
--    gate.sql ile birebir aynı, yalnızca satır 68-70'teki foto kontrolü
--    genişletildi.
-- =========================================================================
create or replace function public.publish_profile()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid           uuid := (select auth.uid());
  v_profile       record;
  v_photo_count   int;
  v_act1_count    int;
  v_act2hard_count int;
  v_custom_count  int;
begin
  if v_uid is null then
    raise exception 'Oturum açılmamış';
  end if;

  select status, username, age_attested_at into v_profile
    from public.profiles where id = v_uid;

  if not found then
    raise exception 'Profilin bulunamadı.';
  end if;

  if v_profile.status <> 'draft' then
    raise exception 'Bu profil zaten yayında.';
  end if;

  if v_profile.username is null then
    raise exception 'Yayınlamadan önce bir kullanıcı adı seçmelisin.';
  end if;

  if v_profile.age_attested_at is null then
    raise exception 'Yayınlamadan önce 18 yaşını beyan etmelisin.';
  end if;

  if not exists (select 1 from public.identity_card where profile_id = v_uid) then
    raise exception 'Yayınlamadan önce künyeni tamamlamalısın.';
  end if;

  if not exists (
    select 1 from public.profile_identity_attributes
    where profile_id = v_uid and is_quiz_eligible
  ) then
    raise exception 'Yayınlamadan önce en az bir künye bilgisini quiz için işaretlemelisin.';
  end if;

  select count(*) into v_photo_count from public.photos where profile_id = v_uid;
  if v_photo_count < 5 or v_photo_count > 7 then
    raise exception 'Fotoğraf sayın 5 ile 7 arasında olmalı (şu an %).', v_photo_count;
  end if;

  if exists (select 1 from public.photos where profile_id = v_uid and moderation_status <> 'approved') then
    raise exception 'Onaylanmamış (bekleyen ya da reddedilen) bir fotoğrafın var — yayınlamadan önce tüm fotoğrafların onaylanmış olmalı.';
  end if;

  select count(*) into v_act1_count
    from public.profile_template_answers pta
    join public.question_templates qt on qt.id = pta.template_id
    where pta.profile_id = v_uid and qt.act = 1 and qt.is_active;
  if v_act1_count < 7 then
    raise exception 'Yayınlamadan önce en az 7 kalıp soru cevaplamalısın (şu an %).', v_act1_count;
  end if;

  select count(*) into v_act2hard_count
    from public.profile_template_answers pta
    join public.question_templates qt on qt.id = pta.template_id
    where pta.profile_id = v_uid and qt.act = 2 and qt.default_difficulty = 'hard' and qt.is_active;
  if v_act2hard_count < 3 then
    raise exception 'Yayınlamadan önce en az 3 zor soru cevaplamalısın (şu an %).', v_act2hard_count;
  end if;

  select count(*) into v_custom_count
    from public.custom_questions cq
    where cq.profile_id = v_uid and cq.is_active and cq.correct_option_id is not null;
  if v_custom_count < 1 then
    raise exception 'Yayınlamadan önce doğru cevabı işaretlenmiş bir serbest soru eklemelisin.';
  end if;

  update public.profiles set status = 'published' where id = v_uid;

  return jsonb_build_object('status', 'published');
end;
$$;

-- =========================================================================
-- 3) profiles — yayınlandıktan sonra birth_date/sex donuyor. age_attested_at
--    ilk kez verilen bir 18+ beyanı; profil "published" olduktan sonra
--    doğum tarihi/cinsiyet değişimi bu beyanın bütünlüğünü zayıflatıyordu.
--    Trigger, sütunlar hâlâ (yayın ÖNCESİ kurulum sihirbazı için) UPDATE
--    grant listesinde kalsa da yayın SONRASI değişimi engelliyor.
-- =========================================================================
create or replace function public.prevent_identity_field_change_after_publish()
returns trigger
language plpgsql
as $$
begin
  if old.status = 'published' and (new.birth_date is distinct from old.birth_date or new.sex is distinct from old.sex) then
    raise exception 'Profil yayınlandıktan sonra doğum tarihi/cinsiyet değiştirilemez';
  end if;
  return new;
end;
$$;

create trigger profiles_lock_identity_fields_after_publish
  before update on public.profiles
  for each row
  execute function public.prevent_identity_field_change_after_publish();
