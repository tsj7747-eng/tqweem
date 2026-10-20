-- ==========================================================
--  تحديث أمني صغير — شغّله مرة واحدة
--  Supabase ← SQL Editor ← New query ← الصق ← Run
--  لا يغيّر بياناتك، فقط يشدّد صلاحيتين:
--   1) إضافة مدرسة جديدة لصاحب الإشراف العام (superadmin) وحده
--   2) لا يكتب أحد في سجل نشاط مدرسة غير مدرسته
-- ==========================================================

create or replace function public.create_school(p_name text)
returns uuid
language plpgsql security definer set search_path = public as $fn$
declare sid uuid;
begin
  if auth.uid() is not null and not public.is_super() then
    raise exception 'غير مصرح لك بإضافة مدرسة';
  end if;
  insert into public.schools (name) values (p_name) returning id into sid;
  insert into public.evidence (school_id, ord, domain, standard, title)
    select sid, ord, domain, standard, title from public.evidence_template order by ord;
  return sid;
end;
$fn$;

drop policy if exists p_activity_ins on public.activity;
create policy p_activity_ins on public.activity for insert
  with check (auth.uid() is not null
              and (public.is_super() or school_id = public.my_school()));

-- للتأكد: يجب أن يظهر سطر واحد
select policyname from pg_policies where tablename = 'activity' and policyname = 'p_activity_ins';
