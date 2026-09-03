-- ============================================================================
--  ผู้ช่วยตัดสินใจคัดกรองช่องทาง ER/OPD — Database Schema (9 ตาราง)
--  วิชา 5 Data Architecture & Backend · Vibe Coding for Clinical Innovation (ศ.น.พ.)
--  นพ.กิตติพศ เกียรติพัฒนาชัย · User Code P49
--
--  schema นี้ถอดมาจากแอปที่ทำงานจริงแล้ว: https://mikeysi124.github.io/ccme-vibecode-w5/
--  ส่วน seed ท้ายไฟล์สร้างจากไฟล์เกณฑ์ชุดเดียวกับที่แอปใช้ (criteria-moph-2561.json)
--
--  วิธีใช้: Supabase → SQL Editor → วางทั้งไฟล์ → Run → เลือก "enable RLS"
--           แล้วเช็คที่ Table Editor ว่าได้ครบ 9 ตาราง
--
--  ⚠️  ใช้สถานการณ์จำลองเท่านั้น — ไม่มีคอลัมน์ระบุตัวผู้ป่วย
--      (ไม่มีชื่อ, HN, เลขบัตรประชาชน, วันเกิด) ตาม PDPA และข้อกำหนดของคอร์ส
-- ============================================================================

-- ---------------------------------------------------------------- 1. profiles
-- ผู้ใช้ระบบ + บทบาท (ฐานของ RBAC) · PK เดียวกับ auth.users ของ Supabase
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text not null,
  role        text not null default 'nurse'
              check (role in ('nurse','doctor','head_nurse','admin')),
  unit        text,
  created_at  timestamptz not null default now()
);

-- ----------------------------------------------------------- 2. criteria_sets
-- ชุดเกณฑ์ 1 เวอร์ชัน · parent_set_id อ้างตารางตัวเอง ทำให้ "ฉบับโรงพยาบาล"
-- ชี้กลับไปยังฉบับคู่มือที่ต่อยอดมาได้ (คู่มือหน้า 12 เปิดให้ รพ. นิยามเพิ่มเอง)
create table public.criteria_sets (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,
  source          text not null,
  version         text not null,
  effective_date  date not null,
  parent_set_id   uuid references public.criteria_sets (id),
  is_active       boolean not null default false,
  created_at      timestamptz not null default now(),
  unique (source, version)
);

-- ---------------------------------------------------------------- 3. criteria
-- เกณฑ์รายข้อ · logic เก็บเงื่อนไขเป็น jsonb เพราะโครงสร้างต่างกันไปในแต่ละข้อ
create table public.criteria (
  id              uuid primary key default gen_random_uuid(),
  criteria_set_id uuid not null references public.criteria_sets (id) on delete cascade,
  code            text not null,                     -- 'A1','B10','D7' → text (nominal)
  decision_point  char(1) not null check (decision_point in ('A','B','C','D')),
  group_name      text,                              -- ภาวะเสี่ยง / ภาวะซึม / ภาวะปวด
  description     text not null,
  manual_page     smallint,                          -- เลขหน้าในคู่มือ ตรวจย้อนได้
  level_if_met    smallint check (level_if_met between 1 and 5),
  is_danger_zone  boolean not null default false,
  nurse_judgment  boolean not null default false,    -- ข้อที่คู่มือให้ใช้ประสบการณ์
  advisory_only   boolean not null default false,    -- เตือนได้ แต่ห้ามเปลี่ยนระดับเอง
  source_note     text,                              -- ที่มาของข้อที่ รพ. เพิ่มเอง
  logic           jsonb not null,
  sort_order      smallint not null default 0,
  unique (criteria_set_id, code)
);

-- ---------------------------------------------------------- 4. resource_types
-- รายการกิจกรรมของแต่ละชุดเกณฑ์ · is_counted แยก "กิจกรรมที่นับ / ไม่นับ"
-- ตามคู่มือหน้า 13–14 — ติ๊กของที่ไม่นับกี่อย่างก็ไม่เพิ่ม resource_count
create table public.resource_types (
  id              uuid primary key default gen_random_uuid(),
  criteria_set_id uuid not null references public.criteria_sets (id) on delete cascade,
  code            text not null,
  label           text not null,
  is_counted      boolean not null,
  grouping_rule   text,                              -- 'CXR + CT scan = 2 กิจกรรม'
  sort_order      smallint not null default 0,
  unique (criteria_set_id, code)
);

