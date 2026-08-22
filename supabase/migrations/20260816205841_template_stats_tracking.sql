-- Farket: template_stats güncellemesi + taban oran filtresi
-- (brifing v3, bölüm 9 adım 7)
--
-- Tasarım kararı: brifing bu güncellemeyi finish_quiz'in sorumluluğu
-- olarak listeliyor, ama onu submit_answer'a taşıdım — her cevap
-- VERİLDİĞİ anda sayılıyor, deneme sonunda toplu değil. Gerekçe:
--   * finish_quiz yalnızca denemeyi TAMAMLAYAN (10/10) kullanıcılar için
--     çalışıyor. Checkpoint'te başarısız olan denemelerin ilk 5 cevabı
--     da gerçek bir seçimdir ve istatistiğe dahil edilmeli — yoksa veri
--     sistematik olarak "checkpoint'i geçebilen dikkatli kullanıcılar"a
--     yanlı kalır.
--   * Cevap anında sayarsak çift sayım riski hiç oluşmaz (her cevap tam
--     bir kez eklenir); checkpoint ve finish'te ayrı ayrı toplu güncelleme
--     yapılsaydı bu ayrımı elle yönetmek gerekirdi.
--
-- Örneklem eşiği (>=20 seçim) brifingde belirtilmemiş bir eklentidir —
-- küçük örneklemde (ör. 2 seçimden 2'si aynı yönde) gürültüyle
-- yanlışlıkla pasifleşmeyi önlemek için eklendi.

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

  -- Taban oran takibi: yalnızca kalıp sorularda (custom sorularda yok —
  -- template_stats'ın FK'si question_templates'e, custom_questions'a değil).
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

    if not v_checkpoint_passed then
      insert into public.hidden_profiles (viewer_id, target_profile_id, hidden_until)
        values (v_attempt.viewer_id, v_attempt.target_profile_id, now() + interval '3 months')
        on conflict (viewer_id, target_profile_id)
        do update set hidden_until = excluded.hidden_until;
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
-- start_quiz — is_active filtresi eklendi.
-- Taban oran filtresi bir kalıbı pasifleştirdiğinde (yukarıdaki
-- submit_answer), start_quiz bunu artık yeni denemelere seçmemeli. Adım
-- 5'te bu filtre unutulmuştu (o an is_active hiç değişmiyordu, fark
-- etmiyordu); şimdi düzeltiliyor. Fonksiyonun geri kalanı değişmedi.
-- =========================================================================
create or replace function public.start_quiz(p_target_profile_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id     uuid := (select auth.uid());
  v_attempt_id    uuid;
  v_quiz_quota    int;
  v_position      int := 0;
  v_row           record;
  v_distractors   int[];
  v_option_ids    int[];
  v_shown         jsonb;
  v_correct       text;
  v_result        jsonb;
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

  -- 1-7: hedefin act 1 havuzundan rastgele 7 soru.
  for v_row in
    select pta.template_id, pta.selected_option_id, pta.selected_item_id, pta.difficulty,
           qt.body, qt.taxonomy_id
    from public.profile_template_answers pta
    join public.question_templates qt on qt.id = pta.template_id
    where pta.profile_id = p_target_profile_id and qt.act = 1 and qt.is_active
    order by random()
    limit 7
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

  if v_position < 7 then
    raise exception 'Hedef profilin act 1 soru havuzu yetersiz (en az 7 kalıp soru seçmiş olmalı)';
  end if;

  -- 8-9: hedefin act 2 + zor kalıp havuzundan rastgele 2 soru.
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

  -- 10: hedefin 5 serbest sorusundan rastgele 1.
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
