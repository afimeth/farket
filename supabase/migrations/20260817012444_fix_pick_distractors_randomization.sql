-- Farket: pick_distractors'taki rastgelelik hatasını düzelt.
--
-- Görev 1'in "pick_distractors aynı madde için art arda çağrıldığında
-- farklı çeldirici setleri dönüyor" kabul kriterini test ederken ortaya
-- çıktı: 'hard' ve 'easy' dallarında kullanılan
--   (select array_agg(x) from (select unnest(arr) x order by random() limit n) s)
-- kalıbı, Postgres'te unnest() SELECT listesinde (FROM yerine)
-- kullanıldığında ORDER BY random()'ı SESSİZCE ETKİSİZ bırakıyor —
-- hata vermiyor, sadece her zaman aynı (dizideki ilk n) elemanı
-- döndürüyor. Elle doğrulandı: 10 art arda çağrıda her seferinde aynı
-- sonuç çıktı.
--
-- 'medium' dalı zaten doğru kalıbı (from unnest(arr) x order by random())
-- kullanıyordu, o yüzden etkilenmedi.
--
-- Bu, taksonomi sisteminin BÜTÜN amacını (aynı ekranın her ziyaretçiye
-- gösterilmesini engellemek) sessizce boşa çıkaran ciddi bir hataydı —
-- 2 komşuyla zaten fark edilmiyordu (zaten tek kombinasyon vardı), ama
-- Görev 1'de komşu sayısı 4'e çıkarılınca hatanın etkisi ortaya çıktı.

create or replace function public.pick_distractors(
  p_taxonomy_id       int,
  p_correct_item_id   int,
  p_difficulty        text
)
returns int[]
language plpgsql
security definer
set search_path = public
as $$
declare
  v_neighbors   int[];
  v_far         int[];
  v_difficulty  text := p_difficulty;
begin
  select coalesce(array_agg(ta.neighbor_item_id), '{}')
    into v_neighbors
    from public.taxonomy_adjacency ta
    join public.taxonomy_items ti on ti.id = ta.neighbor_item_id
    where ta.item_id = p_correct_item_id and ti.is_active;

  select coalesce(array_agg(ti.id), '{}')
    into v_far
    from public.taxonomy_items ti
    where ti.taxonomy_id = p_taxonomy_id
      and ti.is_active
      and ti.id <> p_correct_item_id
      and not (ti.id = any (v_neighbors));

  loop
    if v_difficulty = 'hard' and array_length(v_neighbors, 1) >= 2 then
      return (select array_agg(x) from (select x from unnest(v_neighbors) x order by random() limit 2) s);
    elsif v_difficulty = 'medium' and array_length(v_neighbors, 1) >= 1 and array_length(v_far, 1) >= 1 then
      return array[
        (select x from unnest(v_neighbors) x order by random() limit 1),
        (select x from unnest(v_far) x order by random() limit 1)
      ];
    elsif v_difficulty = 'easy' and array_length(v_far, 1) >= 2 then
      return (select array_agg(x) from (select x from unnest(v_far) x order by random() limit 2) s);
    end if;

    if v_difficulty = 'hard' then
      v_difficulty := 'medium';
    elsif v_difficulty = 'medium' then
      v_difficulty := 'easy';
    else
      raise exception
        'pick_distractors: taxonomy % madde % için yeterli çeldirici üretilemiyor (havuz çok küçük) — bu madde havuzdan çıkarılmalı',
        p_taxonomy_id, p_correct_item_id;
    end if;
  end loop;
end;
$$;

revoke execute on function public.pick_distractors(int, int, text) from public;
