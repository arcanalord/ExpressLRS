from pathlib import Path
import re


def must(text, old, new, label):
    n = text.count(old)
    if n != 1:
        raise RuntimeError(f"{label}: expected 1 match, got {n}")
    return text.replace(old, new, 1)


def line_replace(text, prefix, replacement, label):
    lines = text.splitlines()
    hits = [i for i, x in enumerate(lines) if x.startswith(prefix)]
    if len(hits) != 1:
        raise RuntimeError(f"{label}: expected 1 line, got {len(hits)}")
    lines[hits[0]] = replacement
    return "\n".join(lines) + ("\n" if text.endswith("\n") else "")


# -----------------------------------------------------------------------------
# Firmware
# -----------------------------------------------------------------------------
p = Path('rf_finder/firmware/src/main.cpp')
s = p.read_text(encoding='utf-8')
s = must(s, '#include <WiFi.h>\n', '#include <WiFi.h>\n#include <math.h>\n', 'math include')
s = must(s,
'''static constexpr char FW_VERSION[] = "0.6.1-dev1";
static constexpr char PROTOCOL_VERSION[] = "0.6";
static constexpr uint32_t MIN_FREQ_HZ = 2400000000UL;
static constexpr uint32_t MAX_FREQ_HZ = 2480000000UL;
static constexpr uint32_t DEFAULT_FREQ_HZ = 2440000000UL;''',
'''static constexpr char FW_VERSION[] = "0.6.2-dev1";
static constexpr char PROTOCOL_VERSION[] = "0.7";
// DAKER board range proven in the field.  The extra 20 MHz is deliberately
// marked EXPERIMENTAL: LR1121 silicon supports 2400-2500 MHz, but this board's
// RF front-end/antenna has not been characterized there.
static constexpr uint32_t VERIFIED_MIN_FREQ_HZ = 2400000000UL;
static constexpr uint32_t VERIFIED_MAX_FREQ_HZ = 2480000000UL;
static constexpr uint32_t EXPERIMENTAL_MIN_FREQ_HZ = 2400000000UL;
static constexpr uint32_t EXPERIMENTAL_MAX_FREQ_HZ = 2500000000UL;
static constexpr uint32_t DEFAULT_FREQ_HZ = 2440000000UL;''', 'range constants')
s = s.replace('uint32_t startHz = MIN_FREQ_HZ;', 'uint32_t startHz = VERIFIED_MIN_FREQ_HZ;', 1)
s = s.replace('uint32_t stopHz = MAX_FREQ_HZ;', 'uint32_t stopHz = VERIFIED_MAX_FREQ_HZ;', 1)
s = s.replace('uint32_t currentHz = MIN_FREQ_HZ;', 'uint32_t currentHz = VERIFIED_MIN_FREQ_HZ;', 1)
s = s.replace('uint32_t peakHz = MIN_FREQ_HZ;', 'uint32_t peakHz = VERIFIED_MIN_FREQ_HZ;', 1)

s = must(s,
'''    uint32_t recoveries = 0;
    uint32_t lastSweepDurationMs = 0;''',
'''    uint32_t recoveries = 0;
    uint32_t irqReadFail = 0;
    uint32_t irqSpurious = 0;
    uint32_t probeSourceReject = 0;
    uint32_t lastSweepDurationMs = 0;''', 'diagnostics fields')

s = must(s,
'''struct ProbeState {
    uint32_t requestedFreqHz = DEFAULT_FREQ_HZ;
    uint32_t activeProbeFreqHz = DEFAULT_FREQ_HZ;
    uint32_t timeoutMs = 10000;
    uint32_t startedMs = 0;
    uint32_t slotStartedMs = 0;
    size_t profile = 0;
    uint8_t channel = 0;
    uint32_t packets = 0;
    uint32_t syncPackets = 0;
    uint8_t lastUid3 = 0, lastUid4 = 0, lastUid5 = 0;
    uint8_t consistentSync = 0;
    bool confirmed = false;
};
static ProbeState probe;''',
'''struct ProbeState {
    uint32_t requestedFreqHz = DEFAULT_FREQ_HZ;
    uint32_t activeProbeFreqHz = DEFAULT_FREQ_HZ;
    uint32_t timeoutMs = 10000;
    uint32_t startedMs = 0;
    uint32_t slotStartedMs = 0;
    size_t profile = 0;
    uint8_t channel = 0;
    uint32_t packets = 0;
    uint32_t syncPackets = 0;
    uint8_t lastUid3 = 0, lastUid4 = 0, lastUid5 = 0;
    uint8_t consistentSync = 0;
    bool confirmed = false;
    bool trackOnly = false;
};
static ProbeState probe;

struct ElrsLock {
    bool valid = false;
    size_t profile = 0;
    uint8_t uid3 = 0, uid4 = 0, uid5 = 0;
    uint8_t rateIndex = 0xFF;
    uint8_t lastChannel = 0;
};
static ElrsLock elrsLock;''', 'ELRS lock state')