-- ------------------------------------------------------------------- 5. cases
-- เคสคัดกรอง 1 ราย (สถานการณ์จำลอง) — เก็บเฉพาะสิ่งที่พยาบาลประเมินอยู่แล้ว
create table public.cases (
  id              uuid primary key default gen_random_uuid(),
  case_code       text not null unique,              -- รหัสเคส = nominal scale → text
  created_by      uuid not null references public.profiles (id),
  arrived_at      timestamptz not null default now(),
  age_value       smallint not null check (age_value between 0 and 120),
  age_unit        text not null default 'year' check (age_unit in ('year','month')),
  -- ตาราง danger zone ของคู่มือแบ่ง 4 ช่วงอายุเป็นเดือน ให้ DB คำนวณเอง
  -- จะได้ไม่มีทางไม่ตรงกับ age_value/age_unit
  age_months      smallint generated always as
                  ((case when age_unit = 'month' then age_value else age_value * 12 end)::smallint) stored,
  sex             text check (sex in ('M','F','other')),
  chief_complaint text,
  gcs             smallint check (gcs between 3 and 15),
  sbp             smallint check (sbp between 30 and 300),
  dbp             smallint check (dbp between 10 and 200),
  -- คู่มือใช้ MAP < 60 เป็นเกณฑ์ shock ที่จุด ก — คำนวณที่ฐานข้อมูลที่เดียว
  -- ต้อง round ไม่ใช่หารจำนวนเต็ม (ซึ่งตัดเศษ) ให้ตรงกับที่ engine คำนวณฝั่งหน้าเว็บ
  -- เช่น BP 102/70 → 242/3 = 80.67 · round = 81 แต่หารจำนวนเต็มได้ 80 ซึ่งพลิกผลที่ขอบ MAP < 60 ได้
  map             smallint generated always as
                  (case when sbp is null or dbp is null then null
                        else round((sbp + 2 * dbp) / 3.0)::smallint end) stored,
  hr              smallint check (hr between 10 and 300),
  rr              smallint check (rr between 4 and 90),
  spo2            smallint check (spo2 between 50 and 100),
  temp_c          numeric(3,1) check (temp_c between 25.0 and 43.0),
  pain_score      smallint check (pain_score between 0 and 10),
  flags           text[] not null default '{}',
  is_synthetic    boolean not null default true check (is_synthetic),
  created_at      timestamptz not null default now(),
  check (dbp is null or sbp is null or dbp < sbp)
);

-- ------------------------------------------------------------- 6. assessments
-- การประเมิน 1 ครั้ง · 1 เคสประเมินซ้ำได้ → 1:N ไม่ใช่ 1:1
create table public.assessments (
  id                uuid primary key default gen_random_uuid(),
  case_id           uuid not null references public.cases (id) on delete cascade,
  criteria_set_id   uuid not null references public.criteria_sets (id),  -- ตรึงเวอร์ชันที่ใช้
  assessed_by       uuid not null references public.profiles (id),
  suggested_level   smallint not null check (suggested_level between 1 and 5),
  suggested_channel text not null check (suggested_channel in ('ER','OPD')),
  stopped_at        char(1) not null check (stopped_at in ('A','B','C','D')),
  is_consider       boolean not null default false,  -- จุด ง → "พิจารณายกเป็นระดับ 2"
  resource_count    smallint,
  engine_version    text not null,
  elapsed_seconds   numeric(5,1),
  assessed_at       timestamptz not null default now()
);

-- ------------------------------------------------- 7. assessment_criteria (N:M)
-- ตารางกลาง assessments × criteria = หลักฐานว่า "ข้อเสนอนี้มาจากเกณฑ์ข้อไหน"
create table public.assessment_criteria (
  id             uuid primary key default gen_random_uuid(),
  assessment_id  uuid not null references public.assessments (id) on delete cascade,
  criterion_id   uuid not null references public.criteria (id),
  -- ตั้งใจให้ NULL ได้ = "ตัดสินไม่ได้เพราะยังไม่ได้วัด"
  -- ถ้าบังคับ NOT NULL "ยังไม่ได้วัด" จะถูกกลืนเป็น "ไม่เข้าเกณฑ์" เงียบ ๆ
  is_met         boolean,
  observed_value text,
  unique (assessment_id, criterion_id)
);

-- ------------------------------------------------ 8. assessment_resources (N:M)
-- กิจกรรมที่คาดว่าจะใช้ในเคสนั้น — ใช้คำนวณ resource_count ที่จุด ค
create table public.assessment_resources (
  id               uuid primary key default gen_random_uuid(),
  assessment_id    uuid not null references public.assessments (id) on delete cascade,
  resource_type_id uuid not null references public.resource_types (id),
  unique (assessment_id, resource_type_id)
);

-- --------------------------------------------------------------- 9. overrides
-- ระดับ/ช่องทางที่พยาบาลตัดสินจริง · 1:1 กับ assessments (บังคับด้วย unique)
create table public.overrides (
  id             uuid primary key default gen_random_uuid(),
  assessment_id  uuid not null unique references public.assessments (id) on delete cascade,
  overridden_by  uuid not null references public.profiles (id),
  final_level    smallint not null check (final_level between 1 and 5),
  final_channel  text not null check (final_channel in ('ER','OPD')),
  reason_code    text not null,
  reason_note    text,
  created_at     timestamptz not null default now()
);

