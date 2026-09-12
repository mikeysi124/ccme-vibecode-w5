-- ============================================================================
--  ส่วนเพิ่มของสัปดาห์ที่ 6 — รันต่อจาก supabase-schema.sql ใน SQL Editor
--  ผู้ช่วยคัดกรองช่องทาง ER/OPD · นพ.กิตติพศ เกียรติพัฒนาชัย (p49)
--
--  ทำไมต้องมีไฟล์นี้: schema ของสัปดาห์ที่ 5 เขียน policy ไว้ครบเฉพาะ
--  select และ insert — ยังไม่มี update/delete และยังไม่มีทางสร้างแถว profiles
--  ให้ผู้ใช้ใหม่ ทำให้ demo CRUD ครบสี่คำสั่งของสัปดาห์นี้ทำไม่ได้จริง
--  (คำสั่งที่ไม่มี policy จะไม่ error แต่กระทบ 0 แถว = เงียบ ซึ่งอันตรายกว่า)
-- ============================================================================

-- 1 ----------------------------------------------------------------- profiles
-- ให้ผู้ใช้สร้างแถวของตัวเองได้ครั้งแรก (fallback ของ trigger ด้านล่าง)
drop policy if exists "profiles: self insert" on public.profiles;
create policy "profiles: self insert" on public.profiles
  for insert with check (id = auth.uid());

-- trigger สร้าง profile อัตโนมัติเมื่อสมัครสมาชิก ตามที่สไลด์ Step 7 กำหนด
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', new.email))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 2 -------------------------------------------------------------- cases DELETE
-- เจ้าของเคสลบได้ · assessments / assessment_criteria / overrides หายตาม cascade
drop policy if exists "cases: owner delete" on public.cases;
create policy "cases: owner delete" on public.cases
  for delete using (created_by = auth.uid());

-- 3 --------------------------------------------------- assessments UPDATE/DELETE
drop policy if exists "assessments: owner update" on public.assessments;
create policy "assessments: owner update" on public.assessments
  for update using (assessed_by = auth.uid());

drop policy if exists "assessments: owner delete" on public.assessments;
create policy "assessments: owner delete" on public.assessments
  for delete using (assessed_by = auth.uid());

-- 4 ---------------------------------------------------- overrides UPDATE/DELETE
-- แก้เหตุผล/ระดับที่ตัดสินจริงได้เฉพาะคนที่บันทึกไว้เอง
drop policy if exists "overrides: owner update" on public.overrides;
create policy "overrides: owner update" on public.overrides
  for update using (overridden_by = auth.uid())
  with check (overridden_by = auth.uid());

drop policy if exists "overrides: owner delete" on public.overrides;
create policy "overrides: owner delete" on public.overrides
  for delete using (overridden_by = auth.uid());

-- 5 ------------------------------------------- assessment_criteria UPDATE/DELETE
drop policy if exists "ac: owner update" on public.assessment_criteria;
create policy "ac: owner update" on public.assessment_criteria
  for update using (exists (select 1 from public.assessments a
                            where a.id = assessment_criteria.assessment_id
                              and a.assessed_by = auth.uid()));

drop policy if exists "ac: owner delete" on public.assessment_criteria;
create policy "ac: owner delete" on public.assessment_criteria
  for delete using (exists (select 1 from public.assessments a
                            where a.id = assessment_criteria.assessment_id
                              and a.assessed_by = auth.uid()));

-- ============================================================================
--  ตรวจว่าครบ: ทุกตารางต้องเปิด RLS และมี policy ของคำสั่งที่แอปใช้จริง
--  select * from pg_policies where schemaname = 'public' order by tablename, cmd;
-- ============================================================================
