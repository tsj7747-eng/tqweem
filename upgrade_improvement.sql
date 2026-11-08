-- ==========================================================
--  ترقية: خطة التحسين (2026-11-08)
--  إضافة فقط: جدول جديد public.improvement — لا يمس أي جدول أو ملف موجود
--  لا يوجد أي سماح بالحذف (لا سياسة delete)، والمدرسة لا تُحذف ما دام لها خطة
--  آمن للتشغيل أكثر من مرة.
-- ==========================================================
create table if not exists public.improvement (
  id         uuid primary key default gen_random_uuid(),
  school_id  uuid not null references public.schools(id),
  code       text not null,
  cur        text not null default '',
  tgt        text not null default '',
  dur        text not null default '',
  own        text not null default '',
  need       text not null default '',
  act        text not null default '',
  mech       text not null default '',
  kpi        text not null default '',
  evd        text not null default '',
  status     text not null default 'لم يبدأ',
  prog       text not null default '',
  src        text not null default '',
  updated_by text not null default '',
  updated_at timestamptz not null default now(),
  unique (school_id, code)
);
create index if not exists improvement_school_idx on public.improvement(school_id);

alter table public.improvement enable row level security;
drop policy if exists p_imp_read on public.improvement;
drop policy if exists p_imp_ins  on public.improvement;
drop policy if exists p_imp_upd  on public.improvement;
create policy p_imp_read on public.improvement for select
  using (public.is_super() or school_id = public.my_school());
create policy p_imp_ins on public.improvement for insert
  with check ((public.is_super() or school_id = public.my_school())
              and public.my_role() in ('superadmin','admin','editor'));
create policy p_imp_upd on public.improvement for update
  using ((public.is_super() or school_id = public.my_school())
         and public.my_role() in ('superadmin','admin','editor'))
  with check ((public.is_super() or school_id = public.my_school())
         and public.my_role() in ('superadmin','admin','editor'));
grant select, insert, update on public.improvement to authenticated;