-- ------------------------------------------------------------------- indexes
create index idx_criteria_set        on public.criteria (criteria_set_id, sort_order);
create index idx_restype_set         on public.resource_types (criteria_set_id, sort_order);
create index idx_cases_created_by    on public.cases (created_by, arrived_at desc);
create index idx_cases_flags         on public.cases using gin (flags);
create index idx_assess_case         on public.assessments (case_id);
create index idx_assess_by           on public.assessments (assessed_by, assessed_at desc);
create index idx_ac_assessment       on public.assessment_criteria (assessment_id);
create index idx_ac_criterion        on public.assessment_criteria (criterion_id);
create index idx_ar_assessment       on public.assessment_resources (assessment_id);

-- ============================================================================
--  Row Level Security — เปิดทุกตาราง ไม่มีข้อยกเว้น
--  RBAC (บทบาททำอะไรได้) อยู่ใน profiles.role · RLS (เห็นแถวไหนได้) อยู่ข้างล่างนี้
-- ============================================================================
alter table public.profiles             enable row level security;
alter table public.criteria_sets        enable row level security;
alter table public.criteria             enable row level security;
alter table public.resource_types       enable row level security;
alter table public.cases                enable row level security;
alter table public.assessments          enable row level security;
alter table public.assessment_criteria  enable row level security;
alter table public.assessment_resources enable row level security;
alter table public.overrides            enable row level security;

-- helper: บทบาทของผู้ใช้ปัจจุบัน
create or replace function public.current_role_name()
returns text language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

-- profiles: เห็น/แก้ของตัวเอง · admin จัดการได้ทั้งหมด
create policy "profiles: self read"   on public.profiles for select
  using (id = auth.uid() or public.current_role_name() = 'admin');
create policy "profiles: self update" on public.profiles for update using (id = auth.uid());

-- ชุดเกณฑ์: ทุกคนที่ล็อกอินอ่านได้ · แก้ได้เฉพาะ admin
create policy "criteria_sets: read"    on public.criteria_sets   for select using (auth.uid() is not null);
create policy "criteria_sets: admin"   on public.criteria_sets   for all    using (public.current_role_name() = 'admin');
create policy "criteria: read"         on public.criteria        for select using (auth.uid() is not null);
create policy "criteria: admin"        on public.criteria        for all    using (public.current_role_name() = 'admin');
create policy "resource_types: read"   on public.resource_types  for select using (auth.uid() is not null);
create policy "resource_types: admin"  on public.resource_types  for all    using (public.current_role_name() = 'admin');

-- cases: พยาบาลเห็นเฉพาะเคสที่ตัวเองสร้าง · แพทย์/หัวหน้าพยาบาลเห็นเคสในหน่วยเดียวกัน
create policy "cases: own or same unit" on public.cases for select using (
  created_by = auth.uid()
  or (public.current_role_name() in ('doctor','head_nurse')
      and exists (select 1 from public.profiles me, public.profiles owner
                  where me.id = auth.uid() and owner.id = cases.created_by and me.unit = owner.unit))
);
create policy "cases: nurse insert" on public.cases for insert with check (created_by = auth.uid());
create policy "cases: owner update" on public.cases for update using (created_by = auth.uid());

-- assessments และตารางกลาง: ผูกสิทธิ์ตามเคส/การประเมินที่มองเห็นได้ (RLS ชั้นบนกรองให้เอง)
create policy "assessments: via case" on public.assessments for select using (
  exists (select 1 from public.cases c where c.id = assessments.case_id));
create policy "assessments: insert own" on public.assessments for insert with check (assessed_by = auth.uid());

create policy "ac: via assessment" on public.assessment_criteria for select using (
  exists (select 1 from public.assessments a where a.id = assessment_criteria.assessment_id));
create policy "ac: insert" on public.assessment_criteria for insert with check (
  exists (select 1 from public.assessments a
          where a.id = assessment_criteria.assessment_id and a.assessed_by = auth.uid()));

create policy "ar: via assessment" on public.assessment_resources for select using (
  exists (select 1 from public.assessments a where a.id = assessment_resources.assessment_id));
create policy "ar: insert" on public.assessment_resources for insert with check (
  exists (select 1 from public.assessments a
          where a.id = assessment_resources.assessment_id and a.assessed_by = auth.uid()));

-- overrides: พยาบาลบันทึกของตัวเอง · หัวหน้าพยาบาล/แพทย์อ่านได้เพื่อ audit
create policy "overrides: read"   on public.overrides for select using (
  overridden_by = auth.uid() or public.current_role_name() in ('head_nurse','doctor'));
