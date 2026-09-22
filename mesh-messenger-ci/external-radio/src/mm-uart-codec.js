const VERSION = 1;

export const FrameType = Object.freeze({
  HELLO: 0x01,
  GET_INFO: 0x02,
  GET_CAPS: 0x03,
  GET_STATE: 0x04,
  GET_STATS: 0x05,
  RADIO_INIT: 0x10,
  SET_PROFILE: 0x11,
  SEND: 0x12,
  CANCEL: 0x13,
  RESET_STATS: 0x14,
  REBOOT: 0x15,
  READY: 0x80,
  STATE_CHANGED: 0x81,
  RX_PACKET: 0x82,
  TX_ACCEPTED: 0x83,
  TX_RESULT: 0x84,
  LINK_STATS: 0x85,
  RADIO_ERROR: 0x86,
  DEVICE_RESET: 0x87,
  RESPONSE: 0x90
});

export const FrameName = Object.freeze(Object.fromEntries(Object.entries(FrameType).map(([k, v]) => [v, k])));

const enc = new TextEncoder();
const dec = new TextDecoder();

export function crc16Ccitt(bytes, initial = 0xffff) {
  let crc = initial & 0xffff;
  for (const b of bytes) {
    crc ^= (b & 0xff) << 8;
    for (let i = 0; i < 8; i++) {
      crc = (crc & 0x8000) ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff;
    }
  }
  return crc & 0xffff;
}

export function cobsEncode(input) {
  const src = input instanceof Uint8Array ? input : Uint8Array.from(input);
  const out = new Uint8Array(src.length + Math.ceil(src.length / 254) + 1);
  let read = 0, write = 1, codeIndex = 0, code = 1;
  while (read < src.length) {
    if (src[read] === 0) {
      out[codeIndex] = code;
      code = 1;
      codeIndex = write++;
      read++;
    } else {
      out[write++] = src[read++];
      code++;
      if (code === 0xff) {
        out[codeIndex] = code;
        code = 1;
        codeIndex = write++;
      }
    }
  }
  out[codeIndex] = code;
  return out.slice(0, write);
}

export function cobsDecode(input) {
  const src = input instanceof Uint8Array ? input : Uint8Array.from(input);
  const out = new Uint8Array(src.length);
  let read = 0, write = 0;
  while (read < src.length) {
    const code = src[read++];
    if (code === 0) throw new Error('COBS_ZERO_CODE');
    const copyCount = code - 1;
    if (read + copyCount > src.length) throw new Error('COBS_TRUNCATED');
    for (let i = 0; i < copyCount; i++) out[write++] = src[read++];
    if (code !== 0xff && read < src.length) out[write++] = 0;
  }
  return out.slice(0, write);
}

function normalizePayload(payload) {
  if (payload == null) return new Uint8Array(0);
  if (payload instanceof Uint8Array) return payload;
  if (typeof payload === 'string') return enc.encode(payload);
  return enc.encode(JSON.stringify(payload));
}

export function encodeFrame({ type, sequence = 0, payload = null, version = VERSION }) {
  if (!Number.isInteger(type) || type < 0 || type > 255) throw new Error('BAD_TYPE');
  if (!Number.isInteger(sequence) || sequence < 0 || sequence > 0xffff) throw new Error('BAD_SEQUENCE');
  const body = normalizePayload(payload);
  if (body.length > 0xffff) throw new Error('PAYLOAD_TOO_LARGE');
  const raw = new Uint8Array(6 + body.length + 2);
  raw[0] = version & 0xff;
  raw[1] = type & 0xff;
  raw[2] = sequence & 0xff;
  raw[3] = (sequence >> 8) & 0xff;
  raw[4] = body.length & 0xff;
  raw[5] = (body.length >> 8) & 0xff;
  raw.set(body, 6);
  const crc = crc16Ccitt(raw.slice(0, raw.length - 2));
  raw[raw.length - 2] = crc & 0xff;
  raw[raw.length - 1] = (crc >> 8) & 0xff;
  const framed = cobsEncode(raw);
  const out = new Uint8Array(framed.length + 1);
  out.set(framed);
  out[out.length - 1] = 0;
  return out;
}

export function decodeFrame(encodedWithoutDelimiter, { allowUnknownVersion = false } = {}) {
  const raw = cobsDecode(encodedWithoutDelimiter);
  if (raw.length < 8) throw new Error('FRAME_TOO_SHORT');
  const version = raw[0];
  if (!allowUnknownVersion && version !== VERSION) throw new Error('UNSUPPORTED_VERSION');
  const type = raw[1];
  const sequence = raw[2] | (raw[3] << 8);
  const payloadLength = raw[4] | (raw[5] << 8);
  if (raw.length !== 6 + payloadLength + 2) throw new Error('BAD_LENGTH');
  const expected = raw[raw.length - 2] | (raw[raw.length - 1] << 8);
  const actual = crc16Ccitt(raw.slice(0, raw.length - 2));
  if (expected !== actual) throw new Error('BAD_CRC');
  return { version, type, typeName: FrameName[type] || 'UNKNOWN', sequence, payloadBytes: raw.slice(6, 6 + payloadLength) };
}

export function decodeJsonPayload(frame) {
  if (!frame?.payloadBytes?.length) return null;
  try { return JSON.parse(dec.decode(frame.payloadBytes)); }
  catch { throw new Error('BAD_JSON_PAYLOAD'); }
}

export class FrameStreamDecoder {
  constructor({ maxFrameLength = 65536, onFrame = () => {}, onError = () => {} } = {}) {
    this.maxFrameLength = maxFrameLength;
    this.onFrame = onFrame;
    this.onError = onError;
    this.buffer = [];
  }
  reset() { this.buffer = []; }
  push(chunk) {
    const bytes = chunk instanceof Uint8Array ? chunk : Uint8Array.from(chunk || []);
    for (const b of bytes) {
      if (b === 0) {
        if (!this.buffer.length) continue;
        const frameBytes = Uint8Array.from(this.buffer);
        this.buffer = [];
        try { this.onFrame(decodeFrame(frameBytes)); }
        catch (err) { this.onError(err); }
      } else {
        this.buffer.push(b);
        if (this.buffer.length > this.maxFrameLength) {
          this.buffer = [];
          this.onError(new Error('FRAME_TOO_LARGE'));
        }
      }
    }
  }
}

export const MM_UART_VERSION = VERSION;
