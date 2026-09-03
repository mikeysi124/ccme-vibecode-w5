/* ============================================================================
 * Known-Answer Test — ชุดสถานการณ์จำลองสำหรับตรวจ criteria engine
 * ไฟล์นี้ถูกใช้ทั้งใน node (test-engine.js) และในแอป (แท็บ "ทดสอบ")
 * เพื่อไม่ให้ชุดทดสอบสองที่หลุดจากกัน
 *
 * ที่มาของเฉลย:
 *   [คู่มือ] = ตัวอย่างผู้ป่วยที่คู่มือ MOPH ED Triage 2561 เฉลยไว้เอง (หน้า 8–9, 11–12, 15)
 *   [ขอบ]   = เคสทดสอบขอบเกณฑ์ที่ผู้พัฒนา (แพทย์ EM) สร้างจากตัวเลขจุดตัดในคู่มือ
 * ทุกเคสเป็นสถานการณ์จำลอง ไม่ใช่ผู้ป่วยจริง
 * ========================================================================== */
(function (root) {
  'use strict';
  var CASES = [

    /* ---------------- จุด ก — ระดับ 1 ---------------- */
    { id: 1, src: 'คู่มือ', name: 'SpO₂ 88 (คู่มือระบุ O₂ sat < 90 เป็น life-saving intervention)',
      data: { cc: 'หายใจเหนื่อย', age_value: 60, age_unit: 'year', spo2: 88, hr: 110, rr: 26,
              sbp: 120, dbp: 70, gcs: 15, pain_score: 3, flags: [], resources: ['lab', 'ekg'] },
      expect: { level: 1, channel: 'ER', codes: ['A5'] } },

    { id: 2, src: 'คู่มือ', name: 'เจ็บหน้าอก ซีด เหงื่อแตก ความดัน 70 คลำมือ → SBP < 90',
      data: { cc: 'เจ็บหน้าอก', age_value: 65, age_unit: 'year', sbp: 70, dbp: 40, hr: 120,
              rr: 24, spo2: 95, gcs: 15, pain_score: 8,
              flags: ['pain_objective_signs'], resources: ['lab', 'ekg'] },
      expect: { level: 1, channel: 'ER', codes: ['A7'] } },

    { id: 3, src: 'ขอบ', name: 'GCS 8 พอดี (เกณฑ์คือ ≤ 8) → ระดับ 1',
      data: { cc: 'ซึมลง', age_value: 70, age_unit: 'year', gcs: 8, sbp: 130, dbp: 80,
              hr: 90, rr: 18, spo2: 96, pain_score: 0, flags: [], resources: ['lab', 'ct'] },
      expect: { level: 1, channel: 'ER', codes: ['A4'] } },

    { id: 4, src: 'ขอบ', name: 'GCS 9 (สูงกว่าเกณฑ์ระดับ 1 หนึ่งแต้ม) → ตกมาที่จุด ข ระดับ 2',
      data: { cc: 'ซึมลง', age_value: 70, age_unit: 'year', gcs: 9, sbp: 130, dbp: 80,
              hr: 90, rr: 18, spo2: 96, pain_score: 0, flags: [], resources: ['lab', 'ct'] },
      expect: { level: 2, channel: 'ER', codes: ['B8'] } },

    { id: 5, src: 'ขอบ', name: 'MAP < 60 จาก BP 92/40 (SBP ไม่ต่ำกว่า 90 แต่ MAP = 57)',
      data: { cc: 'อ่อนเพลีย', age_value: 55, age_unit: 'year', sbp: 92, dbp: 40, hr: 96,
              rr: 20, spo2: 97, gcs: 15, pain_score: 2, flags: [], resources: ['lab'] },
      expect: { level: 1, channel: 'ER', codes: ['A8'] } },

    /* ---------------- จุด ข — ระดับ 2 ---------------- */
    { id: 6, src: 'คู่มือ', name: 'Active chest pain สงสัย ACS อาการคงที่ ไม่ต้องช่วยชีวิตทันที',
      data: { cc: 'เจ็บหน้าอก', age_value: 62, age_unit: 'year', sbp: 150, dbp: 90, hr: 96,
              rr: 18, spo2: 97, gcs: 15, pain_score: 6,
              flags: ['acs_stable'], resources: ['lab', 'ekg'] },
      expect: { level: 2, channel: 'ER', codes: ['B1'] } },

    { id: 7, src: 'คู่มือ', name: 'บุคลากรทางการแพทย์โดนเข็มตำ (สัญญาณชีพปกติทุกค่า)',
      data: { cc: 'เข็มตำ', age_value: 28, age_unit: 'year', sbp: 118, dbp: 74, hr: 78,
              rr: 16, spo2: 99, gcs: 15, pain_score: 1,
              flags: ['needle_stick'], resources: ['lab'] },
      expect: { level: 2, channel: 'ER', codes: ['B2'] } },

    { id: 8, src: 'คู่มือ', name: 'ผู้ป่วยรับยาเคมีบำบัด มาด้วยไข้',
      data: { cc: 'ไข้', age_value: 54, age_unit: 'year', sbp: 112, dbp: 70, hr: 98,
              rr: 18, spo2: 98, temp_c: 38.4, gcs: 15, pain_score: 2,
              flags: ['immunocompromised_fever'], resources: ['lab'] },
      expect: { level: 2, channel: 'ER', codes: ['B5'] } },

    { id: 9, src: 'คู่มือ', name: 'ผู้สูงอายุมาด้วยอาการสับสนที่เพิ่งเป็น (new onset confusion)',
      data: { cc: 'สับสน', age_value: 80, age_unit: 'year', sbp: 134, dbp: 78, hr: 88,
              rr: 18, spo2: 97, gcs: 14, pain_score: 0,
              flags: ['new_onset_altered'], resources: ['lab', 'ct'] },
      expect: { level: 2, channel: 'ER', codes: ['B9'] } },

    { id: 10, src: 'คู่มือ', name: 'ปวดท้องจนเหงื่อแตก หัวใจเต้นเร็ว ความดันสูง · pain 8 + มีลักษณะประกอบ',
      data: { cc: 'ปวดท้อง', age_value: 45, age_unit: 'year', sbp: 158, dbp: 92, hr: 98,
              rr: 18, spo2: 98, gcs: 15, pain_score: 8,
              flags: ['pain_objective_signs'], resources: ['lab', 'us'] },
      expect: { level: 2, channel: 'ER', codes: ['B10'] } },

    { id: 11, src: 'ขอบ', name: 'pain 8 แต่ไม่มีลักษณะประกอบ (คู่มือกำหนดว่าต้องร่วมด้วย) → ไม่เข้า B10',
      note: 'ข้อนี้คือจุดที่ตีความคู่มือผิดได้ง่ายที่สุด — pain ≥ 7 เพียงอย่างเดียวไม่พอ',
      data: { cc: 'ปวดหลัง', age_value: 45, age_unit: 'year', sbp: 128, dbp: 80, hr: 88,
              rr: 18, spo2: 98, gcs: 15, pain_score: 8,
              flags: [], resources: ['lab', 'us'] },
      expect: { level: 3, channel: 'OPD', codes: [] } },

    /* ---------------- จุด ค — ตัวอย่างที่คู่มือเฉลยเอง (หน้า 15) ---------------- */
    { id: 12, src: 'คู่มือ', name: 'เด็ก 10 ปี คันไม่มีผื่น · ตรวจและสั่งยา · ไม่ใช้ทรัพยากร',
      data: { cc: 'คัน', age_value: 10, age_unit: 'year', sbp: 105, dbp: 65, hr: 90,
              rr: 18, spo2: 99, gcs: 15, pain_score: 0, flags: [], resources: ['hp'] },
      expect: { level: 5, channel: 'OPD', codes: [] } },

    { id: 13, src: 'คู่มือ', name: 'ชาย 52 ปี มาขอรับยาความดัน BP 150/92 · ไม่ใช้ทรัพยากร',
      data: { cc: 'มารับยา', age_value: 52, age_unit: 'year', sbp: 150, dbp: 92, hr: 78,
              rr: 16, spo2: 98, gcs: 15, pain_score: 0, flags: [], resources: ['hp', 'oral_scheduled'] },
      expect: { level: 5, channel: 'OPD', codes: [] } },

    { id: 14, src: 'คู่มือ', name: 'ผู้ป่วย 19 ปี เจ็บคอมีไข้ · throat culture + สั่งยา = 1 ทรัพยากร',
      data: { cc: 'เจ็บคอ', age_value: 19, age_unit: 'year', sbp: 116, dbp: 72, hr: 88,
              rr: 18, spo2: 99, temp_c: 38.1, gcs: 15, pain_score: 3,
              flags: [], resources: ['lab'] },
      expect: { level: 4, channel: 'OPD', codes: [] } },

    { id: 15, src: 'คู่มือ', name: 'หญิง 29 ปี ปัสสาวะขุ่น · UA + UC + UPT ถือเป็น Lab 1 กิจกรรม',
      note: 'ทดสอบกติกาจับกลุ่ม: ส่งตรวจหลายอย่างในกลุ่ม Lab เดียวกันยังนับเป็น 1',
      data: { cc: 'ปัสสาวะขุ่น', age_value: 29, age_unit: 'year', sbp: 112, dbp: 70, hr: 82,
              rr: 16, spo2: 99, gcs: 15, pain_score: 2, flags: [], resources: ['lab'] },
      expect: { level: 4, channel: 'OPD', codes: [] } },

    { id: 16, src: 'คู่มือ', name: 'ชาย 22 ปี ปวดท้องน้อยขวา อาเจียน เบื่ออาหาร · Lab + IV fluid + CT = ≥2',
      note: 'สัญญาณชีพในเคสนี้คู่มือไม่ได้ระบุ — กำหนดให้อยู่นอกช่วงอันตรายเพื่อทดสอบเส้นทาง ≥2 → จุด ง',
      data: { cc: 'ปวดท้องน้อยขวา', age_value: 22, age_unit: 'year', sbp: 124, dbp: 76, hr: 92,
              rr: 18, spo2: 99, temp_c: 37.6, gcs: 15, pain_score: 5,
              flags: [], resources: ['lab', 'iv_fluid', 'ct'] },
      expect: { level: 3, channel: 'OPD', codes: [] } },

    { id: 17, src: 'คู่มือ', name: 'หญิง 45 ปี ปวดบวมขาซ้าย 2 วัน หลังนั่งเครื่องบิน 12 ชม. · Lab + vascular studies',
      data: { cc: 'ปวดบวมขาซ้าย', age_value: 45, age_unit: 'year', sbp: 130, dbp: 82, hr: 94,
              rr: 18, spo2: 98, gcs: 15, pain_score: 5,
              flags: [], resources: ['lab', 'us'] },
      expect: { level: 3, channel: 'OPD', codes: [] } },

    /* ---------------- กติกาการนับทรัพยากร ---------------- */
    { id: 18, src: 'ขอบ', name: 'ติ๊กเฉพาะกิจกรรมที่คู่มือระบุว่า "ไม่นับ" ทั้งหมด → นับได้ 0 → ระดับ 5',
      note: 'H&P + heparin lock + ยาฉีดตามนัด + TT + splint + โทรตามแพทย์เวร',
      data: { cc: 'ทำแผล', age_value: 34, age_unit: 'year', sbp: 120, dbp: 76, hr: 80,
              rr: 16, spo2: 99, gcs: 15, pain_score: 2, flags: [],
              resources: ['hp', 'heparin_lock', 'oral_scheduled', 'tt_tat', 'splint', 'call_doctor'] },
      expect: { level: 5, channel: 'OPD', codes: [] } },

    { id: 19, src: 'คู่มือ', name: 'CXR + CT scan = 2 กิจกรรม (คู่มือระบุไว้ตรง ๆ) → ไปจุด ง',
      data: { cc: 'บาดเจ็บทรวงอก', age_value: 40, age_unit: 'year', sbp: 126, dbp: 78, hr: 96,
              rr: 18, spo2: 98, gcs: 15, pain_score: 5,
              flags: [], resources: ['xray', 'ct'] },
      expect: { level: 3, channel: 'OPD', codes: [] } },

    /* ---------------- จุด ง — danger zone แยกตามช่วงอายุ ---------------- */
    { id: 20, src: 'ขอบ', name: 'ทารก 2 เดือน ชีพจร 190 · ความดัน 95/55 (ไม่เข้าเกณฑ์ shock) → เข้า D1',
      data: { cc: 'ไข้ ซึม', age_value: 2, age_unit: 'month', hr: 190, rr: 45, spo2: 97,
              sbp: 95, dbp: 55, gcs: 15, temp_c: 38.5, pain_score: 0,
              flags: [], resources: ['lab', 'xray'] },
      expect: { level: 2, channel: 'ER', codes: ['D1'] } },

    { id: '20b', src: 'ขอบ', name: '⚠️ ทารก 2 เดือน ความดัน 85/50 — คู่มือ MOPH ใช้ SBP < 90 เท่ากันทุกอายุ จึงออกมาเป็นระดับ 1',
      note: 'ความดันนี้ปกติสำหรับทารก แต่ต่ำกว่าจุดตัดผู้ใหญ่ในเล่ม — เครื่องมือแสดงตามที่คู่มือเขียน ไม่แก้ให้เอง เทียบกับเคส 20c',
      data: { cc: 'ไข้ ซึม', age_value: 2, age_unit: 'month', hr: 190, rr: 45, spo2: 97,
              sbp: 85, dbp: 50, gcs: 15, temp_c: 38.5, pain_score: 0,
              flags: [], resources: ['lab', 'xray'] },
      expect: { level: 1, channel: 'ER', codes: ['A7'] } },

    { id: '20c', src: 'ขอบ', set: 'moph-ed-triage-2561-local',
      name: '✅ เคสเดียวกับ 20b แต่ใช้ชุดเกณฑ์ฉบับโรงพยาบาล (จุดตัด shock ตามอายุ = 70) → ไม่ใช่ shock → ระดับ 2 จาก D1',
      note: 'สลับไฟล์เกณฑ์อย่างเดียว คำตอบเปลี่ยน โดยไม่แก้โค้ดแม้บรรทัดเดียว',
      data: { cc: 'ไข้ ซึม', age_value: 2, age_unit: 'month', hr: 190, rr: 45, spo2: 97,
              sbp: 85, dbp: 50, gcs: 15, temp_c: 38.5, pain_score: 0,
              flags: [], resources: ['lab', 'xray'] },
      expect: { level: 2, channel: 'ER', codes: ['D1'] } },

    { id: '20d', src: 'ขอบ', set: 'moph-ed-triage-2561-local',
      name: 'ฉบับโรงพยาบาล: เด็ก 2 ปี ไข้ 38.6 °C → เข้า D11 (คู่มือ MOPH ไม่ได้ให้จุดตัดอุณหภูมิไว้)',
      data: { cc: 'ไข้', age_value: 2, age_unit: 'year', hr: 130, rr: 30, spo2: 98,
              sbp: 95, dbp: 60, gcs: 15, temp_c: 38.6, pain_score: 0,
              flags: [], resources: ['lab', 'xray'] },
      expect: { level: 2, channel: 'ER', codes: ['D11'] } },

    { id: 21, src: 'ขอบ', name: 'เด็ก 2 ปี อัตราหายใจ 45 (เกณฑ์ 3 เดือน–3 ปี คือ > 40)',
      data: { cc: 'ไอ หอบ', age_value: 2, age_unit: 'year', hr: 130, rr: 45, spo2: 96,
              sbp: 95, dbp: 60, gcs: 15, temp_c: 38.2, pain_score: 0,
              flags: [], resources: ['lab', 'xray'] },
      expect: { level: 2, channel: 'ER', codes: ['D4'] } },

    { id: 22, src: 'ขอบ', name: '⚠️ เด็ก 5 ปี ชีพจร 105 — เกินเกณฑ์ผู้ใหญ่ แต่ยังไม่ถึงเกณฑ์ 3–8 ปี (> 140) → ระดับ 3',
      note: 'เคสสำคัญที่สุดของตาราง danger zone — ถ้าใช้จุดตัดผู้ใหญ่กับเด็ก จะ over-triage เด็กทุกราย',
      data: { cc: 'ปวดท้อง', age_value: 5, age_unit: 'year', hr: 105, rr: 24, spo2: 98,
              sbp: 100, dbp: 62, gcs: 15, temp_c: 37.4, pain_score: 4,
              flags: [], resources: ['lab', 'us'] },
      expect: { level: 3, channel: 'OPD', codes: [] } },

    { id: 23, src: 'ขอบ', name: 'ผู้ใหญ่ 45 ปี ชีพจร 105 (เกณฑ์ > 8 ปี คือ > 100) → พิจารณาระดับ 2',
      data: { cc: 'ปวดท้อง', age_value: 45, age_unit: 'year', hr: 105, rr: 18, spo2: 98,
              sbp: 128, dbp: 80, gcs: 15, temp_c: 37.4, pain_score: 4,
              flags: [], resources: ['lab', 'us'] },
      expect: { level: 2, channel: 'ER', codes: ['D7'] } },

    { id: 24, src: 'ขอบ', name: 'ผู้ใหญ่ ชีพจร 100 พอดี (เกณฑ์คือ > 100) → ยังไม่เข้า → ระดับ 3',
      data: { cc: 'ปวดท้อง', age_value: 45, age_unit: 'year', hr: 100, rr: 20, spo2: 98,
              sbp: 128, dbp: 80, gcs: 15, temp_c: 37.4, pain_score: 4,
              flags: [], resources: ['lab', 'us'] },
      expect: { level: 3, channel: 'OPD', codes: [] } },

    { id: 25, src: 'ขอบ', name: 'SpO₂ 91 (เกณฑ์ danger zone คือ < 92 — ต่างจากระดับ 1 ที่ใช้ < 90)',
      data: { cc: 'เหนื่อย', age_value: 58, age_unit: 'year', hr: 92, rr: 20, spo2: 91,
              sbp: 122, dbp: 76, gcs: 15, temp_c: 37, pain_score: 2,
              flags: [], resources: ['lab', 'xray'] },
      expect: { level: 2, channel: 'ER', codes: ['D9'] } },

    { id: 26, src: 'ขอบ', name: 'SpO₂ 92 พอดี → ไม่เข้า danger zone → ระดับ 3',
      data: { cc: 'เหนื่อย', age_value: 58, age_unit: 'year', hr: 92, rr: 20, spo2: 92,
              sbp: 122, dbp: 76, gcs: 15, temp_c: 37, pain_score: 2,
              flags: [], resources: ['lab', 'xray'] },
      expect: { level: 3, channel: 'OPD', codes: [] } }
  ];

  if (typeof module !== 'undefined' && module.exports) module.exports = CASES;
  root.KAT_CASES = CASES;
})(typeof globalThis !== 'undefined' ? globalThis : this);
