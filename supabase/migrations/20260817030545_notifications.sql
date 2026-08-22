-- Farket: notifications tablosu ve entegrasyonu (Görev 3)
--
-- Alan bazlı gizlilik: actor_id kim tarafından yapıldığını taşır ama
-- bazı bildirim tiplerinde (quiz_started, identity_revealed, quiz_passed,
-- perfect_score) bu KİMLİK istemciye asla gitmemeli — künye henüz
-- açılmamış birinin kimliğini "birisi quizini başlattı" bildiriminden
-- çıkarmak mümkün olmamalı. message_request/request_accepted'ta ise
-- künye zaten açılmış olduğu için gönderenin kimliği (username) açık.
--
-- Bu yüzden notifications tablosuna authenticated'a HİÇ GRANT verilmedi
-- (taxonomy_items/profile_template_answers ile aynı desen) — tüm erişim
-- get_my_notifications() üzerinden, alan bazlı filtrelenmiş JSON olarak.
--
-- Günlük gruplama: quiz_started/identity_revealed/quiz_passed/
-- perfect_score gibi "kimliksiz" bildirimler kullanıcı+tip+gün bazında
-- TEK satıra toplanır (payload.count artırılır) — aynı gün 40 kişi
-- quizini başlatırsa 40 ayrı bildirim gitmez. message_request ve
-- request_accepted GRUPLANMAZ — her biri ayrı, üzerinde işlem
-- (kabul/red) yapılması gereken somut bir olaydır.

create table public.notifications (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references public.profiles (id) on delete cascade,
  type              text not null check (
                      type in ('quiz_started', 'identity_revealed', 'quiz_passed',
                                'perfect_score', 'message_request', 'request_accepted')
                    ),
  actor_id          uuid references public.profiles (id) on delete set null,
  attempt_id        uuid references public.quiz_attempts (id) on delete set null,
  conversation_id   uuid references public.conversations (id) on delete set null,
  payload           jsonb not null default '{}'::jsonb,
  read_at           timestamptz,
  created_at        timestamptz not null default now()
);

-- Kimliksiz tiplerin günlük gruplaması için kısmi UNIQUE index —
-- ON CONFLICT hedefi bu.
create unique index idx_notifications_daily_group
  on public.notifications (user_id, type, ((created_at at time zone 'utc')::date))
  where type in ('quiz_started', 'identity_revealed', 'quiz_passed', 'perfect_score');

create index idx_notifications_user_created on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;
-- Bilerek hiçbir policy/GRANT yok — erişim yalnızca get_my_notifications().

-- =========================================================================
-- _notify — dahili yardımcı, istemciye asla açılmaz.
-- =========================================================================
create or replace function public._notify(
  p_user_id         uuid,
  p_type            text,
  p_actor_id        uuid,
  p_attempt_id      uuid,
  p_conversation_id uuid,
  p_payload         jsonb
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
    insert into public.notifications (user_id, type, actor_id, attempt_id, conversation_id, payload)
      values (p_user_id, p_type, p_actor_id, p_attempt_id, p_conversation_id, p_payload);
  end if;
end;
$$;

revoke execute on function public._notify(uuid, text, uuid, uuid, uuid, jsonb) from public;

-- =========================================================================
-- get_my_notifications — actor_id yalnızca kimliğin zaten açık olduğu
-- tiplerde (message_request, request_accepted) username olarak döner.
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
           'read_at', x.read_at,
           'created_at', x.created_at
         ) order by x.created_at desc), '[]'::jsonb)
    into v_result
    from (
      select n.id, n.type, n.payload, n.read_at, n.created_at,
             case when n.type in ('message_request', 'request_accepted') then p.username else null end
               as actor_username
      from public.notifications n
      left join public.profiles p on p.id = n.actor_id
      where n.user_id = v_uid
      order by n.created_at desc
      limit p_limit
    ) x;

  return v_result;
end;
$$;

revoke execute on function public.get_my_notifications(int) from public;
grant execute on function public.get_my_notifications(int) to authenticated;

