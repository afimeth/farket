-- Görev 6: profil kurulum fonksiyonları (get_taxonomy_items,
-- set_template_answer/remove_template_answer, custom_question içerik
-- filtresi, publish_profile).

BEGIN;
SELECT plan(23);

insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir');

SELECT tests.create_supabase_user('66660000-0000-0000-0000-000000000000', 'setup@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, username, status)
values ('66660000-0000-0000-0000-000000000000', 'S', '1995-01-01', 'female', 900001, 's_user', 'draft');

-- Soru altyapısı: 8 sabit şıklı act1 (easy/medium), 2 taksonomi tabanlı
-- act1 (hard), 2 act2-hard, hepsi 940000+ aralığında (üretim seed'iyle
-- çakışmasın diye).
insert into public.question_templates (id, body, act, default_difficulty) overriding system value
select g + 940000, 'Kalıp soru ' || g, 1, case when g <= 4 then 'easy' else 'medium' end
from generate_series(1, 8) g;
insert into public.template_options (id, template_id, body, position) overriding system value
select g + 941000, g + 940000, 'Şık A', 1 from generate_series(1, 8) g
union all
select g + 942000, g + 940000, 'Şık B', 2 from generate_series(1, 8) g;

insert into public.taxonomies (id, name, question_body, is_active) overriding system value
values (940101, 'Meslek', 'Mesleği ne?', true), (940102, 'Pasif', 'Kullanılmayan', false);
insert into public.taxonomy_items (id, taxonomy_id, label, is_active) overriding system value
values (940101, 940101, 'Öğretmen', true), (940102, 940101, 'Mühendis', true), (940103, 940101, 'Pasif Madde', false);
insert into public.taxonomy_adjacency (item_id, neighbor_item_id) values (940101, 940102), (940102, 940101);
insert into public.question_templates (id, body, act, default_difficulty, taxonomy_id) overriding system value
values (940201, 'Zor soru 1', 2, 'hard', 940101), (940202, 'Zor soru 2', 2, 'hard', 940101),
       (940110, 'Meslek nedir?', 1, 'hard', 940101);

-- 3. bir act2-zor soru: start_quiz'in 2. faz'ı yalnızca 1 custom + 1 künye
-- sorusunu garanti ediyor, kalanı act2-zor havuzundan dolduruyor (2 zor
-- soru tek başına yetmez), bu yüzden publish_profile artık en az 3 istiyor.
insert into public.question_templates (id, body, act, default_difficulty) overriding system value
values (940299, 'Zor soru 3', 2, 'hard');
insert into public.template_options (id, template_id, body, position) overriding system value
values (940391, 940299, 'Şık A', 1), (940392, 940299, 'Şık B', 2);

SELECT tests.authenticate_as('66660000-0000-0000-0000-000000000000');

-- ---------------------------------------------------------------------
-- get_taxonomy_items
-- ---------------------------------------------------------------------
SELECT is(
  public.get_taxonomy_items(940101),
  '[{"id": 940102, "label": "Mühendis"}, {"id": 940101, "label": "Öğretmen"}]'::jsonb,
  'get_taxonomy_items yalnızca aktif maddeleri döndürür (940103 pasif olduğu için yok)'
);

SELECT throws_ok(
  $$ select public.get_taxonomy_items(940102) $$,
  'Geçersiz taksonomi',
  'get_taxonomy_items, pasif bir taksonomide hata verir'
);

SELECT throws_ok(
  $$ select count(*) from public.taxonomy_items where taxonomy_id = 940101 $$,
  'permission denied for table taxonomy_items',
  'taxonomy_items hâlâ doğrudan hiç kimseye açık değil (yalnızca fonksiyon üzerinden)'
);

-- ---------------------------------------------------------------------
-- set_template_answer / remove_template_answer
-- ---------------------------------------------------------------------
SELECT lives_ok(
  $$ select public.set_template_answer(940001, 941001, null) $$,
  'Sabit şıklı soruya geçerli bir şık ile cevap yazılabilir'
);

SELECT throws_ok(
  $$ select public.set_template_answer(940001, null, 940101) $$,
  'Bu soruya bir cevap seçmen gerekiyor.',
  'Sabit şıklı soruya taksonomi maddesiyle cevap yazılamaz'
);

SELECT throws_ok(
  $$ select public.set_template_answer(940001, 942099, null) $$,
  'Seçtiğin şık bu soruya ait değil.',
  'Başka bir soruya ait şık kabul edilmiyor'
);

SELECT lives_ok(
  $$ select public.set_template_answer(940110, null, 940101) $$,
  'Taksonomi tabanlı soruya geçerli bir madde ile cevap yazılabilir'
);

SELECT throws_ok(
  $$ select public.set_template_answer(940110, null, 940103) $$,
  'Seçtiğin madde bu soruya ait değil.',
  'Pasif bir taksonomi maddesi cevap olarak kabul edilmiyor'
);

SELECT lives_ok(
  $$ select public.set_template_answer(940001, 942001, null) $$,
  'Aynı soruya ikinci kez cevap yazmak upsert ile günceller (hata vermez)'
);

-- profile_template_answers'a authenticated'ın hiç GRANT'ı yok (tamamen
-- kapalı tablo) — bu yüzden içeriğini postgres olarak (RLS/GRANT'ı
-- atlayarak) doğruluyoruz.
SELECT tests.clear_authentication();

