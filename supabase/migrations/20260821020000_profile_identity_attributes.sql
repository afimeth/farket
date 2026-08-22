-- Replaces identity_card's fixed columns with a flexible key-value attribute set,
-- so a profile owner can add facts (school, job, height, weight, ...) beyond the
-- original 5 hardcoded fields, and mark individual attributes as eligible for
-- auto-generated quiz questions. identity_card itself is left untouched here —
-- it stays live until the Android app fully cuts over, then gets dropped in a
-- separate future migration.

create table public.profile_identity_attributes (
  id                  uuid primary key default gen_random_uuid(),
  profile_id          uuid not null references public.profiles (id) on delete cascade,
  -- 'name'/'age' are always derived from profiles at reveal_identity time (see
  -- that function's CREATE OR REPLACE), never entered by the user directly.
  attribute_type      text not null check (attribute_type in (
                        'name', 'age', 'school', 'job', 'height_cm', 'weight_kg',
                        'city', 'intent', 'hometown'
                      )),
  value_text          text check (char_length(value_text) <= 60),
  value_numeric       numeric,
  is_shown_on_reveal  boolean not null default false,
  is_quiz_eligible    boolean not null default false,
  created_at          timestamptz not null default now(),
  unique (profile_id, attribute_type),
  check ((value_text is not null)::int + (value_numeric is not null)::int = 1),
  -- v1: only numeric attributes can drive auto-generated quiz questions (see
  -- pick_numeric_distractors); text attributes are only quizzable via the
  -- existing profile-owner-authored custom_questions flow.
  check (not is_quiz_eligible or attribute_type in ('height_cm', 'weight_kg', 'age'))
);

comment on table public.profile_identity_attributes is
  'Flexible key-value identity facts a profile owner may (a) reveal after quiz checkpoint pass and/or (b) mark eligible for auto-generated quiz questions.';

create index profile_identity_attributes_profile_id_idx
  on public.profile_identity_attributes (profile_id);

alter table public.profile_identity_attributes enable row level security;

-- Same shape as identity_card_*_own policies: owner-only, nobody else can read
-- directly — cross-user reads (e.g. reveal_identity, quiz question generation)
-- go through SECURITY DEFINER functions.
create policy profile_identity_attributes_select_own
  on public.profile_identity_attributes for select
  to authenticated
  using (profile_id = (select auth.uid()));

create policy profile_identity_attributes_insert_own
  on public.profile_identity_attributes for insert
  to authenticated
  with check (profile_id = (select auth.uid()));

create policy profile_identity_attributes_update_own
  on public.profile_identity_attributes for update
  to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

create policy profile_identity_attributes_delete_own
  on public.profile_identity_attributes for delete
  to authenticated
  using (profile_id = (select auth.uid()));

grant select, insert, update, delete on public.profile_identity_attributes to authenticated;

-- One-time backfill: translate existing identity_card content (occupation/intent)
-- into the new table. show_name/show_age/show_city are NOT backfilled as rows
-- here — name/age are derived pseudo-attributes written by reveal_identity
-- on first read, and city is already covered by the 'city' attribute_type only
-- if a profile owner explicitly adds it (identity_card never had free-text city
-- content beyond the profile's own city_id, which is not a personal fact worth
-- migrating as a fake user-entered attribute).
insert into public.profile_identity_attributes (profile_id, attribute_type, value_text, is_shown_on_reveal, is_quiz_eligible)
select profile_id, 'job', occupation, show_occupation, false
  from public.identity_card
  where occupation is not null
on conflict (profile_id, attribute_type) do nothing;

insert into public.profile_identity_attributes (profile_id, attribute_type, value_text, is_shown_on_reveal, is_quiz_eligible)
select profile_id, 'intent', intent, show_intent, false
  from public.identity_card
  where intent is not null
on conflict (profile_id, attribute_type) do nothing;

-- name/age are derived pseudo-attributes (reveal_identity keeps their
-- value_text/value_numeric fresh from profiles on every call), but their
-- is_shown_on_reveal flag must be backfilled from identity_card.show_name/
-- show_age here, otherwise a profile that already had show_name=true would
-- silently lose that reveal setting the first time reveal_identity runs
-- post-migration (it would insert a fresh row defaulting to false).
insert into public.profile_identity_attributes (profile_id, attribute_type, value_text, is_shown_on_reveal)
select ic.profile_id, 'name', p.display_name, ic.show_name
  from public.identity_card ic
  join public.profiles p on p.id = ic.profile_id
on conflict (profile_id, attribute_type) do nothing;

insert into public.profile_identity_attributes (profile_id, attribute_type, value_numeric, is_shown_on_reveal)
select ic.profile_id, 'age', extract(year from age(p.birth_date))::int, ic.show_age
  from public.identity_card ic
  join public.profiles p on p.id = ic.profile_id
on conflict (profile_id, attribute_type) do nothing;
