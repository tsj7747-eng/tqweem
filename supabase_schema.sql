-- ==========================================================
--  منصة شواهد التقويم المدرسي الخارجي — إصدار تعدد المدارس
--  الصق هذا الملف كاملاً في: Supabase ← SQL Editor ← New query ← Run
--
--  يعمل في الحالتين:
--   • تركيب جديد من الصفر
--   • ترقية تركيب قديم كان بمدرسة واحدة (بياناتك تبقى كما هي
--     وتُنسب تلقائيًا إلى مدرستك الأولى)
--  آمن للتشغيل أكثر من مرة.
-- ==========================================================

-- ---------- 1) جدول المدارس ----------
create table if not exists public.schools (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  stage      text not null default '',
  edu        text not null default '',
  prin       text not null default '',
  year       text not null default '',
  visit      date,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------- 2) المستخدمون والأدوار ----------
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text,
  full_name  text,
  role       text not null default 'viewer',
  created_at timestamptz not null default now()
);
alter table public.profiles add column if not exists school_id uuid references public.schools(id);
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('superadmin','admin','editor','viewer'));

create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public as $fn$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email,
          coalesce(new.raw_user_meta_data ->> 'full_name', new.email))
  on conflict (id) do nothing;
  return new;
end;
$fn$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.my_role()
returns text language sql stable security definer set search_path = public as $fn$
  select coalesce((select role from public.profiles where id = auth.uid()), 'viewer');
$fn$;

create or replace function public.my_school()
returns uuid language sql stable security definer set search_path = public as $fn$
  select school_id from public.profiles where id = auth.uid();
$fn$;

create or replace function public.is_super()
returns boolean language sql stable security definer set search_path = public as $fn$
  select coalesce((select role = 'superadmin' from public.profiles where id = auth.uid()), false);
$fn$;

-- ---------- 3) الشواهد والمرفقات والسجل ----------
create table if not exists public.evidence (
  id         uuid primary key default gen_random_uuid(),
  ord        int  not null default 0,
  domain     text not null,
  standard   text not null,
  title      text not null,
  status     text not null default 'لم يبدأ',
  owner      text not null default '',
  due        date,
  hijri      text not null default '',
  note       text not null default '',
  link       text not null default '',
  updated_by text not null default '',
  updated_at timestamptz not null default now()
);
alter table public.evidence add column if not exists school_id uuid references public.schools(id);
create index if not exists evidence_school_idx on public.evidence(school_id);

create table if not exists public.attachments (
  id          uuid primary key default gen_random_uuid(),
  evidence_id uuid not null references public.evidence(id) on delete cascade,
  name        text not null,
  size        bigint not null default 0,
  mime        text not null default '',
  path        text not null,
  uploaded_by text not null default '',
  created_at  timestamptz not null default now()
);
alter table public.attachments add column if not exists school_id uuid references public.schools(id);
create index if not exists attachments_evidence_idx on public.attachments(evidence_id);

create table if not exists public.activity (
  id         bigserial primary key,
  actor      text not null default '',
  action     text not null default '',
  created_at timestamptz not null default now()
);
alter table public.activity add column if not exists school_id uuid references public.schools(id);

-- جدول الإعدادات القديم يبقى كما هو لأغراض الترقية فقط
create table if not exists public.settings (
  id   int primary key default 1 check (id = 1),
  data jsonb not null default '{}'::jsonb
);
insert into public.settings (id, data) values (1, '{}'::jsonb) on conflict (id) do nothing;

