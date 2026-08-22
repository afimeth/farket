-- Bulgu (backend, kritik → düzeltildi): Android tarafında fotoğraf sırası değiştirme
-- (moveUp/moveDown) iki ayrı UPDATE isteğiyle yapılıyordu (PhotosRepository.swapPositions).
-- İlk UPDATE, `photos_profile_id_position_key` unique kısıtına (profile_id, position) hemen
-- çarpıyordu, çünkü hedef position henüz diğer satırda boşalmamış oluyordu — canlı testte
-- "duplicate key value violates unique constraint" (23505) hatası olarak gözlemlendi.
-- Kısıt DEFERRABLE yapılmadan iki ayrı istek (iki ayrı transaction) hiçbir sırada güvenli
-- swap yapamaz. Çözüm: kısıtı DEFERRABLE INITIALLY DEFERRED yapıp, iki UPDATE'i tek bir
-- RPC transaction'ı içinde çalıştırmak (kontrol commit anına erteleniyor).

alter table public.photos
  drop constraint photos_profile_id_position_key,
  add constraint photos_profile_id_position_key
    unique (profile_id, position) deferrable initially deferred;

create or replace function public.swap_photo_positions(photo_a_id uuid, photo_b_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_pos_a int;
  v_pos_b int;
begin
  if v_uid is null then
    raise exception 'Oturum açılmamış';
  end if;

  select position into v_pos_a from public.photos where id = photo_a_id and profile_id = v_uid;
  select position into v_pos_b from public.photos where id = photo_b_id and profile_id = v_uid;

  if v_pos_a is null or v_pos_b is null then
    raise exception 'Fotoğraf bulunamadı';
  end if;

  update public.photos set position = v_pos_b where id = photo_a_id;
  update public.photos set position = v_pos_a where id = photo_b_id;
end;
$$;

grant execute on function public.swap_photo_positions(uuid, uuid) to authenticated;
