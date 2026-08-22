-- Bilinen boşluk (DURUM.md'de kayıtlıydı, Android session tarafından
-- bulunmuştu): get_my_notifications() dönüşünde conversation_id yoktu.
-- message_request/request_accepted bildirimleri bu yüzden istemcide
-- ilgili konuşma detayına deep-link atamıyordu. Tek satırlık ek.

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
           'conversation_id', x.conversation_id,
           'progress_current', x.progress_current,
           'progress_score', x.progress_score,
           'is_near_miss', x.is_near_miss,
           'read_at', x.read_at,
           'created_at', x.created_at
         ) order by x.created_at desc), '[]'::jsonb)
    into v_result
    from (
      select n.id, n.type, n.payload, n.read_at, n.created_at, n.conversation_id,
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
