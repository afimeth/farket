-- Farket — bağlantı mesajlaşması (22 Ağustos). Bkz. 20260822040000_connection_rounds.
--
-- İki değişiklik:
--   a) send_message: bağlantı kurulmuş çiftte günlük 300 mesaj kotası uygulanmaz.
--      Bağlantı değilse (karşı taraf henüz hiç yazmadıysa) kota aynen işler —
--      kotanın asıl amacı olan tek taraflı yığın mesaj koruması bozulmaz.
--   b) send_message'ın 'closed' dalı artık ölü uç değil: bağlantıdan çıkarma
--      sonrası gönderen GÜNCEL TURDA quizi yeniden çözmüşse aynı sohbet satırı
--      yeniden açılır (çift başına tek satır kısıtı yeni satır açmaya izin vermiyor).
--   c) accept_conversation: tur > 1 ise kabul edenin de karşı tarafın quizini bu
--      turda geçmiş olması aranır — "tekrar birbirlerinin quizlerini çözmeleri
--      gerekli" kuralını fiilen uygulayan yer burası.

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
as $fn$
declare
  v_sender_id     uuid := (select auth.uid());
  v_conversation  record;
  v_had_conv      boolean;
  v_tier          int;
  v_char_limit    int;
  v_conv_id       uuid;
  v_calls_used    int;
  v_round         int;
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

  v_round := public._current_round(v_sender_id, p_target_profile_id);

  select * into v_conversation
    from public.conversations
    where (participant_a = v_sender_id and participant_b = p_target_profile_id)
       or (participant_a = p_target_profile_id and participant_b = v_sender_id)
    for update;
  v_had_conv := found;

  -- ---- İlk mesaj: sohbet hiç yok, ya da bağlantıdan çıkarılıp kapatılmış ----
  if not v_had_conv or v_conversation.status = 'closed' then
    select qa.unlocked_tier into v_tier
      from public.quiz_attempts qa
      where qa.viewer_id = v_sender_id and qa.target_profile_id = p_target_profile_id
        and qa.round_no = v_round
        and qa.status = 'completed' and qa.unlocked_tier > 0
      order by qa.unlocked_tier desc
      limit 1;

    if v_tier is null then
      if v_had_conv then
        raise exception 'Bu kişiyle yeniden iletişim kurmak için quizini baştan çözmen gerekiyor';
      else
        raise exception 'Bu kişiye mesaj isteği gönderme hakkın yok (en az 7 doğru cevap gerekiyor)';
      end if;
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

    select message_requests_used into v_calls_used
      from public.daily_quotas where user_id = v_sender_id and date = current_date;
    if coalesce(v_calls_used, 0) >= 10 then
      raise exception 'Günlük mesaj isteği kotan doldu';
    end if;

    if not v_had_conv then
      insert into public.conversations (participant_a, participant_b, status, expires_at, unlocked_tier, has_seal)
        values (v_sender_id, p_target_profile_id, 'pending', now() + interval '7 days', v_tier, v_tier = 10)
        returning id into v_conv_id;
    else
      -- Yeniden açılış. Yön de güncelleniyor: bu turda isteği gönderen taraf
      -- önceki turdakinden farklı olabilir ve participant_a "gönderen" demek
      -- (accept_conversation ve get_sender_identity buna dayanıyor).
      update public.conversations
        set status = 'pending',
            participant_a = v_sender_id,
            participant_b = p_target_profile_id,
            expires_at = now() + interval '7 days',
            unlocked_tier = v_tier,
            has_seal = (v_tier = 10)
        where id = v_conversation.id
        returning id into v_conv_id;
    end if;

    insert into public.messages
      (conversation_id, sender_id, body, char_limit_applied, referenced_photo_id, asked_question)
      values (v_conv_id, v_sender_id, p_body, v_char_limit, p_referenced_photo_id, p_asked_question);

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

  -- ---- Devam eden sohbet ----
  if v_conversation.status = 'accepted' then
    -- Bağlantı kurulmuşsa (iki taraf da yazmışsa) günlük kota uygulanmaz.
    if not public._is_connection(v_conversation.id) then
      select messages_sent_used into v_calls_used
        from public.daily_quotas where user_id = v_sender_id and date = current_date;
      if coalesce(v_calls_used, 0) >= 300 then
        raise exception 'Günlük mesaj gönderme kotan doldu, yarın tekrar dene';
      end if;

      insert into public.daily_quotas as dq (user_id, date, messages_sent_used)
        values (v_sender_id, current_date, 1)
        on conflict (user_id, date)
        do update set messages_sent_used = dq.messages_sent_used + 1;
    end if;

    insert into public.messages (conversation_id, sender_id, body, char_limit_applied)
      values (v_conversation.id, v_sender_id, p_body, null);

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
$fn$;

revoke execute on function public.send_message(uuid, text, uuid, text) from public;
grant execute on function public.send_message(uuid, text, uuid, text) to authenticated;

create or replace function public.accept_conversation(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_viewer_id uuid := (select auth.uid());
  v_conv      record;
  v_round     int;
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

  v_round := public._current_round(v_conv.participant_a, v_conv.participant_b);

  -- İlk turda davranış değişmiyor; yalnızca daha önce bağlantıdan çıkarma yaşamış
  -- çiftlerde kabul edenin de bu turda karşı tarafın quizini geçmiş olması aranıyor.
  if v_round > 1 and not exists (
    select 1 from public.quiz_attempts
    where viewer_id = v_viewer_id
      and target_profile_id = v_conv.participant_a
      and round_no = v_round
      and status = 'completed'
      and unlocked_tier > 0
  ) then
    raise exception 'Bağlantınız sonlandığı için, yeniden mesajlaşmadan önce senin de bu kişinin quizini çözmen gerekiyor';
  end if;

  update public.conversations set status = 'accepted' where id = p_conversation_id;

  perform public._notify(
    v_conv.participant_a, 'request_accepted', v_viewer_id, null, p_conversation_id, '{}'::jsonb
  );
end;
$fn$;

revoke execute on function public.accept_conversation(uuid) from public;
grant execute on function public.accept_conversation(uuid) to authenticated;
