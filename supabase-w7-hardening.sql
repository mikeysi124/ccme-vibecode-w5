-- ============================================================================
--  ปิดจุดอ่อนด้านสิทธิ์ก่อนทดสอบเจาะ 27–30 ก.ย. 2569 · รันใน Supabase SQL Editor
--  โปรเจกต์ ccme-triage-p49 · รันต่อจาก supabase-schema.sql + supabase-w6-additions.sql
--  ผู้ช่วยคัดกรองช่องทาง ER/OPD · นพ.กิตติพศ เกียรติพัฒนาชัย (p49)
--
--  ที่มา: Codex ตรวจเวอร์ชัน 1.2.0 สองรอบ (23 ก.ย. 2569) พบว่า
--   1) policy "profiles: self update" ไม่กันคอลัมน์ role → ผู้ใช้ที่ล็อกอินตั้งตัวเองเป็น admin หรือ doctor ได้
--   2) policy "overrides: read" ให้ doctor/head_nurse อ่านได้ทุกหน่วย ไม่ผูกกับหน่วยของเคส
--   3) policy "cases: own or same unit" ไม่เคยทำงานข้ามคน เพราะ join profiles ของเจ้าของเคสติด RLS ของ profiles
--  รันแล้วบน ccme-triage-p49 เมื่อ 23 ก.ย. 2569: ส่วนที่ 4 ได้ครบ 4 แถว · ส่วนที่ 5 ผ่าน 5 ข้อ · anon ยังได้ [] ทุกตาราง
--
--  วิธีรัน: รอบแรกวางส่วนที่ 1–4 แล้วกด Run · รอบสองวางเฉพาะส่วนที่ 5 แล้วกด Run แยก
--  ส่วนที่ 5 ตั้งใจจบด้วย error "ผลทดสอบ: …" เพื่อย้อนผู้ใช้ชั่วคราวทิ้งทั้งหมด
-- ============================================================================

-- 1 ------------------------------------------------ กันผู้ใช้แก้บทบาท/หน่วยงานตัวเอง
-- คำขอจากหน้าเว็บวิ่งในบทบาท authenticated · trigger สร้าง profile และ SQL Editor ในบทบาท postgres ไม่ถูกกัน
-- ฟังก์ชันนี้ตั้งใจไม่ใช้ security definer เพื่อให้ current_user เป็นบทบาทของผู้เรียกจริง
create or replace function public.protect_profile_role()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user = 'authenticated' and coalesce(public.current_role_name(), '') <> 'admin' then
    if tg_op = 'INSERT' then
      new.role := 'nurse';
      new.unit := null;
    elsif new.role is distinct from old.role or new.unit is distinct from old.unit then
      raise exception 'เปลี่ยนบทบาทหรือหน่วยงานได้เฉพาะผู้ดูแลระบบ';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists protect_profile_role on public.profiles;
create trigger protect_profile_role
  before insert or update on public.profiles
  for each row execute function public.protect_profile_role();

-- 2 --------------------------------------------- เคสของหน่วยเดียวกัน อ่านได้จริง
-- helper อ่านหน่วยงานข้าม RLS ของ profiles · วางใน schema private ที่ API ไม่เปิด ผู้ใช้เรียกตรงไม่ได้
-- anon ต้องได้สิทธิ์ด้วย เพราะ policy ถูกประเมินตอน anon ยิง API ถ้าไม่ให้จะได้ error แทน []
create schema if not exists private;
grant usage on schema private to anon, authenticated;
create or replace function private.unit_of(uid uuid)
returns text language sql stable security definer set search_path = public as $$
  select unit from public.profiles where id = uid
$$;
revoke all on function private.unit_of(uuid) from public;
grant execute on function private.unit_of(uuid) to anon, authenticated;