create policy "overrides: insert" on public.overrides for insert with check (overridden_by = auth.uid());

-- ============================================================================
--  SEED — ชุดเกณฑ์จริงทั้ง 2 ฉบับ ตรงกับที่แอปใช้ทุกตัวอักษร
--  (ส่วนนี้สร้างอัตโนมัติจาก criteria-moph-2561.json และ ...-local.json)
-- ============================================================================


-- ---- ชุดเกณฑ์: MOPH ED Triage (กรมการแพทย์ 2561) ----
insert into public.criteria_sets (name, source, version, effective_date, parent_set_id, is_active)
values ('MOPH ED Triage (กรมการแพทย์ 2561)', 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด', '2561', '2018-01-01', null, true);

insert into public.criteria (criteria_set_id, code, decision_point, group_name,
  description, manual_page, level_if_met, is_danger_zone, nurse_judgment,
  advisory_only, source_note, logic, sort_order) values
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'A1', 'A', null, 'ต้องทำ CPR', 8, 1, false, false, false, null, '{"flag": "cpr"}'::jsonb, 1),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'A2', 'A', null, 'ต้องใส่ท่อช่วยหายใจ (ET tube)', 8, 1, false, false, false, null, '{"flag": "et_tube"}'::jsonb, 2),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'A3', 'A', null, 'ต้องใส่สายระบายทรวงอก (ICD)', 8, 1, false, false, false, null, '{"flag": "icd"}'::jsonb, 3),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'A4', 'A', null, 'GCS ≤ 8', 8, 1, false, false, false, null, '{"field": "gcs", "lte": 8}'::jsonb, 4),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'A5', 'A', null, 'O₂ sat < 90', 8, 1, false, false, false, null, '{"field": "spo2", "lt": 90}'::jsonb, 5),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'A6', 'A', null, 'Life-threatening arrhythmia', 8, 1, false, false, false, null, '{"flag": "arrhythmia"}'::jsonb, 6),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'A7', 'A', null, 'Shock — SBP < 90', 8, 1, false, false, false, null, '{"field": "sbp", "lt": 90}'::jsonb, 7),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'A8', 'A', null, 'Shock — MAP < 60', 8, 1, false, false, false, null, '{"field": "map", "lt": 60}'::jsonb, 8),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'A9', 'A', null, 'ชัก', 8, 1, false, false, false, null, '{"flag": "seizure"}'::jsonb, 9),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'A10', 'A', null, 'Apnea', 8, 1, false, false, false, null, '{"flag": "apnea"}'::jsonb, 10),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'B1', 'B', 'ภาวะเสี่ยง', 'Active chest pain สงสัยเส้นเลือดหัวใจตีบ อาการคงที่ ไม่ต้องการเครื่องมือช่วยชีวิตทันที', 11, 2, false, false, false, null, '{"flag": "acs_stable"}'::jsonb, 11),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'B2', 'B', 'ภาวะเสี่ยง', 'บุคลากรทางการแพทย์ที่โดนเข็มตำ (needle stick)', 11, 2, false, false, false, null, '{"flag": "needle_stick"}'::jsonb, 12),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'B3', 'B', 'ภาวะเสี่ยง', 'Signs of a stroke ที่ไม่เข้าตามข้อบ่งชี้ระดับ 1', 11, 2, false, false, false, null, '{"flag": "stroke_signs"}'::jsonb, 13),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'B4', 'B', 'ภาวะเสี่ยง', 'สงสัยท้องนอกมดลูก (r/o ectopic pregnancy) สัญญาณชีพคงที่', 11, 2, false, false, false, null, '{"flag": "ectopic"}'::jsonb, 14),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'B5', 'B', 'ภาวะเสี่ยง', 'ผู้ป่วยที่รับยาเคมีบำบัด/ภูมิคุ้มกันบกพร่อง มาด้วยไข้', 11, 2, false, false, false, null, '{"flag": "immunocompromised_fever"}'::jsonb, 15),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'B6', 'B', 'ภาวะเสี่ยง', 'ผู้ป่วยที่เสี่ยงต่อการฆ่าตัวตายหรือทำร้ายผู้อื่น (suicidal / homicidal)', 11, 2, false, false, false, null, '{"flag": "suicidal"}'::jsonb, 16),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'B7', 'B', 'ภาวะเสี่ยง', 'ภาวะเสี่ยงอื่นจากการซักประวัติและประสบการณ์ผู้คัดกรอง — คู่มือระบุว่า "จำเป็นต้องใช้พื้นฐานของการซักประวัติและใช้สัมผัสที่หก จากประสบการณ์" และแต่ละโรงพยาบาลนิยามเพิ่มเองได้', 10, 2, false, true, false, null, '{"flag": "high_risk_other"}'::jsonb, 17),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'B8', 'B', 'ภาวะซึม', 'GCS 9–12', 12, 2, false, false, false, null, '{"all": [{"field": "gcs", "gte": 9}, {"field": "gcs", "lte": 12}]}'::jsonb, 18),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'B9', 'B', 'ภาวะซึม', 'New onset alteration of conscious / confusion / lethargy (เช่น ผู้สูงอายุสับสนที่เพิ่งเป็น, เด็ก 3 เดือนนอนทั้งวัน, วัยรุ่นสับสนถามตอบไม่รู้เรื่อง)', 12, 2, false, false, false, null, '{"flag": "new_onset_altered"}'::jsonb, 19),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'B10', 'B', 'ภาวะปวด', 'ปวดมาก pain score ≥ 7 ร่วมกับการประเมินจากลักษณะ (สีหน้า เหงื่อแตก ท่าทาง การเปลี่ยนแปลงของสัญญาณชีพ) โดยสัมพันธ์กับอวัยวะสำคัญอย่างสมเหตุสมผล', 12, 2, false, false, false, null, '{"all": [{"field": "pain_score", "gte": 7}, {"flag": "pain_objective_signs"}]}'::jsonb, 20),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'D1', 'D', null, 'อายุ < 3 เดือน: ชีพจร > 180 ครั้ง/นาที', 16, 2, true, false, false, 'ตารางในคู่มือพิมพ์ "180" โดยไม่มีเครื่องหมาย > ต่างจากช่วงอายุอื่น — ตีความเป็น > 180 ให้สอดคล้องกับทั้งตาราง', '{"all": [{"field": "age_months", "lt": 3}, {"field": "hr", "gt": 180}]}'::jsonb, 21),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'D2', 'D', null, 'อายุ < 3 เดือน: อัตราการหายใจ > 50 ครั้ง/นาที', 16, 2, true, false, false, null, '{"all": [{"field": "age_months", "lt": 3}, {"field": "rr", "gt": 50}]}'::jsonb, 22),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'D3', 'D', null, 'อายุ 3 เดือน – 3 ปี: ชีพจร > 160 ครั้ง/นาที', 16, 2, true, false, false, null, '{"all": [{"field": "age_months", "gte": 3}, {"field": "age_months", "lt": 36}, {"field": "hr", "gt": 160}]}'::jsonb, 23),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'D4', 'D', null, 'อายุ 3 เดือน – 3 ปี: อัตราการหายใจ > 40 ครั้ง/นาที', 16, 2, true, false, false, null, '{"all": [{"field": "age_months", "gte": 3}, {"field": "age_months", "lt": 36}, {"field": "rr", "gt": 40}]}'::jsonb, 24),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'D5', 'D', null, 'อายุ 3–8 ปี: ชีพจร > 140 ครั้ง/นาที', 16, 2, true, false, false, null, '{"all": [{"field": "age_months", "gte": 36}, {"field": "age_months", "lte": 96}, {"field": "hr", "gt": 140}]}'::jsonb, 25),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'D6', 'D', null, 'อายุ 3–8 ปี: อัตราการหายใจ > 30 ครั้ง/นาที', 16, 2, true, false, false, null, '{"all": [{"field": "age_months", "gte": 36}, {"field": "age_months", "lte": 96}, {"field": "rr", "gt": 30}]}'::jsonb, 26),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'D7', 'D', null, 'อายุ > 8 ปี: ชีพจร > 100 ครั้ง/นาที', 16, 2, true, false, false, null, '{"all": [{"field": "age_months", "gt": 96}, {"field": "hr", "gt": 100}]}'::jsonb, 27),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'D8', 'D', null, 'อายุ > 8 ปี: อัตราการหายใจ > 20 ครั้ง/นาที', 16, 2, true, false, false, null, '{"all": [{"field": "age_months", "gt": 96}, {"field": "rr", "gt": 20}]}'::jsonb, 28),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'D9', 'D', null, 'SpO₂ < 92% (ทุกช่วงอายุ)', 16, 2, true, false, false, null, '{"field": "spo2", "lt": 92}'::jsonb, 29),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'D10', 'D', null, 'อายุ < 3 ปี ให้ใช้อุณหภูมิร่วมด้วยในการตัดสินใจ — คู่มือไม่ได้ระบุจุดตัดของอุณหภูมิไว้ ระบบจึงยกให้พยาบาลพิจารณา ไม่ตัดสินแทน', 16, 2, true, true, true, null, '{"field": "age_months", "lt": 36}'::jsonb, 30);

