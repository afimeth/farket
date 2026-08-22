-- Ses tonu düzeltmesi: kullanıcıya doğrudan gösterilen hata mesajlarından
-- bazıları bir API dokümantasyonu gibi okunuyordu (iç parametre adı
-- sızdıran "selected_option_id gerekli" gibi ifadeler dahil). Bu migration
-- yalnızca `raise exception` metinlerini değiştiriyor — mantık aynı,
-- fonksiyon imzaları aynı, davranış aynı. Kapsam: set_template_answer,
-- publish_profile. (Bkz. BACKEND_SES_TONU.md — frontend oturumunun ses
-- tonu incelemesinden.)
--
-- publish_profile burada 20260818105759_v41_moderation.sql'deki GÜNCEL
-- gövdeden (reddedilmiş fotoğraf kontrolü dahil) türetildi —
-- 20260817074343_profile_setup_functions.sql'deki İLK tanımdan değil;
-- aksi halde bu migration o kontrolü sessizce geri alırdı.

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
    raise exception 'Bu soruda tam olarak bir cevap seçilmeli.';
  end if;

  select id, taxonomy_id, default_difficulty into v_template
    from public.question_templates
    where id = p_template_id and is_active;

  if not found then
    raise exception 'Bu soru artık kullanılamıyor.';
  end if;

  if v_template.taxonomy_id is null then
    if p_selected_option_id is null then
      raise exception 'Bu soruya bir cevap seçmen gerekiyor.';
    end if;
    if not exists (
      select 1 from public.template_options
      where id = p_selected_option_id and template_id = p_template_id
    ) then
      raise exception 'Seçtiğin şık bu soruya ait değil.';
    end if;
  else
    if p_selected_item_id is null then
      raise exception 'Bu soruya bir cevap seçmen gerekiyor.';
    end if;
    if not exists (
      select 1 from public.taxonomy_items
      where id = p_selected_item_id and taxonomy_id = v_template.taxonomy_id and is_active
    ) then
      raise exception 'Seçtiğin madde bu soruya ait değil.';
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

  select count(*) into v_photo_count from public.photos where profile_id = v_uid;
  if v_photo_count < 5 or v_photo_count > 7 then
    raise exception 'Fotoğraf sayın 5 ile 7 arasında olmalı (şu an %).', v_photo_count;
  end if;

  if exists (select 1 from public.photos where profile_id = v_uid and moderation_status = 'rejected') then
    raise exception 'Reddedilen bir fotoğrafın var — yayınlamadan önce onu kaldırmalı ya da değiştirmelisin.';
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
  if v_act2hard_count < 2 then
    raise exception 'Yayınlamadan önce en az 2 zor soru cevaplamalısın (şu an %).', v_act2hard_count;
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