SELECT is(
  (select selected_option_id from public.profile_template_answers
     where profile_id = '66660000-0000-0000-0000-000000000000' and template_id = 940001),
  942001,
  'Upsert sonrası şık gerçekten güncellenmiş'
);

SELECT tests.authenticate_as('66660000-0000-0000-0000-000000000000');

SELECT lives_ok(
  $$ select public.remove_template_answer(940001) $$,
  'remove_template_answer, kendi cevabını silebilir'
);

SELECT tests.clear_authentication();

SELECT is(
  (select count(*) from public.profile_template_answers
     where profile_id = '66660000-0000-0000-0000-000000000000' and template_id = 940001),
  0::bigint,
  'Silinen cevap gerçekten kalkmış'
);

SELECT tests.authenticate_as('66660000-0000-0000-0000-000000000000');

-- publish_profile'ın act1/act2 eşiklerini geçebilmesi için kalan
-- cevapları tamamla (7 act1 + 3 act2-hard).
SELECT public.set_template_answer(940001, 941001, null);
SELECT public.set_template_answer(940002, 941002, null);
SELECT public.set_template_answer(940003, 941003, null);
SELECT public.set_template_answer(940004, 941004, null);
SELECT public.set_template_answer(940005, 941005, null);
SELECT public.set_template_answer(940006, 941006, null);
SELECT public.set_template_answer(940201, null, 940101);
SELECT public.set_template_answer(940202, null, 940102);
SELECT public.set_template_answer(940299, 940391, null);

-- ---------------------------------------------------------------------
-- custom_questions / custom_options içerik filtresi
-- ---------------------------------------------------------------------
SELECT throws_ok(
  $$ insert into public.custom_questions (profile_id, body)
     values ('66660000-0000-0000-0000-000000000000', 'Bana 05551234567''den ulaş') $$,
  'Soru metni izin verilmeyen içerik barındırıyor (telefon/sosyal medya paylaşımı, şık yönlendirmesi ya da hakaret olamaz)',
  'Telefon numarası içeren soru metni reddediliyor'
);

SELECT throws_ok(
  $$ insert into public.custom_questions (profile_id, body)
     values ('66660000-0000-0000-0000-000000000000', 'Instagram''dan takip et @gizli_hesap') $$,
  'Soru metni izin verilmeyen içerik barındırıyor (telefon/sosyal medya paylaşımı, şık yönlendirmesi ya da hakaret olamaz)',
  'Sosyal medya yönlendirmesi içeren soru metni reddediliyor'
);

