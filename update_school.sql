-- ==========================================================
--  تحديث اسم المدرسة وإدارة التعليم
--  الصقه في: Supabase ← SQL Editor ← New query ← Run
--  يعدّل أول مدرسة في الجدول. إن كان لديك أكثر من مدرسة،
--  استبدل السطر الأخير بمعرّف المدرسة المقصودة.
-- ==========================================================

update public.schools
   set name  = 'الثانوية الثالثة ببريدة',
       edu   = 'إدارة تعليم القصيم',
       stage = 'ثانوية'
 where id = (select id from public.schools order by created_at limit 1);

-- للتأكد:
select id, name, edu, stage from public.schools;
