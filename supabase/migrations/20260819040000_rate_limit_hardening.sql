-- Bulgu (backend, orta öncelik): send_message'ın YENİ mesaj isteği dalı zaten günlük
-- kotaya tabiydi (message_requests_used, günde 10), ama zaten kabul edilmiş bir
-- konuşma içindeki mesajların (status = 'accepted' dalı) HİÇBİR limiti yoktu — bir
-- kullanıcı aynı konuşmaya saniyede onlarca mesaj gönderebilirdi. Aynı şekilde
-- public.reports'a INSERT tamamen doğrudan PostgREST üzerinden açıktı (grants.sql),
-- rate limiting hiç yoktu — sahte/spam şikayetle moderasyon kuyruğu şişirilebilirdi.
-- İkisi de burada, mevcut daily_quotas desenine uyacak şekilde kapatılıyor.

alter table public.daily_quotas
  add column if not exists messages_sent_used int not null default 0;

create or replace function public.send_message(
  p_target_profile_id    uuid,
  p_body                 text,
  p_referenced_photo_id  uuid default null,
  p_asked_question       text default null
)
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

    if p_referenced_photo_id is not null then
      if v_tier < 8 then
        raise exception 'Fotoğraf referansı göndermek için en az 8 doğru cevap gerekiyor';
      end if;
      if not exists (
        select 1 from public.photos
        where id = p_referenced_photo_id and profile_id = p_target_profile_id and moderation_status = 'approved'
      ) then
        raise exception 'Geçersiz fotoğraf referansı';
      end if;
    end if;

    if p_asked_question is not null then
      if v_tier < 9 then
        raise exception 'Soru sormak için en az 9 doğru cevap gerekiyor';
      end if;
      if char_length(p_asked_question) > 100 then
        raise exception 'Sorulan soru en fazla 100 karakter olabilir';
      end if;
    end if;

    insert into public.conversations (participant_a, participant_b, status, expires_at, unlocked_tier, has_seal)
      values (v_sender_id, p_target_profile_id, 'pending', now() + interval '7 days', v_tier, v_tier = 10)
      returning id into v_conv_id;

    insert into public.messages
      (conversation_id, sender_id, body, char_limit_applied, referenced_photo_id, asked_question)
      values (v_conv_id, v_sender_id, p_body, v_char_limit, p_referenced_photo_id, p_asked_question);

    select message_requests_used into v_calls_used
      from public.daily_quotas where user_id = v_sender_id and date = current_date;
    if coalesce(v_calls_used, 0) >= 10 then
      raise exception 'Günlük mesaj isteği kotan doldu';
    end if;

    insert into public.daily_quotas as dq (user_id, date, message_requests_used)
      values (v_sender_id, current_date, 1)
      on conflict (user_id, date)
      do update set message_requests_used = dq.message_requests_used + 1;

    perform public._notify(
      p_target_profile_id, 'message_request', v_sender_id, null, v_conv_id, '{}'::jsonb
    );

    if v_tier = 10 then
      if not exists (
        select 1 from public.identity_reveals
        where viewer_id = p_target_profile_id and target_profile_id = v_sender_id
      ) then
        insert into public.identity_reveals (viewer_id, target_profile_id)
          values (p_target_profile_id, v_sender_id);
      end if;
    end if;

    return jsonb_build_object('conversation_id', v_conv_id, 'status', 'pending');
  end if;

  if v_conversation.status = 'accepted' then
    select messages_sent_used into v_calls_used
      from public.daily_quotas where user_id = v_sender_id and date = current_date;
    if coalesce(v_calls_used, 0) >= 300 then
      raise exception 'Günlük mesaj gönderme kotan doldu, yarın tekrar dene';
    end if;

    insert into public.messages (conversation_id, sender_id, body, char_limit_applied)
      values (v_conversation.id, v_sender_id, p_body, null);

    insert into public.daily_quotas as dq (user_id, date, messages_sent_used)
      values (v_sender_id, current_date, 1)
      on conflict (user_id, date)
      do update set messages_sent_used = dq.messages_sent_used + 1;

    return jsonb_build_object('conversation_id', v_conversation.id, 'status', 'accepted');
  end if;

  if v_conversation.status = 'pending' and v_conversation.expires_at < now() then
    raise exception 'Bu mesaj isteğinin süresi doldu';
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

revoke execute on function public.send_message(uuid, text, uuid, text) from public;
grant execute on function public.send_message(uuid, text, uuid, text) to authenticated;

-- reports: doğrudan PostgREST INSERT'i (grants.sql) trigger ile sınırlandırılıyor —
-- ayrı bir RPC'ye çevirmek istemci tarafını da değiştirmeyi gerektirirdi, trigger
-- mevcut yazma yolunu koruyarak sınırı ekliyor.
create or replace function public.enforce_report_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count_today int;
begin
  select count(*) into v_count_today
    from public.reports
    where reporter_id = new.reporter_id
      and created_at >= now() - interval '24 hours';

  if v_count_today >= 20 then
    raise exception 'Bugün çok fazla şikayet gönderdin, yarın tekrar dene';
  end if;

  return new;
end;
$$;

drop trigger if exists reports_rate_limit on public.reports;
create trigger reports_rate_limit
  before insert on public.reports
  for each row execute function public.enforce_report_rate_limit();
