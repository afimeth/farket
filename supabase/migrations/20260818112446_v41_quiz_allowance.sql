-- Farket v4.1 — Migration 5/5: hak sistemi.
--
-- daily_quotas.quiz_attempts_used -> quiz_credits_used (isim değişikliği).
-- Sabit "15" (quiz) ve "200" (keşif çağrısı) limitleri kalkıyor:
--   - quiz hakkı artık get_quiz_allowance() ile GÜNDE BİR HESAPLANIP
--     daily_quotas.quiz_allowance'a yazılıyor (aynı gün içinde koşullar
--     değişse bile sabit kalır — "Her gün yeniden hesaplanır" ifadesi
--     GÜN başına bir kez anlamına geliyor, her çağrıda değil).
--   - keşif artık "çağrı" değil "gösterilen profil" bazında sınırlanıyor
--     (deck_profiles_served), ayarlanabilir bir günlük deste limitiyle
--     (app_settings, koda gömülü değil — migration 1'deki desenle aynı).
--
-- BİLİNÇLİ BASİTLEŞTİRME — "quiz sağlığı" koşulu: v4.1 §4 "ölü soru yok
-- (30+ gösterimde %5'in altında çözülen)" diye tanımlıyor ama bu, mevcut
-- template_stats/is_active altyapısının izlediği sinyalden (bir şıkkın
-- %55+ baskın seçilmesi -> "çok kolay/belli") FARKLI bir eşik ("çok zor/
-- bozuk" sinyali) ve ayrı bir istatistik toplama gerektiriyor. Burada
-- onun yerine ELİMİZDEKİ en yakın sinyal kullanıldı: kullanıcının
-- cevapladığı hiçbir kalıp sorunun otomatik pasife düşmemiş olması
-- (question_templates.is_active) + genel çözülme oranının %10-85
-- aralığında olması. Bu bir YORUM/basitleştirme, birebir spesifikasyon
-- değil — gerçek "30+ gösterim / <%5 doğru" metriği ayrı bir agregasyon
-- gerektirir, istenirse ayrı bir migration'da eklenebilir.
--
-- BİLİNÇLİ KAPSAM DIŞI: "doğrulanmamış profiller alt sıralara" /
-- verified_only parametresi (doğrulama akışı henüz yok, sonraki bir
-- faz), conversations.expires_at'in send_message'da uygulanması
-- (expire_pending_conversations sonraki bir faz), ödül merdiveni/
-- bildirim ilerlemesi (ayrı fazlar) — bunların hiçbiri bu migration'da
-- YOK, yalnızca hak sistemi.

-- =========================================================================
-- 1) daily_quotas — yeniden adlandırma + yeni kolonlar.
-- =========================================================================
alter table public.daily_quotas rename column quiz_attempts_used to quiz_credits_used;
alter table public.daily_quotas add column quiz_allowance        int;
alter table public.daily_quotas add column deck_profiles_served  int not null default 0;

insert into public.app_settings (key, value) values ('daily_deck_limit', '25')
  on conflict (key) do nothing;

-- =========================================================================
-- 2) get_quiz_allowance — bölüm 3'teki hesap. authenticated kendi
-- hakkını sorgulayabilsin diye açık (yalnızca p_user_id = auth.uid()
-- olduğunda çalışır, başkasınınkini sorgulayamaz).
-- =========================================================================
create or replace function public.get_quiz_allowance(p_user_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid              uuid := (select auth.uid());
  v_allowance        int := 3;
  v_verified         boolean;
  v_has_pending      boolean;
  v_solve_rate       numeric;
  v_no_dead_question boolean;
  v_photo_ok         boolean;
  v_custom_ok        boolean;
  v_secret_card_ok   boolean;
begin
  if v_uid is null then
    raise exception 'Oturum açılmamış';
  end if;
  if p_user_id <> v_uid then
    raise exception 'Yalnızca kendi hakkını sorgulayabilirsin';
  end if;

  select verified_at is not null into v_verified from public.profiles where id = p_user_id;
  if v_verified then
    v_allowance := v_allowance + 1;
  end if;

  select not exists (
    select 1 from public.conversations where participant_b = p_user_id and status = 'pending'
  ) into v_has_pending;
  if v_has_pending then
    v_allowance := v_allowance + 1;
  end if;

  select not exists (
    select 1 from public.profile_template_answers pta
    join public.question_templates qt on qt.id = pta.template_id
    where pta.profile_id = p_user_id and not qt.is_active
  ) into v_no_dead_question;

  select case
           when count(*) filter (where qa.status in ('completed', 'failed_checkpoint')) = 0 then null
           else 100.0 * count(*) filter (where qa.unlocked_tier > 0)
                / count(*) filter (where qa.status in ('completed', 'failed_checkpoint'))
         end
    into v_solve_rate
    from public.quiz_attempts qa
    where qa.target_profile_id = p_user_id;

  if v_no_dead_question and v_solve_rate is not null and v_solve_rate between 10 and 85 then
    v_allowance := v_allowance + 1;
  end if;

  select count(*) = 7 into v_photo_ok from public.photos where profile_id = p_user_id;
  select count(*) >= 5 into v_custom_ok from public.custom_questions where profile_id = p_user_id and is_active;
  select secret_card_type is not null into v_secret_card_ok from public.profiles where id = p_user_id;

  if v_photo_ok and v_custom_ok and v_secret_card_ok then
    v_allowance := v_allowance + 1;
  end if;

  return least(v_allowance, 7);
end;
$$;

revoke execute on function public.get_quiz_allowance(uuid) from public;
grant execute on function public.get_quiz_allowance(uuid) to authenticated;

-- =========================================================================
-- 3) start_quiz / start_retry — sabit 15 -> get_quiz_allowance.
-- Yalnızca kota bloğu değişti, geri kalan (attempt_no/hariç tutma vb.,
-- Migration 4) aynı.
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
  v_allowance       int;
  v_used            int;
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

  select coalesce(array_agg(distinct aq.template_id) filter (where aq.template_id is not null), '{}'),
         coalesce(array_agg(distinct aq.custom_question_id) filter (where aq.custom_question_id is not null), '{}')
    into v_excluded_templates, v_excluded_customs
    from public.attempt_questions aq
    join public.quiz_attempts qa on qa.id = aq.attempt_id
    where qa.viewer_id = v_viewer_id and qa.target_profile_id = p_target_profile_id;

  -- Günlük hak: gün içindeki İLK sorguda hesaplanıp saklanır, aynı gün
  -- içinde tekrar hesaplanmaz (koşullar değişse bile o gün sabit kalır).
  insert into public.daily_quotas as dq (user_id, date, quiz_allowance)
    values (v_viewer_id, current_date, public.get_quiz_allowance(v_viewer_id))
    on conflict (user_id, date) do update set quiz_allowance = coalesce(dq.quiz_allowance, excluded.quiz_allowance)
    returning quiz_allowance, quiz_credits_used into v_allowance, v_used;

  if v_attempt_no = 1 then
    if coalesce(v_used, 0) >= v_allowance then
      raise exception 'Günlük quiz deneme kotan doldu';
    end if;

    update public.daily_quotas
      set quiz_credits_used = quiz_credits_used + 1
      where user_id = v_viewer_id and date = current_date;
  end if;
  -- attempt_no=2 kredisi start_retry'de önceden düşüldü, burada tekrar
  -- düşülmez.

  insert into public.quiz_attempts (viewer_id, target_profile_id, attempt_no, max_tier, credits_spent)
    values (v_viewer_id, p_target_profile_id, v_attempt_no, v_max_tier, v_credits_spent)
    returning id into v_attempt_id;

  perform public._notify(p_target_profile_id, 'quiz_started', null, v_attempt_id, null, '{}'::jsonb);

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

create or replace function public.start_retry(p_target_profile_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id uuid := (select auth.uid());
  v_hide      record;
  v_allowance int;
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

  insert into public.daily_quotas as dq (user_id, date, quiz_allowance)
    values (v_viewer_id, current_date, public.get_quiz_allowance(v_viewer_id))
    on conflict (user_id, date) do update set quiz_allowance = coalesce(dq.quiz_allowance, excluded.quiz_allowance)
    returning quiz_allowance, quiz_credits_used into v_allowance, v_used;

  if coalesce(v_used, 0) + v_hide.retry_cost > v_allowance then
    raise exception 'Günlük quiz hakkın ikinci deneme için yetersiz (gereken: %, kalan: %)',
      v_hide.retry_cost, greatest(0, v_allowance - coalesce(v_used, 0));
  end if;

  update public.daily_quotas
    set quiz_credits_used = quiz_credits_used + v_hide.retry_cost
    where user_id = v_viewer_id and date = current_date;

  update public.hidden_profiles
    set retry_used = true
    where viewer_id = v_viewer_id and target_profile_id = p_target_profile_id;

  return jsonb_build_object('retry_cost', v_hide.retry_cost, 'max_tier', 8);
end;
$$;

revoke execute on function public.start_retry(uuid) from public;
grant execute on function public.start_retry(uuid) to authenticated;

-- =========================================================================
-- 4) submit_answer — yalnızca sütun adı değişti (quiz_attempts_used ->
-- quiz_credits_used), mantık aynı.
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

      update public.daily_quotas
        set quiz_credits_used = greatest(0, quiz_credits_used - v_attempt.credits_spent)
        where user_id = v_attempt.viewer_id and date = current_date;
    end if;

    v_result := v_result || jsonb_build_object('checkpoint_passed', v_checkpoint_passed);
  end if;

  if p_position = 10 and v_attempt.status = 'in_progress' then
    v_result := v_result || public.finish_quiz(p_attempt_id);
  end if;

  return v_result;
end;
$$;

revoke execute on function public.submit_answer(uuid, int, text) from public;
grant execute on function public.submit_answer(uuid, int, text) to authenticated;

-- =========================================================================
-- 5) discover_profiles — 200 çağrı kotası -> günlük deste sınırı
-- (deck_profiles_served, ayarlanabilir app_settings.daily_deck_limit).
-- discover_calls_used hâlâ bilgi amaçlı sayılıyor ama artık gate değil.
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
  v_deck_limit    int;
  v_served        int;
  v_remaining     int;
  v_effective_limit int;
  v_result        jsonb;
  v_served_now    int;
begin
  if v_viewer_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  select city_id into v_viewer_city from public.profiles where id = v_viewer_id;
  if v_viewer_city is null then
    raise exception 'Profilin bulunamadı';
  end if;

  select value::int into v_deck_limit from public.app_settings where key = 'daily_deck_limit';

  select deck_profiles_served into v_served
    from public.daily_quotas
    where user_id = v_viewer_id and date = current_date;
  v_served := coalesce(v_served, 0);

  if v_served >= v_deck_limit then
    raise exception 'Günlük deste sınırına ulaştın';
  end if;

  v_remaining := v_deck_limit - v_served;
  v_effective_limit := least(p_limit, v_remaining);

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
    limit v_effective_limit;

  v_result := coalesce(v_result, '[]'::jsonb);
  v_served_now := jsonb_array_length(v_result);

  update public.daily_quotas
    set deck_profiles_served = deck_profiles_served + v_served_now
    where user_id = v_viewer_id and date = current_date;

  return v_result;
end;
$$;

revoke execute on function public.discover_profiles(int) from public;
grant execute on function public.discover_profiles(int) to authenticated;