-- ---------- 4) قالب الشواهد الـ52 ----------
create table if not exists public.evidence_template (
  ord      int primary key,
  domain   text not null,
  standard text not null,
  title    text not null
);
insert into public.evidence_template (ord, domain, standard, title)
select * from (values
  (1, 'المجال الأول: الإدارة (القيادة) المدرسية', 'المعيار 1: التخطيط', 'الخطة التشغيلية للمدرسة معتمدة ومكتملة العناصر'),
  (2, 'المجال الأول: الإدارة (القيادة) المدرسية', 'المعيار 1: التخطيط', 'محضر تشكيل فريق التخطيط وفريق التقويم الذاتي وتحديد المهام'),
  (3, 'المجال الأول: الإدارة (القيادة) المدرسية', 'المعيار 1: التخطيط', 'تحليل الوضع الراهن للمدرسة (نقاط القوة وأولويات التطوير)'),
  (4, 'المجال الأول: الإدارة (القيادة) المدرسية', 'المعيار 1: التخطيط', 'خطة متابعة مؤشرات الأداء والتقارير الدورية لها'),
  (5, 'المجال الأول: الإدارة (القيادة) المدرسية', 'المعيار 1: التخطيط', 'محاضر اجتماعات متابعة تنفيذ الخطة والتعديلات عليها'),
  (6, 'المجال الأول: الإدارة (القيادة) المدرسية', 'المعيار 2: قيادة العملية التعليمية', 'خطة وبرامج تعزيز القيم الإسلامية والهوية الوطنية وشواهد تنفيذها'),
  (7, 'المجال الأول: الإدارة (القيادة) المدرسية', 'المعيار 2: قيادة العملية التعليمية', 'خطة الزيارات الصفية وسجل الزيارات والتغذية الراجعة للمعلمين'),
  (8, 'المجال الأول: الإدارة (القيادة) المدرسية', 'المعيار 2: قيادة العملية التعليمية', 'شواهد متابعة تنفيذ المناهج ومطابقتها للخطة الدراسية'),
  (9, 'المجال الأول: الإدارة (القيادة) المدرسية', 'المعيار 2: قيادة العملية التعليمية', 'محاضر مجلس المعلمين واللجان المدرسية'),
  (10, 'المجال الأول: الإدارة (القيادة) المدرسية', 'المعيار 2: قيادة العملية التعليمية', 'برامج دعم الطلاب المتعثرين وشواهد أثرها'),
  (11, 'المجال الأول: الإدارة (القيادة) المدرسية', 'المعيار 2: قيادة العملية التعليمية', 'برامج رعاية الموهوبين وذوي الإعاقة'),
  (12, 'المجال الأول: الإدارة (القيادة) المدرسية', 'المعيار 2: قيادة العملية التعليمية', 'خطة التوجيه الطلابي وبرامج الإرشاد المنفذة'),
  (13, 'المجال الأول: الإدارة (القيادة) المدرسية', 'المعيار 3: المجتمع المدرسي', 'خطة الشراكة مع الأسرة والمجتمع المحلي'),
  (14, 'المجال الأول: الإدارة (القيادة) المدرسية', 'المعيار 3: المجتمع المدرسي', 'محاضر مجلس أولياء الأمور واجتماعاته وقراراته'),
  (15, 'المجال الأول: الإدارة (القيادة) المدرسية', 'المعيار 3: المجتمع المدرسي', 'سجل الشراكات المجتمعية ومذكرات التعاون'),
  (16, 'المجال الأول: الإدارة (القيادة) المدرسية', 'المعيار 3: المجتمع المدرسي', 'شواهد قنوات التواصل مع أولياء الأمور'),
  (17, 'المجال الأول: الإدارة (القيادة) المدرسية', 'المعيار 3: المجتمع المدرسي', 'استطلاعات رضا المستفيدين وتحليل نتائجها وإجراءات المعالجة'),
  (18, 'المجال الأول: الإدارة (القيادة) المدرسية', 'المعيار 4: التطوير المؤسسي', 'بيان اكتمال الكادر التعليمي والإداري ومؤهلاتهم'),
  (19, 'المجال الأول: الإدارة (القيادة) المدرسية', 'المعيار 4: التطوير المؤسسي', 'سجل الرخص المهنية لمنسوبي المدرسة'),
  (20, 'المجال الأول: الإدارة (القيادة) المدرسية', 'المعيار 4: التطوير المؤسسي', 'خطة التطوير المهني مبنية على تحليل الاحتياج التدريبي'),
  (21, 'المجال الأول: الإدارة (القيادة) المدرسية', 'المعيار 4: التطوير المؤسسي', 'سجل البرامج التدريبية المنفذة وشهادات الحضور'),
  (22, 'المجال الأول: الإدارة (القيادة) المدرسية', 'المعيار 4: التطوير المؤسسي', 'تقرير التقويم الذاتي وفق معايير الهيئة'),
  (23, 'المجال الأول: الإدارة (القيادة) المدرسية', 'المعيار 4: التطوير المؤسسي', 'خطة التحسين المبنية على نتائج التقويم الذاتي وشواهد تنفيذها'),
  (24, 'المجال الثاني: التعليم والتعلم', 'المعيار 5: بناء خبرات التعلم', 'نماذج من خطط الدروس تُظهر تنوع استراتيجيات التدريس'),
  (25, 'المجال الثاني: التعليم والتعلم', 'المعيار 5: بناء خبرات التعلم', 'شواهد توفير فرص متكافئة تلبي احتياجات المتعلمين (ذوو الإعاقة والموهوبون)'),
  (26, 'المجال الثاني: التعليم والتعلم', 'المعيار 5: بناء خبرات التعلم', 'سجل الأنشطة التطبيقية والمشاريع المرتبطة بحياة المتعلمين'),
  (27, 'المجال الثاني: التعليم والتعلم', 'المعيار 5: بناء خبرات التعلم', 'برامج تنمية المهارات القرائية والعددية الأساسية'),
  (28, 'المجال الثاني: التعليم والتعلم', 'المعيار 5: بناء خبرات التعلم', 'شواهد توظيف التقنية ومصادر التعلم في الحصص'),
  (29, 'المجال الثاني: التعليم والتعلم', 'المعيار 5: بناء خبرات التعلم', 'سجل استخدام المعامل ومركز مصادر التعلم'),
  (30, 'المجال الثاني: التعليم والتعلم', 'المعيار 6: تقويم التعلم', 'خطة التقويم وأدواته المتنوعة معتمدة'),
  (31, 'المجال الثاني: التعليم والتعلم', 'المعيار 6: تقويم التعلم', 'نماذج من أعمال الطلاب مصححة مع تغذية راجعة مكتوبة'),
  (32, 'المجال الثاني: التعليم والتعلم', 'المعيار 6: تقويم التعلم', 'تحليل نتائج الاختبارات والفترات الدراسية'),
  (33, 'المجال الثاني: التعليم والتعلم', 'المعيار 6: تقويم التعلم', 'خطط المعالجة والإثراء المبنية على نتائج التقويم'),
  (34, 'المجال الثاني: التعليم والتعلم', 'المعيار 6: تقويم التعلم', 'سجلات متابعة تقدم الطلاب'),
  (35, 'المجال الثالث: نواتج التعلم', 'المعيار 7: التحصيل التعليمي', 'نتائج الطلاب في القراءة والرياضيات والعلوم'),
  (36, 'المجال الثالث: نواتج التعلم', 'المعيار 7: التحصيل التعليمي', 'نتائج اختبارات «نافس» وتحليلها'),
  (37, 'المجال الثالث: نواتج التعلم', 'المعيار 7: التحصيل التعليمي', 'مقارنة أداء المدرسة عبر الفصول والأعوام السابقة'),
  (38, 'المجال الثالث: نواتج التعلم', 'المعيار 7: التحصيل التعليمي', 'خطة تحسين التحصيل الدراسي وشواهد تنفيذها'),
  (39, 'المجال الثالث: نواتج التعلم', 'المعيار 8: التطور الشخصي والاجتماعي', 'إحصاءات المواظبة والالتزام بلائحة السلوك والانضباط'),
  (40, 'المجال الثالث: نواتج التعلم', 'المعيار 8: التطور الشخصي والاجتماعي', 'سجل الأنشطة المجتمعية والأعمال التطوعية والخيرية'),
  (41, 'المجال الثالث: نواتج التعلم', 'المعيار 8: التطور الشخصي والاجتماعي', 'برامج الصحة المدرسية والممارسات الصحية السليمة'),
  (42, 'المجال الثالث: نواتج التعلم', 'المعيار 8: التطور الشخصي والاجتماعي', 'شواهد قدرة الطلاب على البحث والتعلم الذاتي (مشاريع/مسابقات)'),
  (43, 'المجال الثالث: نواتج التعلم', 'المعيار 8: التطور الشخصي والاجتماعي', 'إنجازات ومشاركات الطلاب الداخلية والخارجية'),
  (44, 'المجال الرابع: البيئة المدرسية', 'المعيار 9: المبنى المدرسي', 'مخطط المبنى وتوزيع الفصول ومناسبته لأعداد المتعلمين'),
  (45, 'المجال الرابع: البيئة المدرسية', 'المعيار 9: المبنى المدرسي', 'سجل الصيانة الدورية وتقاريرها'),
  (46, 'المجال الرابع: البيئة المدرسية', 'المعيار 9: المبنى المدرسي', 'تقرير جاهزية الفصول والمعامل والمرافق والملاعب'),
  (47, 'المجال الرابع: البيئة المدرسية', 'المعيار 9: المبنى المدرسي', 'شواهد تهيئة البيئة المدرسية لذوي الإعاقة'),
  (48, 'المجال الرابع: البيئة المدرسية', 'المعيار 10: الأمن والسلامة', 'خطة الأمن والسلامة معتمدة'),
  (49, 'المجال الرابع: البيئة المدرسية', 'المعيار 10: الأمن والسلامة', 'خطة الإخلاء ومحاضر تنفيذ التجارب وتقويمها'),
  (50, 'المجال الرابع: البيئة المدرسية', 'المعيار 10: الأمن والسلامة', 'سجل تجهيزات السلامة (الطفايات، الإنذار، المخارج) وتواريخ الفحص'),
  (51, 'المجال الرابع: البيئة المدرسية', 'المعيار 10: الأمن والسلامة', 'شواهد برامج التدريب والتوعية بالأمن والسلامة'),
  (52, 'المجال الرابع: البيئة المدرسية', 'المعيار 10: الأمن والسلامة', 'خطة الطوارئ والإسعافات الأولية وسجل الحوادث')
) as v(ord, domain, standard, title)
on conflict (ord) do nothing;