SELECT throws_ok(
  $$ insert into public.custom_questions (profile_id, body)
     values ('66660000-0000-0000-0000-000000000000', 'En sevdiğim renk? (ipucu: cevap C)') $$,
  'Soru metni izin verilmeyen içerik barındırıyor (telefon/sosyal medya paylaşımı, şık yönlendirmesi ya da hakaret olamaz)',
  'Şık yönlendirmesi içeren soru metni reddediliyor'
);

insert into public.custom_questions (id, profile_id, body)
values ('77770000-0000-0000-0000-000000000001', '66660000-0000-0000-0000-000000000000', 'En sevdiğim renk?');

SELECT throws_ok(
  $$ insert into public.custom_options (question_id, body, position)
     values ('77770000-0000-0000-0000-000000000001', 'whatsapp''tan yaz', 1) $$,
  'Şık metni izin verilmeyen içerik barındırıyor (telefon/sosyal medya paylaşımı, şık yönlendirmesi ya da hakaret olamaz)',
  'Şık metnindeki sosyal medya yönlendirmesi de reddediliyor'
);

insert into public.custom_options (id, question_id, body, position)
values
  ('77770000-0000-0000-0000-000000000002', '77770000-0000-0000-0000-000000000001', 'Mavi', 1),
  ('77770000-0000-0000-0000-000000000003', '77770000-0000-0000-0000-000000000001', 'Yeşil', 2);

-- ---------------------------------------------------------------------
-- publish_profile
-- ---------------------------------------------------------------------
SELECT throws_ok(
  $$ select public.publish_profile() $$,
  'Yayınlamadan önce 18 yaşını beyan etmelisin.',
  'age_attested_at yokken yayınlanamaz'
);

update public.profiles set age_attested_at = now() where id = '66660000-0000-0000-0000-000000000000';

SELECT throws_ok(
  $$ select public.publish_profile() $$,
  'Yayınlamadan önce künyeni tamamlamalısın.',
  'identity_card yokken yayınlanamaz'
);

insert into public.identity_card (profile_id, show_name) values ('66660000-0000-0000-0000-000000000000', true);

SELECT throws_ok(
  $$ select public.publish_profile() $$,
  'Yayınlamadan önce en az bir künye bilgisini quiz için işaretlemelisin.',
  'Quiz için işaretlenmiş künye bilgisi yokken yayınlanamaz'
);

insert into public.profile_identity_attributes (profile_id, attribute_type, value_numeric, is_quiz_eligible)
values ('66660000-0000-0000-0000-000000000000', 'height_cm', 170, true);

SELECT throws_ok(
  $$ select public.publish_profile() $$,
  'Fotoğraf sayın 5 ile 7 arasında olmalı (şu an 0).',
  'Fotoğraf yokken yayınlanamaz'
);

insert into public.photos (profile_id, position, storage_path_thumb, storage_path_full)
select '66660000-0000-0000-0000-000000000000', g,
       '66660000-0000-0000-0000-000000000000/' || g || '_thumb.webp',
       '66660000-0000-0000-0000-000000000000/' || g || '_full.webp'
from generate_series(1, 5) g;

SELECT throws_ok(
  $$ select public.publish_profile() $$,
  'Yayınlamadan önce doğru cevabı işaretlenmiş bir serbest soru eklemelisin.',
  'correct_option_id atanmamış serbest soru yeterli sayılmıyor'
);

update public.custom_questions set correct_option_id = '77770000-0000-0000-0000-000000000002'
  where id = '77770000-0000-0000-0000-000000000001';

SELECT is(
  public.publish_profile(),
  '{"status": "published"}'::jsonb,
  'Tüm eşikler karşılanınca publish_profile başarıyla yayınlar'
);

SELECT throws_ok(
  $$ select public.publish_profile() $$,
  'Bu profil zaten yayında.',
  'Zaten yayınlanmış bir profil ikinci kez yayınlanamaz'
);

SELECT tests.clear_authentication();

SELECT * FROM finish();
ROLLBACK;