s = must(s,
'''static bool setFrequency(uint32_t freqHz)
{
    if (freqHz < MIN_FREQ_HZ || freqHz > MAX_FREQ_HZ) return false;''',
'''static bool isVerifiedFrequency(uint32_t freqHz)
{
    return freqHz >= VERIFIED_MIN_FREQ_HZ && freqHz <= VERIFIED_MAX_FREQ_HZ;
}

static bool isExperimentalFrequency(uint32_t freqHz)
{
    return freqHz >= EXPERIMENTAL_MIN_FREQ_HZ && freqHz <= EXPERIMENTAL_MAX_FREQ_HZ;
}

static bool setFrequency(uint32_t freqHz)
{
    if (!isExperimentalFrequency(freqHz)) return false;''', 'frequency acceptance')

s = must(s,
'''static bool clearAllIrq()
{
    const uint8_t p[4] = {0xFF, 0xFF, 0xFF, 0xFF};
    return writeCommand(lr1121::SYS_CLEAR_IRQ, p, sizeof(p));
}''',
'''static bool clearAllIrq()
{
    const uint8_t p[4] = {0xFF, 0xFF, 0xFF, 0xFF};
    return writeCommand(lr1121::SYS_CLEAR_IRQ, p, sizeof(p));
}

// LR11xx GET IRQ is a full-duplex CLEAR_IRQ transaction.  This mirrors the
// current ExpressLRS LR1121 driver: [01 14 FF FF FF FF] -> IRQ in bytes 2..5.
static bool readAndClearIrqStatus(uint32_t &irq)
{
    uint8_t frame[6] = {0x01, 0x14, 0xFF, 0xFF, 0xFF, 0xFF};
    if (!waitBusy()) { ++diag.irqReadFail; return false; }
    selectRadio();
    for (size_t i = 0; i < sizeof(frame); ++i) frame[i] = SPI.transfer(frame[i]);
    deselectRadio();
    if (!waitBusy()) { ++diag.irqReadFail; return false; }
    irq = ((uint32_t)frame[2] << 24) | ((uint32_t)frame[3] << 16) |
          ((uint32_t)frame[4] << 8) | frame[5];
    return true;
}''', 'IRQ read')

s = must(s,
'''static bool startProbe(uint32_t freqHz, uint32_t timeoutMs)
{
    if (freqHz < MIN_FREQ_HZ || freqHz > MAX_FREQ_HZ) return false;
    probe = ProbeState{};
    probe.requestedFreqHz = freqHz;
    probe.timeoutMs = constrain(timeoutMs, 3000UL, 30000UL);
    probe.startedMs = millis();
    // Start at the ELRS channel nearest the selected marker, then walk all 80 channels.
    int32_t c = (int32_t)((freqHz - 2400400000UL + 500000UL) / 1000000UL);
    probe.channel = (uint8_t)constrain(c, 0L, 79L);
    runMode = RunMode::PACKET_PROBE;
    return configureProbeSlot();
}''',
'''static bool startProbe(uint32_t freqHz, uint32_t timeoutMs)
{
    // ELRS 2.4 grid itself remains 2400.4-2479.4 MHz even when generic tuning
    // is allowed into the experimental 2480-2500 MHz window.
    if (!isVerifiedFrequency(freqHz)) return false;
    probe = ProbeState{};
    probe.requestedFreqHz = freqHz;
    probe.timeoutMs = constrain(timeoutMs, 3000UL, 30000UL);
    probe.startedMs = millis();
    int32_t c = (int32_t)((freqHz - 2400400000UL + 500000UL) / 1000000UL);
    probe.channel = (uint8_t)constrain(c, 0L, 79L);
    runMode = RunMode::PACKET_PROBE;
    return configureProbeSlot();
}

static bool startTrack(uint32_t timeoutMs)
{
    if (!elrsLock.valid || elrsLock.profile >= PROBE_PROFILE_COUNT) return false;
    probe = ProbeState{};
    probe.timeoutMs = constrain(timeoutMs, 3000UL, 60000UL);
    probe.startedMs = millis();
    probe.profile = elrsLock.profile;
    probe.channel = elrsLock.lastChannel;
    probe.confirmed = true;
    probe.trackOnly = true;
    runMode = RunMode::PACKET_PROBE;
    Serial.printf("Q,STATE,TRACK,%s,%lu\n", PROBE_PROFILES[probe.profile].name, elrsChannelHz(probe.channel));
    return configureProbeSlot();
}''', 'probe/track start')

