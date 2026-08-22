-- Generates plausible wrong-answer options for a numeric identity attribute
-- (height_cm, weight_kg, age), analogous in spirit to pick_distractors' role
-- for taxonomy-based template questions, but numeric-spread based instead of
-- adjacency-based since these attributes have no taxonomy pool.

create or replace function public.pick_numeric_distractors(
  p_true_value    numeric,
  p_attribute_type text
)
returns numeric[]
language plpgsql
security definer
set search_path = public
as $$
declare
  v_spread    numeric;
  v_min_bound numeric;
  v_max_bound numeric;
  v_result    numeric[] := '{}';
  v_candidate numeric;
  v_attempts  int := 0;
begin
  if p_attribute_type not in ('height_cm', 'weight_kg', 'age') then
    raise exception 'pick_numeric_distractors: desteklenmeyen attribute_type: %', p_attribute_type;
  end if;

  v_spread := case p_attribute_type
    when 'height_cm' then 6
    when 'weight_kg' then 4
    when 'age'       then 3
  end;

  v_min_bound := case p_attribute_type
    when 'height_cm' then 150
    when 'weight_kg' then 40
    when 'age'       then 18
    else 0
  end;

  v_max_bound := case p_attribute_type
    when 'height_cm' then 210
    when 'weight_kg' then 150
    when 'age'       then 90
    else 999
  end;

  while array_length(v_result, 1) is null or array_length(v_result, 1) < 2 loop
    v_attempts := v_attempts + 1;
    if v_attempts > 50 then
      raise exception 'pick_numeric_distractors: % için yeterli çeldirici üretilemedi', p_attribute_type;
    end if;

    v_candidate := round(p_true_value + (random() * 2 - 1) * v_spread * (1 + (v_attempts / 10)));
    if v_candidate = p_true_value
      or v_candidate < v_min_bound
      or v_candidate > v_max_bound
      or v_candidate = any (v_result)
    then
      continue;
    end if;

    v_result := v_result || v_candidate;
  end loop;

  return v_result;
end;
$$;