insert into public.resource_types (criteria_set_id, code, label, is_counted, grouping_rule, sort_order) values
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'lab', 'Lab (เจาะเลือด, ตรวจปัสสาวะ)', true, 'CBC, BUN/Cr, E''lyte, G/M ถือเป็นการเจาะเลือดทั้งหมด = 1 กิจกรรม · CBC + UA ถือว่าเป็น Lab = 1 กิจกรรม', 1),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'ekg', 'EKG', true, null, 2),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'xray', 'X-ray', true, 'CXR, Skull film, C-spine ถือว่าเป็น x-ray เหมือนกัน = 1 กิจกรรม', 3),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'us', 'Ultrasound', true, null, 4),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'ct', 'CT scan', true, 'CXR + CT scan = 2 กิจกรรม', 5),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'iv_fluid', 'IV fluid (hydration)', true, null, 6),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'injection', 'ฉีดยา IV, IM หรือพ่นยา', true, null, 7),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'consult', 'Consult เฉพาะทาง', true, null, 8),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'procedure', 'หัตถการ NG, foley''s, เย็บแผล, eye irrigation, remove FB, I&D, เช็ดตัวลดไข้', true, null, 9),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'hp', 'การซักประวัติและตรวจร่างกาย (History & Physical)', false, null, 10),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'heparin_lock', 'On heparin lock', false, null, 11),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'oral_scheduled', 'ยากิน, ยาฉีดตามนัด', false, null, 12),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'tt_tat', 'ฉีด tetanus toxoid (TT), TAT', false, null, 13),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'rabies', 'ฉีด rabies vaccine (Verorab, Speeda, PCEC), ERIG, HRIG', false, null, 14),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'splint', 'Splint, sling, ล้างแผล/dressing, cold pack', false, null, 15),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), 'call_doctor', 'โทรตามแพทย์เวร', false, null, 16);