# Replace packet handler as a whole.
start = s.index('static void handleProbePacket()')
end = s.index('\nstatic void probeTick()', start)
new_handler = r'''static void handleProbePacket()
{
    const ProbeProfile &pr = PROBE_PROFILES[probe.profile];
    uint8_t b[20] = {0};
    const size_t total = (size_t)pr.payloadLen + 6;
    if (!writeCommand(lr1121::RADIO_GET_PACKET) || !readResponse(b, total)) {
        enterContinuousRx();
        return;
    }

    ++probe.packets;
    const int rssi = -(int)(b[5] / 2);
    const float snr = ((int8_t)b[2]) / 4.0f;
    const uint8_t *payload = b + 6;
    const uint8_t type = payload[0] & 0x03;
    const bool sync = (type == 2 && pr.payloadLen == 8);
    uint8_t rateIndex = 0xFF, fhssIndex = 0xFF;
    bool uidMatch = false;

    if (sync) {
        ++probe.syncPackets;
        fhssIndex = payload[1];
        rateIndex = (payload[3] >> 4) & 0x0F;
        uidMatch = elrsLock.valid && rateIndex == elrsLock.rateIndex &&
                   payload[4] == elrsLock.uid3 && payload[5] == elrsLock.uid4 && payload[6] == elrsLock.uid5;

        if (!probe.trackOnly && rateIndex == pr.expectedRateIndex) {
            if (payload[4] == probe.lastUid3 && payload[5] == probe.lastUid4 && payload[6] == probe.lastUid5) {
                if (probe.consistentSync < 255) ++probe.consistentSync;
            } else {
                probe.lastUid3 = payload[4]; probe.lastUid4 = payload[5]; probe.lastUid5 = payload[6];
                probe.consistentSync = 1;
            }
        }
    }

    // In TRACK mode only source-specific matching SYNC packets are measurement
    // records.  This is intentionally sparse but prevents another LoRa/ELRS
    // source from steering the bearing.
    const bool measurement = !probe.trackOnly || uidMatch;
    if (measurement) {
        const String hex = toHex(payload, pr.payloadLen);
        Serial.printf("D,%lu,%lu,LORA,%s,%d,%.2f,%s,%u,%s\n",
                      millis(), probe.activeProbeFreqHz, pr.name, rssi, snr,
                      uidMatch ? "ELRS_UID_MATCH" : (sync ? "SYNC" : "PACKET"), pr.payloadLen, hex.c_str());
    } else {
        ++diag.probeSourceReject;
    }

    if (!probe.trackOnly) Serial.printf("Q,STATE,PHY_LOCK,%s,%lu\n", pr.name, probe.activeProbeFreqHz);

    if (!probe.trackOnly && !probe.confirmed && sync && rateIndex == pr.expectedRateIndex && probe.consistentSync >= 3) {
        probe.confirmed = true;
        elrsLock.valid = true;
        elrsLock.profile = probe.profile;
        elrsLock.uid3 = payload[4]; elrsLock.uid4 = payload[5]; elrsLock.uid5 = payload[6];
        elrsLock.rateIndex = rateIndex;
        elrsLock.lastChannel = probe.channel;
        Serial.printf("E,ELRS,CONFIRMED,%s,%lu,%lu,%u,%u,%02X%02X%02X\n",
                      pr.name, probe.packets, probe.syncPackets, rateIndex, fhssIndex,
                      elrsLock.uid3, elrsLock.uid4, elrsLock.uid5);
        Serial.printf("Q,STATE,CONFIRMED,%s,%lu\n", pr.name, probe.activeProbeFreqHz);
    }

    if (probe.trackOnly && uidMatch) {
        elrsLock.lastChannel = probe.channel;
        Serial.printf("Q,STATE,TRACK_PACKET,%s,%lu\n", pr.name, probe.activeProbeFreqHz);
    }
    enterContinuousRx();
}'''
s = s[:start] + new_handler + s[end:]

s = must(s,
'''    if (digitalRead(hw::DIO1) == HIGH) handleProbePacket();

    // 12 ms slot gives a chance to catch 50-500 Hz packets while covering the full
    // 80-channel grid in under one second per PHY. Start near marker, then walk grid.
    if ((uint32_t)(now - probe.slotStartedMs) >= 12UL) {
        probe.channel = (uint8_t)((probe.channel + 1) % 80);
        if (probe.channel == 0 && !probe.confirmed) probe.profile = (probe.profile + 1) % PROBE_PROFILE_COUNT;
        if (!configureProbeSlot()) stopProbe("ERROR");
    }''',
'''    if (digitalRead(hw::DIO1) == HIGH) {
        uint32_t irq = 0;
        if (readAndClearIrqStatus(irq)) {
            if (irq & lr1121::IRQ_RX_DONE) handleProbePacket();
            else ++diag.irqSpurious;
        }
    }

    // During TRACK keep the confirmed PHY and sweep the ELRS grid. During
    // detection rotate PHY only after a full grid pass.
    if ((uint32_t)(now - probe.slotStartedMs) >= 12UL) {
        probe.channel = (uint8_t)((probe.channel + 1) % 80);
        if (probe.channel == 0 && !probe.confirmed) probe.profile = (probe.profile + 1) % PROBE_PROFILE_COUNT;
        if (!configureProbeSlot()) stopProbe("ERROR");
    }''', 'probe IRQ tick')

