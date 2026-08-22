-- Farket: pick_distractors + start_quiz (brifing v3, bölüm 9 adım 5)
--
-- Kararlaştırılan noktalar:
--   * pick_distractors, en zor seviyede bile yetersiz komşusu olan bir
--     maddeyle karşılaşırsa hata fırlatır (böyle maddeler profil kurulum
--     ekranında/veri küratörlüğünde havuzdan çıkarılmalı — bu bir çalışma
--     zamanı normal durumu değil, veri sorunudur).
--   * Quiz'e giren 10 sorunun zorluk dağılımı garanti edilmiyor; act 1
--     havuzundan (kullanıcının seçtiği kalıplar) tamamen rastgele 7 soru
--     çekiliyor.
--   * 8-10. sorular: hedefin act 2 + zor kalıp havuzundan rastgele 2 soru,
--     hedefin 5 serbest sorusundan rastgele 1 soru.
--   * Tüm kalıp sorularının (act 1 ve act 2) doğru cevabı
--     profile_template_answers'tan gelir — "zor kalıp sorular" ayrı,
--     sahipsiz bir havuz değildir; hedef profilin bunlardan da yeterli
--     sayıda seçmiş olması gerekir (bu, profil yayınlama doğrulamasına
--     eklenmesi gereken yeni bir kural — adım 4'te ele alınacak).

-- =========================================================================
-- pick_distractors — istemciye asla açılmaz, yalnızca start_quiz içinden
-- çağrılır.
-- =========================================================================
create or replace function public.pick_distractors(
  p_taxonomy_id       int,
  p_correct_item_id   int,
  p_difficulty        text
)
returns int[]
language plpgsql
security definer
set search_path = public
as $$
declare
  v_neighbors   int[];
  v_far         int[];
  v_difficulty  text := p_difficulty;
begin
  select coalesce(array_agg(ta.neighbor_item_id), '{}')
    into v_neighbors
    from public.taxonomy_adjacency ta
    join public.taxonomy_items ti on ti.id = ta.neighbor_item_id
    where ta.item_id = p_correct_item_id and ti.is_active;

  select coalesce(array_agg(ti.id), '{}')
    into v_far
    from public.taxonomy_items ti
    where ti.taxonomy_id = p_taxonomy_id
      and ti.is_active
      and ti.id <> p_correct_item_id
      and not (ti.id = any (v_neighbors));

  loop
    if v_difficulty = 'hard' and array_length(v_neighbors, 1) >= 2 then
      return (select array_agg(x) from (select unnest(v_neighbors) x order by random() limit 2) s);
    elsif v_difficulty = 'medium' and array_length(v_neighbors, 1) >= 1 and array_length(v_far, 1) >= 1 then
      return array[
        (select x from unnest(v_neighbors) x order by random() limit 1),
        (select x from unnest(v_far) x order by random() limit 1)
      ];
    elsif v_difficulty = 'easy' and array_length(v_far, 1) >= 2 then
      return (select array_agg(x) from (select unnest(v_far) x order by random() limit 2) s);
    end if;

    if v_difficulty = 'hard' then
      v_difficulty := 'medium';
    elsif v_difficulty = 'medium' then
      v_difficulty := 'easy';
    else
      raise exception
        'pick_distractors: taxonomy % madde % için yeterli çeldirici üretilemiyor (havuz çok küçük) — bu madde havuzdan çıkarılmalı',
        p_taxonomy_id, p_correct_item_id;
    end if;
  end loop;
end;
$$;

revoke execute on function public.pick_distractors(int, int, text) from public;

-- =========================================================================
-- start_quiz — istemcinin çağırdığı tek giriş noktası.
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
    where pta.profile_id = p_target_profile_id and qt.act = 1
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
    where pta.profile_id = p_target_profile_id and qt.act = 2 and qt.default_difficulty = 'hard'
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
