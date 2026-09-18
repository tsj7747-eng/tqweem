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
  if auth.uid() is not null and public.my_role() not in ('superadmin','admin') then
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
  with check (auth.uid() is not null);

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
--  انتهى.
--
--  لإضافة مدرسة جديدة، نفّذ سطرًا واحدًا في SQL Editor:
--      select public.create_school('اسم المدرسة');
--  فتُنشأ المدرسة ومعها الشواهد الـ52 جاهزة.
--
--  ثم من Table Editor ← profiles حدّد لكل مستخدم:
--      role       : superadmin أو admin أو editor أو viewer
--      school_id  : معرّف مدرسته (انسخه من جدول schools)
--  و superadmin لا يحتاج school_id لأنه يرى كل المدارس.
-- ==========================================================
