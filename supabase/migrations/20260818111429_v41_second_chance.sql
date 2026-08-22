-- Farket v4.1 — Migration 4/5: ikinci şans.
--
-- hidden_profiles artık "ceza" değil "ikinci şans kapısı". Kapsam:
--   1) hidden_profiles yapısal yeniden yazım (hidden_until -> available_at
--      + first_attempt_score/retry_cost/retry_used/released_early)
--   2) start_quiz: attempt_no farkında hale geldi, 2. denemede önceki
--      denemenin sorularını HARİÇ TUTUYOR (bkz. not aşağıda)
--   3) start_retry: yeni fonksiyon — ikinci deneme hakkını satın alır
--      (uygunluk + bedel kontrolü + retry_used işaretleme), asıl quiz'i
--      BAŞLATMAZ — client bundan sonra start_quiz'i tekrar çağırır.
--   4) submit_answer (checkpoint bloğu) / finish_quiz (bitiş bloğu):
--      blanket 3 aylık gizleme -> skora göre derecelendirilmiş bekleme/bedel,
--      SADECE attempt_no=1 için (2. denemenin sonucu retry_used=true'yu
--      hiç değiştirmiyor — zaten kalıcı gizli demek).
--   5) discover_profiles: hidden_until>now() kontrolü yeni kolonlara göre.
--
-- BİLİNÇLİ KAPSAM DIŞI (henüz migration 5'in konusu): daily_quotas'ın
-- hak sistemi (get_quiz_allowance, quiz_credits_used rename) burada YOK —
-- start_quiz/start_retry hâlâ eski quiz_attempts_used sayacını ve sabit
-- 15 limitini kullanıyor, yalnızca retry_cost kadar FAZLADAN düşüyor.
-- Migration 5 bu sayaçları yeniden adlandırıp dinamik hak hesabına
-- geçirecek.
--
-- ÖNEMLİ NOT (soru hariç tutma): attempt_questions tablosu zaten her
-- denemede sorulan template_id/custom_question_id'yi tutuyordu ama bunu
-- FİİLEN hariç tutan bir sorgu hiç yazılmamıştı (tek deneme mümkünken
-- gerek yoktu). Bu migration'da start_quiz'in TÜM soru seçim sorgularına
-- (1-7 katmanlı, 8-9 act2-zor, 10 serbest) bu hariç tutma eklendi —
-- atlanması en kolay adım budur, bkz. v41_second_chance_test.sql'deki
-- özel doğrulama.

-- =========================================================================
-- 1) hidden_profiles — yapısal yeniden yazım.
-- =========================================================================
alter table public.hidden_profiles
  add column first_attempt_score int,
  add column available_at        timestamptz,
  add column retry_cost          int,
  add column retry_used          boolean not null default false,
  add column released_early      boolean not null default false;

update public.hidden_profiles
  set available_at = hidden_until, retry_cost = 5, first_attempt_score = 0
  where available_at is null;

alter table public.hidden_profiles
  alter column available_at set not null,
  alter column retry_cost set not null;

alter table public.hidden_profiles drop column hidden_until;

drop index if exists idx_hidden_profiles_viewer_until;
create index idx_hidden_profiles_viewer_available on public.hidden_profiles (viewer_id, available_at);

-- =========================================================================
-- 1b) can_view_profile_photo_object — hidden_until yerine yeni kolonlar.
-- discover_profiles'ın hidden_profiles filtresiyle birebir aynı mantık
-- (kalıcı gizli ya da henüz uygun olmayan bekleme -> göremez).
-- =========================================================================
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
        where h.viewer_id = viewer.id and h.target_profile_id = target.id
          and (h.retry_used or h.available_at > now())
      )
  );
end;
$$;

