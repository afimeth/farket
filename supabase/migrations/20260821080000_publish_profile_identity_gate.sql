-- Publish now also requires at least one quiz-eligible identity attribute,
-- since start_quiz's phase-2 block (positions 6-10) mandates 1-2
-- identity-derived questions and raises otherwise.
--
-- The act2-hard minimum is raised from 2 to 3 here: phase-2 guarantees only
-- 1 custom question + 1 identity-derived question as a hard floor (a second
-- identity question is a bonus, not guaranteed, when a profile has exactly
-- one eligible attribute) — 1 + 1 + 2 = 4 would leave start_quiz unable to
-- reach the required 5 phase-2 questions in that minimum case. 1 + 1 + 3 = 5
-- always reaches it.
--
-- Everything else in this function is unchanged from the previous latest
-- definition (20260818222452_warmer_error_messages.sql).

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
