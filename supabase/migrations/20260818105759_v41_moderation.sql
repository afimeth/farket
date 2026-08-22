-- Farket v4.1 — Migration 1/5: fotoğraf moderasyonu (sessiz blokaj düzeltmesi).
--
-- Diff raporunda doğrulanan bug: photos.moderation_status varsayılanı
-- 'pending' idi ama discover_profiles/get_public_profile/
-- can_view_profile_photo_object hepsi 'approved' arıyordu ve hiçbir onay
-- mekanizması yoktu — prodüksiyonda hiçbir profil hiçbir zaman görünmezdi.
--
-- Tasarım: varsayılan artık 'approved'. Kötüye kullanımı önlemek için tek
-- bir şikayet fotoğrafı ASLA otomatik gizlemiyor — eşik ayarlanabilir bir
-- yapılandırma değeri (app_settings), koda gömülü değil. reports tablosu
-- hâlâ profil bazlı (photo_id yok, şemaya eklenmedi — v4.1 bunu istemiyor);
-- eşiğe ulaşınca o profilin TÜM 'approved' fotoğrafları 'pending'e düşer,
-- moderatör (Studio'dan elle) approved/rejected kararını verir.

-- =========================================================================
-- 1) Varsayılan + backfill.
-- =========================================================================
alter table public.photos alter column moderation_status set default 'approved';

update public.photos set moderation_status = 'approved' where moderation_status = 'pending';

-- =========================================================================
-- 2) Ayarlanabilir eşik — koda gömülmesin diye küçük bir config tablosu.
-- =========================================================================
create table public.app_settings (
  key    text primary key,
  value  text not null
);

insert into public.app_settings (key, value) values ('photo_report_threshold', '3');

alter table public.app_settings enable row level security;
-- Bilerek hiçbir policy/GRANT yok — istemci eşiği okuyup davranış
-- değiştirmemeli, yalnızca backend'in kendi (SECURITY DEFINER içi) kararı.

-- =========================================================================
-- 3) 3 farklı kullanıcıdan şikayet -> profilin onaylı fotoğrafları 'pending'.
-- Aynı kullanıcının tekrar tekrar şikayet etmesi sayılmaz (distinct reporter_id).
-- =========================================================================
create or replace function public.check_photo_report_threshold()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_threshold      int;
  v_distinct_count int;
begin
  select value::int into v_threshold from public.app_settings where key = 'photo_report_threshold';

  select count(distinct reporter_id) into v_distinct_count
    from public.reports
    where reported_profile_id = new.reported_profile_id;

  if v_distinct_count >= v_threshold then
    update public.photos
      set moderation_status = 'pending'
      where profile_id = new.reported_profile_id and moderation_status = 'approved';
  end if;

  return new;
end;
$$;

create trigger trg_check_photo_report_threshold
  after insert on public.reports
  for each row execute function public.check_photo_report_threshold();

-- =========================================================================
-- 4) publish_profile — rejected fotoğrafı olan profil yayınlanamaz (kapak
-- pozisyonu dahil, tüm pozisyonlar için — 'rejected' hiçbir pozisyonda
-- kabul edilmez).
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
    raise exception 'Profil bulunamadı';
  end if;

  if v_profile.status <> 'draft' then
    raise exception 'Profil zaten yayınlanmış ya da uygun durumda değil (mevcut durum: %)', v_profile.status;
  end if;

  if v_profile.username is null then
    raise exception 'Kullanıcı adı (@handle) belirlenmeden yayınlanamaz';
  end if;

  if v_profile.age_attested_at is null then
    raise exception '18 yaş beyanı yapılmadan yayınlanamaz';
  end if;

  if not exists (select 1 from public.identity_card where profile_id = v_uid) then
    raise exception 'Künye bilgileri tamamlanmadan yayınlanamaz';
  end if;

  select count(*) into v_photo_count from public.photos where profile_id = v_uid;
  if v_photo_count < 5 or v_photo_count > 7 then
    raise exception 'Fotoğraf sayısı 5 ile 7 arasında olmalı (şu an: %)', v_photo_count;
  end if;

  if exists (select 1 from public.photos where profile_id = v_uid and moderation_status = 'rejected') then
    raise exception 'Reddedilmiş bir fotoğrafın varken yayınlanamaz, önce kaldır ya da değiştir';
  end if;

  select count(*) into v_act1_count
    from public.profile_template_answers pta
    join public.question_templates qt on qt.id = pta.template_id
    where pta.profile_id = v_uid and qt.act = 1 and qt.is_active;
  if v_act1_count < 7 then
    raise exception 'En az 7 kalıp soru (1. perde) cevaplanmadan yayınlanamaz (şu an: %)', v_act1_count;
  end if;

  select count(*) into v_act2hard_count
    from public.profile_template_answers pta
    join public.question_templates qt on qt.id = pta.template_id
    where pta.profile_id = v_uid and qt.act = 2 and qt.default_difficulty = 'hard' and qt.is_active;
  if v_act2hard_count < 2 then
    raise exception 'En az 2 zor kalıp soru (2. perde) cevaplanmadan yayınlanamaz (şu an: %)', v_act2hard_count;
  end if;

  select count(*) into v_custom_count
    from public.custom_questions cq
    where cq.profile_id = v_uid and cq.is_active and cq.correct_option_id is not null;
  if v_custom_count < 1 then
    raise exception 'En az 1 serbest soru (doğru cevabı işaretlenmiş) eklenmeden yayınlanamaz';
  end if;

  update public.profiles set status = 'published' where id = v_uid;

  return jsonb_build_object('status', 'published');
end;
$$;
