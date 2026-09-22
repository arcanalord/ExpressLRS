import { FrameStreamDecoder, FrameType, encodeFrame, decodeJsonPayload } from '../src/mm-uart-codec.js';

export class MockRadioFirmware {
  constructor({
    boardId = 'mock-board',
    radioFamily = 'SX1280',
    firmwareVersion = '0.1.0-mock',
    profileIds = ['MM-PHY-SX1280-LAB-v0'],
    responseDelayMs = 0,
    dropCommands = [],
    bootId = 'boot-1'
  } = {}) {
    this.boardId = boardId;
    this.radioFamily = radioFamily;
    this.firmwareVersion = firmwareVersion;
    this.profileIds = profileIds;
    this.responseDelayMs = responseDelayMs;
    this.dropCommands = new Set(dropCommands);
    this.bootId = bootId;
    this.ready = true;
    this.profileId = profileIds[0] || null;
    this.stats = { tx: 0, rx: 0, retries: 0, errors: 0, rssi: -60, snr: 8 };
    this.emitBytes = () => {};
    this.decoder = new FrameStreamDecoder({ onFrame: frame => this.#handle(frame) });
  }
  attachEmitter(fn) { this.emitBytes = fn; }
  receive(bytes) { this.decoder.push(bytes); }
  async #respond(sequence, data = null, ok = true, error = null) {
    if (this.responseDelayMs) await new Promise(r => setTimeout(r, this.responseDelayMs));
    this.emitBytes(encodeFrame({ type: FrameType.RESPONSE, sequence, payload: { ok, data, error } }));
  }
  async #handle(frame) {
    const payload = decodeJsonPayload(frame);
    if (this.dropCommands.has(frame.type)) return;
    switch (frame.type) {
      case FrameType.HELLO:
        return this.#respond(frame.sequence, { protocol: 1, bootId: this.bootId, host: payload?.host || null });
      case FrameType.GET_INFO:
        return this.#respond(frame.sequence, { protocolVersion: 1, firmwareFamily: 'mesh-radio-mock', firmwareVersion: this.firmwareVersion, boardId: this.boardId, radioFamily: this.radioFamily, buildHash: 'mock' });
      case FrameType.GET_CAPS:
        return this.#respond(frame.sequence, {
          radioFamily: this.radioFamily,
          frequencyRanges: [[2400, 2500]],
          profileIds: this.profileIds,
          maxPayload: 512,
          rssiAvailable: true,
          snrAvailable: true,
          rangingAvailable: this.radioFamily === 'SX1280',
          timeSyncAvailable: false,
          txPowerRange: [-18, 20],
          duplexMode: 'half'
        });
      case FrameType.GET_STATE:
        return this.#respond(frame.sequence, { ready: this.ready, state: this.ready ? 'ready' : 'connected', profileId: this.profileId });
      case FrameType.GET_STATS:
        return this.#respond(frame.sequence, this.stats);
      case FrameType.SET_PROFILE:
        if (!this.profileIds.includes(payload?.profileId)) return this.#respond(frame.sequence, null, false, 'UNSUPPORTED_PROFILE');
        this.profileId = payload.profileId;
        return this.#respond(frame.sequence, { profileId: this.profileId });
      case FrameType.SEND:
        if (!this.ready) return this.#respond(frame.sequence, null, false, 'RADIO_NOT_READY');
        this.stats.tx++;
        this.emitBytes(encodeFrame({ type: FrameType.TX_ACCEPTED, sequence: 0, payload: { messageId: payload.messageId } }));
        return this.#respond(frame.sequence, { accepted: true, messageId: payload.messageId });
      case FrameType.RESET_STATS:
        this.stats = { tx: 0, rx: 0, retries: 0, errors: 0, rssi: -60, snr: 8 };
        return this.#respond(frame.sequence, { reset: true });
      case FrameType.REBOOT:
        this.bootId = 'boot-' + Math.random().toString(16).slice(2, 10);
        await this.#respond(frame.sequence, { rebooting: true });
        this.emitBytes(encodeFrame({ type: FrameType.DEVICE_RESET, payload: { bootId: this.bootId } }));
        return;
      default:
        return this.#respond(frame.sequence, null, false, 'UNSUPPORTED_COMMAND');
    }
  }
  emitRxPacket(packet) {
    this.stats.rx++;
    this.emitBytes(encodeFrame({ type: FrameType.RX_PACKET, payload: packet }));
  }
  emitStats() {
    this.emitBytes(encodeFrame({ type: FrameType.LINK_STATS, payload: this.stats }));
  }
  emitReady() {
    this.ready = true;
    this.emitBytes(encodeFrame({ type: FrameType.READY, payload: { profileId: this.profileId } }));
  }
}

export class MockHostLink {
  constructor(firmware = new MockRadioFirmware()) {
    this.firmware = firmware;
    this.receiver = () => {};
    this.disconnectHandler = () => {};
    this.opened = false;
    firmware.attachEmitter(bytes => {
      if (this.opened) queueMicrotask(() => this.receiver(bytes));
    });
  }
  setReceiver(fn) { this.receiver = typeof fn === 'function' ? fn : () => {}; }
  setDisconnectHandler(fn) { this.disconnectHandler = typeof fn === 'function' ? fn : () => {}; }
  async open() { this.opened = true; }
  async close() { this.opened = false; }
  async write(bytes) {
    if (!this.opened) throw new Error('LINK_CLOSED');
    queueMicrotask(() => this.firmware.receive(bytes));
  }
  forceDisconnect() {
    if (!this.opened) return;
    this.opened = false;
    queueMicrotask(() => this.disconnectHandler());
  }
  reconnect() { this.opened = true; }
}