-- ---------- 5) دالة إضافة مدرسة جديدة ----------
--  الاستخدام:  select public.create_school('ابتدائية الأمير سلطان');
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

-- ---------- 6) ترقية تركيب قديم بمدرسة واحدة ----------
do $mig$
declare sid uuid; nm text;
begin
  if exists (select 1 from public.evidence where school_id is null) then
    select nullif(trim(coalesce(data ->> 'name','')), '') into nm
      from public.settings where id = 1;
    insert into public.schools (name) values (coalesce(nm, 'مدرستي'))
      returning id into sid;
    update public.schools s
       set stage = coalesce(d.data ->> 'stage',''),
           edu   = coalesce(d.data ->> 'edu',''),
           prin  = coalesce(d.data ->> 'prin',''),
           year  = coalesce(d.data ->> 'year','')
      from public.settings d
     where d.id = 1 and s.id = sid;
    update public.evidence    set school_id = sid where school_id is null;
    update public.attachments set school_id = sid where school_id is null;
    update public.activity    set school_id = sid where school_id is null;
    update public.profiles    set school_id = sid where school_id is null;
  end if;
end
$mig$;

-- ==========================================================
--  7) الصلاحيات
--  كل مستخدم محبوس داخل مدرسته. صاحب الدور superadmin وحده
--  يرى كل المدارس ويتنقل بينها.
-- ==========================================================
alter table public.profiles          enable row level security;
alter table public.schools           enable row level security;
alter table public.evidence          enable row level security;
alter table public.attachments       enable row level security;
alter table public.activity          enable row level security;
alter table public.settings          enable row level security;
alter table public.evidence_template enable row level security;