s = must(s,
'''    const uint8_t cal[2] = {
        (uint8_t)(((MIN_FREQ_HZ / 1000000UL) - 1) / 4),
        (uint8_t)(1 + ((MAX_FREQ_HZ / 1000000UL) + 1) / 4)
    };''',
'''    const uint8_t cal[2] = {
        (uint8_t)(((EXPERIMENTAL_MIN_FREQ_HZ / 1000000UL) - 1) / 4),
        (uint8_t)(1 + ((EXPERIMENTAL_MAX_FREQ_HZ / 1000000UL) + 1) / 4)
    };''', 'image calibration range')

s = must(s,
'''static bool readAverageRssi(uint8_t samples, uint32_t gapUs, float &avg)
{
    float sum = 0.0f;
    uint8_t good = 0;
    for (uint8_t i = 0; i < samples; ++i) {
        float v = 0.0f;
        if (readRssiDbm(v)) { sum += v; ++good; }
        if (i + 1 < samples) delayMicroseconds(gapUs);
    }
    if (!good) return false;
    avg = sum / good;
    return true;
}''',
'''static bool readAverageRssi(uint8_t samples, uint32_t gapUs, float &avg)
{
    float sumPower = 0.0f;
    uint8_t good = 0;
    for (uint8_t i = 0; i < samples; ++i) {
        float v = 0.0f;
        if (readRssiDbm(v)) { sumPower += powf(10.0f, v / 10.0f); ++good; }
        if (i + 1 < samples) delayMicroseconds(gapUs);
    }
    if (!good || sumPower <= 0.0f) return false;
    avg = 10.0f * log10f(sumPower / good);
    return true;
}''', 'power-domain RSSI')

s = must(s,
'''    Serial.printf("I,diag,recoveries,%lu\n", diag.recoveries);
    Serial.printf("I,diag,last_sweep_ms,%lu\n", diag.lastSweepDurationMs);''',
'''    Serial.printf("I,diag,recoveries,%lu\n", diag.recoveries);
    Serial.printf("I,diag,irq_read_fail,%lu\n", diag.irqReadFail);
    Serial.printf("I,diag,irq_spurious,%lu\n", diag.irqSpurious);
    Serial.printf("I,diag,source_reject,%lu\n", diag.probeSourceReject);
    Serial.printf("I,diag,last_sweep_ms,%lu\n", diag.lastSweepDurationMs);''', 'diag print')

s = must(s,
'''    Serial.printf("I,range,%lu,%lu\n", MIN_FREQ_HZ, MAX_FREQ_HZ);''',
'''    Serial.printf("I,range,%lu,%lu\n", VERIFIED_MIN_FREQ_HZ, VERIFIED_MAX_FREQ_HZ);
    Serial.printf("I,cap,experimental_range,%lu,%lu\n", EXPERIMENTAL_MIN_FREQ_HZ, EXPERIMENTAL_MAX_FREQ_HZ);''', 'info ranges')
s = must(s,
'''    Serial.println("I,cap,elrs_profiles,LORA500|LORA250|LORA150|LORA50");
    Serial.println("I,protocol,F|S|X|I|A|D|G|T|Z,DIAG|Q,ELRS|Q,X");''',
'''    Serial.println("I,cap,elrs_profiles,LORA500|LORA250|LORA150|LORA50");
    Serial.println("I,cap,elrs_track,SYNC_UID_LOCK");
    Serial.println("I,protocol,F|S|X|I|A|D|G|T|Z,DIAG|Q,ELRS|Q,TRACK|Q,X");''', 'protocol capabilities')

s = must(s,
'''    Serial.printf("A,F,%lu\n", fixedFreqHz);''',
'''    Serial.printf("A,F,%lu,%s\n", fixedFreqHz, isVerifiedFrequency(fixedFreqHz) ? "VERIFIED" : "EXPERIMENTAL");''', 'frequency ack')

s = must(s,
'''    if (start < MIN_FREQ_HZ || stop > MAX_FREQ_HZ || start >= stop) return false;''',
'''    if (start < EXPERIMENTAL_MIN_FREQ_HZ || stop > EXPERIMENTAL_MAX_FREQ_HZ || start >= stop) return false;''', 'sweep range')

