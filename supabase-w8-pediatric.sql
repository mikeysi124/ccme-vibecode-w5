-- supabase-w8-pediatric.sql · แอปเวอร์ชัน 1.3.0 · 7 ต.ค. 2569
-- รันใน Supabase SQL Editor ก่อน deploy แอป 1.3.0 · รันซ้ำได้ ผลเท่าเดิม
-- ลำดับตั้งใหม่จากศูนย์: supabase-schema.sql → supabase-w6-additions.sql → supabase-w7-hardening.sql → ไฟล์นี้
--   1) ตาราง criteria รับจุดตัดสินใจ P ข้อพิจารณาผู้ป่วยเด็ก จากกรอบ Pediatric Triage คู่มือหน้า 13
--   2) เลขหน้าคู่มือเปลี่ยนจากหน้า PDF เป็นเลขหน้าเล่ม · หน้า PDF = เลขหน้าเล่ม + 3 · ตั้งค่าตามรหัสจึงรันซ้ำได้ · แก้เฉพาะชุด 2561 กับ 2561-local
--   3) ข้อความ D10 · เพิ่ม P1–P4 ทั้งชุดหลักและฉบับโรงพยาบาล ข้อความกับ logic สร้างจาก criteria-moph-2561.json
-- ไม่สร้างตารางใหม่ จึงไม่ต้อง GRANT เพิ่ม
begin;

-- ลบ check เดิมของ decision_point ทุกตัวไม่ว่าชื่ออะไร แล้วสร้างใหม่ที่รับ P
do $$
declare r record;
begin
  for r in select conname from pg_constraint
           where conrelid = 'public.criteria'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) like '%decision_point%'
  loop
    execute format('alter table public.criteria drop constraint %I', r.conname);
  end loop;
end $$;
alter table public.criteria add constraint criteria_decision_point_check
  check (decision_point in ('A','B','C','D','P'));

update public.criteria set manual_page = 5  where code in ('A1','A2','A3','A4','A5','A6','A7','A8','A9','A10') and criteria_set_id in (select id from public.criteria_sets where version in ('2561', '2561-local'));
update public.criteria set manual_page = 8  where code in ('B1','B2','B3','B4','B5','B6','B9') and criteria_set_id in (select id from public.criteria_sets where version in ('2561', '2561-local'));
update public.criteria set manual_page = 7  where code = 'B7' and criteria_set_id in (select id from public.criteria_sets where version in ('2561', '2561-local'));
update public.criteria set manual_page = 9  where code in ('B8','B10') and criteria_set_id in (select id from public.criteria_sets where version in ('2561', '2561-local'));
update public.criteria set manual_page = 13 where code in ('D1','D2','D3','D4','D5','D6','D7','D8','D9','D10','D11') and criteria_set_id in (select id from public.criteria_sets where version in ('2561', '2561-local'));

update public.criteria set description = 'อายุ < 3 ปี ให้ใช้อุณหภูมิร่วมด้วยในการตัดสินใจ — จุดตัดอุณหภูมิอยู่ในข้อ P1–P3 กรอบ Pediatric Triage หน้าเดียวกัน' where code = 'D10' and criteria_set_id in (select id from public.criteria_sets where version in ('2561', '2561-local'));

insert into public.criteria (criteria_set_id, code, decision_point, group_name, description, manual_page,
  level_if_met, is_danger_zone, nurse_judgment, advisory_only, source_note, logic, sort_order)
select s.id, v.code, 'P', 'ข้อพิจารณาผู้ป่วยเด็ก', v.description, 13, v.level, false, v.nurse, v.advisory, null, v.logic::jsonb, v.sort_order
from public.criteria_sets s
cross join (values
    ('P1', 'อายุ 1–28 วัน อุณหภูมิ > 38.0 °C ให้พิจารณาเป็นคัดแยกระดับ 2 เป็นอย่างน้อย', 2, false, false, '{"all": [{"field": "age_months", "lt": 1}, {"field": "temp_c", "gt": 38.0}]}', 101),
    ('P2', 'อายุ 1–3 เดือน อุณหภูมิ > 38.0 °C ให้พิจารณาเป็นคัดแยกระดับ 2', 2, false, false, '{"all": [{"field": "age_months", "gte": 1}, {"field": "age_months", "lt": 3}, {"field": "temp_c", "gt": 38.0}]}', 102),
    ('P3', 'อายุ 3 เดือน – 3 ปี อุณหภูมิ > 39.0 °C ให้พิจารณาเป็นคัดแยกระดับ 3', 3, false, false, '{"all": [{"field": "age_months", "gte": 3}, {"field": "age_months", "lt": 36}, {"field": "temp_c", "gt": 39.0}]}', 103),
    ('P4', 'อายุ 3 เดือน – 3 ปี ได้รับวัคซีนไม่ครบตามกำหนด หรือไข้ไม่ทราบสาเหตุ คู่มือให้พิจารณาเป็นคัดแยกระดับ 3 · ระบบไม่ได้ถามสองข้อนี้ พยาบาลประเมินเอง', 3, true, true, '{"all": [{"field": "age_months", "gte": 3}, {"field": "age_months", "lt": 36}]}', 104)
) as v(code, description, level, nurse, advisory, logic, sort_order)
where s.version in ('2561', '2561-local')
on conflict (criteria_set_id, code) do update set
  decision_point = excluded.decision_point, group_name = excluded.group_name, description = excluded.description,
  manual_page = excluded.manual_page, level_if_met = excluded.level_if_met, nurse_judgment = excluded.nurse_judgment,
  advisory_only = excluded.advisory_only, logic = excluded.logic, sort_order = excluded.sort_order;

commit;

-- ตรวจผล: ชุด 2561 และ 2561-local ต้องได้ total 34 · p_rows 4 · d7_page 13
select s.version,
       count(*) as total,
       count(*) filter (where c.decision_point = 'P') as p_rows,
       max(c.manual_page) filter (where c.code = 'D7') as d7_page
from public.criteria c join public.criteria_sets s on s.id = c.criteria_set_id
group by s.version order by s.version;
