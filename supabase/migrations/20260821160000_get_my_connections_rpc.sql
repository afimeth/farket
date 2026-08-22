-- Farket: "Bağlantılarım" (ürün kararı, 21 Ağustos). Bir bağlantı, quiz çözmekle ya da
-- ilk etabı geçmekle DEĞİL, yalnızca karşılıklı mesajlaşmayla oluşur: sohbette her iki
-- tarafın da en az bir mesajı olmalı. Tek taraflı gönderilen mesaj bağlantı saymaz.
--
-- get_blocked_users ile aynı desen: profiles üzerindeki tek select politikası "yalnızca
-- kendi profilin" olduğu için karşı tarafın username'i istemciden okunamıyor; bu yüzden
-- SECURITY DEFINER bir RPC, çağıranın yalnızca kendi sohbetlerini okuyup karşı tarafın
-- görünen bilgisini döndürüyor.

create or replace function public.get_my_connections()
returns table (
  profile_id       uuid,
  username         text,
  conversation_id  uuid,
  connected_at     timestamptz,
  last_message_at  timestamptz
)
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

  return query
    select
      p.id,
      p.username,
      c.id,
      -- Bağlantının kurulduğu an = karşılıklılığın sağlandığı an, yani iki taraftan
      -- geç kalanın ilk mesajı. (İlk mesaj tek taraflıyken henüz bağlantı yoktu.)
      greatest(
        min(m.created_at) filter (where m.sender_id = v_uid),
        min(m.created_at) filter (where m.sender_id <> v_uid)
      ),
      max(m.created_at)
    from public.conversations c
    join public.profiles p
      on p.id = case when c.participant_a = v_uid then c.participant_b else c.participant_a end
    join public.messages m
      on m.conversation_id = c.id
    where (c.participant_a = v_uid or c.participant_b = v_uid)
      -- Engellenen ya da engelleyen taraf bağlantı listesinde görünmez.
      and not exists (
        select 1 from public.blocks b
        where (b.blocker_id = v_uid and b.blocked_id = p.id)
           or (b.blocker_id = p.id and b.blocked_id = v_uid)
      )
    group by p.id, p.username, c.id
    -- Karşılıklılık şartı: iki taraf da en az bir mesaj atmış olmalı.
    having count(*) filter (where m.sender_id = v_uid) > 0
       and count(*) filter (where m.sender_id <> v_uid) > 0
    order by max(m.created_at) desc;
end;
$$;

grant execute on function public.get_my_connections() to authenticated;

comment on function public.get_my_connections() is
  'Karşılıklı mesajlaşmanın gerçekleştiği sohbetleri "bağlantı" olarak döndürür; '
  'quiz/checkpoint durumuna bakmaz, tek taraflı mesajı bağlantı saymaz.';
