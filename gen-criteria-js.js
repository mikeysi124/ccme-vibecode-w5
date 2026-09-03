/* สร้างไฟล์ชุดเกณฑ์ที่แอปใช้ตอนรัน จากไฟล์ต้นทาง criteria-moph-2561.json
 *   1) criteria-moph-2561.js        — ชุดหลัก (ให้เปิดจากไฟล์ได้โดยไม่ต้องมีเซิร์ฟเวอร์)
 *   2) criteria-moph-2561-local.json + .js — "ฉบับโรงพยาบาล" = ชุดหลัก + ส่วนขยาย 3 จุด
 *
 * ทำไมต้องมีฉบับโรงพยาบาล: คู่มือ MOPH เขียนเองว่า "โรงพยาบาลต่าง ๆ สามารถอธิบาย
 * เพิ่มเติมได้" (หน้า 12) และเกณฑ์ shock ในเล่มใช้ SBP < 90 เท่ากันทุกอายุ ซึ่งถ้า
 * ใช้ตรงตัวกับทารกจะจัดเป็นระดับ 1 แทบทุกราย — ส่วนขยายด้านล่างจึงหยิบจุดตัดตามอายุ
 * จาก WI ของโรงพยาบาลจริงมาใช้แทน พร้อมอ้างที่มารายข้อ
 *
 * รันเมื่อแก้ไฟล์ .json:  node gen-criteria-js.js
 * (test-engine.js จะตรวจว่าไฟล์ที่สร้างตรงกับต้นทางเสมอ)
 */
'use strict';
var fs = require('fs'), path = __dirname + '/';
var PMK = 'กองการพยาบาล รพ.พระมงกุฎเกล้า. วิธีปฏิบัติ PMK-WND-037 การคัดกรองผู้ป่วยนอก (แก้ไขครั้งที่ 1, 9 ต.ค. 2561) ผนวก จ/ฉ';

function write(name, obj) {
  fs.writeFileSync(path + name + '.js',
    '/* ไฟล์นี้สร้างอัตโนมัติจาก criteria-moph-2561.json — อย่าแก้ไฟล์นี้โดยตรง\n' +
    '   แก้ที่ .json แล้วรัน: node gen-criteria-js.js */\n' +
    '(function(r){var S=' + JSON.stringify(obj) + ';\n' +
    'if(typeof module!=="undefined"&&module.exports)module.exports=S;\n' +
    'r.CRITERIA_SETS=r.CRITERIA_SETS||{};r.CRITERIA_SETS[S.meta.id]=S;\n' +
    '})(typeof globalThis!=="undefined"?globalThis:this);\n');
}

var base = JSON.parse(fs.readFileSync(path + 'criteria-moph-2561.json', 'utf8'));
write('criteria-moph-2561', base);

/* ---------------- ฉบับโรงพยาบาล = ชุดหลัก + ส่วนขยาย 3 จุด ---------------- */
var local = JSON.parse(JSON.stringify(base));
local.meta.id = 'moph-ed-triage-2561-local';
local.meta.name = 'MOPH ED Triage 2561 — ฉบับโรงพยาบาล (จุดตัดตามอายุ)';
/* version ต้องไม่ซ้ำกับชุดหลัก — ฐานข้อมูลบังคับ unique (source, version) */
local.meta.version = '2561-local';
local.meta.parent_set_id = base.meta.id;
local.meta.local_source = PMK;
local.meta.local_changes = [
  'A7 — เปลี่ยนจุดตัด shock จาก SBP < 90 เท่ากันทุกอายุ เป็นจุดตัดตามอายุ',
  'A8 — เปลี่ยน MAP < 60 เป็น MAP < 65 (ใช้กับอายุ > 10 ปี)',
  'D11 — เพิ่มไข้ > 38 °C ในเด็กอายุ < 3 ปี เป็นสัญญาณช่วงอันตราย (คู่มือ MOPH ระบุให้ "ใช้อุณหภูมิร่วมด้วย" แต่ไม่ได้ให้จุดตัด)'
];

function replace(code, patch) {
  var i = local.criteria.findIndex(function (c) { return c.code === code; });
  if (i < 0) throw new Error('ไม่พบเกณฑ์ ' + code);
  local.criteria[i] = Object.assign({}, local.criteria[i], patch, { local_addition: true, source: PMK });
}

replace('A7', {
  text: 'Shock — SBP ต่ำกว่าจุดตัดตามอายุ (อายุ > 10 ปี: < 90 · อายุ 1–10 ปี: < 70 + (อายุ × 2) · อายุ < 1 ปี: < 70)',
  test: { field: 'sbp', lt_field: 'sbp_shock_cutoff' }
});
replace('A8', { text: 'Shock — MAP < 65 (อายุ > 10 ปี)',
  test: { all: [{ field: 'age_months', gt: 120 }, { field: 'map', lt: 65 }] } });

/* D10 ของชุดหลักเป็นแค่คำเตือนว่า "ให้ใช้อุณหภูมิร่วมด้วย" — ฉบับโรงพยาบาลใส่จุดตัดจริง */
local.criteria = local.criteria.filter(function (c) { return c.code !== 'D10'; });
local.criteria.push({
  code: 'D11', dp: 'D', level: 2, danger_zone: true, local_addition: true, source: PMK,
  text: 'อายุ < 3 ปี ร่วมกับมีไข้ > 38 °C', page: 16,
  test: { all: [{ field: 'age_months', lt: 36 }, { field: 'temp_c', gt: 38 }] }
});

fs.writeFileSync(path + 'criteria-moph-2561-local.json', JSON.stringify(local, null, 2) + '\n');
write('criteria-moph-2561-local', local);
console.log('เขียนแล้ว: criteria-moph-2561.js · criteria-moph-2561-local.json · criteria-moph-2561-local.js');
