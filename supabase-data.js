/* ชั้นข้อมูล Supabase ของผู้ช่วยคัดกรอง ER/OPD — วิชา 5 Part 2 (สัปดาห์ที่ 6)
   ทำ CRUD ครบสี่คำสั่งบนตารางจริงตาม ERD 9 ตาราง:
     POST   บันทึกเคส  → cases → assessments → assessment_criteria → overrides
     GET    อ่านเคส    → assessments พร้อม case และ override ที่ผูกอยู่
     PUT    แก้ override ของเคสที่บันทึกไว้
     DELETE ลบเคส (assessments/criteria/overrides ตามด้วย on delete cascade)

   ไม่มี key ฝังในไฟล์นี้ — อ่านจาก window.SUPA_CONFIG (supabase-config.js ที่ gitignore ไว้)
   ถ้าไม่มี config แอปจะกลับไปใช้ localStorage เหมือนเดิม */
(function (root) {
  'use strict';

  var cfg = root.SUPA_CONFIG || null;
  var sb = null;
  var setCache = {};                 // engineSetId → { setId, byCode: {code → criterionId} }
  var ENGINE_VERSION = 'p49-triage-1.0';
  var VERSION_OF = {                 // meta.id ของชุดเกณฑ์ฝั่งแอป → คอลัมน์ version ในฐานข้อมูล
    'moph-ed-triage-2561': '2561',
    'moph-ed-triage-2561-local': '2561-local'
  };

  function ready() {
    if (sb) return sb;
    if (!cfg || !cfg.url || !cfg.anonKey || !root.supabase) return null;
    sb = root.supabase.createClient(cfg.url, cfg.anonKey);
    return sb;
  }

  function fail(res) { if (res.error) throw new Error(res.error.message); return res.data; }

  /* ------------------------------------------------------------- ตัวตน */
  function getUser() {
    var c = ready();
    if (!c) return Promise.resolve(null);
    return c.auth.getUser().then(function (r) { return r.data ? r.data.user : null; });
  }

  function need() {
    var c = ready();
    if (!c) throw new Error('ยังไม่ได้ตั้งค่า supabase-config.js');
    return c;
  }

  function signIn(email, password) {
    return need().auth.signInWithPassword({ email: email, password: password })
      .then(fail).then(function () { return ensureProfile(); });
  }

  function signUp(email, password, fullName, unit) {
    return need().auth.signUp({ email: email, password: password }).then(fail)
      .then(function (data) {
        /* ถ้าโปรเจกต์เปิดยืนยันอีเมล จะยังไม่มี session — ต้องยืนยันก่อนแล้วค่อยล็อกอิน */
        if (!data.session) return { pending_email_confirm: true };
        return ensureProfile(fullName, unit);
      });
  }

  function signOut() { setCache = {}; return need().auth.signOut(); }

  /* แถวใน profiles ต้องมีก่อน เพราะ cases.created_by อ้าง profiles ไม่ใช่ auth.users */
  function ensureProfile(fullName, unit) {
    return getUser().then(function (u) {
      if (!u) throw new Error('ยังไม่ได้เข้าสู่ระบบ');
      return need().from('profiles')
        .upsert({ id: u.id, full_name: fullName || u.email, unit: unit || null }, { onConflict: 'id' })
        .select().single().then(fail);
    });
  }

  /* ------------------------------------- แปลงรหัสเกณฑ์ฝั่งแอป → id ฝั่ง DB */
  function setInfo(engineSetId) {
    if (setCache[engineSetId]) return Promise.resolve(setCache[engineSetId]);
    var version = VERSION_OF[engineSetId];
    if (!version) return Promise.reject(new Error('ไม่รู้จักชุดเกณฑ์ ' + engineSetId));
    var c = need();
    return c.from('criteria_sets').select('id').eq('version', version).single().then(fail)
      .then(function (row) {
        return c.from('criteria').select('id, code').eq('criteria_set_id', row.id).then(fail)
          .then(function (rows) {
            var byCode = {};
            rows.forEach(function (r) { byCode[r.code] = r.id; });
            setCache[engineSetId] = { setId: row.id, byCode: byCode };
            return setCache[engineSetId];
          });
      });
  }

  function num(v) { return v === '' || v === null || v === undefined ? null : Number(v); }

  /* --------------------------------------------------------------- POST */
  /* d = ข้อมูลที่ผ่าน validate แล้ว · r = ผลจาก engine · ovr = {level, reason, note} หรือ null */
  function saveAssessment(d, r, ovr) {
    var c = need(), user, info, caseRow, asmRow;
    return getUser().then(function (u) {
      if (!u) throw new Error('ยังไม่ได้เข้าสู่ระบบ');
      user = u;
      return setInfo(r.set_id);
    }).then(function (i) {
      info = i;
      var now = new Date();
      return c.from('cases').insert({
        case_code: 'C' + now.toISOString().replace(/[-:TZ.]/g, '').slice(0, 14) +
                   '-' + Math.random().toString(36).slice(2, 6),
        created_by: user.id,
        age_value: num(d.age_value),
        age_unit: d.age_unit,
        sex: d.sex || null,
        chief_complaint: d.cc || null,
        gcs: num(d.gcs), sbp: num(d.sbp), dbp: num(d.dbp), hr: num(d.hr),
        rr: num(d.rr), spo2: num(d.spo2), temp_c: num(d.temp_c),
        pain_score: num(d.pain_score),
        flags: d.flags || []
      }).select().single().then(fail);
    }).then(function (row) {
      caseRow = row;
      return c.from('assessments').insert({
        case_id: caseRow.id,
        criteria_set_id: info.setId,
        assessed_by: user.id,
        suggested_level: r.level,
        suggested_channel: r.channel,
        stopped_at: r.stopped_at,
        is_consider: !!r.consider,
        resource_count: r.resource_count === undefined ? null : r.resource_count,
        engine_version: ENGINE_VERSION
      }).select().single().then(fail);
    }).then(function (row) {
      asmRow = row;
      /* เก็บเฉพาะข้อที่เข้าเกณฑ์ (true) และข้อที่ตัดสินไม่ได้ ณ จุดที่ยังไม่ถูกข้าม (null)
         ข้อที่ไม่เข้าเกณฑ์ไม่เก็บ เพราะอนุมานกลับได้จากชุดเกณฑ์เวอร์ชันเดียวกัน */
      var rows = [];
      (r.matched || []).forEach(function (x) {
        if (info.byCode[x.code]) rows.push({
          assessment_id: asmRow.id, criterion_id: info.byCode[x.code],
          is_met: true, observed_value: x.observed || null });
      });
      (r.blocking_unknown || []).forEach(function (x) {
        if (info.byCode[x.code]) rows.push({
          assessment_id: asmRow.id, criterion_id: info.byCode[x.code],
          is_met: null, observed_value: x.observed || null });
      });
      return rows.length ? c.from('assessment_criteria').insert(rows).then(fail) : null;
    }).then(function () {
      if (!ovr) return null;
      return c.from('overrides').insert({
        assessment_id: asmRow.id,
        overridden_by: user.id,
        final_level: ovr.level,
        final_channel: ovr.level <= 2 ? 'ER' : 'OPD',
        reason_code: ovr.reason || 'ไม่ระบุ',
        reason_note: ovr.note || null
      }).select().single().then(fail);
    }).then(function () { return asmRow.id; });
  }

  /* ---------------------------------------------------------------- GET */
  function listAssessments() {
    var c = ready();
    if (!c) return Promise.resolve([]);
    return c.from('assessments')
      .select('id, suggested_level, suggested_channel, stopped_at, assessed_at,' +
              ' cases (id, case_code, chief_complaint, age_value, age_unit),' +
              ' overrides (id, final_level, final_channel, reason_code, reason_note),' +
              ' assessment_criteria (is_met, criteria (code))')
      .order('assessed_at', { ascending: false })
      .then(fail)
      .then(function (rows) { return (rows || []).map(toView); });
  }

  /* แปลงให้หน้าตาเหมือนแถวเดิมใน localStorage — หน้าจอเดิมจะได้ไม่ต้องแก้ตรรกะ */
  function toView(a) {
    var kase = a.cases || {};
    var ovr = Array.isArray(a.overrides) ? a.overrides[0] : a.overrides;
    var codes = (a.assessment_criteria || [])
      .filter(function (x) { return x.is_met === true && x.criteria; })
      .map(function (x) { return x.criteria.code; });
    return {
      id: a.id, case_id: kase.id, case_code: kase.case_code,
      at: a.assessed_at, cc: kase.chief_complaint || '-',
      age: kase.age_value, age_unit: kase.age_unit === 'month' ? 'เดือน' : 'ปี',
      sug_level: a.suggested_level, sug_channel: a.suggested_channel,
      level: ovr ? ovr.final_level : a.suggested_level,
      channel: ovr ? ovr.final_channel : a.suggested_channel,
      overridden: !!ovr && ovr.final_level !== a.suggested_level,
      reason: ovr ? ovr.reason_code : '', note: ovr ? ovr.reason_note || '' : '',
      override_id: ovr ? ovr.id : null,
      codes: codes.join(' ')
    };
  }

  /* ---------------------------------------------------------------- PUT */
  function updateOverride(overrideId, level, reason, note) {
    return need().from('overrides').update({
      final_level: level,
      final_channel: level <= 2 ? 'ER' : 'OPD',
      reason_code: reason || 'ไม่ระบุ',
      reason_note: note || null
    }).eq('id', overrideId).select().single().then(fail);
  }

  /* ------------------------------------------------------------- DELETE */
  function deleteCase(caseId) {
    return need().from('cases').delete().eq('id', caseId).select().then(fail);
  }

  root.TriageDB = {
    get enabled() { return !!ready(); },
    getUser: getUser, signIn: signIn, signUp: signUp, signOut: signOut,
    ensureProfile: ensureProfile,
    saveAssessment: saveAssessment, listAssessments: listAssessments,
    updateOverride: updateOverride, deleteCase: deleteCase
  };
})(typeof globalThis !== 'undefined' ? globalThis : this);
