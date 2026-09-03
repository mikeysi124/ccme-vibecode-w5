/* ============================================================================
 * ผู้ช่วยตัดสินใจคัดกรองช่องทาง ER/OPD — criteria engine v0
 * วิชา 4 Clinical App Mini-Project · Vibe Coding for Clinical Innovation (ศ.น.พ.)
 * นพ.กิตติพศ เกียรติพัฒนาชัย · P49
 *
 * หลักการ: engine ไม่รู้จักเกณฑ์ข้อใดเลย — เกณฑ์ทั้งหมดเป็น "ข้อมูล" ที่โหลดเข้ามา
 * (ดู criteria-moph-2561.json) เปลี่ยนชุดเกณฑ์ = เปลี่ยนพฤติกรรมทั้งระบบ
 * โดยไม่แก้โค้ดแม้บรรทัดเดียว
 *
 * ผลลัพธ์ deterministic: input เดิม → output เดิมเสมอ ไม่มีการสุ่ม ไม่เรียก AI
 * ========================================================================== */
(function (root) {
  'use strict';

  /* ------------------------------------------------- ตัวประเมินเงื่อนไข (tri-state)
   * คืน true / false / null   (null = ข้อมูลไม่พอจะตัดสินข้อนี้)
   * ต้องเป็น tri-state เพราะ "ยังไม่ได้วัด" ไม่เท่ากับ "ไม่เข้าเกณฑ์" —
   * พยาบาลต้องเห็นว่าข้อไหนตัดสินไม่ได้ ไม่ใช่ถูกนับเป็นผ่านเงียบ ๆ            */
  function evalTest(t, d) {
    if (!t || typeof t !== 'object') return null;

    if (t.all) {
      var sawUnknown = false;
      for (var i = 0; i < t.all.length; i++) {
        var r = evalTest(t.all[i], d);
        if (r === false) return false;
        if (r === null) sawUnknown = true;
      }
      return sawUnknown ? null : true;
    }
    if (t.any) {
      var unknown = false;
      for (var j = 0; j < t.any.length; j++) {
        var q = evalTest(t.any[j], d);
        if (q === true) return true;
        if (q === null) unknown = true;
      }
      return unknown ? null : false;
    }
    if (t.flag) return (d.flags || []).indexOf(t.flag) !== -1;

    if (t.field) {
      var v = d[t.field];
      if (v === undefined || v === null || v === '') return null;
      if (t.in) return t.in.indexOf(v) !== -1;
      if (typeof v !== 'number' || !isFinite(v)) return null;
      if (t.gt !== undefined) return v > t.gt;
      if (t.gte !== undefined) return v >= t.gte;
      if (t.lt !== undefined) return v < t.lt;
      if (t.lte !== undefined) return v <= t.lte;
      if (t.eq !== undefined) return v === t.eq;
      /* เทียบกับค่าที่คำนวณจากข้อมูลผู้ป่วยเอง เช่น จุดตัด shock ที่ขึ้นกับอายุ */
      if (t.lt_field !== undefined) {
        var lim = d[t.lt_field];
        return (typeof lim === 'number' && isFinite(lim)) ? v < lim : null;
      }
    }
    return null;
  }

  /* ----------------------------------------------------------- นับทรัพยากร
   * นับเฉพาะกิจกรรมที่อยู่ในรายการ "กิจกรรมที่นับ" ของชุดเกณฑ์ —
   * ติ๊กของในรายการ "ไม่นับ" กี่อย่างก็ไม่เพิ่มจำนวน (คู่มือหน้า 13–14)   */
  function countResources(picked, set) {
    var counted = ((set.resources || {}).counted || []).map(function (r) { return r.id; });
    var seen = {}, n = 0;
    (picked || []).forEach(function (id) {
      if (counted.indexOf(id) !== -1 && !seen[id]) { seen[id] = 1; n++; }
    });
    return n;
  }

  /* --------------------------------------------------------------- assess()
   * เดินตาม 4 จุดตัดสินใจตามลำดับ หยุดที่จุดแรกที่ตัดสินได้
   * ก (A): ต้องการ life-saving intervention? → ระดับ 1
   * ข (B): รอได้ไหม — ภาวะเสี่ยง / ภาวะซึม / ภาวะปวด → ระดับ 2
   * ค (C): ใช้ทรัพยากรกี่อย่าง → 0 = ระดับ 5 · 1 = ระดับ 4 · ≥2 = ไปจุด ง
   * ง (D): สัญญาณชีพช่วงอันตรายตามช่วงอายุ → เข้า = พิจารณาระดับ 2 · ไม่เข้า = 3 */
  function assess(data, set) {
    if (!set || !set.criteria) throw new Error('assess() ต้องได้รับชุดเกณฑ์');
    var crit = set.criteria, matched = [], unmatched = [], unknown = [], advisories = [];

    for (var i = 0; i < crit.length; i++) {
      var c = crit[i];
      var row = { code: c.code, dp: c.dp, group: c.group || '', text: c.text,
                  page: c.page || null, danger_zone: !!c.danger_zone,
                  nurse_judgment: !!c.nurse_judgment, advisory_only: !!c.advisory_only,
                  note: c.note || '', observed: describe(c.test, data) };
      var r = evalTest(c.test, data);
      if (r === true) { (c.advisory_only ? advisories : matched).push(row); }
      else if (r === false) unmatched.push(row);
      else unknown.push(row);
    }

    function firstAt(dp) {
      for (var k = 0; k < matched.length; k++) if (matched[k].dp === dp) return matched[k];
      return null;
    }

    var out = { matched: matched, unmatched: unmatched, unknown: unknown,
                advisories: advisories, set_id: (set.meta || {}).id || 'unknown',
                set_name: (set.meta || {}).name || '' };

    if (firstAt('A')) {
      out.level = 1; out.stopped_at = 'A';
      out.reason = 'จุด ก — ผู้ป่วยต้องการการช่วยชีวิตทันที (life-saving intervention)';
    } else if (firstAt('B')) {
      out.level = 2; out.stopped_at = 'B';
      out.reason = 'จุด ข — รอไม่ได้ (' + (firstAt('B').group || 'ภาวะเสี่ยง') + ')';
    } else {
      var n = countResources(data.resources, set);
      out.resource_count = n;
      if (n === 0) {
        out.level = 5; out.stopped_at = 'C';
        out.reason = 'จุด ค — คาดว่าไม่ต้องใช้ทรัพยากร';
      } else if (n === 1) {
        out.level = 4; out.stopped_at = 'C';
        out.reason = 'จุด ค — คาดว่าใช้ทรัพยากร 1 อย่าง';
      } else {
        out.stopped_at = 'D';
        if (firstAt('D')) {
          out.level = 2; out.consider = true;
          out.reason = 'จุด ง — ใช้ทรัพยากร ≥ 2 อย่าง และสัญญาณชีพอยู่ในช่วงอันตราย → พิจารณายกเป็นระดับ 2';
        } else {
          out.level = 3;
          out.reason = 'จุด ง — ใช้ทรัพยากร ≥ 2 อย่าง และสัญญาณชีพไม่อยู่ในช่วงอันตราย';
        }
      }
    }

    out.channel = out.level <= 2 ? 'ER' : 'OPD';
    /* ข้อที่ตัดสินไม่ได้ ณ จุดที่ยังไม่ถูกข้าม = ต้องเตือนพยาบาล ไม่กลืนเงียบ */
    var order = ['A', 'B', 'C', 'D'], stopIdx = order.indexOf(out.stopped_at);
    out.blocking_unknown = unknown.filter(function (u) { return order.indexOf(u.dp) <= stopIdx; });
    return out;
  }

  /* ค่าที่สังเกตได้จริงของเกณฑ์ข้อนั้น — ไว้แสดงข้าง ๆ ว่าทำไมถึงเข้า/ไม่เข้า */
  var LABEL = { gcs: 'GCS', spo2: 'SpO₂', sbp: 'SBP', dbp: 'DBP', map: 'MAP', hr: 'ชีพจร',
                rr: 'อัตราหายใจ', temp_c: 'อุณหภูมิ', pain_score: 'pain score',
                age_months: 'อายุ (เดือน)' };
  function describe(t, d) {
    if (!t) return '';
    if (t.field) {
      var v = d[t.field], nm = LABEL[t.field] || t.field;
      if (v === undefined || v === null || v === '') return nm + ': ยังไม่ได้ระบุ';
      /* อายุอ่านง่ายกว่าเมื่อแสดงเป็นปีสำหรับผู้ใหญ่ แต่เป็นเดือนสำหรับทารก */
      if (t.field === 'age_months') {
        return 'อายุ = ' + (v >= 24 ? Math.floor(v / 12) + ' ปี' : v + ' เดือน');
      }
      return nm + ' = ' + v;
    }
    if (t.flag) return (d.flags || []).indexOf(t.flag) !== -1 ? 'พยาบาลติ๊กไว้' : 'ไม่ได้ติ๊ก';
    var parts = (t.all || t.any || []).map(function (x) { return describe(x, d); });
    return parts.join(t.all ? ' + ' : ' หรือ ');
  }

  /* ------------------------------------------------------------- validate()
   * ทุกช่องเว้นว่างได้ (= ยังไม่ได้วัด → engine จะขึ้นว่า "ตัดสินไม่ได้")
   * แต่ถ้ากรอกแล้วต้องอยู่ในช่วงที่เป็นไปได้ — กันค่าพิมพ์ผิดอย่าง HR 400
   * ไหลเข้า engine จนได้ผลที่ดูสมเหตุสมผลแต่ผิด                              */
  var FIELDS = {
    age_value:  { label: 'อายุ',          min: 0,  max: 120, unit: '',      integer: true },
    gcs:        { label: 'GCS',           min: 3,  max: 15,  unit: '',      integer: true },
    sbp:        { label: 'ความดันตัวบน',   min: 30, max: 300, unit: 'mmHg', integer: true },
    dbp:        { label: 'ความดันตัวล่าง', min: 10, max: 200, unit: 'mmHg', integer: true },
    hr:         { label: 'ชีพจร',          min: 10, max: 300, unit: '/นาที', integer: true },
    rr:         { label: 'อัตราหายใจ',     min: 4,  max: 90,  unit: '/นาที', integer: true },
    spo2:       { label: 'SpO₂',           min: 50, max: 100, unit: '%',     integer: true },
    temp_c:     { label: 'อุณหภูมิ',        min: 25, max: 43,  unit: '°C' },
    pain_score: { label: 'ระดับความปวด',   min: 0,  max: 10,  unit: '',      integer: true }
  };

  function validate(raw) {
    var data = { cc: (raw.cc || '').trim() || null, sex: raw.sex || null,
                 flags: raw.flags || [], resources: raw.resources || [] };
    var errors = [], bad = {}, k, spec, s, n;

    for (k in FIELDS) {
      spec = FIELDS[k]; s = raw[k];
      if (s === undefined || s === null || String(s).trim() === '') { data[k] = null; continue; }
      n = Number(String(s).trim());
      if (!isFinite(n)) { errors.push(spec.label + ': ต้องเป็นตัวเลข'); bad[k] = 1; data[k] = null; continue; }
      if (spec.integer && n !== Math.round(n)) { errors.push(spec.label + ': ต้องเป็นจำนวนเต็ม'); bad[k] = 1; data[k] = null; continue; }
      if (n < spec.min || n > spec.max) {
        errors.push(spec.label + ': ต้องอยู่ระหว่าง ' + spec.min + '–' + spec.max + (spec.unit ? ' ' + spec.unit : ''));
        bad[k] = 1; data[k] = null; continue;
      }
      data[k] = n;
    }

    /* อายุ: รับเป็นปีหรือเดือน แล้วแปลงเป็นเดือนให้ engine ใช้กับตาราง danger zone */
    if (data.age_value === null) { data.age_months = null; }
    else if (raw.age_unit === 'month') {
      if (data.age_value > 1440) { errors.push('อายุ: จำนวนเดือนมากเกินไป'); bad.age_value = 1; data.age_months = null; }
      else data.age_months = data.age_value;
    } else {
      data.age_months = data.age_value * 12;
    }
    data.age_unit = raw.age_unit === 'month' ? 'month' : 'year';

    /* MAP = (SBP + 2×DBP) ÷ 3 — คู่มือใช้ MAP < 60 เป็นเกณฑ์ shock ที่จุด ก */
    data.map = (data.sbp !== null && data.dbp !== null && data.dbp < data.sbp)
      ? Math.round((data.sbp + 2 * data.dbp) / 3) : null;

    if (data.sbp !== null && data.dbp !== null && data.dbp >= data.sbp) {
      errors.push('ความดันตัวล่างต้องน้อยกว่าตัวบน'); bad.dbp = 1;
    }

    /* จุดตัด SBP ของภาวะ shock ที่ขึ้นกับอายุ — สูตรจาก WI คัดกรองผู้ป่วยนอก
     * รพ.พระมงกุฎเกล้า PMK-WND-037 (2561): อายุ > 10 ปี SBP < 90 ·
     * อายุ 1–10 ปี SBP < 70 + (อายุ × 2) · อายุ < 1 ปี SBP < 70
     * ชุดเกณฑ์ที่ต้องการใช้ค่านี้อ้างถึงด้วย {"field":"sbp","lt_field":"sbp_shock_cutoff"}
     * ชุดเกณฑ์ MOPH 2561 ไม่ได้ใช้ค่านี้ (เล่มระบุ SBP < 90 เท่ากันทุกอายุ) */
    if (data.age_months === null) data.sbp_shock_cutoff = null;
    else if (data.age_months < 12) data.sbp_shock_cutoff = 70;
    else if (data.age_months <= 120) data.sbp_shock_cutoff = 70 + 2 * Math.floor(data.age_months / 12);
    else data.sbp_shock_cutoff = 90;

    if (data.age_value === null) errors.push('อายุ: จำเป็นต้องระบุ — ตารางสัญญาณชีพช่วงอันตรายและจุดตัด shock ขึ้นกับช่วงอายุ');

    return { ok: errors.length === 0, errors: errors, bad: bad, data: data };
  }

  var API = { FIELDS: FIELDS, evalTest: evalTest, assess: assess, describe: describe,
              validate: validate, countResources: countResources };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  root.TriageEngine = API;
})(typeof globalThis !== 'undefined' ? globalThis : this);
