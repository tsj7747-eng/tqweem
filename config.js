/* =========================================================
   ملف الإعدادات — عدّل السطرين التاليين فقط
   ---------------------------------------------------------
   تجدهما في Supabase ← Project Settings ← API
     SUPABASE_URL      = "https://czrzdwbmclfrqftxxvpx.supabase.co",
     SUPABASE_ANON_KEY = sb_publishable_1LMWyji8gVR7Hjderk_iTQ_pIVkdiug
   ---------------------------------------------------------
   ملاحظة أمنية: مفتاح anon مصمَّم ليكون ظاهرًا في المتصفح،
   والحماية الحقيقية تأتي من سياسات RLS في ملف supabase_schema.sql.
   لا تضع هنا أبدًا مفتاح service_role.
   ========================================================= */

window.APP_CONFIG = {
  SUPABASE_URL:      "PASTE_PROJECT_URL_HERE",
  SUPABASE_ANON_KEY: "PASTE_ANON_KEY_HERE",

  // اسم المدرسة الظاهر في الترويسة (اختياري)
  SCHOOL_NAME: "منصة شواهد التقويم المدرسي الخارجي",

  // أقصى حجم للملف الواحد بالميجابايت
  MAX_FILE_MB: 25
};
