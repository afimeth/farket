-- Taksonomi komşuluk sağlık kontrolü.
--
-- Görev 1'in kabul kriteri: her aktif taksonomi maddesinin en az 4 aktif
-- komşusu olmalı (havuzda 10'dan az madde varsa esneyebilir). Gerçek
-- içerik (140 soru / 8 taksonomi havuzu) seed'lendikten sonra bu sorguyu
-- çalıştır — boş sonuç = her şey yolunda.
--
-- Kullanım: supabase db execute'a yapıştır, ya da
--   docker exec supabase_db_farket psql -U postgres -f supabase/scripts/validate_taxonomy_adjacency.sql

with pool_sizes as (
  select taxonomy_id, count(*) as pool_size
  from public.taxonomy_items
  where is_active
  group by taxonomy_id
),
neighbor_counts as (
  select ti.id as item_id, ti.taxonomy_id, ti.label,
         count(ta.neighbor_item_id) filter (
           where exists (
             select 1 from public.taxonomy_items n
             where n.id = ta.neighbor_item_id and n.is_active
           )
         ) as neighbor_count
  from public.taxonomy_items ti
  left join public.taxonomy_adjacency ta on ta.item_id = ti.id
  where ti.is_active
  group by ti.id, ti.taxonomy_id, ti.label
)
select
  t.name as taxonomy,
  nc.label as item,
  nc.neighbor_count,
  ps.pool_size,
  case
    when ps.pool_size < 10 then 'havuz küçük (<10) — 4 komşu şartı esneyebilir'
    when nc.neighbor_count < 4 then 'YETERSİZ — en az 4 komşu gerekiyor'
    else 'ok'
  end as durum
from neighbor_counts nc
join pool_sizes ps on ps.taxonomy_id = nc.taxonomy_id
join public.taxonomies t on t.id = nc.taxonomy_id
where nc.neighbor_count < 4
order by t.name, nc.neighbor_count;

-- Komşuluğun gerçekten çift yönlü kaydedildiğini de doğrula (A→B varsa
-- B→A da olmalı). Boş sonuç = her şey yolunda.
select ta.item_id, ta.neighbor_item_id
from public.taxonomy_adjacency ta
where not exists (
  select 1 from public.taxonomy_adjacency ta2
  where ta2.item_id = ta.neighbor_item_id and ta2.neighbor_item_id = ta.item_id
);
