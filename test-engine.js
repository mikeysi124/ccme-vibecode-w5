/* Known-Answer Test ของ criteria engine — รันด้วย: node test-engine.js
 * ชุดเคสอยู่ใน kat-cases.js (ไฟล์เดียวกับที่แอปใช้ในแท็บ "ทดสอบ") */
'use strict';
var E = require('./engine.js');
var CASES = require('./kat-cases.js');
var SETS = { 'moph-ed-triage-2561': require('./criteria-moph-2561.js'),
             'moph-ed-triage-2561-local': require('./criteria-moph-2561-local.js') };
var SET = SETS['moph-ed-triage-2561'];
var fs = require('fs');

var pass = 0, fail = 0;

function expect(name, cond) {
  if (cond) pass++; else { fail++; console.log('  ✗ ' + name); }
}

console.log('Known-Answer Test — criteria engine v0 · ชุดเกณฑ์: ' + SET.meta.name + '\n');

/* ------------------------- 1) เคสจำลองทั้งชุด (ผ่าน validate → assess) */
CASES.forEach(function (t) {
  var v = E.validate(t.data);
  if (!v.ok) { fail++; console.log('  ✗ #' + t.id + ' ' + t.name + '\n     ข้อมูลไม่ผ่าน validate: ' + v.errors.join(' · ')); return; }
  var r = E.assess(v.data, SETS[t.set || 'moph-ed-triage-2561']);
  var codes = r.matched.map(function (m) { return m.code; });
  var ok = r.level === t.expect.level && r.channel === t.expect.channel &&
           (t.expect.codes || []).every(function (c) { return codes.indexOf(c) !== -1; });
  if (ok) pass++;
  else {
    fail++;
    console.log('  ✗ #' + t.id + ' [' + t.src + '] ' + t.name);
    console.log('     คาดหวัง: ระดับ ' + t.expect.level + ' · ' + t.expect.channel +
                ((t.expect.codes || []).length ? ' · เข้าเกณฑ์ ' + t.expect.codes.join(',') : ''));
    console.log('     ได้จริง: ระดับ ' + r.level + ' · ' + r.channel + ' · เข้าเกณฑ์ ' +
                (codes.join(',') || '(ไม่มี)') + ' · หยุดที่จุด ' + r.stopped_at);
  }
});

/* ------------------------- 2) tri-state: ไม่รู้ ≠ ไม่เข้าเกณฑ์ */
expect('ไม่ได้วัดชีพจร → ตัดสินไม่ได้ (null) ไม่ใช่ false',
  E.evalTest({ field: 'hr', gt: 100 }, { flags: [] }) === null);
expect('all ที่มีข้อหนึ่ง false → false ทันที แม้อีกข้อยังไม่รู้',
  E.evalTest({ all: [{ flag: 'x' }, { field: 'hr', gt: 100 }] }, { flags: [] }) === false);
expect('any ที่มีข้อหนึ่ง true → true แม้อีกข้อยังไม่รู้',
  E.evalTest({ any: [{ flag: 'x' }, { field: 'hr', gt: 100 }] }, { flags: ['x'] }) === true);

var noVital = E.validate({ cc: 'ปวดท้อง', age_value: 45, age_unit: 'year', gcs: 15,
                           spo2: 98, sbp: 128, dbp: 80, pain_score: 4,
                           flags: [], resources: ['lab', 'us'] });
var rU = E.assess(noVital.data, SET);
expect('ไม่ได้วัดชีพจร/อัตราหายใจ → D7,D8 ต้องอยู่ในกลุ่ม "ตัดสินไม่ได้"',
  rU.unknown.some(function (x) { return x.code === 'D7'; }) &&
  !rU.unmatched.some(function (x) { return x.code === 'D7'; }));
expect('ข้อที่ตัดสินไม่ได้ ณ จุดที่ใช้ตัดสินจริง ต้องถูกยกมาเตือน (blocking_unknown)',
  rU.blocking_unknown.some(function (x) { return x.code === 'D7'; }));