s = must(s,
'''    if (line.startsWith("Q,ELRS,")) {
        unsigned long f = 0, window = 0, timeout = 0;
        if (sscanf(line.c_str(), "Q,ELRS,%lu,%lu,%lu", &f, &window, &timeout) != 3 ||
            f < MIN_FREQ_HZ || f > MAX_FREQ_HZ) {
            Serial.println("E,PROBE_ARGS");
            return;
        }
        (void)window;
        if (!startProbe((uint32_t)f, (uint32_t)timeout)) Serial.println("E,PROBE_START");
        return;
    }
    if (line.startsWith("F,")) {
        const uint32_t f = strtoul(line.c_str() + 2, nullptr, 10);
        if (f < MIN_FREQ_HZ || f > MAX_FREQ_HZ) { Serial.println("E,FREQ_RANGE"); return; }
        switchToFixed(f);
        return;
    }''',
'''    if (line.startsWith("Q,ELRS,")) {
        unsigned long f = 0, window = 0, timeout = 0;
        if (sscanf(line.c_str(), "Q,ELRS,%lu,%lu,%lu", &f, &window, &timeout) != 3 ||
            !isVerifiedFrequency((uint32_t)f)) {
            Serial.println("E,PROBE_ARGS");
            return;
        }
        (void)window;
        if (!startProbe((uint32_t)f, (uint32_t)timeout)) Serial.println("E,PROBE_START");
        return;
    }
    if (line.startsWith("Q,TRACK,")) {
        const uint32_t timeout = strtoul(line.c_str() + 8, nullptr, 10);
        if (!elrsLock.valid) { Serial.println("E,NO_ELRS_LOCK"); return; }
        if (!startTrack(timeout)) Serial.println("E,TRACK_START");
        return;
    }
    if (line.startsWith("F,")) {
        const uint32_t f = strtoul(line.c_str() + 2, nullptr, 10);
        if (!isExperimentalFrequency(f)) { Serial.println("E,FREQ_RANGE"); return; }
        switchToFixed(f);
        return;
    }''', 'command tune/probe/track')

p.write_text(s, encoding='utf-8')

# -----------------------------------------------------------------------------
# Android native bridge: monotonic timestamps for serial/heading.
# -----------------------------------------------------------------------------
p = Path('rf_finder/android/app/src/main/java/ru/fpvclub/rangerrf/MainActivity.java')
s = p.read_text(encoding='utf-8')
s = must(s, 'import android.os.Looper;\n', 'import android.os.Looper;\nimport android.os.SystemClock;\n', 'SystemClock import')
s = must(s,
'''        lastHeadingDeg = deg;
        lastHeadingAtMs = System.currentTimeMillis();
        eval("window.onHeading && window.onHeading(" + String.format(Locale.US, "%.1f", deg) + ")");''',
'''        lastHeadingDeg = deg;
        lastHeadingAtMs = System.currentTimeMillis();
        long sensorMs = event.timestamp / 1000000L;
        eval("window.onHeading && window.onHeading(" + String.format(Locale.US, "%.1f", deg) + "," + sensorMs + ")");''', 'heading timestamp')
s = must(s,
'''                if (!line.isEmpty()) { ++rxLines; pushLine(line); }''',
'''                if (!line.isEmpty()) { ++rxLines; pushLine(line, SystemClock.elapsedRealtime()); }''', 'serial timestamp')
s = must(s,
'''    private void pushLine(String line) { eval("window.onSerialLine && window.onSerialLine(" + JSONObject.quote(line) + ")"); }''',
'''    private void pushLine(String line, long monoMs) { eval("window.onSerialLine && window.onSerialLine(" + JSONObject.quote(line) + "," + monoMs + ")"); }''', 'pushLine timestamp')
p.write_text(s, encoding='utf-8')

# -----------------------------------------------------------------------------
# Android Web UI
# -----------------------------------------------------------------------------
p = Path('rf_finder/android/app/src/main/assets/index.html')
s = p.read_text(encoding='utf-8')

# Small, evidence-oriented status additions; no duplicate tuning controls.
s = must(s,
'''<div id="tuneState" class="muted tuneState">ввод с клавиатуры · Enter применить</div><div id="receiverRange" class="muted">заявлено приёмником: 2400–2480 МГц</div>''',
'''<div id="tuneState" class="muted tuneState">ввод с клавиатуры · Enter применить</div><div id="receiverRange" class="muted">VERIFIED 2400–2480 · EXPERIMENTAL до 2500 МГц</div>''', 'range label')
s = must(s,
'''<div class="control"><div class="label">СЛЕДЯЩИЙ ПИК</div><div class="chips"><button id="peakHold" class="chip active">Авто · 8с</button></div><div id="coverage" class="muted">покрытие 0%</div></div>''',
'''<div class="control"><div class="label">ПЕЛЕНГ</div><div class="chips"><button id="peakHold" class="chip active">Авто · 8с</button></div><div id="coverage" class="muted">проход 0%</div></div>''', 'bearing control label')

s = line_replace(s, 'let lo=', "let lo=2400,hi=2480,expLo=2400,expHi=2500,fixed=2440,scanStart=2400,scanStop=2480,heading=null,compassAccuracy='UNRELIABLE',smoothing='normal',ema=null,peakHold=true,bestHeading=null,bestDb=-Infinity,bearingSamples=[],pendingTuneMHz=null,tuneAckTimer=null,headingHistory=[],rotationRateDps=0,passBins=Array.from({length:72},()=>[]);", 'state')
s = line_replace(s, 'let cap=', "let cap={bw:812500,minStep:100000,maxStep:10000000,minDwell:1,maxDwell:100,minAvg:1,maxAvg:32,maxSettle:50000,maxPoints:801,packetProbe:false},fwDiag={},lastP={duration:null,points:null},probeOn=false,packetRows=[],elrsConfirmed=false,elrsBearing=false,elrsLock={profile:null,uid:null};", 'cap state')

