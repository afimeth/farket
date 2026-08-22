-- Bugfix: BACKEND_BUG_zorluk_dagilimi.md raporunda tarif edilen sorun.
--
-- Onboarding'in 6/9 adımı ("Kalıp sorular — 1. perde") kullanıcıya yalnızca
-- TOPLAM cevap sayısını şart koşuyor ("en az 7"), ama start_quiz'in 1.
-- perde seçim algoritması (20260817011038_tiered_difficulty_selection.sql,
-- Migration 5'te hak sistemiyle güncellenmiş hâli) 3 easy + 3 medium +
-- 1 hard hedefliyor ve yedekleme yalnızca "kolay açığı ortadan, orta
-- açığı kolaydan, zor açığı ortadan" şeklinde sınırlı çapraz dolduruyor.
-- Kullanıcı toplamda 7 cevap verip wizard'ı geçebiliyor ama zorluk
-- dağılımı (örn. 5 easy + 2 medium + 0 hard) bu yedeklemeyle
-- kapanmıyorsa, start_quiz HER ZAMAN hata fırlatıyor ve profil kalıcı
-- olarak quizlenemez hale geliyor — hiçbir uyarı yayınlama anında
-- verilmiyor.
--
-- Seçilen çözüm (rapordaki 3 seçenekten "Öneri 2"): start_quiz'in kendisi
-- toleranslı hale getirildi. 3/3/1 hedefi ve yedekleme sırası aynen
-- korunuyor (mümkünse hâlâ dengeli bir dağılım seçiliyor), ama zorluk
-- bazlı yedekleme bittiğinde hâlâ açık varsa artık hata fırlatmak yerine
-- kalan havuzdan (hangi zorluktan olursa olsun) elde ne kaldıysa onunla
-- 7'ye tamamlanıyor. Yalnızca gerçekten 7'den AZ cevaplanmış kalıp
-- sorusu olan (yani wizard'ın "en az 7" şartını hiç sağlamamış) bir
-- profil için hata fırlatılmaya devam ediyor.
--
-- Bu, sadece yeni profiller için değil — fonksiyon her çağrıda çalıştığı
-- için, bu bug yüzünden zaten yayınlanmış ve şu an quizlenemez durumda
-- olan profiller de bu migration'dan sonra otomatik olarak düzeliyor,
-- ayrı bir geriye dönük veri düzeltmesi gerekmiyor.
--
-- Wizard tarafında per-tier validasyon eklenmesi (rapordaki Öneri 1)
-- kapsam dışı bırakıldı: bu backend-only düzeltme kendi başına yeterli
-- ve Android session'a bağımlı değil. DURUM.md'ye not düşüldü.

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

  -- BUGFIX: eskiden burada deficit kalmışsa hata fırlatılıyordu ("zorluk
  -- dağılımı karşılanamıyor"). Artık zorluk oranı garanti edilemese bile
  -- kalan havuzdan (hangi zorluktan olursa olsun) elde ne varsa onunla
  -- 7'ye tamamlanıyor — profil sırf zorluk dağılımı dengesiz diye
  -- quizlenemez hale gelmiyor.
  if v_deficit_easy + v_deficit_medium + v_deficit_hard > 0 then
    v_take := v_deficit_easy + v_deficit_medium + v_deficit_hard;
    v_selected_ids := v_selected_ids || (v_easy_ids || v_medium_ids || v_hard_ids)[1:v_take];
  end if;

  if coalesce(array_length(v_selected_ids, 1), 0) < 7 then
    raise exception 'Hedef profilin 1. perde için soru havuzu yetersiz (en az 7 kalıp soru cevaplanmış olmalı)';
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
