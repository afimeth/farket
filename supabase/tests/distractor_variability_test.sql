-- Görev 1 kabul kriteri (mekanizma kısmı): en az 4 komşusu olan bir
-- madde için pick_distractors zor modda art arda çağrıldığında farklı
-- çeldirici setleri dönüyor mu?
--
-- Gerçek içerik (140 soru / 8 taksonomi havuzu) henüz seed'lenmediği
-- için burada sentetik bir madde kullanılıyor — asıl kanıt, seed
-- sonrası supabase/scripts/validate_taxonomy_adjacency.sql çalıştırılıp
-- boş sonuç alınmasıdır.

BEGIN;
SELECT plan(2);

-- NOT: id'ler yüksek bir aralıkta (920000+) — production seed migration'ı
-- taxonomies/taxonomy_items'ı 1'den başlayarak dolduruyor, çakışmasın diye.
insert into public.taxonomies (id, name, question_body) overriding system value
values (920001, 'Test Havuzu', 'Test sorusu?');

-- Madde 920001'in 4 komşusu var — zor modda C(4,2)=6 farklı çeldirici
-- kombinasyonu mümkün.
insert into public.taxonomy_items (id, taxonomy_id, label) overriding system value
values (920001, 920001, 'A'), (920002, 920001, 'B'), (920003, 920001, 'C'),
       (920004, 920001, 'D'), (920005, 920001, 'E'), (920006, 920001, 'F');

insert into public.taxonomy_adjacency (item_id, neighbor_item_id)
values
  (920001, 920002), (920002, 920001),
  (920001, 920003), (920003, 920001),
  (920001, 920004), (920004, 920001),
  (920001, 920005), (920005, 920001);

-- 30 kez zor modda çeldirici üret, kaç farklı (sırasız) ikili kombinasyon
-- çıktığını say.
--
-- NOT: pick_distractors'ı unnest() ile SELECT listesinde saran korelasyonsuz
-- bir alt sorguya sarmıyoruz — Postgres bu deseni "initplan" olarak TEK
-- SEFER değerlendirip sonucu her satıra kopyalıyor (volatile bir fonksiyon
-- olsa bile). Bu tuzağa bu testi yazarken düşüldü; least/greatest ile aynı
-- satırda doğrudan karşılaştırmak bu sorunu tamamen atlıyor.
SELECT ok(
  (
    select count(distinct (least(d[1], d[2]), greatest(d[1], d[2]))) > 1
    from (select public.pick_distractors(920001, 920001, 'hard') as d from generate_series(1, 30)) t
  ),
  '4 komşulu bir madde için 30 çağrıda birden fazla farklı çeldirici kombinasyonu çıkıyor'
);

-- Üretilen çeldiriciler her zaman gerçek komşulardan geliyor (madde
-- kendisi asla çeldirici olarak dönmüyor).
SELECT ok(
  (
    select bool_and(920001 <> d[1] and 920001 <> d[2])
    from (select public.pick_distractors(920001, 920001, 'hard') as d from generate_series(1, 10)) t
  ),
  'Doğru maddenin kendisi hiçbir zaman çeldirici olarak dönmüyor'
);

SELECT * FROM finish();
ROLLBACK;