s = line_replace(s, 'function resetPass()', "function resetPass(){bestHeading=null;bestDb=-Infinity;bearingSamples=[];angleBins.fill(0);passBins=Array.from({length:72},()=>[]);ui.bestH.textContent='—°';ui.bestP.textContent='— dBm';ui.coverage.textContent='проход 0%';renderCompass()}", 'reset pass')

insert_after = "function renderStats(){ui.min.textContent=Number.isFinite(stats.min)?fmt(stats.min):'—';ui.avg.textContent=stats.n?fmt(stats.mean):'—';ui.peak.textContent=Number.isFinite(stats.max)?fmt(stats.max):'—'}"
extra = r'''
function angleDelta(a,b){return((a-b+540)%360)-180}
function headingAt(t){if(!Number.isFinite(t)||!headingHistory.length)return heading;let best=headingHistory[0],bd=Math.abs(best.t-t);for(const x of headingHistory){const d=Math.abs(x.t-t);if(d<bd){best=x;bd=d}else if(x.t>t&&d>bd)break}return best.h}
function updatePass(h,db){if(!Number.isFinite(h)||!Number.isFinite(db))return;const bi=Math.floor((((h%360)+360)%360)/5),arr=passBins[bi];arr.push(db);if(arr.length>24)arr.shift();const valid=passBins.map((x,i)=>x.length?{i,v:quantile(x,.7)}:null).filter(Boolean);const coverage=valid.length/72*100;ui.coverage.textContent='проход '+Math.round(coverage)+'%'+(rotationRateDps>90?' · медленнее':'');if(valid.length<12)return;valid.sort((a,b)=>b.v-a.v);const first=valid[0];let second=null;for(const x of valid.slice(1)){const sep=Math.abs(angleDelta(x.i*5,first.i*5));if(sep>120){second=x;break}}if(coverage>=55){bestHeading=first.i*5+2.5;bestDb=first.v;ui.bestH.textContent=Math.round(bestHeading)+'°';ui.bestP.textContent=fmt(bestDb)+' dBm';if(second&&first.v-second.v<3&&Math.abs(Math.abs(angleDelta(second.i*5,first.i*5))-180)<35)ui.coverage.textContent+=' · возможен задний лепесток'}}
'''
s = must(s, insert_after, insert_after + extra, 'bearing helpers')

s = line_replace(s, 'function renderCompass()', "function renderCompass(){const h=Number.isFinite(heading)?heading:0;ui.rose.style.transform='rotate('+(-h)+'deg)';const ok=bestHeading!==null&&Number.isFinite(bestHeading);ui.bearing.textContent=Math.round(ok?bestHeading:h)+'°';ui.bearingLabel.textContent=ok?'НА ИСТОЧНИК':'АЗИМУТ';if(rotationRateDps>90&&Number.isFinite(heading)){ui.turn.className='hint warn';ui.turn.textContent='Вращай медленнее · '+Math.round(rotationRateDps)+'°/с';if(!ok)return}if(!ok||!Number.isFinite(heading)||!peakHold){ui.target.style.display='none';ui.turn.className='hint';ui.turn.textContent=!Number.isFinite(heading)?'Жду датчик компаса':!peakHold?'Следящий пик выключен':'Наводись на максимум';return}const d=((bestHeading-heading+540)%360)-180,ad=Math.abs(d);ui.target.style.display='block';ui.target.style.transform='rotate('+d+'deg)';ui.turn.textContent=ad<=6?'ПИК ПРЯМО ПО КУРСУ':'Поверни '+Math.round(ad)+'° '+(d>0?'вправо':'влево');ui.turn.className='hint'+(ad<=6?' good':'')}", 'render compass')
s = line_replace(s, 'function updateBearingTracker(', "function updateBearingTracker(db,h=heading,t=performance.now()){if(!peakHold||!Number.isFinite(h))return;const now=Number.isFinite(t)?t:performance.now(),hh=((h%360)+360)%360;bearingSamples.push({t:now,h:hh,db});const cutoff=now-TRACK_MS;while(bearingSamples.length&&bearingSamples[0].t<cutoff)bearingSamples.shift();if(!bearingSamples.length)return;const floor=quantile(bearingSamples.map(x=>x.db),.25),bins=new Map();for(const x of bearingSamples){const bi=Math.floor(x.h/5);let b=bins.get(bi);if(!b)b={sum:0,n:0,max:-Infinity,last:0,cx:0,cy:0};b.sum+=x.db;b.n++;b.max=Math.max(b.max,x.db);b.last=Math.max(b.last,x.t);const r=x.h*Math.PI/180;b.cx+=Math.cos(r);b.cy+=Math.sin(r);bins.set(bi,b)}let pick=null;for(const b of bins.values()){const mean=b.sum/b.n,relative=Math.min(15,mean-floor),age=(now-b.last)/1000,score=relative-age*1.5+Math.min(b.n,4)*.12;if(!pick||score>pick.score)pick={b,score}}if(!pick)return;let h2=Math.atan2(pick.b.cy,pick.b.cx)*180/Math.PI;if(h2<0)h2+=360;if(passBins.filter(x=>x.length).length<40){bestHeading=h2;bestDb=pick.b.max;ui.bestH.textContent=Math.round(bestHeading)+'°';ui.bestP.textContent=fmt(bestDb)+' dBm'}}", 'tracker with timestamp')
s = line_replace(s, 'function updateRssi(', "function updateRssi(raw,sampleHeading=heading,sampleT=performance.now()){if(!Number.isFinite(raw)||raw>0||raw<-180)return;ema=ema===null?raw:alpha[smoothing]*raw+(1-alpha[smoothing])*ema;stats.n++;stats.min=Math.min(stats.min,raw);stats.max=Math.max(stats.max,raw);const p=10**(raw/10),oldP=stats.n>1?10**(stats.mean/10)*(stats.n-1):0;stats.mean=10*Math.log10((oldP+p)/stats.n);history.push(ema);if(history.length>240)history.shift();ui.rssi.textContent=fmt(ema);ui.meter.style.width=clamp((ema+120)/90*100,0,100)+'%';renderStats();if(Number.isFinite(sampleHeading)){const bi=Math.floor((((sampleHeading%360)+360)%360)/5);angleBins[bi]++;updatePass(sampleHeading,ema);updateBearingTracker(ema,sampleHeading,sampleT)}renderCompass();drawHistory()}", 'RSSI timestamp/power')

