(function (global) {
'use strict';

const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const normalizeHeading = deg => ((Number(deg) % 360) + 360) % 360;
const angleDelta = (a, b) => ((a - b + 540) % 360) - 180;

function quantile(values, q) {
  const a = (values || []).filter(Number.isFinite).slice().sort((x, y) => x - y);
  if (!a.length) return NaN;
  const x = (a.length - 1) * q;
  const i = Math.floor(x);
  const f = x - i;
  return a[i + 1] === undefined ? a[i] : a[i] + f * (a[i + 1] - a[i]);
}

function createState() {
  let offset = Number(localStorage.getItem('rf_direction_antenna_offset_deg'));
  if (!Number.isFinite(offset)) offset = 0;
  return {
    antennaOffsetDeg: clamp(offset, -180, 180),
    maxRotationDps: 90,
    passHistory: []
  };
}

function setAntennaOffset(state, value) {
  let v = Number(value);
  if (!Number.isFinite(v)) v = 0;
  v = clamp(v, -180, 180);
  state.antennaOffsetDeg = v;
  try { localStorage.setItem('rf_direction_antenna_offset_deg', String(v)); } catch (e) {}
  return v;
}

function createMeasurement(state, input) {
  const rawHeading = Number(input.headingDeg);
  const rotation = Number(input.rotationRateDps);
  const corrected = Number.isFinite(rawHeading)
    ? normalizeHeading(rawHeading + Number(state.antennaOffsetDeg || 0))
    : null;
  const compass = String(input.compassAccuracy || 'UNRELIABLE');

  let accepted = Number.isFinite(corrected) && Number.isFinite(input.rssiDbm);
  let rejectReason = null;
  if (!Number.isFinite(corrected)) {
    accepted = false;
    rejectReason = 'NO_HEADING';
  } else if (Number.isFinite(rotation) && rotation > state.maxRotationDps) {
    accepted = false;
    rejectReason = 'ROTATION_TOO_FAST';
  } else if (compass === 'NO_SENSOR') {
    accepted = false;
    rejectReason = 'NO_COMPASS';
  }

  return {
    timestamp: Number(input.timestamp),
    frequencyHz: Number(input.frequencyHz),
    rssiDbm: Number(input.rssiDbm),
    headingRawDeg: Number.isFinite(rawHeading) ? normalizeHeading(rawHeading) : null,
    headingDeg: corrected,
    compassAccuracy: compass,
    rotationRateDps: Number.isFinite(rotation) ? rotation : null,
    sourceId: input.sourceId || null,
    radioProfile: input.radioProfile || null,
    accepted,
    rejectReason
  };
}

function contiguousPeakWidth(valid, peakIndex, threshold, binSizeDeg) {
  if (!valid.length || peakIndex < 0) return NaN;
  const byIndex = new Map(valid.map(x => [x.i, x.v]));
  let count = 1;
  for (let step = 1; step < 72; step++) {
    const i = (peakIndex + step) % 72;
    if (!byIndex.has(i) || byIndex.get(i) < threshold) break;
    count++;
  }
  for (let step = 1; step < 72; step++) {
    const i = (peakIndex - step + 72) % 72;
    if (!byIndex.has(i) || byIndex.get(i) < threshold) break;
    count++;
  }
  return Math.min(360, count * binSizeDeg);
}

function circularSpread(headings) {
  const a = (headings || []).filter(Number.isFinite);
  if (a.length < 2) return null;
  let sx = 0, sy = 0;
  for (const h of a) {
    const r = h * Math.PI / 180;
    sx += Math.cos(r);
    sy += Math.sin(r);
  }
  let mean = Math.atan2(sy, sx) * 180 / Math.PI;
  if (mean < 0) mean += 360;
  return Math.max(...a.map(h => Math.abs(angleDelta(h, mean))));
}

function summarizeBins(state, passBins, compassAccuracy) {
  const valid = (passBins || []).map((x, i) => {
    const values = (x || []).filter(Number.isFinite);
    return values.length ? { i, v: quantile(values, 0.7), n: values.length } : null;
  }).filter(Boolean);

  const coveragePct = valid.length / 72 * 100;
  if (!valid.length) {
    return {
      level: 'LOW',
      coveragePct,
      peakContrastDb: null,
      peakWidthDeg: null,
      repeatabilityDeg: circularSpread(state.passHistory.slice(-3)),
      reason: 'нет данных'
    };
  }

  const sorted = valid.slice().sort((a, b) => b.v - a.v);
  const peak = sorted[0];
  const median = quantile(valid.map(x => x.v), 0.5);
  const contrast = peak.v - median;
  const width = contiguousPeakWidth(valid, peak.i, peak.v - 3, 5);
  const repeat = circularSpread(state.passHistory.slice(-3));

  const compassBad = compassAccuracy === 'LOW' || compassAccuracy === 'UNRELIABLE' || compassAccuracy === 'NO_SENSOR';
  let level = 'LOW';
  if (!compassBad && coveragePct >= 55 && contrast >= 6 && width <= 45 && (repeat === null || repeat <= 15)) level = 'HIGH';
  else if (compassAccuracy !== 'NO_SENSOR' && coveragePct >= 35 && contrast >= 3 && width <= 90 && (repeat === null || repeat <= 30)) level = 'MEDIUM';

  const reason = [
    Math.round(coveragePct) + '% круга',
    'контраст ' + contrast.toFixed(1) + ' dB',
    'пик ' + Math.round(width) + '°',
    repeat === null ? null : 'повторы ±' + Math.round(repeat) + '°',
    compassBad ? 'компас ' + compassAccuracy : null
  ].filter(Boolean).join(' · ');

  return {
    level,
    coveragePct,
    peakContrastDb: contrast,
    peakWidthDeg: width,
    repeatabilityDeg: repeat,
    peakHeadingDeg: peak.i * 5 + 2.5,
    peakRssiDbm: peak.v,
    reason
  };
}

function archivePass(state, heading, coveragePct) {
  if (!Number.isFinite(heading) || Number(coveragePct) < 35) return false;
  state.passHistory.push(normalizeHeading(heading));
  if (state.passHistory.length > 8) state.passHistory.shift();
  return true;
}

global.RFDirectionCore = Object.freeze({
  createState,
  setAntennaOffset,
  createMeasurement,
  summarizeBins,
  archivePass,
  normalizeHeading,
  angleDelta
});
})(window);
