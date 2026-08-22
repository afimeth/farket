-- Farket — quiz turları + soru çeşitliliği (22 Ağustos).
-- Bkz. 20260822040000_connection_rounds (round_no, _current_round).
--
-- İki değişiklik:
--
-- 1) TUR FARKINDALIĞI. Deneme sayımı ve ikinci-şans mantığı artık GÜNCEL TUR
--    içinde çalışıyor. Bağlantıdan çıkarma yeni bir tur açtığı için taraflar
--    birbirlerinin quizini baştan çözebiliyor; "profil başına ömürlük 2 deneme"
--    kuralı kalkmıyor, "tur başına 2 deneme"ye dönüşüyor.
--
-- 2) SORU ÇEŞİTLİLİĞİ. Daha önce görülmüş sorular SERT DIŞLANIYORDU
--    (`template_id <> all (excluded)`). Bunun iki sorunu vardı:
--      * Havuz yetmediğinde start_quiz 'soru havuzu yetersiz' diye patlıyordu —
--        yani ikinci deneme hakkı bazı profillerde fiilen kullanılamıyordu.
--      * Tur kavramıyla birlikte havuz kaçınılmaz olarak tükenecekti.
--    Artık dışlama yok, SIRALAMA TERCİHİ var: önce bu turda hiç çıkmamışlar,
--    sonra hiçbir turda çıkmamışlar, sonra rastgele. Havuzu geniş profillerde
--    kullanıcı pratikte hep yeni soru görür; havuzu dar profilde soru
--    tekrarlanabilir ama quiz her koşulda kurulabilir.
--
--    Zorluk dağılımı (2 kolay + 2 orta + 1 zor / 1 serbest + 1-2 künye + kalan
--    act2-zor) ve yedekleme (deficit) mantığı DEĞİŞMEDİ.

