-- Farket v4.1 — sonraki fazlar, Faz 2/6: bildirim ilerlemesi + kıl payı.
--
-- quiz_progress: her cevaptan sonra hedefe "birisi quizini X. soruda,
-- Y doğruyla sürdürüyor" bildirimi gider. Aynı denemenin önceki ilerleme
-- bildirimi superseded_by ile bastırılır (get_my_notifications listede
-- yalnızca EN GÜNCEL ilerlemeyi göstermeli — istemci superseded_by dolu
-- olan satırları filtrelemeli/gizlemeli, bkz. rapor).
--
-- near_miss: 6 doğruyla checkpoint sonrası biten (finish_quiz'e ulaşan)
-- denemelerde hedefe "kıl payı kaçırdın" bildirimi — GRUPLANMAZ (mevcut 4
-- günlük-gruplu tipin aksine), her olay kendi satırını alır çünkü somut
-- ve aksiyona açık bir olay (retry hemen mümkün).

-- =========================================================================
-- 0) notifications — progress_current/progress_score/is_near_miss/
-- superseded_by kolonları. Bunlar v4.1 §3'te notifications şeması
-- altında listelenmişti ama Migration 2 (additive kolonlar) yalnızca
-- type CHECK listesini genişletmişti, kolonların kendisi eklenmemişti —
-- burada, fiilen kullanılacakları yerde ekleniyor.
-- =========================================================================
alter table public.notifications
  add column progress_current int,
  add column progress_score   int,
  add column is_near_miss     boolean not null default false,
  add column superseded_by    uuid references public.notifications (id) on delete set null;

-- =========================================================================
-- 1) _notify_progress — quiz_progress'e özel, superseded_by zinciri kuran
-- dahili yardımcı. Genel _notify()'dan ayrı: o günlük-gruplama ya da
-- düz-insert deseni için tasarlandı, bu ise "aynı denemenin en güncel
-- satırı" deseni için.
-- =========================================================================
create or replace function public._notify_progress(
  p_user_id     uuid,
  p_attempt_id  uuid,
  p_position    int,
  p_score       int
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_id uuid;
  v_new_id uuid;
begin
  select id into v_old_id
    from public.notifications
    where user_id = p_user_id and type = 'quiz_progress' and attempt_id = p_attempt_id and superseded_by is null
    order by created_at desc
    limit 1;

  insert into public.notifications (user_id, type, attempt_id, payload, progress_current, progress_score)
    values (p_user_id, 'quiz_progress', p_attempt_id, '{}'::jsonb, p_position, p_score)
    returning id into v_new_id;

  if v_old_id is not null then
    update public.notifications set superseded_by = v_new_id where id = v_old_id;
  end if;
end;
$$;

revoke execute on function public._notify_progress(uuid, uuid, int, int) from public;

-- =========================================================================
-- 2) _notify — near_miss için is_near_miss bayrağını da yazabilsin diye
-- yedinci, DEFAULT'lu bir parametre eklendi. Eski 6 parametreli çağrılar
-- (start_quiz/finish_quiz/send_message/accept_conversation içindeki
-- perform _notify(...) satırları) hiç değişmeden çalışmaya devam eder.
-- DİKKAT: parametre eklemek eski imzayla YENİ bir overload yaratır (bkz.
-- send_message'da yaşanan "is not unique" hatası) — eski imza açıkça
-- DROP edilmeden iki sürüm birlikte yaşayıp ilk 6 argümanlı çağrıyı
-- belirsizleştirirdi.
-- =========================================================================
drop function if exists public._notify(uuid, text, uuid, uuid, uuid, jsonb);

create or replace function public._notify(
  p_user_id         uuid,
  p_type            text,
  p_actor_id        uuid,
  p_attempt_id      uuid,
  p_conversation_id uuid,
  p_payload         jsonb,
  p_is_near_miss    boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_type in ('quiz_started', 'identity_revealed', 'quiz_passed', 'perfect_score') then
    insert into public.notifications (user_id, type, actor_id, attempt_id, conversation_id, payload)
      values (p_user_id, p_type, p_actor_id, p_attempt_id, p_conversation_id,
              jsonb_build_object('count', 1) || p_payload)
    on conflict (user_id, type, ((created_at at time zone 'utc')::date))
      where type in ('quiz_started', 'identity_revealed', 'quiz_passed', 'perfect_score')
    do update set
      payload = notifications.payload || jsonb_build_object(
        'count', coalesce((notifications.payload ->> 'count')::int, 1) + 1
      ),
      actor_id = excluded.actor_id,
      attempt_id = excluded.attempt_id,
      conversation_id = excluded.conversation_id,
      read_at = null;
  else
    insert into public.notifications (user_id, type, actor_id, attempt_id, conversation_id, payload, is_near_miss)
      values (p_user_id, p_type, p_actor_id, p_attempt_id, p_conversation_id, p_payload, p_is_near_miss);
  end if;
end;
$$;

revoke execute on function public._notify(uuid, text, uuid, uuid, uuid, jsonb, boolean) from public;

-- =========================================================================
-- 3) submit_answer — her cevaptan sonra _notify_progress.
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
-- 4) finish_quiz — skor tam 6'da near_miss bildirimi (yalnızca attempt_no=1,
-- ikinci denemede "kıl payı" kavramı anlamsız — zaten son şans).
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
    when v_attempt.score >= 7 then least(v_attempt.score, v_attempt.max_tier)
    else 0
  end;

  if v_attempt.attempt_no = 1 and v_attempt.score < 7 then
    if v_attempt.score = 6 then
      v_wait := interval '0 days'; v_cost := 2;
      perform public._notify(
        v_attempt.target_profile_id, 'near_miss', null, p_attempt_id, null,
        jsonb_build_object('score', 6), true
      );
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
-- 5) get_my_notifications — superseded (eski ilerleme) satırları listeden
-- hariç tutuluyor artık (istemci ayrıca filtrelemek zorunda kalmasın),
-- progress_current/progress_score/is_near_miss alanları dönüşe eklendi.
-- =========================================================================
create or replace function public.get_my_notifications(p_limit int default 30)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := (select auth.uid());
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'Oturum açılmamış';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', x.id,
           'type', x.type,
           'payload', x.payload,
           'actor_username', x.actor_username,
           'progress_current', x.progress_current,
           'progress_score', x.progress_score,
           'is_near_miss', x.is_near_miss,
           'read_at', x.read_at,
           'created_at', x.created_at
         ) order by x.created_at desc), '[]'::jsonb)
    into v_result
    from (
      select n.id, n.type, n.payload, n.read_at, n.created_at,
             n.progress_current, n.progress_score, n.is_near_miss,
             case when n.type in ('message_request', 'request_accepted') then p.username else null end
               as actor_username
      from public.notifications n
      left join public.profiles p on p.id = n.actor_id
      where n.user_id = v_uid and n.superseded_by is null
      order by n.created_at desc
      limit p_limit
    ) x;

  return v_result;
end;
$$;

revoke execute on function public.get_my_notifications(int) from public;
grant execute on function public.get_my_notifications(int) to authenticated;