drop policy if exists "cases: own or same unit" on public.cases;
create policy "cases: own or same unit" on public.cases for select using (
  created_by = auth.uid()
  or (coalesce(public.current_role_name(), '') in ('doctor','head_nurse')
      and private.unit_of(auth.uid()) is not null
      and private.unit_of(auth.uid()) = private.unit_of(cases.created_by))
);

-- 3 ------------------------------------------- overrides อ่านได้ตามเคสที่มองเห็นเท่านั้น
-- assessments มองเห็นผ่าน RLS ของ cases อยู่แล้ว = เจ้าของ หรือแพทย์/หัวหน้าพยาบาลหน่วยเดียวกัน
drop policy if exists "overrides: read" on public.overrides;
create policy "overrides: read" on public.overrides for select using (
  overridden_by = auth.uid()
  or exists (select 1 from public.assessments a where a.id = overrides.assessment_id)
);

-- 4 ------------------------------------------------------------------ ตรวจการติดตั้ง
select 'trigger' as what, tgname as name from pg_trigger where tgname = 'protect_profile_role'
union all
select 'policy ' || tablename, policyname from pg_policies
 where tablename in ('cases','overrides') and policyname in ('cases: own or same unit','overrides: read')
union all
select 'function', 'private.unit_of' from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'private' and p.proname = 'unit_of';
-- ต้องได้ 4 แถว

-- ============================================================ รอบที่ 2 วางรันแยก
-- 5 ทดสอบในบทบาท authenticated ด้วยผู้ใช้ชั่วคราว ไม่มีรหัสผ่าน ไม่ส่งอีเมล · ทุกอย่างย้อนกลับเพราะจบด้วย raise exception
do $$
declare
  uid uuid := gen_random_uuid();
  res text := '';
  n int;
begin
  begin
    insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
            'rls-test-' || uid || '@example.invalid', '{}'::jsonb, '{}'::jsonb, now(), now());
  exception when others then
    raise exception 'ผลทดสอบ: สร้างผู้ใช้ชั่วคราวไม่ได้ — %', sqlerrm;
  end;
  select count(*) into n from public.profiles where id = uid;
  res := res || case when n = 1 then 'PASS trigger สร้าง profile | ' else 'FAIL ไม่มี profile | ' end;
  select count(*) into n from public.profiles where id = uid and role = 'nurse';
  res := res || case when n = 1 then 'PASS role เริ่มต้น nurse | ' else 'FAIL role เริ่มต้นไม่ใช่ nurse | ' end;

  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    update public.profiles set role = 'admin' where id = uid;
    get diagnostics n = row_count;
    res := res || case when n = 0 then 'FAIL ไม่เห็นแถวของตัวเอง | ' else 'FAIL เปลี่ยน role ได้ | ' end;
  exception when others then res := res || case when sqlerrm like 'เปลี่ยนบทบาทหรือหน่วยงาน%' then 'PASS กัน role | ' else 'FAIL error อื่น: ' || sqlerrm || ' | ' end;
  end;
  begin
    update public.profiles set unit = 'TEST-UNIT' where id = uid;
    get diagnostics n = row_count;
    res := res || case when n = 0 then 'FAIL ไม่เห็นแถวของตัวเอง | ' else 'FAIL เปลี่ยน unit ได้ | ' end;
  exception when others then res := res || case when sqlerrm like 'เปลี่ยนบทบาทหรือหน่วยงาน%' then 'PASS กัน unit | ' else 'FAIL error อื่น: ' || sqlerrm || ' | ' end;
  end;
  begin
    update public.profiles set full_name = 'ชื่อทดสอบ' where id = uid;
    get diagnostics n = row_count;
    res := res || case when n = 1 then 'PASS แก้ชื่อที่แสดงได้' else 'FAIL แก้ชื่อได้ ' || n || ' แถว' end;
  exception when others then res := res || 'FAIL แก้ชื่อไม่ได้: ' || sqlerrm;
  end;
  raise exception 'ผลทดสอบ: %', res;
end $$;