drop policy if exists p_profiles_read  on public.profiles;
drop policy if exists p_profiles_write on public.profiles;
drop policy if exists p_schools_read   on public.schools;
drop policy if exists p_schools_upd    on public.schools;
drop policy if exists p_evidence_read  on public.evidence;
drop policy if exists p_evidence_ins   on public.evidence;
drop policy if exists p_evidence_upd   on public.evidence;
drop policy if exists p_evidence_del   on public.evidence;
drop policy if exists p_attach_read    on public.attachments;
drop policy if exists p_attach_ins     on public.attachments;
drop policy if exists p_attach_del     on public.attachments;
drop policy if exists p_activity_read  on public.activity;
drop policy if exists p_activity_ins   on public.activity;
drop policy if exists p_settings_read  on public.settings;
drop policy if exists p_settings_upd   on public.settings;
drop policy if exists p_tpl_read       on public.evidence_template;

create policy p_profiles_read on public.profiles for select
  using (auth.uid() = id or public.is_super()
         or (public.my_role() = 'admin' and school_id = public.my_school()));
create policy p_profiles_write on public.profiles for update
  using (public.is_super()) with check (public.is_super());

create policy p_schools_read on public.schools for select
  using (public.is_super() or id = public.my_school());
create policy p_schools_upd on public.schools for update
  using ((public.is_super() or id = public.my_school())
         and public.my_role() in ('superadmin','admin','editor'))
  with check ((public.is_super() or id = public.my_school())
         and public.my_role() in ('superadmin','admin','editor'));

create policy p_evidence_read on public.evidence for select
  using (public.is_super() or school_id = public.my_school());
create policy p_evidence_ins on public.evidence for insert
  with check ((public.is_super() or school_id = public.my_school())
              and public.my_role() in ('superadmin','admin','editor'));
create policy p_evidence_upd on public.evidence for update
  using ((public.is_super() or school_id = public.my_school())
         and public.my_role() in ('superadmin','admin','editor'))
  with check ((public.is_super() or school_id = public.my_school())
         and public.my_role() in ('superadmin','admin','editor'));
create policy p_evidence_del on public.evidence for delete
  using ((public.is_super() or school_id = public.my_school())
         and public.my_role() in ('superadmin','admin','editor'));

create policy p_attach_read on public.attachments for select
  using (public.is_super() or school_id = public.my_school());
create policy p_attach_ins on public.attachments for insert
  with check ((public.is_super() or school_id = public.my_school())
              and public.my_role() in ('superadmin','admin','editor'));
create policy p_attach_del on public.attachments for delete
  using ((public.is_super() or school_id = public.my_school())
         and public.my_role() in ('superadmin','admin','editor'));

create policy p_activity_read on public.activity for select
  using (public.is_super() or school_id = public.my_school());
create policy p_activity_ins on public.activity for insert
  with check (auth.uid() is not null
              and (public.is_super() or school_id = public.my_school()));

create policy p_settings_read on public.settings for select using (auth.uid() is not null);
create policy p_settings_upd  on public.settings for update
  using (public.is_super()) with check (public.is_super());

create policy p_tpl_read on public.evidence_template for select using (auth.uid() is not null);

-- ==========================================================
--  8) مساحة تخزين الملفات — كل مدرسة في مجلد باسم معرّفها
-- ==========================================================
insert into storage.buckets (id, name, public)
values ('evidence', 'evidence', false)
on conflict (id) do nothing;

drop policy if exists p_files_read on storage.objects;
drop policy if exists p_files_ins  on storage.objects;
drop policy if exists p_files_del  on storage.objects;

create policy p_files_read on storage.objects for select
  using (bucket_id = 'evidence' and auth.uid() is not null
         and (public.is_super()
              or (storage.foldername(name))[1] = public.my_school()::text));
create policy p_files_ins on storage.objects for insert
  with check (bucket_id = 'evidence'
              and public.my_role() in ('superadmin','admin','editor')
              and (public.is_super()
                   or (storage.foldername(name))[1] = public.my_school()::text));
create policy p_files_del on storage.objects for delete
  using (bucket_id = 'evidence'
         and public.my_role() in ('superadmin','admin','editor')
         and (public.is_super()
              or (storage.foldername(name))[1] = public.my_school()::text));

-- ==========================================================
--  9) ربط الشواهد بالمؤشرات (نفس محتوى upgrade_indicators.sql)
-- ==========================================================
--  ربط الشواهد بمؤشرات التقويم المدرسي
--  المرجع: وثيقة معايير التقويم والتصنيف والاعتماد المدرسي لمدارس التعليم العام
--          الإصدار الثاني 2026م — المعتمد للعام الدراسي 1448هـ
--  4 مجالات — 11 معيارًا — 49 مؤشرًا للحكومية و52 للأهلية والعالمية
--  آمن للتشغيل أكثر من مرة، ولا يحذف أي ملف أو حالة أو ملاحظة.
--   • يضيف لكل شاهد رموز المؤشرات التي يدعمها
--   • يعيد تسمية المعايير وفق الإصدار الجديد (منها «حقوق المتعلم وحمايته»)
--   • يضيف 20 شاهدًا لتغطية المؤشرات التي لم يكن لها شاهد
--   • يضيف نوع المدرسة (حكومية/أهلية/عالمية)
-- ==========================================================