-- =========================================================================
-- 2) start_quiz — attempt_no farkında, soru hariç tutma.
-- =========================================================================
create or replace function public.start_quiz(p_target_profile_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id       uuid := (select auth.uid());
  v_attempt_id      uuid;
  v_existing_count  int;
  v_hide            record;
  v_attempt_no      int;
  v_max_tier        int;
  v_credits_spent   int;
  v_position        int := 0;
  v_row             record;
  v_distractors     int[];
  v_option_ids      int[];
  v_shown           jsonb;
  v_correct         text;
  v_result          jsonb;

  v_excluded_templates int[];
  v_excluded_customs   uuid[];

  v_easy_ids        int[];
  v_medium_ids      int[];
  v_hard_ids        int[];
  v_take            int;
  v_deficit_easy    int;
  v_deficit_medium  int;
  v_deficit_hard    int;
  v_selected_ids    int[] := '{}';
  v_selected_id     int;
begin
  if v_viewer_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  if v_viewer_id = p_target_profile_id then
    raise exception 'Kendi profiline quiz başlatamazsın';
  end if;

  if not exists (
    select 1 from public.profiles
    where id = p_target_profile_id and status = 'published'
  ) then
    raise exception 'Hedef profil bulunamadı veya yayınlanmamış';
  end if;

  if exists (
    select 1 from public.blocks
    where (blocker_id = v_viewer_id and blocked_id = p_target_profile_id)
       or (blocker_id = p_target_profile_id and blocked_id = v_viewer_id)
  ) then
    raise exception 'Bu profille etkileşim engellenmiş';
  end if;

  -- ---------------------------------------------------------------------
  -- attempt_no belirleme: 0 önceki deneme -> 1 (normal). 1 önceki deneme
  -- -> ancak start_retry ile retry_used=true işaretlenmişse 2. 2 önceki
  -- deneme -> hiçbir zaman (CHECK kısıtı da bunu garanti eder).
  -- ---------------------------------------------------------------------
  select count(*) into v_existing_count
    from public.quiz_attempts
    where viewer_id = v_viewer_id and target_profile_id = p_target_profile_id;

  if v_existing_count >= 2 then
    raise exception 'Bu profil için iki deneme hakkını da kullandın';
  elsif v_existing_count = 1 then
    select * into v_hide
      from public.hidden_profiles
      where viewer_id = v_viewer_id and target_profile_id = p_target_profile_id
      for update;

    if not found or not v_hide.retry_used then
      raise exception 'Bu profile zaten bir deneme açtın';
    end if;

    v_attempt_no := 2;
    v_max_tier := 8;
    v_credits_spent := v_hide.retry_cost;
  else
    v_attempt_no := 1;
    v_max_tier := 10;
    v_credits_spent := 1;
  end if;

  -- Önceki deneme(ler)de sorulan sorular — 2. denemede tekrar sorulmasın.
  -- (1. denemede boş küme döner, sorgulara etkisi olmaz.)
  select coalesce(array_agg(distinct aq.template_id) filter (where aq.template_id is not null), '{}'),
         coalesce(array_agg(distinct aq.custom_question_id) filter (where aq.custom_question_id is not null), '{}')
    into v_excluded_templates, v_excluded_customs
    from public.attempt_questions aq
    join public.quiz_attempts qa on qa.id = aq.attempt_id
    where qa.viewer_id = v_viewer_id and qa.target_profile_id = p_target_profile_id;

  insert into public.quiz_attempts (viewer_id, target_profile_id, attempt_no, max_tier, credits_spent)
    values (v_viewer_id, p_target_profile_id, v_attempt_no, v_max_tier, v_credits_spent)
    returning id into v_attempt_id;

  -- quiz_started: kimliksiz, günlük gruplanır.
  perform public._notify(p_target_profile_id, 'quiz_started', null, v_attempt_id, null, '{}'::jsonb);

  if v_attempt_no = 1 then
    -- 2. deneme kredisi start_retry'de ÖNCEDEN düşüldü, burada tekrar
    -- düşülmez.
    select quiz_attempts_used into v_credits_spent
      from public.daily_quotas
      where user_id = v_viewer_id and date = current_date;
    if coalesce(v_credits_spent, 0) >= 15 then
      raise exception 'Günlük quiz deneme kotan doldu';
    end if;

    insert into public.daily_quotas as dq (user_id, date, quiz_attempts_used)
      values (v_viewer_id, current_date, 1)
      on conflict (user_id, date)
      do update set quiz_attempts_used = dq.quiz_attempts_used + 1;
  end if;

  -- ---------------------------------------------------------------------
  -- 1-7: katmanlı zorluk çekilişi (3 kolay + 3 orta + 1 zor).
  -- ---------------------------------------------------------------------
  select coalesce(array_agg(pta.template_id order by random()), '{}') into v_easy_ids
    from public.profile_template_answers pta
    join public.question_templates qt on qt.id = pta.template_id
    where pta.profile_id = p_target_profile_id and qt.act = 1 and qt.is_active and pta.difficulty = 'easy'
      and pta.template_id <> all (v_excluded_templates);

  select coalesce(array_agg(pta.template_id order by random()), '{}') into v_medium_ids
    from public.profile_template_answers pta
    join public.question_templates qt on qt.id = pta.template_id
    where pta.profile_id = p_target_profile_id and qt.act = 1 and qt.is_active and pta.difficulty = 'medium'
      and pta.template_id <> all (v_excluded_templates);

  select coalesce(array_agg(pta.template_id order by random()), '{}') into v_hard_ids
    from public.profile_template_answers pta
    join public.question_templates qt on qt.id = pta.template_id
    where pta.profile_id = p_target_profile_id and qt.act = 1 and qt.is_active and pta.difficulty = 'hard'
      and pta.template_id <> all (v_excluded_templates);

  v_take := least(3, coalesce(array_length(v_easy_ids, 1), 0));
  v_selected_ids := v_selected_ids || v_easy_ids[1:v_take];
  v_easy_ids := v_easy_ids[v_take + 1:];
  v_deficit_easy := 3 - v_take;

  v_take := least(3, coalesce(array_length(v_medium_ids, 1), 0));
  v_selected_ids := v_selected_ids || v_medium_ids[1:v_take];
  v_medium_ids := v_medium_ids[v_take + 1:];
  v_deficit_medium := 3 - v_take;

  v_take := least(1, coalesce(array_length(v_hard_ids, 1), 0));
  v_selected_ids := v_selected_ids || v_hard_ids[1:v_take];
  v_hard_ids := v_hard_ids[v_take + 1:];
  v_deficit_hard := 1 - v_take;

  if v_deficit_easy > 0 then
    v_take := least(v_deficit_easy, coalesce(array_length(v_medium_ids, 1), 0));
    v_selected_ids := v_selected_ids || v_medium_ids[1:v_take];
    v_medium_ids := v_medium_ids[v_take + 1:];
    v_deficit_easy := v_deficit_easy - v_take;
  end if;

  if v_deficit_medium > 0 then
    v_take := least(v_deficit_medium, coalesce(array_length(v_easy_ids, 1), 0));
    v_selected_ids := v_selected_ids || v_easy_ids[1:v_take];
    v_easy_ids := v_easy_ids[v_take + 1:];
    v_deficit_medium := v_deficit_medium - v_take;
  end if;

  if v_deficit_hard > 0 then
    v_take := least(v_deficit_hard, coalesce(array_length(v_medium_ids, 1), 0));
    v_selected_ids := v_selected_ids || v_medium_ids[1:v_take];
    v_medium_ids := v_medium_ids[v_take + 1:];
    v_deficit_hard := v_deficit_hard - v_take;
  end if;

  if v_deficit_easy + v_deficit_medium + v_deficit_hard > 0 then
    raise exception 'Hedef profilin 1. perde için soru havuzu yetersiz (zorluk dağılımı karşılanamıyor)';
  end if;

  select array_agg(x order by random()) into v_selected_ids from unnest(v_selected_ids) x;

  foreach v_selected_id in array v_selected_ids loop
    v_position := v_position + 1;

    select pta.template_id, pta.selected_option_id, pta.selected_item_id, pta.difficulty,
           qt.body, qt.taxonomy_id
      into v_row
      from public.profile_template_answers pta
      join public.question_templates qt on qt.id = pta.template_id
      where pta.profile_id = p_target_profile_id and pta.template_id = v_selected_id;

    if v_row.selected_item_id is not null then
      v_distractors := public.pick_distractors(v_row.taxonomy_id, v_row.selected_item_id, v_row.difficulty);
      v_option_ids := array_append(v_distractors, v_row.selected_item_id);
      select jsonb_agg(jsonb_build_object('id', ti.id::text, 'body', ti.label) order by random())
        into v_shown
        from public.taxonomy_items ti
        where ti.id = any (v_option_ids);
      v_correct := v_row.selected_item_id::text;
    else
      select jsonb_agg(jsonb_build_object('id', tpo.id::text, 'body', tpo.body) order by random())
        into v_shown
        from public.template_options tpo
        where tpo.template_id = v_row.template_id;
      v_correct := v_row.selected_option_id::text;
    end if;

    insert into public.attempt_questions (attempt_id, position, template_id, shown_option_ids, correct_option_id)
      values (
        v_attempt_id, v_position, v_row.template_id,
        jsonb_build_object('question_body', v_row.body, 'options', v_shown),
        v_correct
      );
  end loop;

  -- ---------------------------------------------------------------------
  -- 8-9: hedefin act 2 + zor kalıp havuzundan rastgele 2 soru.
  -- ---------------------------------------------------------------------
  for v_row in
    select pta.template_id, pta.selected_option_id, pta.selected_item_id, pta.difficulty,
           qt.body, qt.taxonomy_id
    from public.profile_template_answers pta
    join public.question_templates qt on qt.id = pta.template_id
    where pta.profile_id = p_target_profile_id and qt.act = 2 and qt.default_difficulty = 'hard' and qt.is_active
      and pta.template_id <> all (v_excluded_templates)
    order by random()
    limit 2
  loop
    v_position := v_position + 1;

    if v_row.selected_item_id is not null then
      v_distractors := public.pick_distractors(v_row.taxonomy_id, v_row.selected_item_id, v_row.difficulty);
      v_option_ids := array_append(v_distractors, v_row.selected_item_id);
      select jsonb_agg(jsonb_build_object('id', ti.id::text, 'body', ti.label) order by random())
        into v_shown
        from public.taxonomy_items ti
        where ti.id = any (v_option_ids);
      v_correct := v_row.selected_item_id::text;
    else
      select jsonb_agg(jsonb_build_object('id', tpo.id::text, 'body', tpo.body) order by random())
        into v_shown
        from public.template_options tpo
        where tpo.template_id = v_row.template_id;
      v_correct := v_row.selected_option_id::text;
    end if;

    insert into public.attempt_questions (attempt_id, position, template_id, shown_option_ids, correct_option_id)
      values (
        v_attempt_id, v_position, v_row.template_id,
        jsonb_build_object('question_body', v_row.body, 'options', v_shown),
        v_correct
      );
  end loop;

  if v_position < 9 then
    raise exception 'Hedef profilin act 2 zor kalıp soru havuzu yetersiz (en az 2 zor soru seçmiş olmalı)';
  end if;

  -- ---------------------------------------------------------------------
  -- 10: hedefin serbest sorularından, önceki denemede sorulmamış rastgele 1.
  -- ---------------------------------------------------------------------
  select cq.id, cq.body into v_row
    from public.custom_questions cq
    where cq.profile_id = p_target_profile_id and cq.is_active
      and cq.id <> all (v_excluded_customs)
    order by random()
    limit 1;

  if not found then
    raise exception 'Hedef profilin aktif serbest sorusu yok';
  end if;

  v_position := v_position + 1;

  select jsonb_agg(jsonb_build_object('id', co.id::text, 'body', co.body) order by random())
    into v_shown
    from public.custom_options co
    where co.question_id = v_row.id;

  select correct_option_id::text into v_correct
    from public.custom_questions where id = v_row.id;

  insert into public.attempt_questions (attempt_id, position, custom_question_id, shown_option_ids, correct_option_id)
    values (
      v_attempt_id, v_position, v_row.id,
      jsonb_build_object('question_body', v_row.body, 'options', v_shown),
      v_correct
    );

  select jsonb_agg(
           jsonb_build_object(
             'position', aq.position,
             'question_body', aq.shown_option_ids -> 'question_body',
             'options', aq.shown_option_ids -> 'options'
           ) order by aq.position
         )
    into v_result
    from public.attempt_questions aq
    where aq.attempt_id = v_attempt_id;

  return jsonb_build_object(
    'attempt_id', v_attempt_id, 'attempt_no', v_attempt_no, 'max_tier', v_max_tier,
    'questions', v_result
  );
end;
$$;

revoke execute on function public.start_quiz(uuid) from public;
grant execute on function public.start_quiz(uuid) to authenticated;

-- =========================================================================
-- 3) start_retry — ikinci deneme hakkını "satın alır", asıl quiz'i
-- BAŞLATMAZ. Client bunu çağırıp başarılı olursa hemen ardından
-- start_quiz(target)'i tekrar çağırır (o zaman attempt_no=2 olarak açılır).
-- =========================================================================
create or replace function public.start_retry(p_target_profile_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id uuid := (select auth.uid());
  v_hide      record;
  v_used      int;
begin
  if v_viewer_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  select * into v_hide
    from public.hidden_profiles
    where viewer_id = v_viewer_id and target_profile_id = p_target_profile_id
    for update;

  if not found then
    raise exception 'Bu profil için bir ikinci şans kaydı yok';
  end if;

  if v_hide.retry_used then
    raise exception 'Bu profil için ikinci şansını zaten kullandın';
  end if;

  if v_hide.available_at > now() then
    raise exception 'Henüz tekrar deneyemezsin (uygun olduğu tarih: %)', v_hide.available_at;
  end if;

  select quiz_attempts_used into v_used
    from public.daily_quotas
    where user_id = v_viewer_id and date = current_date;
  if coalesce(v_used, 0) + v_hide.retry_cost > 15 then
    raise exception 'Günlük quiz hakkın ikinci deneme için yetersiz (gereken: %)', v_hide.retry_cost;
  end if;

  insert into public.daily_quotas as dq (user_id, date, quiz_attempts_used)
    values (v_viewer_id, current_date, v_hide.retry_cost)
    on conflict (user_id, date)
    do update set quiz_attempts_used = dq.quiz_attempts_used + v_hide.retry_cost;

  update public.hidden_profiles
    set retry_used = true
    where viewer_id = v_viewer_id and target_profile_id = p_target_profile_id;

  return jsonb_build_object('retry_cost', v_hide.retry_cost, 'max_tier', 8);
end;
$$;

revoke execute on function public.start_retry(uuid) from public;
grant execute on function public.start_retry(uuid) to authenticated;

-- =========================================================================
-- 4) submit_answer — checkpoint bloğu: blanket 3 ay -> 3 gün/bedel 0/hak
-- iadesi, SADECE attempt_no=1 için.
-- =========================================================================
create or replace function public.submit_answer(
  p_attempt_id  uuid,
  p_position    int,
  p_option_id   text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id           uuid := (select auth.uid());
  v_attempt             record;
  v_question            record;
  v_expected_position   int;
  v_is_correct          boolean;
  v_new_score           int;
  v_checkpoint_passed   boolean;
  v_result              jsonb;
  v_taxonomy_id         int;
  v_max_count           int;
  v_total_count         int;
begin
  if v_viewer_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  select * into v_attempt
    from public.quiz_attempts
    where id = p_attempt_id
    for update;

  if not found or v_attempt.viewer_id <> v_viewer_id then
    raise exception 'Bu deneme sana ait değil';
  end if;

  if v_attempt.status <> 'in_progress' then
    raise exception 'Bu deneme artık aktif değil';
  end if;

  select correct_option_id, template_id into v_question
    from public.attempt_questions
    where attempt_id = p_attempt_id and position = p_position;

  if not found then
    raise exception 'Geçersiz soru pozisyonu: %', p_position;
  end if;

  select count(*) + 1 into v_expected_position
    from public.attempt_answers
    where attempt_id = p_attempt_id;

  if p_position <> v_expected_position then
    raise exception 'Sorulara sırayla cevap vermelisin (beklenen pozisyon: %)', v_expected_position;
  end if;

  v_is_correct := (p_option_id = v_question.correct_option_id);

  insert into public.attempt_answers (attempt_id, question_position, selected_option_id, is_correct)
    values (p_attempt_id, p_position, p_option_id, v_is_correct);

  update public.quiz_attempts
    set score = score + (case when v_is_correct then 1 else 0 end)
    where id = p_attempt_id
    returning score into v_new_score;

  if v_question.template_id is not null then
    select taxonomy_id into v_taxonomy_id
      from public.question_templates
      where id = v_question.template_id;

    if v_taxonomy_id is not null then
      insert into public.template_stats (template_id, item_id, selected_count)
        values (v_question.template_id, p_option_id::int, 1)
        on conflict (template_id, item_id) where item_id is not null
        do update set selected_count = template_stats.selected_count + 1;
    else
      insert into public.template_stats (template_id, option_id, selected_count)
        values (v_question.template_id, p_option_id::int, 1)
        on conflict (template_id, option_id) where option_id is not null
        do update set selected_count = template_stats.selected_count + 1;
    end if;

    select max(selected_count), sum(selected_count)
      into v_max_count, v_total_count
      from public.template_stats
      where template_id = v_question.template_id;

    if v_total_count >= 20 and v_max_count::numeric / v_total_count > 0.55 then
      update public.question_templates set is_active = false where id = v_question.template_id;
    end if;
  end if;

  v_result := jsonb_build_object('score', v_new_score);

  -- Kontrol noktası: 5. soru cevaplanınca otomatik değerlendirilir.
  if p_position = 5 then
    v_checkpoint_passed := (v_new_score >= 4);

    update public.quiz_attempts
      set checkpoint_passed = v_checkpoint_passed,
          status = case when v_checkpoint_passed then status else 'failed_checkpoint' end,
          completed_at = case when v_checkpoint_passed then completed_at else now() end
      where id = p_attempt_id;

    if not v_checkpoint_passed and v_attempt.attempt_no = 1 then
      insert into public.hidden_profiles
        (viewer_id, target_profile_id, first_attempt_score, available_at, retry_cost, retry_used, released_early)
        values (v_attempt.viewer_id, v_attempt.target_profile_id, v_new_score, now() + interval '3 days', 0, false, false)
        on conflict (viewer_id, target_profile_id) do update set
          first_attempt_score = excluded.first_attempt_score,
          available_at = excluded.available_at,
          retry_cost = excluded.retry_cost,
          retry_used = false,
          released_early = false;

      -- Checkpoint'te elenmenin bedeli yok — bu denemenin harcadığı hak
      -- iade edilir.
      update public.daily_quotas
        set quiz_attempts_used = greatest(0, quiz_attempts_used - v_attempt.credits_spent)
        where user_id = v_attempt.viewer_id and date = current_date;
    end if;

    v_result := v_result || jsonb_build_object('checkpoint_passed', v_checkpoint_passed);
  end if;

  -- 10. soru cevaplanınca (ve deneme hâlâ in_progress'se) otomatik bitirilir.
  if p_position = 10 and v_attempt.status = 'in_progress' then
    v_result := v_result || public.finish_quiz(p_attempt_id);
  end if;

  return v_result;
end;
$$;

revoke execute on function public.submit_answer(uuid, int, text) from public;
grant execute on function public.submit_answer(uuid, int, text) to authenticated;

-- =========================================================================
-- 5) finish_quiz — blanket 3 ay -> skora göre derecelendirilmiş bekleme/
-- bedel, SADECE attempt_no=1 için (2. denemenin sonucu ne olursa olsun
-- retry_used=true zaten kalıcı gizliyor, ayrıca bir hidden_profiles
-- güncellemesi gerekmiyor).
-- =========================================================================
create or replace function public.finish_quiz(p_attempt_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id   uuid := (select auth.uid());
  v_attempt     record;
  v_tier        int;
  v_answered    int;
  v_wait        interval;
  v_cost        int;
begin
  if v_viewer_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  select * into v_attempt
    from public.quiz_attempts
    where id = p_attempt_id
    for update;

  if not found or v_attempt.viewer_id <> v_viewer_id then
    raise exception 'Bu deneme sana ait değil';
  end if;

  if v_attempt.status in ('completed', 'failed_checkpoint') then
    return jsonb_build_object(
      'score', v_attempt.score,
      'unlocked_tier', v_attempt.unlocked_tier,
      'status', v_attempt.status
    );
  end if;

  select count(*) into v_answered
    from public.attempt_answers
    where attempt_id = p_attempt_id;

  if v_answered < 10 then
    raise exception 'Quiz henüz tamamlanmadı (% / 10 soru cevaplandı)', v_answered;
  end if;

  v_tier := case
    when v_attempt.score >= 8 then least(8, v_attempt.max_tier)
    when v_attempt.score = 7 then 7
    else 0
  end;

  if v_attempt.attempt_no = 1 and v_attempt.score < 7 then
    if v_attempt.score = 6 then
      v_wait := interval '0 days'; v_cost := 2;
    elsif v_attempt.score between 4 and 5 then
      v_wait := interval '3 days'; v_cost := 3;
    else
      v_wait := interval '14 days'; v_cost := 5;
    end if;

    insert into public.hidden_profiles
      (viewer_id, target_profile_id, first_attempt_score, available_at, retry_cost, retry_used, released_early)
      values (v_attempt.viewer_id, v_attempt.target_profile_id, v_attempt.score, now() + v_wait, v_cost, false, false)
      on conflict (viewer_id, target_profile_id) do update set
        first_attempt_score = excluded.first_attempt_score,
        available_at = excluded.available_at,
        retry_cost = excluded.retry_cost,
        retry_used = false,
        released_early = false;
  end if;

  update public.quiz_attempts
    set status = 'completed',
        unlocked_tier = v_tier,
        completed_at = now()
    where id = p_attempt_id;

  if v_attempt.score >= 7 then
    perform public._notify(
      v_attempt.target_profile_id,
      case when v_attempt.score = 10 then 'perfect_score' else 'quiz_passed' end,
      null, p_attempt_id, null,
      jsonb_build_object('score', v_attempt.score)
    );
  end if;

  return jsonb_build_object('score', v_attempt.score, 'unlocked_tier', v_tier, 'status', 'completed');
end;
$$;

revoke execute on function public.finish_quiz(uuid) from public;
grant execute on function public.finish_quiz(uuid) to authenticated;

-- =========================================================================
-- 6) discover_profiles — hidden_until>now() kontrolü yeni kolonlara göre.
-- NOT: retry_used=false + available_at geçmiş bir profil artık bu filtreyi
-- geçer, AMA fonksiyonun ayrı, bu migration'ın kapsamı DIŞINDAKİ
-- "not exists (select 1 from quiz_attempts where viewer/target eşleşiyor)"
-- kısıtı onu yine de akıştan dışlamaya devam ediyor (v4.1 bunu değiştirmeyi
-- istemedi). Yani bugün itibarıyla retry-uygun bir profile ulaşmanın tek
-- yolu start_retry + start_quiz'i doğrudan target_profile_id ile çağırmak —
-- ana keşif akışında kendiliğinden yeniden belirmiyor. Bu gözlem raporda
-- ayrıca not edildi.
-- =========================================================================
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
        where h.viewer_id = v_viewer_id and h.target_profile_id = p.id
          and (h.retry_used or h.available_at > now())
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

revoke execute on function public.discover_profiles(int) from public;
grant execute on function public.discover_profiles(int) to authenticated;
