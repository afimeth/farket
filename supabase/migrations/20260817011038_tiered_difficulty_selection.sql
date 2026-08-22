-- Farket: start_quiz'de 1. perde (soru 1-7) için katmanlı zorluk çekilişi
-- (Görev 2 — Sonraki Adımlar talimatı)
--
-- Sorun: önceki sürüm 7 soruyu act1 havuzundan TAMAMEN rastgele çekiyordu.
-- Kurulumdaki "en az 4 kolay, 3 orta" kuralı havuzu kısıtlıyordu, çekilişi
-- değil — aynı profili çözen iki kişi çok farklı zorlukta 7 soru
-- görebiliyordu, bu da 7/8/10 eşiklerinin anlamını taşımasını engelliyordu.
--
-- Çözüm: 3 kolay + 3 orta + 1 zor, her katman kendi içinde rastgele.
-- Yedekleme kuralı: kolay yetmezse ortadan, orta yetmezse kolaydan, zor
-- yetmezse ortadan tamamlanır (talimattaki sıra). Hiçbiri yetmezse
-- start_quiz hata döndürür — profil bu haliyle yayınlanmamalıydı.
--
-- Seçilen 7 sorunun POZİSYON sırası da ayrıca karıştırılıyor — yoksa
-- "1-3. pozisyonlar hep kolaydır" gibi öğrenilebilir bir örüntü oluşurdu,
-- ki bu tam olarak taksonomi sisteminin ve bu değişikliğin önlemeye
-- çalıştığı türden bir sızıntı.
--
-- 8-9 (act2-zor) ve 10 (serbest soru) mantığı DEĞİŞMEDİ.

create or replace function public.start_quiz(p_target_profile_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id       uuid := (select auth.uid());
  v_attempt_id      uuid;
  v_quiz_quota      int;
  v_position        int := 0;
  v_row             record;
  v_distractors     int[];
  v_option_ids      int[];
  v_shown           jsonb;
  v_correct         text;
  v_result          jsonb;

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

  if exists (
    select 1 from public.hidden_profiles
    where viewer_id = v_viewer_id and target_profile_id = p_target_profile_id
      and hidden_until > now()
  ) then
    raise exception 'Bu profil şu anda gizli, tekrar deneyemezsin';
  end if;

  if exists (
    select 1 from public.quiz_attempts
    where viewer_id = v_viewer_id and target_profile_id = p_target_profile_id
  ) then
    raise exception 'Bu profile zaten bir deneme açtın';
  end if;

  select quiz_attempts_used into v_quiz_quota
    from public.daily_quotas
    where user_id = v_viewer_id and date = current_date;
  if coalesce(v_quiz_quota, 0) >= 15 then
    raise exception 'Günlük quiz deneme kotan doldu';
  end if;

  insert into public.quiz_attempts (viewer_id, target_profile_id)
    values (v_viewer_id, p_target_profile_id)
    returning id into v_attempt_id;

  insert into public.daily_quotas as dq (user_id, date, quiz_attempts_used)
    values (v_viewer_id, current_date, 1)
    on conflict (user_id, date)
    do update set quiz_attempts_used = dq.quiz_attempts_used + 1;

  -- ---------------------------------------------------------------------
  -- 1-7: katmanlı zorluk çekilişi (3 kolay + 3 orta + 1 zor).
  -- ---------------------------------------------------------------------
  select coalesce(array_agg(pta.template_id order by random()), '{}') into v_easy_ids
    from public.profile_template_answers pta
    join public.question_templates qt on qt.id = pta.template_id
    where pta.profile_id = p_target_profile_id and qt.act = 1 and qt.is_active and pta.difficulty = 'easy';

  select coalesce(array_agg(pta.template_id order by random()), '{}') into v_medium_ids
    from public.profile_template_answers pta
    join public.question_templates qt on qt.id = pta.template_id
    where pta.profile_id = p_target_profile_id and qt.act = 1 and qt.is_active and pta.difficulty = 'medium';

  select coalesce(array_agg(pta.template_id order by random()), '{}') into v_hard_ids
    from public.profile_template_answers pta
    join public.question_templates qt on qt.id = pta.template_id
    where pta.profile_id = p_target_profile_id and qt.act = 1 and qt.is_active and pta.difficulty = 'hard';

  -- Her katmanın kendi hedefi.
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

  -- Yedekleme: kolay açığı ortadan, orta açığı kolaydan, zor açığı ortadan.
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

  -- Pozisyon sırası zorluğu ele vermesin diye seçilen 7'yi ayrıca karıştır.
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
  -- 8-9: hedefin act 2 + zor kalıp havuzundan rastgele 2 soru. DEĞİŞMEDİ.
  -- ---------------------------------------------------------------------
  for v_row in
    select pta.template_id, pta.selected_option_id, pta.selected_item_id, pta.difficulty,
           qt.body, qt.taxonomy_id
    from public.profile_template_answers pta
    join public.question_templates qt on qt.id = pta.template_id
    where pta.profile_id = p_target_profile_id and qt.act = 2 and qt.default_difficulty = 'hard' and qt.is_active
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
  -- 10: hedefin 5 serbest sorusundan rastgele 1. DEĞİŞMEDİ.
  -- ---------------------------------------------------------------------
  select cq.id, cq.body into v_row
    from public.custom_questions cq
    where cq.profile_id = p_target_profile_id and cq.is_active
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

  -- İstemciye dönecek: correct_option_id HARİÇ.
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

  return jsonb_build_object('attempt_id', v_attempt_id, 'questions', v_result);
end;
$$;

revoke execute on function public.start_quiz(uuid) from public;
grant execute on function public.start_quiz(uuid) to authenticated;
