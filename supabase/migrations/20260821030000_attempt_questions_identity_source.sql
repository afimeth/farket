-- attempt_questions currently only tracks two question sources (template_id XOR
-- custom_question_id). The new phase-2 quiz block can also draw a question
-- auto-generated from a profile_identity_attributes row (e.g. "Boyu sence kaç
-- cm?") — add a third nullable source column and widen the "exactly one
-- source" CHECK to cover it.

alter table public.attempt_questions
  add column identity_attribute_id uuid references public.profile_identity_attributes (id);

alter table public.attempt_questions
  drop constraint if exists attempt_questions_check;

alter table public.attempt_questions
  add constraint attempt_questions_check check (
    (template_id is not null)::int
    + (custom_question_id is not null)::int
    + (identity_attribute_id is not null)::int
    = 1
  );
