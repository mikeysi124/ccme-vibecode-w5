/* ตรวจชั้นข้อมูล: saveAssessment ต้องไม่ insert ถ้าบัญชีเปลี่ยนหรือความยินยอมล่าสุดใช้ไม่ได้ (Codex รอบ 3 ข้อ 3)
   และต้องไม่ insert ถ้าผลประเมินมีรหัสเกณฑ์ที่ฐานข้อมูลยังไม่มี เช่นข้อ P ก่อนรัน supabase-w8-pediatric.sql (1.3.0)
   รัน: node test-consent.js · ไม่ต่อฐานข้อมูลจริง ใช้ client จำลอง */
var assert = require('assert');
var inserts = [], userNow = null, criteriaRows = [];
var rows = { criteria_sets: { id: 1 }, cases: { id: 10 }, assessments: { id: 20 } };
globalThis.SUPA_CONFIG = { url: 'https://example.invalid', anonKey: 'test' };
globalThis.supabase = { createClient: function () {
  return {
    auth: { getUser: function () { return Promise.resolve({ data: { user: userNow } }); } },
    from: function (t) {
      var q = {
        select: function () { return q; }, eq: function () { return q; },
        insert: function () { inserts.push(t); return q; },
        single: function () { return Promise.resolve({ data: rows[t], error: null }); },
        then: function (ok, bad) { return Promise.resolve({ data: t === 'criteria' ? criteriaRows : [], error: null }).then(ok, bad); }
      };
      return q;
    }
  };
} };
require('./supabase-data.js');

var d = { age_value: 30, age_unit: 'y', flags: [] };
var r = { set_id: 'moph-ed-triage-2561', level: 3, channel: 'OPD', stopped_at: 'D', matched: [], blocking_unknown: [] };
function consentOk(u) { var c = u.user_metadata.consent; return !!(c && c.c1 && c.c2); }
function user(id, c1) { return { id: id, user_metadata: { consent: { c1: c1, c2: true } } }; }
function save(expectId) { inserts = []; return TriageDB.saveAssessment(d, r, null, expectId, consentOk); }

(async function () {
  userNow = user('A', false);   // ถอนข้อ 1 จากอีกแท็บหลังหน้าแอปตรวจผ่านไปแล้ว
  await assert.rejects(save('A'), /ความยินยอม/);
  assert.deepStrictEqual(inserts, []);
  userNow = user('B', true);    // สลับบัญชีจากอีกแท็บ
  await assert.rejects(save('A'), /บัญชีเปลี่ยน/);
  assert.deepStrictEqual(inserts, []);
  userNow = user('A', true);    // ปกติ
  await save('A');
  assert.deepStrictEqual(inserts, ['cases', 'assessments']);
  var rP = Object.assign({}, r, { level: 2, channel: 'ER', matched: [{ code: 'P2', observed: 'อายุ = 2 เดือน' }] });
  inserts = [];                 // ฐานข้อมูลยังไม่มีข้อ P2
  await assert.rejects(TriageDB.saveAssessment(d, rP, null, 'A', consentOk), /supabase-w8-pediatric/);
  assert.deepStrictEqual(inserts, []);
  criteriaRows = [{ id: 'c-p2', code: 'P2' }];   // รัน migration แล้วกดบันทึกใหม่ ต้องโหลดรายการเกณฑ์ใหม่
  inserts = [];
  await TriageDB.saveAssessment(d, rP, null, 'A', consentOk);
  assert.deepStrictEqual(inserts, ['cases', 'assessments', 'assessment_criteria']);
  console.log('ผ่าน 5 / 5 ข้อ · ไม่ยินยอม สลับบัญชี หรือรหัสเกณฑ์ที่ฐานข้อมูลยังไม่มี = ไม่ insert');
})().catch(function (e) { console.error('✗', e.message); process.exit(1); });
