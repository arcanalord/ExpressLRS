import { FrameStreamDecoder, FrameType, encodeFrame, decodeJsonPayload } from './mm-uart-codec.js';

export class ExternalRadioSession {
  constructor({ requestTimeoutMs = 1000, onEvent = () => {}, clock = () => Date.now() } = {}) {
    this.requestTimeoutMs = requestTimeoutMs;
    this.onEvent = onEvent;
    this.clock = clock;
    this.link = null;
    this.state = 'offline';
    this.info = null;
    this.capabilities = null;
    this.stats = null;
    this.sequence = 1;
    this.pending = new Map();
    this.lastError = null;
    this.bootId = null;
    this.decoder = new FrameStreamDecoder({
      onFrame: frame => this.#handleFrame(frame),
      onError: err => this.#emitError(err)
    });
  }

  snapshot() {
    return { state: this.state, info: this.info, capabilities: this.capabilities, stats: this.stats, bootId: this.bootId, lastError: this.lastError };
  }

  #setState(state, extra = {}) {
    this.state = state;
    this.onEvent({ type: 'stateChanged', state, ...extra });
  }

  #emitError(err) {
    const message = String(err?.message || err || 'UNKNOWN_ERROR');
    this.lastError = message;
    this.onEvent({ type: 'radioError', error: message });
  }

  #nextSequence() {
    const current = this.sequence;
    this.sequence = (this.sequence + 1) & 0xffff;
    if (this.sequence === 0) this.sequence = 1;
    return current;
  }

  async connect(link) {
    if (!link || typeof link.open !== 'function' || typeof link.write !== 'function') throw new Error('BAD_HOST_LINK');
    if (this.link && this.link !== link) await this.disconnect();
    this.link = link;
    this.decoder.reset();
    link.setReceiver?.(chunk => this.decoder.push(chunk));
    link.setDisconnectHandler?.(() => this.#handleDisconnect('HOST_LINK_DISCONNECTED'));
    this.#setState('connecting');
    await link.open();
    try {
      const hello = await this.request(FrameType.HELLO, { host: 'mesh-messenger', protocol: 1 });
      this.bootId = hello?.bootId ?? null;
      this.info = await this.request(FrameType.GET_INFO);
      this.capabilities = await this.request(FrameType.GET_CAPS);
      const state = await this.request(FrameType.GET_STATE);
      this.#setState(state?.ready ? 'ready' : (state?.state || 'connected'));
      return this.snapshot();
    } catch (err) {
      this.#setState('error');
      this.#emitError(err);
      throw err;
    }
  }

  async disconnect() {
    const link = this.link;
    this.link = null;
    this.#rejectPending(new Error('DISCONNECTED'));
    this.decoder.reset();
    this.#setState('offline');
    if (link?.close) await link.close();
  }

  #handleDisconnect(reason) {
    this.#rejectPending(new Error(reason));
    this.#setState('offline', { reason });
  }

  #rejectPending(err) {
    for (const [, p] of this.pending) {
      clearTimeout(p.timer);
      p.reject(err);
    }
    this.pending.clear();
  }

  async request(type, payload = null, timeoutMs = this.requestTimeoutMs) {
    if (!this.link) throw new Error('NO_HOST_LINK');
    const sequence = this.#nextSequence();
    const frame = encodeFrame({ type, sequence, payload });
    const promise = new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(sequence);
        reject(new Error('REQUEST_TIMEOUT'));
      }, timeoutMs);
      this.pending.set(sequence, { resolve, reject, timer, requestType: type, startedAt: this.clock() });
    });
    try { await this.link.write(frame); }
    catch (err) {
      const p = this.pending.get(sequence);
      if (p) { clearTimeout(p.timer); this.pending.delete(sequence); }
      throw err;
    }
    return promise;
  }

  async setProfile(profileId) {
    const supported = this.capabilities?.profileIds || [];
    if (supported.length && !supported.includes(profileId)) throw new Error('UNSUPPORTED_PROFILE');
    return this.request(FrameType.SET_PROFILE, { profileId });
  }

  async send({ messageId, recipientBinding, payload, payloadType = 'text', qos = 'normal' }) {
    if (!messageId) throw new Error('MESSAGE_ID_REQUIRED');
    if (!recipientBinding) throw new Error('RECIPIENT_REQUIRED');
    return this.request(FrameType.SEND, { messageId, recipientBinding, payload, payloadType, qos });
  }

  async refreshStats() {
    this.stats = await this.request(FrameType.GET_STATS);
    return this.stats;
  }

  #handleFrame(frame) {
    let payload = null;
    try { payload = decodeJsonPayload(frame); }
    catch (err) { this.#emitError(err); return; }

    if (frame.type === FrameType.RESPONSE) {
      const pending = this.pending.get(frame.sequence);
      if (!pending) return;
      clearTimeout(pending.timer);
      this.pending.delete(frame.sequence);
      if (payload?.ok === false) pending.reject(new Error(payload.error || 'REMOTE_ERROR'));
      else pending.resolve(payload?.data ?? null);
      return;
    }

    if (frame.type === FrameType.READY) { this.#setState('ready', { payload }); return; }
    if (frame.type === FrameType.STATE_CHANGED) { this.#setState(payload?.state || 'connected', { payload }); return; }
    if (frame.type === FrameType.LINK_STATS) { this.stats = payload; this.onEvent({ type: 'linkStats', stats: payload }); return; }
    if (frame.type === FrameType.RX_PACKET) { this.onEvent({ type: 'packetReceived', packet: payload }); return; }
    if (frame.type === FrameType.TX_ACCEPTED) { this.onEvent({ type: 'transportAccepted', tx: payload }); return; }
    if (frame.type === FrameType.TX_RESULT) { this.onEvent({ type: 'txResult', tx: payload }); return; }
    if (frame.type === FrameType.DEVICE_RESET) {
      const previousBootId = this.bootId;
      this.bootId = payload?.bootId ?? null;
      this.info = null;
      this.capabilities = null;
      this.#setState('connecting', { reason: 'deviceReset', previousBootId, bootId: this.bootId });
      this.onEvent({ type: 'deviceReset', payload });
      return;
    }
    if (frame.type === FrameType.RADIO_ERROR) { this.#emitError(payload?.error || 'REMOTE_RADIO_ERROR'); return; }
    this.onEvent({ type: 'unknownFrame', frame, payload });
  }
}
