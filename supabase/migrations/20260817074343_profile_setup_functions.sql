-- Farket: Görev 6 — profil kurulum ekranının backend fonksiyonları.
-- Android istemci geliştirmesi başladığı için bilerek ertelenen son parça.
--
-- Kapsam: get_taxonomy_items, set_template_answer/remove_template_answer,
-- custom_question içerik filtresi (custom_questions/custom_options zaten
-- doğrudan CRUD grant'ına sahipti — bkz. grants.sql — burada yalnızca
-- filtre eklendi), publish_profile. Telefon/OTP auth tarafı ayrı olarak
-- config.toml'da (yerel test_otp eşlemesi) yapılandırıldı.
--
-- KASITLI OLARAK YAPILMAYAN: fotoğraf moderasyon onayı (approve/reject)
-- için hiçbir admin/otomatik mekanizma yok (bu proje boyunca hiç
-- kurulmadı — ayrı bir görev). publish_profile bu yüzden moderation_status
-- değil YALNIZCA fotoğraf SAYISINI (5-7) doğruluyor; discover_profiles/
-- get_public_profile zaten yalnızca 'approved' fotoğrafları gösteriyor,
-- yani bir profil yayınlanabilir ama fotoğrafları moderasyon onayı
-- gelene kadar hiçbir yerde görünmez olabilir — bu bilinen bir boşluk.

-- =========================================================================
-- 1) get_taxonomy_items — profil kurulumu sırasında bir taksonomi
-- havuzunun maddelerini listelemek için. taxonomies (ad + soru gövdesi)
-- zaten authenticated'a SELECT ile açık (grants.sql); yalnızca items
-- (seçilebilecek cevaplar) kapalıydı, burada açılıyor.
--
-- "Birinin quizini çözerken havuzu sızdırmamalı" notu: bu fonksiyon
-- hedef-bağımsızdır (yalnızca taxonomy_id alır, hangi profille ilgili
-- olduğunu bilmez) ve döndürdüğü tam madde listesi zaten pick_distractors
-- çağrısının KOMŞULUK grafiğini (taxonomy_adjacency) içermiyor — yani bir
-- viewer bu fonksiyonu quiz sırasında çağırsa bile hangi maddelerin
-- birbirine komşu (= olası çeldirici) olduğunu öğrenemez, yalnızca genel
-- kategori listesini (ör. "hangi meslekler var") görür ki bu zaten
-- profil kurulumunda herkese açık olması gereken bir bilgi.
-- =========================================================================
create or replace function public.get_taxonomy_items(p_taxonomy_id int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := (select auth.uid());
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'Oturum açılmamış';
  end if;

  if not exists (select 1 from public.taxonomies where id = p_taxonomy_id and is_active) then
    raise exception 'Geçersiz taksonomi';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('id', ti.id, 'label', ti.label) order by ti.label), '[]'::jsonb)
    into v_result
    from public.taxonomy_items ti
    where ti.taxonomy_id = p_taxonomy_id and ti.is_active;

  return v_result;
end;
$$;

revoke execute on function public.get_taxonomy_items(int) from public;
grant execute on function public.get_taxonomy_items(int) to authenticated;

