(function (global) {
'use strict';

const PROFILES = Object.freeze({
  DAKER_LR1121: Object.freeze({
    id: 'DAKER_LR1121',
    label: 'DAKERFPV · LR1121',
    chip: 'LR1121',
    capabilities: Object.freeze({
      direction: true,
      instantRssi: true,
      sweep: true,
      packetProbe: true,
      sourceLock: true,
      ranging: false
    })
  }),
  SX1280: Object.freeze({
    id: 'SX1280',
    label: 'SX1280',
    chip: 'SX1280',
    capabilities: Object.freeze({
      direction: true,
      instantRssi: true,
      sweep: false,
      packetProbe: false,
      sourceLock: true,
      ranging: true
    })
  })
});

function cloneCaps(caps) {
  return Object.assign({}, caps || {});
}

function createState() {
  return {
    selection: 'AUTO',
    activeId: null,
    firmware: null,
    protocol: null,
    capabilities: {}
  };
}

function select(state, selection) {
  state.selection = selection === 'DAKER_LR1121' || selection === 'SX1280' ? selection : 'AUTO';
  if (state.selection !== 'AUTO') {
    state.activeId = state.selection;
    state.capabilities = cloneCaps(PROFILES[state.activeId].capabilities);
  }
  return state;
}

function detectFromInfoParts(parts) {
  const chip = String(parts && parts[3] || '').toUpperCase();
  if (chip.includes('LR1121')) return 'DAKER_LR1121';
  if (chip.includes('SX1280')) return 'SX1280';
  return null;
}

function applyInfoLine(state, line) {
  const parts = String(line || '').split(',');
  if (parts[0] !== 'I') return false;

  if (parts.length >= 5) {
    const detected = detectFromInfoParts(parts);
    if (detected) {
      state.firmware = parts[2] || state.firmware;
      if (state.selection === 'AUTO') {
        state.activeId = detected;
        state.capabilities = cloneCaps(PROFILES[detected].capabilities);
      }
    }
  }

  if (parts[1] === 'cap' && parts[2] === 'protocol') {
    state.protocol = parts[3] || null;
  }

  if (parts[1] === 'cap' && parts[2] === 'hardware_profile' && PROFILES[parts[3]]) {
    if (state.selection === 'AUTO') {
      state.activeId = parts[3];
      state.capabilities = cloneCaps(PROFILES[parts[3]].capabilities);
    }
  }

  const capMap = { direction:'direction', instant_rssi:'instantRssi', sweep:'sweep', source_lock:'sourceLock', ranging:'ranging' };
  if (parts[1] === 'cap' && capMap[parts[2]]) {
    state.capabilities[capMap[parts[2]]] = parts[3] === '1' || parts[3] === 'true' || parts[3] === 'YES';
  }

  if (parts[1] === 'cap' && parts[2] === 'packet_probe') {
    state.capabilities.packetProbe = !!parts[3] && parts[3] !== '0' && parts[3] !== 'NOT_YET_IMPLEMENTED';
  }

  return true;
}

function activeProfile(state) {
  return state && state.activeId ? PROFILES[state.activeId] || null : null;
}

global.RFHardware = Object.freeze({
  PROFILES,
  createState,
  select,
  applyInfoLine,
  activeProfile
});
})(window);
