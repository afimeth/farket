-- pick_numeric_distractors(): numeric-spread distractor generator for
-- identity-derived quiz questions (height_cm/weight_kg/age).

BEGIN;
SELECT plan(6);

SELECT is(
  array_length(public.pick_numeric_distractors(178, 'height_cm'), 1),
  2,
  'height_cm için 2 çeldirici üretiliyor'
);

SELECT ok(
  not (178 = any (public.pick_numeric_distractors(178, 'height_cm'))),
  'height_cm çeldiricileri gerçek değere eşit değil'
);

SELECT ok(
  (select bool_and(d between 150 and 210) from unnest(public.pick_numeric_distractors(178, 'height_cm')) d),
  'height_cm çeldiricileri makul insan boyu aralığında (150-210cm)'
);

SELECT is(
  array_length(public.pick_numeric_distractors(68, 'weight_kg'), 1),
  2,
  'weight_kg için 2 çeldirici üretiliyor'
);

SELECT is(
  array_length(public.pick_numeric_distractors(24, 'age'), 1),
  2,
  'age için 2 çeldirici üretiliyor'
);

SELECT throws_ok(
  $$ select public.pick_numeric_distractors(100, 'school') $$,
  'pick_numeric_distractors: desteklenmeyen attribute_type: school',
  'Desteklenmeyen (metin) attribute_type için hata fırlatır'
);

SELECT * FROM finish();
ROLLBACK;