-- =========================================================================
-- mark_notification_read
-- =========================================================================
create or replace function public.mark_notification_read(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'Oturum açılmamış';
  end if;

  update public.notifications
    set read_at = now()
    where id = p_notification_id and user_id = v_uid;
end;
$$;

revoke execute on function public.mark_notification_read(uuid) from public;
grant execute on function public.mark_notification_read(uuid) to authenticated;

-- =========================================================================
-- start_quiz — quiz_started bildirimi eklendi (tek değişiklik).
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

  -- quiz_started: kimliksiz, günlük gruplanır.
  perform public._notify(p_target_profile_id, 'quiz_started', null, v_attempt_id, null, '{}'::jsonb);

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

-- =========================================================================
-- finish_quiz — quiz_passed / perfect_score bildirimi eklendi. Burada
-- (submit_answer'da değil) eklendi ki quiz'in nasıl tamamlandığından
-- bağımsız (otomatik ya da doğrudan idempotent çağrı) TAM OLARAK BİR KEZ
-- tetiklensin — fonksiyonun zaten sahip olduğu "yalnızca in_progress'ten
-- completed'a ilk geçişte" koruması bunu doğal olarak sağlıyor.
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
    when v_attempt.score >= 8 then 8
    when v_attempt.score = 7 then 7
    else 0
  end;

  if v_attempt.score < 7 then
    insert into public.hidden_profiles (viewer_id, target_profile_id, hidden_until)
      values (v_attempt.viewer_id, v_attempt.target_profile_id, now() + interval '3 months')
      on conflict (viewer_id, target_profile_id)
      do update set hidden_until = excluded.hidden_until;
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
-- reveal_identity — identity_revealed bildirimi eklendi (yalnızca ilk
-- gerçek açılışta, tekrar çağrılarda yeniden bildirim gitmez — zaten
-- "not exists" korumasının içine eklendi).
-- =========================================================================
create or replace function public.reveal_identity(p_attempt_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id uuid := (select auth.uid());
  v_attempt   record;
  v_card      record;
  v_result    jsonb := '{}'::jsonb;
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

  if not v_attempt.checkpoint_passed then
    raise exception 'Checkpoint geçilmeden künye açılamaz';
  end if;

  select p.display_name, p.birth_date,
         ic.show_name, ic.show_age, ic.show_occupation, ic.show_city, ic.show_intent,
         ic.occupation, ic.intent,
         c.name as city_name
    into v_card
    from public.profiles p
    join public.identity_card ic on ic.profile_id = p.id
    join public.cities c on c.id = p.city_id
    where p.id = v_attempt.target_profile_id;

  if not found then
    raise exception 'Künye bulunamadı';
  end if;

  if v_card.show_name then
    v_result := v_result || jsonb_build_object('name', v_card.display_name);
  end if;

  if v_card.show_age then
    v_result := v_result || jsonb_build_object('age', extract(year from age(v_card.birth_date))::int);
  end if;

  if v_card.show_occupation then
    v_result := v_result || jsonb_build_object('occupation', v_card.occupation);
  end if;

  if v_card.show_city then
    v_result := v_result || jsonb_build_object('city', v_card.city_name);
  end if;

  if v_card.show_intent then
    v_result := v_result || jsonb_build_object('intent', v_card.intent);
  end if;

  if not exists (
    select 1 from public.identity_reveals
    where viewer_id = v_attempt.viewer_id and target_profile_id = v_attempt.target_profile_id
  ) then
    insert into public.identity_reveals (viewer_id, target_profile_id)
      values (v_attempt.viewer_id, v_attempt.target_profile_id);

    -- identity_revealed: kimliksiz, günlük gruplanır.
    perform public._notify(
      v_attempt.target_profile_id, 'identity_revealed', null, p_attempt_id, null, '{}'::jsonb
    );
  end if;

  return v_result;
end;
$$;

revoke execute on function public.reveal_identity(uuid) from public;
grant execute on function public.reveal_identity(uuid) to authenticated;

-- =========================================================================
-- send_message — message_request bildirimi eklendi (yalnızca yeni istek
-- açıldığında; künye zaten açık olduğu için gönderenin kimliği görünür).
-- =========================================================================
create or replace function public.send_message(p_target_profile_id uuid, p_body text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sender_id     uuid := (select auth.uid());
  v_conversation  record;
  v_tier          int;
  v_char_limit    int;
  v_conv_id       uuid;
  v_calls_used    int;
begin
  if v_sender_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  if v_sender_id = p_target_profile_id then
    raise exception 'Kendine mesaj gönderemezsin';
  end if;

  if exists (
    select 1 from public.blocks
    where (blocker_id = v_sender_id and blocked_id = p_target_profile_id)
       or (blocker_id = p_target_profile_id and blocked_id = v_sender_id)
  ) then
    raise exception 'Bu kullanıcıyla mesajlaşma engellenmiş';
  end if;

  select * into v_conversation
    from public.conversations
    where (participant_a = v_sender_id and participant_b = p_target_profile_id)
       or (participant_a = p_target_profile_id and participant_b = v_sender_id)
    for update;

  if not found then
    select unlocked_tier into v_tier
      from public.quiz_attempts
      where viewer_id = v_sender_id and target_profile_id = p_target_profile_id
        and status = 'completed' and unlocked_tier > 0;

    if not found then
      raise exception 'Bu kişiye mesaj isteği gönderme hakkın yok (en az 7 doğru cevap gerekiyor)';
    end if;

    v_char_limit := case when v_tier >= 8 then 100 else 50 end;

    if char_length(p_body) > v_char_limit then
      raise exception 'İlk mesaj en fazla % karakter olabilir', v_char_limit;
    end if;

    insert into public.conversations (participant_a, participant_b, status)
      values (v_sender_id, p_target_profile_id, 'pending')
      returning id into v_conv_id;

    insert into public.messages (conversation_id, sender_id, body, char_limit_applied)
      values (v_conv_id, v_sender_id, p_body, v_char_limit);

    select message_requests_used into v_calls_used
      from public.daily_quotas where user_id = v_sender_id and date = current_date;
    if coalesce(v_calls_used, 0) >= 10 then
      raise exception 'Günlük mesaj isteği kotan doldu';
    end if;

    insert into public.daily_quotas as dq (user_id, date, message_requests_used)
      values (v_sender_id, current_date, 1)
      on conflict (user_id, date)
      do update set message_requests_used = dq.message_requests_used + 1;

    -- message_request: kimlik açık (künye zaten görülmüş), gruplanmaz.
    perform public._notify(
      p_target_profile_id, 'message_request', v_sender_id, null, v_conv_id, '{}'::jsonb
    );

    return jsonb_build_object('conversation_id', v_conv_id, 'status', 'pending');
  end if;

  if v_conversation.status = 'accepted' then
    insert into public.messages (conversation_id, sender_id, body, char_limit_applied)
      values (v_conversation.id, v_sender_id, p_body, null);
    return jsonb_build_object('conversation_id', v_conversation.id, 'status', 'accepted');
  end if;

  if v_conversation.status = 'pending' and v_conversation.participant_a = v_sender_id then
    raise exception 'Zaten bekleyen bir mesaj isteğin var, karşı taraf kabul etmeden yeni mesaj gönderemezsin';
  end if;

  if v_conversation.status = 'pending' then
    raise exception 'Önce mesaj isteğini kabul etmelisin';
  end if;

  raise exception 'Bu konuşma kapalı';
end;
$$;

revoke execute on function public.send_message(uuid, text) from public;
grant execute on function public.send_message(uuid, text) to authenticated;

-- =========================================================================
-- accept_conversation — request_accepted bildirimi eklendi.
-- =========================================================================
create or replace function public.accept_conversation(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id uuid := (select auth.uid());
  v_conv      record;
begin
  if v_viewer_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  select * into v_conv from public.conversations where id = p_conversation_id for update;

  if not found or (v_conv.participant_a <> v_viewer_id and v_conv.participant_b <> v_viewer_id) then
    raise exception 'Bu konuşma sana ait değil';
  end if;

  if v_conv.participant_a = v_viewer_id then
    raise exception 'Kendi gönderdiğin mesaj isteğini kabul edemezsin';
  end if;

  if v_conv.status <> 'pending' then
    raise exception 'Bu istek zaten sonuçlanmış';
  end if;

  update public.conversations set status = 'accepted' where id = p_conversation_id;

  -- request_accepted: kimlik açık, gruplanmaz.
  perform public._notify(
    v_conv.participant_a, 'request_accepted', v_viewer_id, null, p_conversation_id, '{}'::jsonb
  );
end;
$$;

revoke execute on function public.accept_conversation(uuid) from public;
grant execute on function public.accept_conversation(uuid) to authenticated;
