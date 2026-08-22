-- Farket: authenticated rolüne tablo/sütun bazlı GRANT'lar (v3).
--
-- Bu proje varsayılan olarak `public` şemadaki yeni tabloları Data API
-- rollerine (anon/authenticated/service_role) OTOMATİK açmayacak şekilde
-- yapılandırılmıştır. Her tablo için GRANT, ilgili RLS politikalarıyla
-- birebir eşleşecek şekilde burada AÇIKÇA verilir. Burada listelenmeyen
-- her (tablo, komut) kombinasyonu authenticated için erişilemez kalır.
--
-- Hiç GRANT verilmeyen tablolar (yalnızca service role / SECURITY DEFINER
-- fonksiyon erişir): taxonomy_items, taxonomy_adjacency,
-- profile_template_answers, template_stats.
--
-- Sütun bazlı kısıtlananlar: custom_questions ve attempt_questions için
-- correct_option_id sütunu SELECT grant'ından kasıtlı olarak dışlanıyor —
-- doğru cevap istemciye asla dönmeyecek, sahibi dahil (v3 bölüm 8, madde 1).

grant select
  on public.cities to authenticated;

grant select
  on public.districts to authenticated;

grant select, insert, update
  on public.profiles to authenticated;

grant select, insert, update
  on public.identity_card to authenticated;

grant select, insert, update, delete
  on public.photos to authenticated;

grant select
  on public.taxonomies to authenticated;

grant select
  on public.question_templates to authenticated;

grant select
  on public.template_options to authenticated;

-- correct_option_id burada YOK.
grant select (id, profile_id, body, is_active)
  on public.custom_questions to authenticated;
grant insert, update
  on public.custom_questions to authenticated;

grant select, insert, update, delete
  on public.custom_options to authenticated;

grant select
  on public.quiz_attempts to authenticated;

-- correct_option_id burada YOK.
grant select (attempt_id, position, template_id, custom_question_id, shown_option_ids)
  on public.attempt_questions to authenticated;

grant select
  on public.attempt_answers to authenticated;

grant select
  on public.skipped_profiles to authenticated;

grant select
  on public.hidden_profiles to authenticated;

grant select
  on public.identity_reveals to authenticated;

grant select
  on public.conversations to authenticated;

grant select
  on public.messages to authenticated;

grant select, insert
  on public.reports to authenticated;

grant select, insert, delete
  on public.blocks to authenticated;

grant select
  on public.daily_quotas to authenticated;