alter table public.evidence          add column if not exists indicators text[] not null default '{}';
alter table public.evidence_template add column if not exists indicators text[] not null default '{}';
alter table public.schools           add column if not exists kind text not null default 'حكومية';
create index if not exists evidence_ind_idx on public.evidence using gin (indicators);

-- القالب الجديد (72 شاهدًا)
delete from public.evidence_template;
insert into public.evidence_template (ord, domain, standard, title, indicators) values
  (1, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-1: التخطيط', 'الخطة التشغيلية للمدرسة معتمدة ومكتملة العناصر', array['1-1-1-1']),
  (2, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-1: التخطيط', 'محضر تشكيل فريق التخطيط وفريق التقويم الذاتي وتحديد المهام', array['1-1-1-1', '1-4-1-6']),
  (3, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-1: التخطيط', 'تحليل الوضع الراهن للمدرسة (نقاط القوة وأولويات التطوير)', array['1-1-1-1']),
  (4, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-1: التخطيط', 'خطة متابعة مؤشرات الأداء والتقارير الدورية لها', array['1-1-1-2']),
  (5, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-1: التخطيط', 'محاضر اجتماعات متابعة تنفيذ الخطة والتعديلات عليها', array['1-1-1-2']),
  (6, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-1: التخطيط', 'محاضر مجلس المعلمين واللجان المدرسية', array['1-1-1-2', '1-2-1-2']),
  (7, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-2: قيادة العملية التعليمية', 'خطة وبرامج تعزيز القيم الإسلامية والهوية الوطنية وشواهد تنفيذها', array['1-2-1-1', '3-2-1-1']),
  (8, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-2: قيادة العملية التعليمية', 'ميثاق أخلاقيات مهنة التعليم وتوقيع المنسوبين عليه ومتابعة الالتزام به', array['1-2-1-2']),
  (9, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-2: قيادة العملية التعليمية', 'قواعد السلوك والمواظبة: نشرها وتوقيع الطلاب وأولياء الأمور وإجراءات متابعة الانضباط', array['1-2-1-3']),
  (10, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-2: قيادة العملية التعليمية', 'خطة التوجيه الطلابي وبرامج الإرشاد المنفذة', array['1-2-1-4', '1-5-1-2']),
  (11, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-2: قيادة العملية التعليمية', 'برامج تعزيز السلوك الإيجابي وسجل التحفيز ومتابعتها', array['1-2-1-4']),
  (12, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-2: قيادة العملية التعليمية', 'برامج رعاية الموهوبين وذوي الإعاقة', array['1-2-1-5', '2-1-1-1']),
  (13, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-2: قيادة العملية التعليمية', 'إنجازات ومشاركات الطلاب الداخلية والخارجية', array['1-2-1-5', '2-1-1-7']),
  (14, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-2: قيادة العملية التعليمية', 'خطة النشاط المدرسي وتقاريره', array['1-2-1-5']),
  (15, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-3: المجتمع المدرسي', 'استطلاعات رضا المستفيدين وتحليل نتائجها وإجراءات المعالجة', array['1-3-1-1']),
  (16, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-3: المجتمع المدرسي', 'برامج وأنشطة تعزيز العلاقات الإيجابية والتعاون بين منسوبي المدرسة', array['1-3-1-1']),
  (17, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-3: المجتمع المدرسي', 'خطة الشراكة مع الأسرة والمجتمع المحلي', array['1-3-1-2', '1-3-1-3']),
  (18, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-3: المجتمع المدرسي', 'محاضر مجلس أولياء الأمور واجتماعاته وقراراته', array['1-3-1-2']),
  (19, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-3: المجتمع المدرسي', 'شواهد قنوات التواصل مع أولياء الأمور', array['1-3-1-2', '2-2-1-4']),
  (20, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-3: المجتمع المدرسي', 'سجل الشراكات المجتمعية ومذكرات التعاون', array['1-3-1-3']),
  (21, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-4: التطوير المؤسسي', 'بيان اكتمال الكادر التعليمي والإداري ومؤهلاتهم', array['1-4-1-1', '1-4-1-2']),
  (22, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-4: التطوير المؤسسي', 'القوائم المالية وما يثبت الملاءة والاستدامة المالية (للمدارس الأهلية والعالمية)', array['1-4-1-3']),
  (23, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-4: التطوير المؤسسي', 'سجل الرخص المهنية لمنسوبي المدرسة', array['1-4-1-4']),
  (24, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-4: التطوير المؤسسي', 'خطة التطوير المهني مبنية على تحليل الاحتياج التدريبي', array['1-4-1-5']),
  (25, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-4: التطوير المؤسسي', 'سجل البرامج التدريبية المنفذة وشهادات الحضور', array['1-4-1-5']),
  (26, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-4: التطوير المؤسسي', 'عينة من ملفات إنجاز المعلمين وتقارير التقويم الذاتي للمعلم والممارسات التأملية', array['1-4-1-5']),
  (27, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-4: التطوير المؤسسي', 'تقرير التقويم الذاتي وفق معايير الهيئة', array['1-4-1-6']),
  (28, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-4: التطوير المؤسسي', 'تطبيق استبانات المتعلم والمعلم والأسرة على منصة تميز وفق حجم العينة', array['1-4-1-6']),
  (29, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-4: التطوير المؤسسي', 'تهيئة المقابلات (المتعلمون، المعلمون، الموجه الطلابي، الإدارة المدرسية) وفق أدوات الهيئة', array['1-4-1-6']),
  (30, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-4: التطوير المؤسسي', 'خطة التحسين المبنية على نتائج التقويم الذاتي وشواهد تنفيذها', array['1-4-1-7']),
  (31, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-5: حقوق المتعلم وحمايته', 'الإجراءات المتبعة لحماية المتعلم والحفاظ على حقوقه (السياسة، آلية البلاغ، التوعية بالحقوق)', array['1-5-1-1']),
  (32, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-5: حقوق المتعلم وحمايته', 'سجل حالات الحماية ومتابعتها مع الجهات المختصة', array['1-5-1-1']),
  (33, 'المجال الأول: الإدارة المدرسية', 'المعيار 1-5: حقوق المتعلم وحمايته', 'برامج المناخ الآمن نفسيًا واجتماعيًا (الوقاية من التنمر، مجالس الحوار الطلابي)', array['1-5-1-2']),
  (34, 'المجال الثاني: التعليم والتعلم', 'المعيار 2-1: بناء خبرات التعلم', 'برامج دعم الطلاب المتعثرين وشواهد أثرها', array['2-1-1-1', '2-2-1-3']),
  (35, 'المجال الثاني: التعليم والتعلم', 'المعيار 2-1: بناء خبرات التعلم', 'شواهد توفير فرص متكافئة تلبي احتياجات المتعلمين (ذوو الإعاقة والموهوبون)', array['2-1-1-1']),
  (36, 'المجال الثاني: التعليم والتعلم', 'المعيار 2-1: بناء خبرات التعلم', 'شواهد متابعة تنفيذ المناهج ومطابقتها للخطة الدراسية', array['2-1-1-2']),
  (37, 'المجال الثاني: التعليم والتعلم', 'المعيار 2-1: بناء خبرات التعلم', 'خطة الزيارات الصفية وسجل الزيارات والتغذية الراجعة للمعلمين', array['2-1-1-3', '1-4-1-5']),
  (38, 'المجال الثاني: التعليم والتعلم', 'المعيار 2-1: بناء خبرات التعلم', 'نماذج من خطط الدروس تُظهر تنوع استراتيجيات التدريس', array['2-1-1-3']),
  (39, 'المجال الثاني: التعليم والتعلم', 'المعيار 2-1: بناء خبرات التعلم', 'شواهد توظيف التقنية ومصادر التعلم في الحصص', array['2-1-1-4']),
  (40, 'المجال الثاني: التعليم والتعلم', 'المعيار 2-1: بناء خبرات التعلم', 'سجل استخدام المعامل ومركز مصادر التعلم', array['2-1-1-4', '4-1-1-3']),
  (41, 'المجال الثاني: التعليم والتعلم', 'المعيار 2-1: بناء خبرات التعلم', 'سجل الأنشطة التطبيقية والمشاريع المرتبطة بحياة المتعلمين', array['2-1-1-5']),
  (42, 'المجال الثاني: التعليم والتعلم', 'المعيار 2-1: بناء خبرات التعلم', 'برامج تنمية المهارات القرائية والعددية الأساسية', array['2-1-1-6']),
  (43, 'المجال الثاني: التعليم والتعلم', 'المعيار 2-1: بناء خبرات التعلم', 'برامج ومشروعات تنمية مهارات التفكير والبحث والابتكار', array['2-1-1-7']),
  (44, 'المجال الثاني: التعليم والتعلم', 'المعيار 2-1: بناء خبرات التعلم', 'برامج تنمية المهارات العاطفية والاجتماعية لدى المتعلمين', array['2-1-1-8']),
  (45, 'المجال الثاني: التعليم والتعلم', 'المعيار 2-1: بناء خبرات التعلم', 'برامج تعزيز دافعية المتعلمين للتعلم والاستمتاع به (التحفيز والتكريم)', array['2-1-1-9']),
  (46, 'المجال الثاني: التعليم والتعلم', 'المعيار 2-2: تقويم التعلم', 'خطة التقويم وأدواته المتنوعة معتمدة', array['2-2-1-1', '2-2-1-2']),
  (47, 'المجال الثاني: التعليم والتعلم', 'المعيار 2-2: تقويم التعلم', 'عينة من ملفات إنجاز المتعلمين ونماذج تقويم أدائهم', array['2-2-1-1']),
  (48, 'المجال الثاني: التعليم والتعلم', 'المعيار 2-2: تقويم التعلم', 'تحليل نتائج الاختبارات والفترات الدراسية', array['2-2-1-3']),
  (49, 'المجال الثاني: التعليم والتعلم', 'المعيار 2-2: تقويم التعلم', 'خطط المعالجة والإثراء المبنية على نتائج التقويم', array['2-2-1-3', '2-1-1-1']),
  (50, 'المجال الثاني: التعليم والتعلم', 'المعيار 2-2: تقويم التعلم', 'نماذج من أعمال الطلاب مصححة مع تغذية راجعة مكتوبة', array['2-2-1-4']),
  (51, 'المجال الثاني: التعليم والتعلم', 'المعيار 2-2: تقويم التعلم', 'سجلات متابعة تقدم الطلاب', array['2-2-1-4']),
  (52, 'المجال الثالث: نواتج التعلم', 'المعيار 3-1: التحصيل التعليمي', 'نتائج الطلاب في القراءة والرياضيات والعلوم', array['3-1-1-1', '3-1-1-2', '3-1-1-3']),
  (53, 'المجال الثالث: نواتج التعلم', 'المعيار 3-1: التحصيل التعليمي', 'نتائج الاختبارات الوطنية وتحليلها (نافس للابتدائية والمتوسطة، التحصيلي والقدرات للثانوية)', array['3-1-1-1', '3-1-1-2', '3-1-1-3']),
  (54, 'المجال الثالث: نواتج التعلم', 'المعيار 3-1: التحصيل التعليمي', 'مقارنة أداء المدرسة عبر الفصول والأعوام السابقة', array['3-1-1-4', '3-1-1-5', '3-1-1-6']),
  (55, 'المجال الثالث: نواتج التعلم', 'المعيار 3-1: التحصيل التعليمي', 'خطة تحسين التحصيل الدراسي وشواهد تنفيذها', array['3-1-1-4', '3-1-1-5', '3-1-1-6']),
  (56, 'المجال الثالث: نواتج التعلم', 'المعيار 3-2: التطور الشخصي والصحي والاجتماعي', 'برامج تعزيز الاتجاهات الإيجابية نحو الذات والآخرين وشواهد أثرها', array['3-2-1-2']),
  (57, 'المجال الثالث: نواتج التعلم', 'المعيار 3-2: التطور الشخصي والصحي والاجتماعي', 'برامج الصحة المدرسية والممارسات الصحية السليمة', array['3-2-1-3']),
  (58, 'المجال الثالث: نواتج التعلم', 'المعيار 3-2: التطور الشخصي والصحي والاجتماعي', 'سجل الأنشطة المجتمعية والأعمال التطوعية والخيرية', array['3-2-1-4']),
  (59, 'المجال الثالث: نواتج التعلم', 'المعيار 3-2: التطور الشخصي والصحي والاجتماعي', 'إحصاءات المواظبة والالتزام بلائحة السلوك والانضباط', array['3-2-1-5', '1-2-1-3']),
  (60, 'المجال الثالث: نواتج التعلم', 'المعيار 3-2: التطور الشخصي والصحي والاجتماعي', 'شواهد قدرة الطلاب على البحث والتعلم الذاتي (مشاريع/مسابقات)', array['3-2-1-6', '2-1-1-7']),
  (61, 'المجال الثالث: نواتج التعلم', 'المعيار 3-2: التطور الشخصي والصحي والاجتماعي', 'أنشطة الاعتزاز بالثقافة الوطنية واحترام التنوع الثقافي', array['3-2-1-7']),
  (62, 'المجال الرابع: البيئة المدرسية', 'المعيار 4-1: المبنى المدرسي', 'وثائق المبنى المدرسي واستيفائه للمواصفات والاشتراطات والخدمات المساندة', array['4-1-1-1']),
  (63, 'المجال الرابع: البيئة المدرسية', 'المعيار 4-1: المبنى المدرسي', 'مخطط المبنى وتوزيع الفصول ومناسبته لأعداد المتعلمين', array['4-1-1-2', '4-1-1-1']),
  (64, 'المجال الرابع: البيئة المدرسية', 'المعيار 4-1: المبنى المدرسي', 'تقرير جاهزية الفصول والمعامل والمرافق والملاعب', array['4-1-1-3', '4-1-1-4']),
  (65, 'المجال الرابع: البيئة المدرسية', 'المعيار 4-1: المبنى المدرسي', 'شواهد تهيئة البيئة المدرسية لذوي الإعاقة', array['4-1-1-4', '4-1-1-2']),
  (66, 'المجال الرابع: البيئة المدرسية', 'المعيار 4-2: الأمن والسلامة', 'خطة الأمن والسلامة معتمدة', array['4-2-1-1']),
  (67, 'المجال الرابع: البيئة المدرسية', 'المعيار 4-2: الأمن والسلامة', 'خطة الإخلاء ومحاضر تنفيذ التجارب وتقويمها', array['4-2-1-1']),
  (68, 'المجال الرابع: البيئة المدرسية', 'المعيار 4-2: الأمن والسلامة', 'سجل تجهيزات السلامة (الطفايات، الإنذار، المخارج) وتواريخ الفحص', array['4-2-1-1']),
  (69, 'المجال الرابع: البيئة المدرسية', 'المعيار 4-2: الأمن والسلامة', 'شواهد برامج التدريب والتوعية بالأمن والسلامة', array['4-2-1-1']),
  (70, 'المجال الرابع: البيئة المدرسية', 'المعيار 4-2: الأمن والسلامة', 'خطة الطوارئ والإسعافات الأولية وسجل الحوادث', array['4-2-1-1', '1-5-1-2']),
  (71, 'المجال الرابع: البيئة المدرسية', 'المعيار 4-2: الأمن والسلامة', 'سجل الصيانة الدورية وتقاريرها', array['4-2-1-2']),
  (72, 'المجال الرابع: البيئة المدرسية', 'المعيار 4-2: الأمن والسلامة', 'خطة النظافة ومتابعتها (جداول وتقارير نظافة المبنى والمرافق)', array['4-2-1-3']);

-- عناوين حُدّثت لتوافق الإصدار الثاني
update public.evidence set title = 'نتائج الاختبارات الوطنية وتحليلها (نافس للابتدائية والمتوسطة، التحصيلي والقدرات للثانوية)' where title = 'نتائج اختبارات «نافس» وتحليلها';

-- الشواهد القائمة: نفس العنوان ← ربطها بمؤشراتها ونقلها لمعيارها الصحيح
update public.evidence e
   set indicators = t.indicators, domain = t.domain, standard = t.standard, ord = t.ord
  from public.evidence_template t
 where e.title = t.title and cardinality(e.indicators) = 0;

-- الشواهد الجديدة لكل مدرسة (مرة واحدة فقط)
insert into public.evidence (school_id, ord, domain, standard, title, indicators)
select s.id, t.ord, t.domain, t.standard, t.title, t.indicators
  from public.schools s
  cross join public.evidence_template t
 where t.title in (
  'ميثاق أخلاقيات مهنة التعليم وتوقيع المنسوبين عليه ومتابعة الالتزام به',
  'قواعد السلوك والمواظبة: نشرها وتوقيع الطلاب وأولياء الأمور وإجراءات متابعة الانضباط',
  'برامج تعزيز السلوك الإيجابي وسجل التحفيز ومتابعتها',
  'خطة النشاط المدرسي وتقاريره',
  'برامج وأنشطة تعزيز العلاقات الإيجابية والتعاون بين منسوبي المدرسة',
  'القوائم المالية وما يثبت الملاءة والاستدامة المالية (للمدارس الأهلية والعالمية)',
  'عينة من ملفات إنجاز المعلمين وتقارير التقويم الذاتي للمعلم والممارسات التأملية',
  'تطبيق استبانات المتعلم والمعلم والأسرة على منصة تميز وفق حجم العينة',
  'تهيئة المقابلات (المتعلمون، المعلمون، الموجه الطلابي، الإدارة المدرسية) وفق أدوات الهيئة',
  'الإجراءات المتبعة لحماية المتعلم والحفاظ على حقوقه (السياسة، آلية البلاغ، التوعية بالحقوق)',
  'سجل حالات الحماية ومتابعتها مع الجهات المختصة',
  'برامج المناخ الآمن نفسيًا واجتماعيًا (الوقاية من التنمر، مجالس الحوار الطلابي)',
  'برامج ومشروعات تنمية مهارات التفكير والبحث والابتكار',
  'برامج تنمية المهارات العاطفية والاجتماعية لدى المتعلمين',
  'برامج تعزيز دافعية المتعلمين للتعلم والاستمتاع به (التحفيز والتكريم)',
  'عينة من ملفات إنجاز المتعلمين ونماذج تقويم أدائهم',
  'برامج تعزيز الاتجاهات الإيجابية نحو الذات والآخرين وشواهد أثرها',
  'أنشطة الاعتزاز بالثقافة الوطنية واحترام التنوع الثقافي',
  'وثائق المبنى المدرسي واستيفائه للمواصفات والاشتراطات والخدمات المساندة',
  'خطة النظافة ومتابعتها (جداول وتقارير نظافة المبنى والمرافق)')
   and not exists (select 1 from public.evidence e where e.school_id = s.id and e.title = t.title);

-- إنشاء مدرسة جديدة ينسخ المؤشرات أيضًا (والإضافة لصاحب الإشراف العام وحده)
create or replace function public.create_school(p_name text)
returns uuid
language plpgsql security definer set search_path = public as $fn$
declare sid uuid;
begin
  if auth.uid() is not null and not public.is_super() then
    raise exception 'غير مصرح لك بإضافة مدرسة';
  end if;
  insert into public.schools (name) values (p_name) returning id into sid;
  insert into public.evidence (school_id, ord, domain, standard, title, indicators)
    select sid, ord, domain, standard, title, indicators from public.evidence_template order by ord;
  return sid;
end;
$fn$;

drop policy if exists p_activity_ins on public.activity;
create policy p_activity_ins on public.activity for insert
  with check (auth.uid() is not null
              and (public.is_super() or school_id = public.my_school()));

-- للتأكد
select (select count(*) from public.evidence_template) as template_rows,
       (select count(*) from public.evidence where cardinality(indicators) = 0) as unlinked_evidence;

-- ==========================================================
--  انتهى.
--
--  لإضافة مدرسة جديدة، نفّذ سطرًا واحدًا في SQL Editor:
--      select public.create_school('اسم المدرسة');
--  فتُنشأ المدرسة ومعها الشواهد الـ72 مربوطة بالمؤشرات الـ52.
--
--  ثم من Table Editor ← profiles حدّد لكل مستخدم:
--      role       : superadmin أو admin أو editor أو viewer
--      school_id  : معرّف مدرسته (انسخه من جدول schools)
--  و superadmin لا يحتاج school_id لأنه يرى كل المدارس.
-- ==========================================================
