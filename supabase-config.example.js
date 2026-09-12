/* คัดลอกไฟล์นี้เป็น supabase-config.js แล้วใส่ค่าจริง
   (รีโปนี้ commit supabase-config.js ไว้ด้วย — anon key เปิดเผยฝั่ง client ได้เมื่อเปิด RLS ครบทุกตาราง)
   ค่าทั้งสองอยู่ที่ Supabase Dashboard → Project Settings → API
   anon key เปิดเผยฝั่ง client ได้ตราบที่เปิด RLS ครบทุกตาราง
   ห้ามใส่ service_role key ที่นี่เด็ดขาด */
window.SUPA_CONFIG = {
  url: 'https://xxxxxxxxxxxx.supabase.co',
  anonKey: 'eyJhbGciOi...'
};