-- =========================================================================
-- 2) set_template_answer / remove_template_answer — profile_template_answers
-- hiç GRANT almadığı için (doğru cevap deposu) tek yazma/silme yolu bu
-- fonksiyonlar. difficulty, question_templates.default_difficulty'den
-- kopyalanır (start_quiz'in katmanlı çekilişi bunu doğrudan pta.difficulty
-- üzerinden filtreliyor, performans için denormalize edilmiş durumda).
-- =========================================================================
create or replace function public.set_template_answer(
  p_template_id        int,
  p_selected_option_id int default null,
  p_selected_item_id   int default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := (select auth.uid());
  v_template  record;
begin
  if v_uid is null then
    raise exception 'Oturum açılmamış';
  end if;

  if (p_selected_option_id is not null)::int + (p_selected_item_id is not null)::int <> 1 then
    raise exception 'Tam olarak bir cevap belirtilmeli (ya şık ya taksonomi maddesi)';
  end if;

  select id, taxonomy_id, default_difficulty into v_template
    from public.question_templates
    where id = p_template_id and is_active;

  if not found then
    raise exception 'Geçersiz ya da pasif kalıp soru';
  end if;

  if v_template.taxonomy_id is null then
    if p_selected_option_id is null then
      raise exception 'Bu soru sabit şıklı — selected_option_id gerekli';
    end if;
    if not exists (
      select 1 from public.template_options
      where id = p_selected_option_id and template_id = p_template_id
    ) then
      raise exception 'Seçilen şık bu soruya ait değil';
    end if;
  else
    if p_selected_item_id is null then
      raise exception 'Bu soru taksonomi tabanlı — selected_item_id gerekli';
    end if;
    if not exists (
      select 1 from public.taxonomy_items
      where id = p_selected_item_id and taxonomy_id = v_template.taxonomy_id and is_active
    ) then
      raise exception 'Seçilen madde bu sorunun taksonomisine ait değil';
    end if;
  end if;

  insert into public.profile_template_answers
    (profile_id, template_id, selected_option_id, selected_item_id, difficulty)
    values (v_uid, p_template_id, p_selected_option_id, p_selected_item_id, v_template.default_difficulty)
  on conflict (profile_id, template_id) do update set
    selected_option_id = excluded.selected_option_id,
    selected_item_id = excluded.selected_item_id,
    difficulty = excluded.difficulty;
end;
$$;

create or replace function public.remove_template_answer(p_template_id int)
returns void
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

  delete from public.profile_template_answers
    where profile_id = v_uid and template_id = p_template_id;
end;
$$;

revoke execute on function public.set_template_answer(int, int, int) from public;
revoke execute on function public.remove_template_answer(int) from public;
grant execute on function public.set_template_answer(int, int, int) to authenticated;
grant execute on function public.remove_template_answer(int) to authenticated;

-- =========================================================================
-- 3) custom_questions / custom_options içerik filtresi. Bu iki tablo zaten
-- doğrudan CRUD grant'ına sahipti (grants.sql) — burada yeni bir yazma
-- yolu AÇILMIYOR, yalnızca var olan yazma yoluna bir içerik denetimi
-- ekleniyor. Kapsam: telefon numarası, sosyal medya/iletişim yönlendirmesi,
-- şık yönlendirmesi ("cevap C", "B şıkkı doğru" gibi metin içi ipucu),
-- küçük bir hakaret listesi. Bu bir NLP/YZ filtresi değil — basit ama
-- gerçek bir regex denetimi; brifingin istediği asgari savunma.
-- =========================================================================
create or replace function public.violates_content_policy(p_text text)
returns boolean
language sql
immutable
as $$
  select
    length(regexp_replace(p_text, '[^0-9]', '', 'g')) >= 10
    or p_text ~* '(instagram|[iı]nsta\y|whatsapp|telegram|snapchat|tiktok|twitter|@[a-z0-9_.]{3,})'
    or p_text ~* '(cev(ap|ab)[ıi]?\s*(şıkk?ı?)?\s*[abc]\y|\y[abc]\s*şıkk?ı?\s*(doğru|seç)|doğrusu\s*[abc]\y|[abc]\s*ye\s*bas|[abc]\s*ya\s*bas)'
    or p_text ~* '\y(aptal|salak|gerizekalı|geri\s*zekalı|mal|ahmak|şerefsiz)\y';
$$;

create or replace function public.check_custom_question_content()
returns trigger
language plpgsql
as $$
begin
  if public.violates_content_policy(new.body) then
    raise exception 'Soru metni izin verilmeyen içerik barındırıyor (telefon/sosyal medya paylaşımı, şık yönlendirmesi ya da hakaret olamaz)';
  end if;
  return new;
end;
$$;

create trigger trg_check_custom_question_content
  before insert or update on public.custom_questions
  for each row execute function public.check_custom_question_content();

create or replace function public.check_custom_option_content()
returns trigger
language plpgsql
as $$
begin
  if public.violates_content_policy(new.body) then
    raise exception 'Şık metni izin verilmeyen içerik barındırıyor (telefon/sosyal medya paylaşımı, şık yönlendirmesi ya da hakaret olamaz)';
  end if;
  return new;
end;
$$;

create trigger trg_check_custom_option_content
  before insert or update on public.custom_options
  for each row execute function public.check_custom_option_content();

-- =========================================================================
-- 4) publish_profile — profil kurulumunun son adımı, 'draft' -> 'published'.
-- Fotoğraf moderasyonu (approved) ayrı/eksik bir katman olduğu için burada
-- KASITLI OLARAK aranmıyor — yalnızca sayı (5-7) doğrulanıyor (bkz. dosya
-- başındaki not).
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

revoke execute on function public.publish_profile() from public;
grant execute on function public.publish_profile() to authenticated;