-- ---- ชุดเกณฑ์: MOPH ED Triage 2561 — ฉบับโรงพยาบาล (จุดตัดตามอายุ) ----
insert into public.criteria_sets (name, source, version, effective_date, parent_set_id, is_active)
values ('MOPH ED Triage 2561 — ฉบับโรงพยาบาล (จุดตัดตามอายุ)', 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด', '2561-local', '2018-01-01', (select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561'), false);

insert into public.criteria (criteria_set_id, code, decision_point, group_name,
  description, manual_page, level_if_met, is_danger_zone, nurse_judgment,
  advisory_only, source_note, logic, sort_order) values
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'A1', 'A', null, 'ต้องทำ CPR', 8, 1, false, false, false, null, '{"flag": "cpr"}'::jsonb, 1),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'A2', 'A', null, 'ต้องใส่ท่อช่วยหายใจ (ET tube)', 8, 1, false, false, false, null, '{"flag": "et_tube"}'::jsonb, 2),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'A3', 'A', null, 'ต้องใส่สายระบายทรวงอก (ICD)', 8, 1, false, false, false, null, '{"flag": "icd"}'::jsonb, 3),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'A4', 'A', null, 'GCS ≤ 8', 8, 1, false, false, false, null, '{"field": "gcs", "lte": 8}'::jsonb, 4),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'A5', 'A', null, 'O₂ sat < 90', 8, 1, false, false, false, null, '{"field": "spo2", "lt": 90}'::jsonb, 5),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'A6', 'A', null, 'Life-threatening arrhythmia', 8, 1, false, false, false, null, '{"flag": "arrhythmia"}'::jsonb, 6),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'A7', 'A', null, 'Shock — SBP ต่ำกว่าจุดตัดตามอายุ (อายุ > 10 ปี: < 90 · อายุ 1–10 ปี: < 70 + (อายุ × 2) · อายุ < 1 ปี: < 70)', 8, 1, false, false, false, 'กองการพยาบาล รพ.พระมงกุฎเกล้า. วิธีปฏิบัติ PMK-WND-037 การคัดกรองผู้ป่วยนอก (แก้ไขครั้งที่ 1, 9 ต.ค. 2561) ผนวก จ/ฉ', '{"field": "sbp", "lt_field": "sbp_shock_cutoff"}'::jsonb, 7),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'A8', 'A', null, 'Shock — MAP < 65 (อายุ > 10 ปี)', 8, 1, false, false, false, 'กองการพยาบาล รพ.พระมงกุฎเกล้า. วิธีปฏิบัติ PMK-WND-037 การคัดกรองผู้ป่วยนอก (แก้ไขครั้งที่ 1, 9 ต.ค. 2561) ผนวก จ/ฉ', '{"all": [{"field": "age_months", "gt": 120}, {"field": "map", "lt": 65}]}'::jsonb, 8),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'A9', 'A', null, 'ชัก', 8, 1, false, false, false, null, '{"flag": "seizure"}'::jsonb, 9),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'A10', 'A', null, 'Apnea', 8, 1, false, false, false, null, '{"flag": "apnea"}'::jsonb, 10),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'B1', 'B', 'ภาวะเสี่ยง', 'Active chest pain สงสัยเส้นเลือดหัวใจตีบ อาการคงที่ ไม่ต้องการเครื่องมือช่วยชีวิตทันที', 11, 2, false, false, false, null, '{"flag": "acs_stable"}'::jsonb, 11),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'B2', 'B', 'ภาวะเสี่ยง', 'บุคลากรทางการแพทย์ที่โดนเข็มตำ (needle stick)', 11, 2, false, false, false, null, '{"flag": "needle_stick"}'::jsonb, 12),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'B3', 'B', 'ภาวะเสี่ยง', 'Signs of a stroke ที่ไม่เข้าตามข้อบ่งชี้ระดับ 1', 11, 2, false, false, false, null, '{"flag": "stroke_signs"}'::jsonb, 13),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'B4', 'B', 'ภาวะเสี่ยง', 'สงสัยท้องนอกมดลูก (r/o ectopic pregnancy) สัญญาณชีพคงที่', 11, 2, false, false, false, null, '{"flag": "ectopic"}'::jsonb, 14),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'B5', 'B', 'ภาวะเสี่ยง', 'ผู้ป่วยที่รับยาเคมีบำบัด/ภูมิคุ้มกันบกพร่อง มาด้วยไข้', 11, 2, false, false, false, null, '{"flag": "immunocompromised_fever"}'::jsonb, 15),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'B6', 'B', 'ภาวะเสี่ยง', 'ผู้ป่วยที่เสี่ยงต่อการฆ่าตัวตายหรือทำร้ายผู้อื่น (suicidal / homicidal)', 11, 2, false, false, false, null, '{"flag": "suicidal"}'::jsonb, 16),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'B7', 'B', 'ภาวะเสี่ยง', 'ภาวะเสี่ยงอื่นจากการซักประวัติและประสบการณ์ผู้คัดกรอง — คู่มือระบุว่า "จำเป็นต้องใช้พื้นฐานของการซักประวัติและใช้สัมผัสที่หก จากประสบการณ์" และแต่ละโรงพยาบาลนิยามเพิ่มเองได้', 10, 2, false, true, false, null, '{"flag": "high_risk_other"}'::jsonb, 17),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'B8', 'B', 'ภาวะซึม', 'GCS 9–12', 12, 2, false, false, false, null, '{"all": [{"field": "gcs", "gte": 9}, {"field": "gcs", "lte": 12}]}'::jsonb, 18),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'B9', 'B', 'ภาวะซึม', 'New onset alteration of conscious / confusion / lethargy (เช่น ผู้สูงอายุสับสนที่เพิ่งเป็น, เด็ก 3 เดือนนอนทั้งวัน, วัยรุ่นสับสนถามตอบไม่รู้เรื่อง)', 12, 2, false, false, false, null, '{"flag": "new_onset_altered"}'::jsonb, 19),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'B10', 'B', 'ภาวะปวด', 'ปวดมาก pain score ≥ 7 ร่วมกับการประเมินจากลักษณะ (สีหน้า เหงื่อแตก ท่าทาง การเปลี่ยนแปลงของสัญญาณชีพ) โดยสัมพันธ์กับอวัยวะสำคัญอย่างสมเหตุสมผล', 12, 2, false, false, false, null, '{"all": [{"field": "pain_score", "gte": 7}, {"flag": "pain_objective_signs"}]}'::jsonb, 20),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'D1', 'D', null, 'อายุ < 3 เดือน: ชีพจร > 180 ครั้ง/นาที', 16, 2, true, false, false, 'ตารางในคู่มือพิมพ์ "180" โดยไม่มีเครื่องหมาย > ต่างจากช่วงอายุอื่น — ตีความเป็น > 180 ให้สอดคล้องกับทั้งตาราง', '{"all": [{"field": "age_months", "lt": 3}, {"field": "hr", "gt": 180}]}'::jsonb, 21),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'D2', 'D', null, 'อายุ < 3 เดือน: อัตราการหายใจ > 50 ครั้ง/นาที', 16, 2, true, false, false, null, '{"all": [{"field": "age_months", "lt": 3}, {"field": "rr", "gt": 50}]}'::jsonb, 22),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'D3', 'D', null, 'อายุ 3 เดือน – 3 ปี: ชีพจร > 160 ครั้ง/นาที', 16, 2, true, false, false, null, '{"all": [{"field": "age_months", "gte": 3}, {"field": "age_months", "lt": 36}, {"field": "hr", "gt": 160}]}'::jsonb, 23),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'D4', 'D', null, 'อายุ 3 เดือน – 3 ปี: อัตราการหายใจ > 40 ครั้ง/นาที', 16, 2, true, false, false, null, '{"all": [{"field": "age_months", "gte": 3}, {"field": "age_months", "lt": 36}, {"field": "rr", "gt": 40}]}'::jsonb, 24),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'D5', 'D', null, 'อายุ 3–8 ปี: ชีพจร > 140 ครั้ง/นาที', 16, 2, true, false, false, null, '{"all": [{"field": "age_months", "gte": 36}, {"field": "age_months", "lte": 96}, {"field": "hr", "gt": 140}]}'::jsonb, 25),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'D6', 'D', null, 'อายุ 3–8 ปี: อัตราการหายใจ > 30 ครั้ง/นาที', 16, 2, true, false, false, null, '{"all": [{"field": "age_months", "gte": 36}, {"field": "age_months", "lte": 96}, {"field": "rr", "gt": 30}]}'::jsonb, 26),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'D7', 'D', null, 'อายุ > 8 ปี: ชีพจร > 100 ครั้ง/นาที', 16, 2, true, false, false, null, '{"all": [{"field": "age_months", "gt": 96}, {"field": "hr", "gt": 100}]}'::jsonb, 27),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'D8', 'D', null, 'อายุ > 8 ปี: อัตราการหายใจ > 20 ครั้ง/นาที', 16, 2, true, false, false, null, '{"all": [{"field": "age_months", "gt": 96}, {"field": "rr", "gt": 20}]}'::jsonb, 28),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'D9', 'D', null, 'SpO₂ < 92% (ทุกช่วงอายุ)', 16, 2, true, false, false, null, '{"field": "spo2", "lt": 92}'::jsonb, 29),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'D11', 'D', null, 'อายุ < 3 ปี ร่วมกับมีไข้ > 38 °C', 16, 2, true, false, false, 'กองการพยาบาล รพ.พระมงกุฎเกล้า. วิธีปฏิบัติ PMK-WND-037 การคัดกรองผู้ป่วยนอก (แก้ไขครั้งที่ 1, 9 ต.ค. 2561) ผนวก จ/ฉ', '{"all": [{"field": "age_months", "lt": 36}, {"field": "temp_c", "gt": 38}]}'::jsonb, 30);

