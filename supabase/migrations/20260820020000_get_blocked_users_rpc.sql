-- Bulgu (backend, orta → düzeltildi): Ayarlar > Engellenenler ekranı, engellenen kullanıcının
-- adını göstermek için doğrudan `profiles` tablosuna select atıyordu (ReportsRepository.
-- listBlocked). `profiles` üzerindeki tek select politikası "yalnızca kendi profilin" olduğu
-- için (bkz. rls_policies.sql profiles_select_own) bu sorgu her zaman boş dönüyor ve istemci
-- "?" göstermek zorunda kalıyordu — canlı testte gözlemlendi. Mesajlaşmadaki
-- get_conversation_participant_username ile aynı desen: SECURITY DEFINER RPC, yalnızca
-- çağıranın kendi blocks satırlarını okuyup karşı tarafın username'ini döndürüyor.

create or replace function public.get_blocked_users()
returns table (profile_id uuid, username text)
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
    select p.id, p.username
    from public.blocks b
    join public.profiles p on p.id = b.blocked_id
    where b.blocker_id = v_uid
    order by b.created_at desc;
end;
$$;

grant execute on function public.get_blocked_users() to authenticated;