/* ------------------------- 3) advisory: เตือนได้ แต่ห้ามเปลี่ยนระดับเอง */
var infant = E.validate({ cc: 'ไข้', age_value: 18, age_unit: 'month', hr: 130, rr: 30,
                          spo2: 98, sbp: 95, dbp: 60, gcs: 15, temp_c: 39.2, pain_score: 0,
                          flags: [], resources: ['lab', 'xray'] });
var rA = E.assess(infant.data, SET);
expect('เด็ก < 3 ปี → ขึ้นคำเตือนเรื่องอุณหภูมิ (D10) เป็น advisory',
  rA.advisories.some(function (x) { return x.code === 'D10'; }));
expect('advisory ต้องไม่ดันระดับเอง — เคสนี้ยังเป็นระดับ 3',
  rA.level === 3 && rA.matched.every(function (m) { return m.code !== 'D10'; }));

/* ------------------------- 4) validate: ค่าขยะต้องไม่ไหลเข้า engine */
var g1 = E.validate({ hr: 400, flags: [], resources: [] });
expect('ชีพจร 400 → ถูกปฏิเสธพร้อมข้อความ ไม่ส่งค่าเข้า engine',
  !g1.ok && g1.bad.hr && g1.data.hr === null);
var g2 = E.validate({ age_value: 40, age_unit: 'year', spo2: -5, temp_c: 'abc', pain_score: 3.5, flags: [], resources: [] });
expect('SpO₂ ติดลบ / อุณหภูมิเป็นตัวอักษร / pain มีทศนิยม → ถูกปฏิเสธครบ 3 ข้อ',
  !g2.ok && g2.errors.length === 3 && g2.data.spo2 === null && g2.data.temp_c === null && g2.data.pain_score === null);
var g3 = E.validate({ sbp: 100, dbp: 120, flags: [], resources: [] });
expect('ความดันตัวล่างสูงกว่าตัวบน → ถูกปฏิเสธ', !g3.ok && !!g3.bad.dbp);
var g4 = E.validate({ age_value: 40, age_unit: 'year', flags: [], resources: [] });
expect('เว้นว่างทุกช่องยกเว้นอายุ → ผ่าน validate (ยังไม่ได้วัด ≠ ผิด) และไม่มี NaN',
  g4.ok && Object.keys(g4.data).every(function (k) {
    return typeof g4.data[k] !== 'number' || isFinite(g4.data[k]);
  }));
var g5 = E.validate({ hr: 90, flags: [], resources: [] });
expect('ไม่กรอกอายุ → ถูกปฏิเสธ เพราะตาราง danger zone และจุดตัด shock ขึ้นกับช่วงอายุ',
  !g5.ok && g5.errors.some(function (e) { return e.indexOf('อายุ') === 0; }));

/* จุดตัด shock ตามอายุ (ใช้โดยชุดเกณฑ์ฉบับโรงพยาบาล) */
expect('จุดตัด shock: อายุ 6 เดือน → 70', E.validate({ age_value: 6, age_unit: 'month' }).data.sbp_shock_cutoff === 70);
expect('จุดตัด shock: อายุ 4 ปี → 70 + (4×2) = 78', E.validate({ age_value: 4, age_unit: 'year' }).data.sbp_shock_cutoff === 78);
expect('จุดตัด shock: อายุ 30 ปี → 90', E.validate({ age_value: 30, age_unit: 'year' }).data.sbp_shock_cutoff === 90);

/* ------------------------- 5) หน่วยอายุและค่าคำนวณ */
expect('อายุ 2 เดือน → age_months = 2', E.validate({ age_value: 2, age_unit: 'month' }).data.age_months === 2);
expect('อายุ 5 ปี → age_months = 60',   E.validate({ age_value: 5, age_unit: 'year' }).data.age_months === 60);
expect('MAP คำนวณจาก (SBP + 2×DBP) ÷ 3 — BP 120/60 → 80',
  E.validate({ sbp: 120, dbp: 60 }).data.map === 80);