insert into public.resource_types (criteria_set_id, code, label, is_counted, grouping_rule, sort_order) values
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'lab', 'Lab (เจาะเลือด, ตรวจปัสสาวะ)', true, 'CBC, BUN/Cr, E''lyte, G/M ถือเป็นการเจาะเลือดทั้งหมด = 1 กิจกรรม · CBC + UA ถือว่าเป็น Lab = 1 กิจกรรม', 1),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'ekg', 'EKG', true, null, 2),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'xray', 'X-ray', true, 'CXR, Skull film, C-spine ถือว่าเป็น x-ray เหมือนกัน = 1 กิจกรรม', 3),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'us', 'Ultrasound', true, null, 4),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'ct', 'CT scan', true, 'CXR + CT scan = 2 กิจกรรม', 5),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'iv_fluid', 'IV fluid (hydration)', true, null, 6),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'injection', 'ฉีดยา IV, IM หรือพ่นยา', true, null, 7),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'consult', 'Consult เฉพาะทาง', true, null, 8),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'procedure', 'หัตถการ NG, foley''s, เย็บแผล, eye irrigation, remove FB, I&D, เช็ดตัวลดไข้', true, null, 9),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'hp', 'การซักประวัติและตรวจร่างกาย (History & Physical)', false, null, 10),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'heparin_lock', 'On heparin lock', false, null, 11),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'oral_scheduled', 'ยากิน, ยาฉีดตามนัด', false, null, 12),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'tt_tat', 'ฉีด tetanus toxoid (TT), TAT', false, null, 13),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'rabies', 'ฉีด rabies vaccine (Verorab, Speeda, PCEC), ERIG, HRIG', false, null, 14),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'splint', 'Splint, sling, ล้างแผล/dressing, cold pack', false, null, 15),
  ((select id from public.criteria_sets where source = 'กรมการแพทย์ กระทรวงสาธารณสุข. MOPH ED. TRIAGE. พิมพ์ครั้งที่ 1 (2561) — แปลมาจาก ESI (Emergency Severity Index) คัดกรอง 5 ระดับ ใช้ 4 หัวข้อเป็นจุดตัด' and version = '2561-local'), 'call_doctor', 'โทรตามแพทย์เวร', false, null, 16);


-- ตรวจว่า seed เข้าครบ
--   select s.name, count(distinct c.id) as criteria, count(distinct r.id) as resources
--   from public.criteria_sets s
--   left join public.criteria c on c.criteria_set_id = s.id
--   left join public.resource_types r on r.criteria_set_id = s.id
--   group by s.name;
