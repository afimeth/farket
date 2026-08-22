-- Görev 1 doğrulama testleri: gerçek production seed'i (140 kalıp soru +
-- 8 taksonomi havuzu) beklenen şekle uyuyor mu?
--
-- Fikstür kurmuyor — doğrudan migration'la yüklenmiş gerçek veriyi
-- sorguluyor.

BEGIN;
SELECT plan(9);

SELECT is((select count(*) from public.question_templates), 148::bigint, '148 kalıp soru (140 sabit şıklı + 8 taksonomi)');
SELECT is((select count(*) from public.template_options), 440::bigint, '440 şık (120×3 act1 + 20×4 act2)');
SELECT is((select count(*) from public.taxonomies), 8::bigint, '8 taksonomi havuzu');
SELECT is((select count(*) from public.taxonomy_items), 98::bigint, '98 taksonomi maddesi');
SELECT is((select count(*) from public.taxonomy_adjacency), 434::bigint, '434 yönlü komşuluk kaydı');

SELECT is(
  (select count(*) from public.question_templates qt
     join public.template_options o on o.template_id = qt.id
     where qt.act = 1
     group by qt.id having count(o.id) <> 3),
  null::bigint,
  'Her act 1 sorusunun tam olarak 3 şıkkı var (aykırı satır yok)'
);

SELECT is(
  (select count(*) from public.taxonomy_items ti
     left join public.taxonomy_adjacency a on a.item_id = ti.id
     group by ti.id having count(a.neighbor_item_id) < 4),
  null::bigint,
  'Her taksonomi maddesinin en az 4 komşusu var'
);

SELECT is(
  (select count(*) from public.taxonomy_adjacency a
     where not exists (
       select 1 from public.taxonomy_adjacency b
       where b.item_id = a.neighbor_item_id and b.neighbor_item_id = a.item_id
     )),
  0::bigint,
  'Komşuluk tamamen simetrik (tek yönlü kayıt yok)'
);

-- Kabul kriteri: en az komşulu (4) bir madde için pick_distractors zor
-- modda 20 kez çağrıldığında en az 4 farklı çeldirici kombinasyonu çıkar.
-- (least/greatest kullanılıyor — unnest'i korelasyonsuz alt sorguya
-- sarmak Postgres'te "initplan" tuzağına düşüyor, bkz. önceki commit.)
SELECT ok(
  (
    with worst_case as (
      select ti.id, ti.taxonomy_id
      from public.taxonomy_items ti
      join public.taxonomy_adjacency a on a.item_id = ti.id
      group by ti.id, ti.taxonomy_id
      order by count(a.neighbor_item_id) asc
      limit 1
    )
    select count(distinct (least(d[1], d[2]), greatest(d[1], d[2]))) >= 4
    from worst_case, lateral (
      select public.pick_distractors(worst_case.taxonomy_id, worst_case.id, 'hard') as d
      from generate_series(1, 20)
    ) calls
  ),
  'En az komşulu (4) gerçek madde için 20 çağrıda en az 4 farklı çeldirici kombinasyonu çıkıyor'
);

SELECT * FROM finish();
ROLLBACK;