/* ------------------------- 6) การนับทรัพยากรตามกติกาคู่มือ */
expect('กิจกรรมในรายการ "ไม่นับ" ไม่เพิ่มจำนวน',
  E.countResources(['hp', 'splint', 'call_doctor', 'lab'], SET) === 1);
expect('ติ๊กซ้ำรายการเดิมไม่นับซ้ำ', E.countResources(['lab', 'lab'], SET) === 1);
expect('x-ray + CT = 2 กิจกรรม', E.countResources(['xray', 'ct'], SET) === 2);

/* ------------------------- 7) deterministic + เกณฑ์เป็นข้อมูลจริง */
var d = E.validate(CASES[9].data).data;
expect('input เดิม → output เดิมทุกครั้ง (deterministic)',
  JSON.stringify(E.assess(d, SET)) === JSON.stringify(E.assess(d, SET)));

var strict = { meta: { id: 'test-strict' }, resources: SET.resources, criteria: [
  { code: 'X1', dp: 'B', level: 2, text: 'ปวด ≥ 5 (ชุดเกณฑ์สมมติ)', test: { field: 'pain_score', gte: 5 } }
] };
var rs = E.assess(E.validate({ cc: 'ปวดท้อง', age_value: 45, age_unit: 'year', pain_score: 6,
                               hr: 80, rr: 16, spo2: 99, sbp: 120, dbp: 78, gcs: 15,
                               flags: [], resources: ['lab', 'us'] }).data, strict);
expect('สลับชุดเกณฑ์แล้วผลเปลี่ยนตาม (pain 6 เคยได้ 3 → ชุดใหม่ได้ 2) โดยไม่แก้โค้ด',
  rs.level === 2 && rs.matched[0].code === 'X1');

/* ------------------------- 8) ไฟล์เกณฑ์ 2 ฉบับต้องตรงกันเป๊ะ (กัน drift) */
['criteria-moph-2561', 'criteria-moph-2561-local'].forEach(function (f) {
  var fromJson = JSON.parse(fs.readFileSync(__dirname + '/' + f + '.json', 'utf8'));
  expect(f + '.js ตรงกับ .json ทุกตัวอักษร (ถ้าไม่ผ่าน: node gen-criteria-js.js)',
    JSON.stringify(fromJson) === JSON.stringify(require('./' + f + '.js')));
});
expect('ชุดเกณฑ์ฉบับโรงพยาบาลอ้างที่มาของทุกข้อที่แก้ไข',
  SETS['moph-ed-triage-2561-local'].criteria
    .filter(function (c) { return c.local_addition; })
    .every(function (c) { return typeof c.source === 'string' && c.source.length > 10; }));

/* ------------------------- 9) ความครบถ้วนของชุดเกณฑ์ */
expect('ชุดเกณฑ์ครบทั้ง 4 จุดตัดสินใจ ก–ง',
  ['A', 'B', 'D'].every(function (dp) { return SET.criteria.some(function (c) { return c.dp === dp; }); }) &&
  (SET.resources.counted || []).length > 0);
expect('ทุกเกณฑ์มีเลขหน้าอ้างอิงกลับไปที่คู่มือ',
  SET.criteria.every(function (c) { return typeof c.page === 'number'; }));
expect('ทุกเกณฑ์มีรหัสไม่ซ้ำกัน',
  new Set(SET.criteria.map(function (c) { return c.code; })).size === SET.criteria.length);

console.log('\nผ่าน ' + pass + ' / ' + (pass + fail) + ' ข้อ  (เคสจำลอง ' + CASES.length + ' เคส + ตรวจตรรกะ ' + (pass + fail - CASES.length) + ' ข้อ)');
if (fail) { console.log('❌ มีข้อไม่ผ่าน — ห้าม deploy จนกว่าจะแก้'); process.exit(1); }
console.log('✅ ผ่านทั้งหมด');
