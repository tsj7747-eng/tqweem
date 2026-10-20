-- ==========================================================
--  ترقية الملفات — آمن للتشغيل أكثر من مرة، لا يحذف شيئًا
--   1) الحذف يصبح «نقلًا إلى المحذوفات» قابلًا للاستعادة
--   2) نقل الملف من شاهد إلى آخر، وملفات «غير مصنّفة» بلا شاهد
--   3) استعادة الملفات الموجودة في التخزين وغير المسجّلة في المنصة
--      (تُنسب لأول مدرسة وتظهر في «مكتبة الملفات ← غير مصنّفة»)
-- ==========================================================

alter table public.attachments add column if not exists deleted_at timestamptz;
alter table public.attachments add column if not exists deleted_by text not null default '';
alter table public.attachments alter column evidence_id drop not null;

-- حذف شاهد لا يحذف ملفاته بعد الآن: تنتقل إلى «غير مصنّفة»
alter table public.attachments
  drop constraint if exists attachments_evidence_id_fkey,
  add constraint attachments_evidence_id_fkey foreign key (evidence_id)
      references public.evidence(id) on delete set null;

-- صلاحيات صريحة (تغيير Supabase في 30 أكتوبر 2026) مع إبقاء RLS مفعّلًا
alter table public.attachments enable row level security;
grant select, insert, update, delete on public.attachments to authenticated;
grant all on public.attachments to service_role;

-- تعديل المرفق (حذف مؤقت/استعادة/نقل) لمحرري المدرسة نفسها
drop policy if exists p_attach_upd on public.attachments;
create policy p_attach_upd on public.attachments for update
  using ((public.is_super() or school_id = public.my_school())
         and public.my_role() in ('superadmin','admin','editor'))
  with check ((public.is_super() or school_id = public.my_school())
         and public.my_role() in ('superadmin','admin','editor')
         and (evidence_id is null or exists (select 1 from public.evidence e
              where e.id = evidence_id and e.school_id = attachments.school_id)));

-- الحذف النهائي للمرفق: مقفل حتى انتهاء التقويم (صاحب الإشراف العام وحده)
drop policy if exists p_attach_del on public.attachments;
create policy p_attach_del on public.attachments for delete
  using (public.is_super());

-- قراءة الملف: من مجلد المدرسة، أو ملف مسجّل باسم المدرسة (للملفات المستعادة)
drop policy if exists p_files_read on storage.objects;
create policy p_files_read on storage.objects for select
  using (bucket_id = 'evidence' and auth.uid() is not null
         and (public.is_super()
              or (storage.foldername(name))[1] = public.my_school()::text
              or exists (select 1 from public.attachments a
                          where a.path = storage.objects.name
                            and a.school_id = public.my_school())));

-- حذف الملف من التخزين: مقفل حتى انتهاء التقويم (صاحب الإشراف العام وحده)
drop policy if exists p_files_del on storage.objects;
create policy p_files_del on storage.objects for delete
  using (bucket_id = 'evidence' and public.is_super());

-- استعادة الملفات غير المسجّلة
insert into public.attachments (evidence_id, school_id, name, size, mime, path, uploaded_by, created_at)
select null,
       (select id from public.schools order by created_at limit 1),
       'ملف مستعاد ' || row_number() over (order by o.created_at)
         || coalesce(substring(o.name from '\.[A-Za-z0-9]+$'), ''),
       coalesce((o.metadata ->> 'size')::bigint, 0),
       coalesce(o.metadata ->> 'mimetype', ''),
       o.name, 'مستعاد', o.created_at
  from storage.objects o
 where o.bucket_id = 'evidence'
   and o.name not like '%.emptyFolderPlaceholder'
   and not exists (select 1 from public.attachments a where a.path = o.name)
   and exists (select 1 from public.schools);

-- للتأكد
select (select count(*) from public.attachments) attachments,
       (select count(*) from public.attachments where evidence_id is null) unsorted,
       (select count(*) from storage.objects where bucket_id = 'evidence') files_in_storage;
