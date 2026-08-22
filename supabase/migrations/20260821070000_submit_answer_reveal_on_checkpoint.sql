-- submit_answer v2: on checkpoint pass (position 5, score >= 4), call
-- reveal_identity() inline and merge its result under an 'identity' key so
-- the Android client gets the hero-card congratulations data and the
-- identity-card reveal in the same round-trip as the checkpoint-pass
-- response, instead of requiring a second network call before it can show
-- the identity screen. Everything else in this function is unchanged from
-- the previous latest definition (20260818115714_v41_notification_progress.sql).

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

  -- İlerleme bildirimi: her cevaptan sonra, aynı denemenin öncekini bastırır.
  perform public._notify_progress(v_attempt.target_profile_id, p_attempt_id, p_position, v_new_score);

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

    if v_checkpoint_passed then
      v_result := v_result || jsonb_build_object('identity', public.reveal_identity(p_attempt_id));
    end if;
  end if;

  if p_position = 10 and v_attempt.status = 'in_progress' then
    v_result := v_result || public.finish_quiz(p_attempt_id);
  end if;

  return v_result;
end;
$$;