# Immediate sweep finalization on P; avoid one-sweep lag.
s = line_replace(s, 'function finalizeSweep()', "function finalizeSweep(){if(!currentSweep.size)return;sweeps.push(new Map(currentSweep));if(sweeps.length>24)sweeps.shift();currentSweep=new Map();analyzeSweeps();drawWaterfall()}", 'finalize sweep')

s = line_replace(s, 'function startElrsBearing()', "function startElrsBearing(){if(!elrsConfirmed)return;resetStats();resetPass();elrsBearing=true;packetRows=[];renderPacketLog();setProbe(true);ui.elrsResult.textContent='ПЕЛЕНГ ELRS…';ui.elrsEvidence.textContent='source-lock · matching SYNC RSSI · 30с';document.querySelector('[data-view=\"bearing\"]').click();send('Q,TRACK,30000')}", 'fast ELRS track')

s = line_replace(s, 'function startScan()', "function startScan(){const[a,b]=bounds(),spanHz=Math.round((b-a)*1e6),dw=clamp(Number(ui.dwell.value||2),cap.minDwell,cap.maxDwell);let step=currentStepHz(),points=Math.floor(spanHz/step)+1;if(points>cap.maxPoints&&ui.profile.value!=='manual'){step=Math.ceil(spanHz/(cap.maxPoints-1)/100000)*100000;step=clamp(step,cap.minStep,cap.maxStep);ui.step.value=Math.round(step/1000);points=Math.floor(spanHz/step)+1;ui.estimate.textContent='AUTO STEP '+fmt(step/1e6,3)+' МГц · '+points+' точек'}else if(points>cap.maxPoints){ui.scanState.textContent='MANUAL: увеличь step · '+points+' > '+cap.maxPoints;ui.scanState.className='muted warn';return}currentSweep.clear();sweeps=[];currentSweepNo=-1;chooseMarker(null,null);send('S,'+Math.round(a*1e6)+','+Math.round(b*1e6)+','+Math.round(step)+','+Math.round(dw));scanOn=true;ui.scan.classList.add('stop');ui.scan.textContent='■ ОСТАНОВИТЬ';ui.scanState.textContent='сканирование';ui.scanState.className='muted'}", 'smart scan step')

# Parser: timestamps, source-only ELRS track, experimental range capability, finalize P.
for line in s.splitlines():
    if line.startswith('function parse(line)'):
        old_parse = line
        break
else:
    raise RuntimeError('parse function missing')
