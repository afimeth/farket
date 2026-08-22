-- Farket: indeksler (v3)

-- Keşif ön filtresi — artık şehir eşitliği üzerinden
create index idx_profiles_status_city on public.profiles (status, city_id);

create index idx_districts_city on public.districts (city_id);

-- Soru altyapısı
create index idx_template_options_template on public.template_options (template_id);
create index idx_taxonomy_items_taxonomy on public.taxonomy_items (taxonomy_id);
create index idx_taxonomy_adjacency_neighbor on public.taxonomy_adjacency (neighbor_item_id);
create index idx_question_templates_taxonomy on public.question_templates (taxonomy_id);
create index idx_question_templates_active_act on public.question_templates (is_active, act);

create index idx_profile_template_answers_template on public.profile_template_answers (template_id);

create index idx_custom_questions_profile on public.custom_questions (profile_id);
create index idx_custom_options_question on public.custom_options (question_id);

-- template_stats.option_id / item_id için kısmi UNIQUE index'ler zaten
-- schema_tables.sql'de tanımlı (idx_template_stats_unique_option/_item).

-- attempt_questions/attempt_answers PK'leri zaten birer benzersizlik
-- indeksi üretir; quiz_attempts'in (viewer_id, target_profile_id) UNIQUE
-- kısıtı da aynı şekilde.
create index idx_attempt_questions_template on public.attempt_questions (template_id);
create index idx_attempt_questions_custom_question on public.attempt_questions (custom_question_id);

-- Keşifte hariç tutma
create index idx_hidden_profiles_viewer_until on public.hidden_profiles (viewer_id, hidden_until);
create index idx_hidden_profiles_target on public.hidden_profiles (target_profile_id);
create index idx_skipped_profiles_viewer on public.skipped_profiles (viewer_id);
create index idx_skipped_profiles_target on public.skipped_profiles (target_profile_id);

create index idx_photos_profile_position on public.photos (profile_id, position);
create index idx_messages_conversation_created on public.messages (conversation_id, created_at);

-- Yabancı anahtarlar
create index idx_identity_card_profile on public.identity_card (profile_id);
create index idx_photos_profile on public.photos (profile_id);
create index idx_quiz_attempts_viewer on public.quiz_attempts (viewer_id);
create index idx_quiz_attempts_target on public.quiz_attempts (target_profile_id);
create index idx_identity_reveals_viewer on public.identity_reveals (viewer_id);
create index idx_identity_reveals_target on public.identity_reveals (target_profile_id);
create index idx_conversations_participant_a on public.conversations (participant_a);
create index idx_conversations_participant_b on public.conversations (participant_b);
create index idx_messages_sender on public.messages (sender_id);
create index idx_reports_reporter on public.reports (reporter_id);
create index idx_reports_reported on public.reports (reported_profile_id);
create index idx_blocks_blocked on public.blocks (blocked_id);

-- Bir çift kullanıcı arasında en fazla bir konuşma olsun; katılımcı sırası
-- önemsiz (A→B ile B→A aynı konuşma sayılır).
create unique index idx_conversations_unique_pair
  on public.conversations (least(participant_a, participant_b), greatest(participant_a, participant_b));
