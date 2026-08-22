-- Yalnızca yerel geliştirme/test ortamında çalışır (supabase db reset /
-- supabase test db). `supabase db push` migration'ları uzak veritabanına
-- gönderir ama bu dosyayı GÖNDERMEZ — bu yüzden test yardımcıları burada.

create schema if not exists tests;

-- Gerçek auth akışından geçmeden minimal bir auth.users satırı oluşturur.
create or replace function tests.create_supabase_user(user_id uuid, user_email text)
returns void
language plpgsql
security definer
set search_path = auth, public
as $$
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data
  ) values (
    '00000000-0000-0000-0000-000000000000', user_id, 'authenticated', 'authenticated',
    user_email, 'x', now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb
  );
end;
$$;

-- Test isteğini, verilen kullanıcı olarak gelmiş gibi işaretler
-- (auth.uid()'in okuduğu request.jwt.claims GUC'unu doldurur) ve rolü
-- `authenticated` yapar. BEGIN ... ROLLBACK içinde `set local` olduğu için
-- işlem bitince kendiliğinden geri alınır.
create or replace function tests.authenticate_as(user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', user_id::text, 'role', 'authenticated')::text,
    true
  );
  execute 'set local role authenticated';
end;
$$;

create or replace function tests.clear_authentication()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$$;

-- Testler bir kullanıcıdan diğerine geçerken (authenticated rolündeyken)
-- tekrar tests.authenticate_as() çağırabilmeli; bu yüzden bu iki fonksiyon
-- authenticated rolüne açık. create_supabase_user() kasıtlı olarak açık
-- DEĞİL — yalnızca fixture kurulumunda, henüz postgres/superuser iken
-- çağrılır.
grant usage on schema tests to authenticated;
grant execute on function tests.authenticate_as(uuid) to authenticated;
grant execute on function tests.clear_authentication() to authenticated;

-- Bir profili quiz'e hazır hale getirir: paylaşılan global şablon
-- kütüphanesinden (template 930001-930007 act1 sabit şıklı, 930201/930202
-- act2 zor taksonomi bazlı — id'ler 930000+ aralığında, production seed
-- migration'ıyla çakışmasın diye; testin kendisi bunları önceden
-- oluşturmuş olmalı) 7+3 profile_template_answers satırı ve 1 aktif
-- custom_questions yazar. Yalnızca fixture kurulumunda (postgres
-- context'inden) çağrılır.
create or replace function tests.provision_quiz_pool(p_profile_id uuid, p_custom_body text)
returns void
language plpgsql
as $$
declare
  v_custom_id uuid := gen_random_uuid();
  v_opt1      uuid := gen_random_uuid();
  v_opt2      uuid := gen_random_uuid();
begin
  -- 3 kolay + 3 orta + 1 zor: start_quiz'in katmanlı çekilişi (1. perde)
  -- için gereken minimum derinlik. Hepsini 'easy' yapmak artık yetersiz
  -- havuz hatasına düşürür.
  insert into public.profile_template_answers (profile_id, template_id, selected_option_id, difficulty)
    select p_profile_id, g + 930000,
           g + 931000,
           case when g <= 3 then 'easy' when g <= 6 then 'medium' else 'hard' end
    from generate_series(1, 7) g;

  insert into public.profile_template_answers (profile_id, template_id, selected_item_id, difficulty)
    values (p_profile_id, 930201, 930101, 'hard'), (p_profile_id, 930202, 930101, 'hard');

  -- 3. bir act2-zor soru: start_quiz'in 2. faz'ı (pozisyon 6-10) yalnızca
  -- 1 custom + 1 quiz-eligible künye sorusunu garanti ediyor, kalanı
  -- act2-zor havuzundan dolduruyor — 2 zor soru tek başına yetmiyor
  -- (1+1+2=4 < 5), bu yüzden burada kendi kendine yeten (taksonomiye
  -- bağımlı olmayan, sabit şıklı) bir 3. tanesi ekleniyor.
  insert into public.question_templates (id, body, act, default_difficulty) overriding system value
    values (930299, 'Paylaşılan zor soru (provision_quiz_pool)', 2, 'hard')
    on conflict (id) do nothing;
  insert into public.template_options (id, template_id, body, position) overriding system value
    values (930391, 930299, 'Şık A', 1), (930392, 930299, 'Şık B', 2)
    on conflict (id) do nothing;
  insert into public.profile_template_answers (profile_id, template_id, selected_option_id, difficulty)
    values (p_profile_id, 930299, 930391, 'hard')
    on conflict (profile_id, template_id) do nothing;

  insert into public.custom_questions (id, profile_id, body) values (v_custom_id, p_profile_id, p_custom_body);
  insert into public.custom_options (id, question_id, body, position)
    values (v_opt1, v_custom_id, 'X', 1), (v_opt2, v_custom_id, 'Y', 2);
  update public.custom_questions set correct_option_id = v_opt1 where id = v_custom_id;

  -- start_quiz'in 2. faz'ı (pozisyon 6-10) en az 1 quiz-eligible sayısal
  -- künye alanı gerektiriyor (bkz. 20260821060000_start_quiz_two_phase.sql).
  insert into public.profile_identity_attributes (profile_id, attribute_type, value_numeric, is_quiz_eligible)
    values (p_profile_id, 'height_cm', 170, true)
    on conflict (profile_id, attribute_type) do nothing;
end;
$$;
