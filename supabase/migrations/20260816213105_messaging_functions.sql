-- Farket: mesajlaşma (brifing v3, bölüm 9 adım 10 — mesajlaşma kısmı)
--
-- Şema düzeltmesi: messages.char_limit_applied NOT NULL + CHECK (50,100)
-- idi, ama "karşı taraf kabul ederse karakter sınırı kalkar" kuralı hem
-- 50 hem 100'den FARKLI bir durumu (sınırsız) gerektiriyor. NULL = sınırsız
-- yapıldı; char_length(body) <= char_limit_applied kısıtı NULL ile
-- otomatik geçer (Postgres'te NULL'lu karşılaştırma CHECK'i ihlal etmez).
--
-- accept_conversation / decline_conversation brifingde açıkça listelenmiş
-- fonksiyonlar değil ama "karşı taraf kabul ederse / reddederse" davranışı
-- bir kabul/red mekanizması gerektiriyor — start_quiz/questions.photo_id
-- gibi önceki eklemelerle aynı gerekçeyle eklendi.
--
-- conversations.status'e 'closed' eklendi (delete_account akışında
-- kullanılacak — bir sonraki migration).

alter table public.messages alter column char_limit_applied drop not null;
alter table public.messages drop constraint messages_char_limit_applied_check;
alter table public.messages add constraint messages_char_limit_applied_check
  check (char_limit_applied is null or char_limit_applied in (50, 100));

alter table public.conversations drop constraint conversations_status_check;
alter table public.conversations add constraint conversations_status_check
  check (status in ('pending', 'accepted', 'declined', 'blocked', 'closed'));

-- =========================================================================
-- send_message
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
    -- Yeni bir mesaj isteği: yalnızca 7+ doğrulanmış (tamamlanmış,
    -- unlocked_tier > 0) bir deneme varsa açılabilir.
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
-- accept_conversation / decline_conversation
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
end;
$$;

create or replace function public.decline_conversation(p_conversation_id uuid)
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

  if v_conv.status <> 'pending' then
    raise exception 'Bu istek zaten sonuçlanmış';
  end if;

  update public.conversations set status = 'declined' where id = p_conversation_id;
end;
$$;

revoke execute on function public.accept_conversation(uuid) from public;
revoke execute on function public.decline_conversation(uuid) from public;
grant execute on function public.accept_conversation(uuid) to authenticated;
grant execute on function public.decline_conversation(uuid) to authenticated;

-- =========================================================================
-- Bir kullanıcı diğerini engellediğinde aralarındaki açık konuşma kapanır.
-- blocks tablosuna doğrudan insert authenticated'a açık (adım 1) — bu
-- trigger, "engellerse konuşma kapanır" kuralını RLS'in dışında, veri
-- bütünlüğü seviyesinde garanti eder.
-- =========================================================================
create or replace function public.close_conversation_on_block()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.conversations
    set status = 'blocked'
    where status in ('pending', 'accepted')
      and ((participant_a = new.blocker_id and participant_b = new.blocked_id)
        or (participant_a = new.blocked_id and participant_b = new.blocker_id));
  return new;
end;
$$;

create trigger trg_close_conversation_on_block
  after insert on public.blocks
  for each row execute function public.close_conversation_on_block();