new_parse = old_parse.replace('function parse(line){', 'function parse(line,rxT=performance.now()){')
new_parse = new_parse.replace('updateRssi(db);return}', 'updateRssi(db,headingAt(Number(rxT)),Number(rxT));return}', 1)
new_parse = new_parse.replace("if(p[0]==='P'&&p.length>=3){const hz=Number(p[1]),db=Number(p[2]);if(Number.isFinite(hz)&&Number.isFinite(db))chooseMarker(hz/1e6,db);if(p.length>=6){lastP.duration=Number(p[5]);lastP.points=p.length>=7?Number(p[6]):null;renderDiag()}return}", "if(p[0]==='P'&&p.length>=3){const hz=Number(p[1]),db=Number(p[2]);if(Number.isFinite(hz)&&Number.isFinite(db))chooseMarker(hz/1e6,db);if(p.length>=6){lastP.duration=Number(p[5]);lastP.points=p.length>=7?Number(p[6]):null;renderDiag()}finalizeSweep();currentSweepNo=-1;return}")
new_parse = new_parse.replace("if(p[0]==='D'&&p.length>=10){packetRows.push(p.slice(1).join(','));renderPacketLog();if(elrsBearing){const db=Number(p[5]);if(Number.isFinite(db))updateRssi(db)}return}", "if(p[0]==='D'&&p.length>=10){packetRows.push(p.slice(1).join(','));renderPacketLog();const flags=p[7]||'';if(elrsBearing&&flags==='ELRS_UID_MATCH'){const db=Number(p[5]);if(Number.isFinite(db))updateRssi(db,headingAt(Number(rxT)),Number(rxT))}return}")
new_parse = new_parse.replace("if(p[1]==='range'&&p.length>=4){lo=Number(p[2])/1e6;hi=Number(p[3])/1e6;ui.receiverRange.textContent='заявлено приёмником: '+fmt(lo,3)+'–'+fmt(hi,3)+' МГц · вне диапазона можно ввести экспериментально';renderWindow()}", "if(p[1]==='range'&&p.length>=4){lo=Number(p[2])/1e6;hi=Number(p[3])/1e6;ui.receiverRange.textContent='VERIFIED '+fmt(lo,3)+'–'+fmt(hi,3)+' МГц';renderWindow()}")
new_parse = new_parse.replace("if(p[2]==='bw_hz'){cap.bw=Number(p[3]);ui.bw.textContent='≈'+fmt(cap.bw/1000,1)+' кГц'}", "if(p[2]==='bw_hz'){cap.bw=Number(p[3]);ui.bw.textContent='≈'+fmt(cap.bw/1000,1)+' кГц'}if(p[2]==='experimental_range'){expLo=Number(p[3])/1e6;expHi=Number(p[4])/1e6;ui.receiverRange.textContent='VERIFIED '+fmt(lo,3)+'–'+fmt(hi,3)+' · EXP '+fmt(expLo,3)+'–'+fmt(expHi,3)+' МГц'}")
new_parse = new_parse.replace("if(p[0]==='A'){if(p[1]==='F'&&p[2])acceptTune(Number(p[2])/1e6);", "if(p[0]==='A'){if(p[1]==='F'&&p[2]){acceptTune(Number(p[2])/1e6);if(p[3]){ui.tuneState.textContent=p[3]+' · '+fmt(Number(p[2])/1e6,3)+' МГц';ui.tuneState.className='muted tuneState'+(p[3]==='EXPERIMENTAL'?' warn':'')}}")
s = must(s, old_parse, new_parse, 'parser update')

# Heading callback with monotonic history and angular speed.
s = must(s,
'''window.onSerialLine=parse;window.onNativeStatus=(t,s)=>setStatus(t,s);window.onSerialTx=()=>{};window.onHeading=v=>{heading=Number(v);renderCompass()};''',
'''window.onSerialLine=parse;window.onNativeStatus=(t,s)=>setStatus(t,s);window.onSerialTx=()=>{};window.onHeading=(v,t)=>{const h=Number(v),tm=Number(t);if(!Number.isFinite(h))return;heading=h;if(Number.isFinite(tm)){const prev=headingHistory.length?headingHistory[headingHistory.length-1]:null;headingHistory.push({t:tm,h});while(headingHistory.length&&tm-headingHistory[0].t>4000)headingHistory.shift();if(prev&&tm>prev.t){rotationRateDps=Math.abs(angleDelta(h,prev.h))/((tm-prev.t)/1000);rotationRateDps=.25*rotationRateDps+.75*(window._rotRate||0);window._rotRate=rotationRateDps}}renderCompass()};''', 'heading history callback')

s = s.replace("const s={app:'0.6.1-dev1'", "const s={app:'0.6.2-dev1'", 1)
s = s.replace('FPV Club RF Finder v0.6.1-dev1 · RX-only · unified tuning + ELRS bearing', 'FPV Club RF Finder v0.6.2-dev1 · RX-only · source-lock + timestamped bearing', 1)
p.write_text(s, encoding='utf-8')

# Android version
p = Path('rf_finder/android/app/build.gradle')
s = p.read_text(encoding='utf-8')
s = must(s, 'versionCode 9', 'versionCode 10', 'version code')
s = must(s, "versionName '0.6.1-dev1'", "versionName '0.6.2-dev1'", 'version name')
p.write_text(s, encoding='utf-8')

print('v0.6.2-dev1 patch applied')