create or replace function public.start_quiz(p_target_profile_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_viewer_id       uuid := (select auth.uid());
  v_viewer_city     int;
  v_target_city     int;
  v_attempt_id      uuid;
  v_existing_count  int;
  v_hide            record;
  v_round_no        int;
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

  -- Sert dışlama listeleri yerine "görülmüşlük" tercihleri.
  v_seen_tpl_round  int[];
  v_seen_cq_round   uuid[];
  v_seen_ia_round   uuid[];
  v_seen_tpl_ever   int[];
  v_seen_cq_ever    uuid[];
  v_seen_ia_ever    uuid[];

  v_easy_ids        int[];
  v_medium_ids      int[];
  v_hard_ids        int[];
  v_take            int;
  v_deficit_easy    int;
  v_deficit_medium  int;
  v_deficit_hard    int;
  v_selected_ids    int[] := '{}';
  v_selected_id     int;

  v_identity_count      int;
  v_numeric_distractors numeric[];
  v_numeric_options     numeric[];
  v_attribute_label     text;
begin
  if v_viewer_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  if v_viewer_id = p_target_profile_id then
    raise exception 'Kendi profiline quiz başlatamazsın';
  end if;

  select city_id into v_target_city
    from public.profiles
    where id = p_target_profile_id and status = 'published';

  if not found then
    raise exception 'Hedef profil bulunamadı veya yayınlanmamış';
  end if;

  select city_id into v_viewer_city from public.profiles where id = v_viewer_id;

  if v_viewer_city is distinct from v_target_city then
    raise exception 'Bu profil senin şehrinde değil';
  end if;

  if exists (
    select 1 from public.blocks
    where (blocker_id = v_viewer_id and blocked_id = p_target_profile_id)
       or (blocker_id = p_target_profile_id and blocked_id = v_viewer_id)
  ) then
    raise exception 'Bu profille etkileşim engellenmiş';
  end if;

  v_round_no := public._current_round(v_viewer_id, p_target_profile_id);

  -- Deneme sayısı TUR İÇİNDE: bağlantıdan çıkarma sonrası yeni turda kullanıcı
  -- yeniden iki deneme hakkıyla başlar.
  select count(*) into v_existing_count
    from public.quiz_attempts
    where viewer_id = v_viewer_id and target_profile_id = p_target_profile_id
      and round_no = v_round_no;

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

  -- Bu turda çıkmış sorular.
  select coalesce(array_agg(distinct aq.template_id) filter (where aq.template_id is not null), '{}'),
         coalesce(array_agg(distinct aq.custom_question_id) filter (where aq.custom_question_id is not null), '{}'),
         coalesce(array_agg(distinct aq.identity_attribute_id) filter (where aq.identity_attribute_id is not null), '{}')
    into v_seen_tpl_round, v_seen_cq_round, v_seen_ia_round
    from public.attempt_questions aq
    join public.quiz_attempts qa on qa.id = aq.attempt_id
    where qa.viewer_id = v_viewer_id and qa.target_profile_id = p_target_profile_id
      and qa.round_no = v_round_no;

  -- Herhangi bir turda çıkmış sorular.
  select coalesce(array_agg(distinct aq.template_id) filter (where aq.template_id is not null), '{}'),
         coalesce(array_agg(distinct aq.custom_question_id) filter (where aq.custom_question_id is not null), '{}'),
         coalesce(array_agg(distinct aq.identity_attribute_id) filter (where aq.identity_attribute_id is not null), '{}')
    into v_seen_tpl_ever, v_seen_cq_ever, v_seen_ia_ever
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

  insert into public.quiz_attempts (viewer_id, target_profile_id, round_no, attempt_no, max_tier, credits_spent)
    values (v_viewer_id, p_target_profile_id, v_round_no, v_attempt_no, v_max_tier, v_credits_spent)
    returning id into v_attempt_id;

  perform public._notify(p_target_profile_id, 'quiz_started', null, v_attempt_id, null, '{}'::jsonb);

  -- ===== Perde 1 (1-5): 2 kolay + 2 orta + 1 zor, toleranslı yedekleme =====
  -- array_agg sırası önemli: aşağıdaki v_take mantığı dizinin başından aldığı
  -- için görülmemiş sorular otomatik olarak önce seçilir.

  select coalesce(array_agg(pta.template_id order by
           (pta.template_id = any (v_seen_tpl_round))::int,
           (pta.template_id = any (v_seen_tpl_ever))::int,
           random()), '{}') into v_easy_ids
    from public.profile_template_answers pta
    join public.question_templates qt on qt.id = pta.template_id
    where pta.profile_id = p_target_profile_id and qt.act = 1 and qt.is_active and pta.difficulty = 'easy';

  select coalesce(array_agg(pta.template_id order by
           (pta.template_id = any (v_seen_tpl_round))::int,
           (pta.template_id = any (v_seen_tpl_ever))::int,
           random()), '{}') into v_medium_ids
    from public.profile_template_answers pta
    join public.question_templates qt on qt.id = pta.template_id
    where pta.profile_id = p_target_profile_id and qt.act = 1 and qt.is_active and pta.difficulty = 'medium';

  select coalesce(array_agg(pta.template_id order by
           (pta.template_id = any (v_seen_tpl_round))::int,
           (pta.template_id = any (v_seen_tpl_ever))::int,
           random()), '{}') into v_hard_ids
    from public.profile_template_answers pta
    join public.question_templates qt on qt.id = pta.template_id
    where pta.profile_id = p_target_profile_id and qt.act = 1 and qt.is_active and pta.difficulty = 'hard';

  v_take := least(2, coalesce(array_length(v_easy_ids, 1), 0));
  v_selected_ids := v_selected_ids || v_easy_ids[1:v_take];
  v_easy_ids := v_easy_ids[v_take + 1:];
  v_deficit_easy := 2 - v_take;

  v_take := least(2, coalesce(array_length(v_medium_ids, 1), 0));
  v_selected_ids := v_selected_ids || v_medium_ids[1:v_take];
  v_medium_ids := v_medium_ids[v_take + 1:];
  v_deficit_medium := 2 - v_take;

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
    v_take := v_deficit_easy + v_deficit_medium + v_deficit_hard;
    v_selected_ids := v_selected_ids || (v_easy_ids || v_medium_ids || v_hard_ids)[1:v_take];
  end if;

  if coalesce(array_length(v_selected_ids, 1), 0) < 5 then
    raise exception 'Hedef profilin 1. perde için soru havuzu yetersiz (en az 5 kalıp soru cevaplanmış olmalı)';
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

  -- ===== Perde 2 (6-10) =====

  -- 2.1: tam olarak 1 serbest soru.
  select cq.id, cq.body into v_row
    from public.custom_questions cq
    where cq.profile_id = p_target_profile_id and cq.is_active
    order by (cq.id = any (v_seen_cq_round))::int,
             (cq.id = any (v_seen_cq_ever))::int,
             random()
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

  -- 2.2: künyedeki sayısal alanlardan 1-2 otomatik soru.
  v_identity_count := 0;
  for v_row in
    select pia.id, pia.attribute_type, pia.value_numeric
      from public.profile_identity_attributes pia
      where pia.profile_id = p_target_profile_id
        and pia.is_quiz_eligible
      order by (pia.id = any (v_seen_ia_round))::int,
               (pia.id = any (v_seen_ia_ever))::int,
               random()
      limit 2
  loop
    v_position := v_position + 1;
    v_identity_count := v_identity_count + 1;

    v_numeric_distractors := public.pick_numeric_distractors(v_row.value_numeric, v_row.attribute_type);
    v_numeric_options := array_append(v_numeric_distractors, v_row.value_numeric);

    v_attribute_label := case v_row.attribute_type
      when 'height_cm' then 'Boyu sence kaç cm?'
      when 'weight_kg' then 'Kilosu sence kaç kg?'
      when 'age'       then 'Yaşı sence kaç?'
      else 'Bu bilgi sence ne?'
    end;

    select jsonb_agg(jsonb_build_object('id', opt::text, 'body', opt::text) order by random())
      into v_shown
      from unnest(v_numeric_options) opt;

    insert into public.attempt_questions (attempt_id, position, identity_attribute_id, shown_option_ids, correct_option_id)
      values (
        v_attempt_id, v_position, v_row.id,
        jsonb_build_object('question_body', v_attribute_label, 'options', v_shown),
        v_row.value_numeric::text
      );
  end loop;

  if v_identity_count = 0 then
    raise exception 'Hedef profilin quiz için işaretlenmiş künye bilgisi yok';
  end if;

  -- 2.3: kalan yerler act-2 zor kalıp havuzundan.
  for v_row in
    select pta.template_id, pta.selected_option_id, pta.selected_item_id, pta.difficulty,
           qt.body, qt.taxonomy_id
    from public.profile_template_answers pta
    join public.question_templates qt on qt.id = pta.template_id
    where pta.profile_id = p_target_profile_id and qt.act = 2 and qt.default_difficulty = 'hard' and qt.is_active
      -- Perde 1'de zaten sorulmuş bir kalıp burada tekrar sorulamaz (aynı quiz
      -- içinde tekrar). Bu SERT kural, turlar arası tercihten farklı.
      and not exists (
        select 1 from public.attempt_questions aq
        where aq.attempt_id = v_attempt_id and aq.template_id = pta.template_id
      )
    order by (pta.template_id = any (v_seen_tpl_round))::int,
             (pta.template_id = any (v_seen_tpl_ever))::int,
             random()
    limit (10 - v_position)
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

  if v_position < 10 then
    raise exception 'Hedef profilin 2. perde soru havuzu yetersiz (özel/künye/zor kalıp soruları toplamda 10a tamamlayamadı)';
  end if;

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
    'attempt_id', v_attempt_id, 'attempt_no', v_attempt_no, 'round_no', v_round_no,
    'max_tier', v_max_tier, 'questions', v_result
  );
end;
$fn$;

revoke execute on function public.start_quiz(uuid) from public;
grant execute on function public.start_quiz(uuid) to authenticated;
