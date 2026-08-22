-- Bugfix: mesajlaşma listesinde/detayında karşı tarafın @handle'ı hiçbir
-- zaman gelmiyordu ("@?"). Kök neden: istemci karşı tarafın username'ini
-- almak için public.profiles tablosuna DOĞRUDAN select atıyordu, ama
-- profiles_select_own RLS policy'si yalnızca id = auth.uid() şartını
-- sağlıyor — başka bir profili doğrudan tablo sorgusuyla okumak sessizce
-- boş dönüyor (RLS varsayılan-reddet). "username herkese açık" varsayımı
-- yalnızca discover_profiles()/get_public_profile() gibi SECURITY DEFINER
-- RPC'ler üzerinden geçerli, mesajlaşma ekranı bunları kullanmıyordu.
--
-- Çözüm: en dar kapsamlı seçenek — RLS'e dokunmadan, yalnızca çağıranın
-- gerçekten o konuşmanın bir tarafı olduğunu doğrulayıp karşı tarafın
-- username'ini döndüren SECURITY DEFINER bir fonksiyon. Rastgele bir
-- profile_id parametresi almak yerine bilerek conversation_id alıyor —
-- böylece bu fonksiyon, aralarında hiç konuşma olmayan profillerin
-- username'ini sorgulamak için kullanılamaz (get_public_profile zaten bu
-- işi genel amaçlı yapıyor, burada tekrar etmiyoruz).

create or replace function public.get_conversation_participant_username(p_conversation_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id uuid := (select auth.uid());
  v_conv      record;
  v_other_id  uuid;
  v_username  text;
begin
  if v_viewer_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  select participant_a, participant_b into v_conv
    from public.conversations
    where id = p_conversation_id;

  if not found or (v_conv.participant_a <> v_viewer_id and v_conv.participant_b <> v_viewer_id) then
    raise exception 'Bu konuşma sana ait değil';
  end if;

  v_other_id := case when v_conv.participant_a = v_viewer_id then v_conv.participant_b else v_conv.participant_a end;

  select username into v_username from public.profiles where id = v_other_id;

  return v_username;
end;
$$;

revoke execute on function public.get_conversation_participant_username(uuid) from public;
grant execute on function public.get_conversation_participant_username(uuid) to authenticated;
