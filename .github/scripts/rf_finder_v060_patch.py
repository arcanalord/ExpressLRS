from pathlib import Path


def replace_one(text: str, old: str, new: str, label: str) -> str:
    n = text.count(old)
    if n != 1:
        raise RuntimeError(f"{label}: expected one match, got {n}")
    return text.replace(old, new, 1)


# ---------------- Firmware ----------------
p = Path("rf_finder/firmware/src/main.cpp")
s = p.read_text(encoding="utf-8")

s = replace_one(s,
'''constexpr uint16_t SYS_SET_DIO_AS_RF_SWITCH = 0x0112;
constexpr uint16_t SYS_SET_STANDBY = 0x011C;''',
'''constexpr uint16_t SYS_SET_DIO_AS_RF_SWITCH = 0x0112;
constexpr uint16_t SYS_SET_DIO_IRQ_PARAMS = 0x0113;
constexpr uint16_t SYS_CLEAR_IRQ = 0x0114;
constexpr uint16_t SYS_SET_STANDBY = 0x011C;''', "irq opcodes")

s = replace_one(s,
'''constexpr uint16_t RADIO_GET_RSSI_INST = 0x0205;
constexpr uint16_t RADIO_SET_RX = 0x0209;''',
'''constexpr uint16_t RADIO_GET_PKT_STATUS = 0x0204;
constexpr uint16_t RADIO_GET_RSSI_INST = 0x0205;
constexpr uint16_t RADIO_SET_RX = 0x0209;''', "packet status")

s = replace_one(s,
'''constexpr uint16_t RADIO_SET_RX_BOOSTED = 0x0227;
''',
'''constexpr uint16_t RADIO_SET_RX_BOOSTED = 0x0227;
constexpr uint16_t RADIO_GET_PACKET = 0x0700;
constexpr uint32_t IRQ_RX_DONE = 0x00000008UL;
''', "get packet")

s = replace_one(s, 'constexpr uint8_t LORA_CR_4_5 = 0x01;',
'''constexpr uint8_t LORA_CR_4_5 = 0x01;
constexpr uint8_t LORA_CR_LI_4_6 = 0x06;
constexpr uint8_t LORA_CR_LI_4_8 = 0x07;''', "coding rates")

s = replace_one(s,
'''static constexpr char FW_VERSION[] = "0.5.0-dev1";
static constexpr char PROTOCOL_VERSION[] = "0.5";''',
'''static constexpr char FW_VERSION[] = "0.6.0-dev1";
static constexpr char PROTOCOL_VERSION[] = "0.6";''', "version")

s = replace_one(s, 'enum class RunMode : uint8_t { FIXED, SWEEP };',
                'enum class RunMode : uint8_t { FIXED, SWEEP, PACKET_PROBE };', "mode enum")

s = replace_one(s,
'''static SweepConfig sweep;

static const char *modeName()
{
    return runMode == RunMode::FIXED ? "FIXED" : "SWEEP";
}''',
'''static SweepConfig sweep;

struct ProbeProfile {
    const char *name;
    uint8_t sf;
    uint8_t cr;
    uint8_t preamble;
    uint8_t payloadLen;
    uint8_t expectedRateIndex;
};

// Current ExpressLRS 2.4 GHz LoRa profiles (classic 8-byte OTA family).
// 13-byte full-resolution and GFSK/K modes are intentionally deferred until dev1 is field-proven.
static const ProbeProfile PROBE_PROFILES[] = {
    {"LORA500", 0x05, lr1121::LORA_CR_LI_4_6, 12, 8, 4},
    {"LORA250", 0x06, lr1121::LORA_CR_LI_4_8, 14, 8, 6},
    {"LORA150", 0x07, lr1121::LORA_CR_LI_4_8, 12, 8, 7},
    {"LORA50",  0x08, lr1121::LORA_CR_LI_4_8, 12, 8, 9},
};
static constexpr size_t PROBE_PROFILE_COUNT = sizeof(PROBE_PROFILES) / sizeof(PROBE_PROFILES[0]);

struct ProbeState {
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
static ProbeState probe;

static const char *modeName()
{
    if (runMode == RunMode::FIXED) return "FIXED";
    if (runMode == RunMode::SWEEP) return "SWEEP";
    return "PACKET_PROBE";
}''', "probe structures")

marker = 'static bool setBoosted(bool enabled)\n{'
if marker not in s:
    raise RuntimeError("setBoosted insertion point missing")
probe_code = r'''static bool setRxDoneIrq()
{
    uint8_t p[8] = {0};
    p[3] = (uint8_t)lr1121::IRQ_RX_DONE;
    return writeCommand(lr1121::SYS_SET_DIO_IRQ_PARAMS, p, sizeof(p));
}

static bool clearAllIrq()
{
    const uint8_t p[4] = {0xFF, 0xFF, 0xFF, 0xFF};
    return writeCommand(lr1121::SYS_CLEAR_IRQ, p, sizeof(p));
}

static uint32_t elrsChannelHz(uint8_t channel)
{
    // ExpressLRS ISM2G4 grid: 80 channels from 2400.4 to 2479.4 MHz inclusive.
    channel %= 80;
    return 2400400000UL + (uint32_t)channel * 1000000UL;
}

static bool configureProbeSlot()
{
    if (probe.profile >= PROBE_PROFILE_COUNT) return false;
    const ProbeProfile &pr = PROBE_PROFILES[probe.profile];
    probe.activeProbeFreqHz = elrsChannelHz(probe.channel);
    if (!standby()) return false;
    const uint8_t pktType = lr1121::PKT_LORA;
    if (!writeCommand(lr1121::RADIO_SET_PKT_TYPE, &pktType, 1)) return false;
    const uint8_t mod[4] = {pr.sf, lr1121::LORA_BW_800, pr.cr, 0x00};
    if (!writeCommand(lr1121::RADIO_SET_MOD_PARAMS, mod, sizeof(mod))) return false;
    const uint8_t pkt[6] = {0x00, pr.preamble, lr1121::LORA_FIXED, pr.payloadLen,
                            lr1121::LORA_CRC_OFF, lr1121::LORA_IQ_STANDARD};
    if (!writeCommand(lr1121::RADIO_SET_PKT_PARAMS, pkt, sizeof(pkt))) return false;
    if (!setFrequency(probe.activeProbeFreqHz)) return false;
    if (!setRxDoneIrq() || !clearAllIrq()) return false;
    if (!enterContinuousRx()) return false;
    probe.slotStartedMs = millis();
    Serial.printf("Q,STATE,SEARCH,%s,%lu\n", pr.name, probe.activeProbeFreqHz);
    return true;
}

static void stopProbe(const char *reason)
{
    clearAllIrq();
    runMode = RunMode::FIXED;
    tuneRx(fixedFreqHz);
    Serial.printf("Q,STATE,%s,NONE,%lu\n", reason, fixedFreqHz);
}

static bool startProbe(uint32_t freqHz, uint32_t timeoutMs)
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
}

static String toHex(const uint8_t *data, size_t len)
{
    static const char H[] = "0123456789ABCDEF";
    String out;
    out.reserve(len * 2);
    for (size_t i = 0; i < len; ++i) {
        out += H[data[i] >> 4];
        out += H[data[i] & 0x0F];
    }
    return out;
}

static void handleProbePacket()
{
    const ProbeProfile &pr = PROBE_PROFILES[probe.profile];
    uint8_t b[20] = {0};
    const size_t total = (size_t)pr.payloadLen + 6;
    if (!writeCommand(lr1121::RADIO_GET_PACKET) || !readResponse(b, total)) {
        clearAllIrq();
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

    if (sync) {
        ++probe.syncPackets;
        // OTA_Packet4_s: byte0 is type/crcHigh; OTA_Sync_s starts at byte1.
        fhssIndex = payload[1];
        rateIndex = (payload[3] >> 4) & 0x0F;
        if (rateIndex == pr.expectedRateIndex) {
            if (payload[4] == probe.lastUid3 && payload[5] == probe.lastUid4 && payload[6] == probe.lastUid5) {
                if (probe.consistentSync < 255) ++probe.consistentSync;
            } else {
                probe.lastUid3 = payload[4];
                probe.lastUid4 = payload[5];
                probe.lastUid5 = payload[6];
                probe.consistentSync = 1;
            }
        }
    }

    const String hex = toHex(payload, pr.payloadLen);
    Serial.printf("D,%lu,%lu,LORA,%s,%d,%.2f,type=%u,%u,%s\n",
                  millis(), probe.activeProbeFreqHz, pr.name, rssi, snr, type, pr.payloadLen, hex.c_str());
    Serial.printf("Q,STATE,PHY_LOCK,%s,%lu\n", pr.name, probe.activeProbeFreqHz);

    // Strong protocol match: repeated hardware-demodulated ELRS-shaped SYNC packets,
    // constant UID suffix, and rateIndex matching the active ELRS PHY profile.
    // OTA CRC cannot be independently checked before the full UID-derived initializer is known.
    if (!probe.confirmed && sync && rateIndex == pr.expectedRateIndex && probe.consistentSync >= 3) {
        probe.confirmed = true;
        Serial.printf("E,ELRS,CONFIRMED,%s,%lu,%lu,%u,%u\n",
                      pr.name, probe.packets, probe.syncPackets, rateIndex, fhssIndex);
        Serial.printf("Q,STATE,CONFIRMED,%s,%lu\n", pr.name, probe.activeProbeFreqHz);
    }

    clearAllIrq();
    enterContinuousRx();
}

static void probeTick()
{
    const uint32_t now = millis();
    if ((uint32_t)(now - probe.startedMs) >= probe.timeoutMs) {
        if (!probe.confirmed) {
            Serial.printf("E,ELRS,NOT_CONFIRMED,%s,%lu,%lu,255,255\n",
                          PROBE_PROFILES[probe.profile].name, probe.packets, probe.syncPackets);
        }
        stopProbe("TIMEOUT");
        return;
    }

    if (digitalRead(hw::DIO1) == HIGH) handleProbePacket();

    // 12 ms slot gives a chance to catch 50-500 Hz packets while covering the full
    // 80-channel grid in under one second per PHY. Start near marker, then walk grid.
    if (!probe.confirmed && (uint32_t)(now - probe.slotStartedMs) >= 12UL) {
        probe.channel = (uint8_t)((probe.channel + 1) % 80);
        if (probe.channel == 0) probe.profile = (probe.profile + 1) % PROBE_PROFILE_COUNT;
        if (!configureProbeSlot()) stopProbe("ERROR");
    }
}

'''
s = s.replace(marker, probe_code + marker, 1)

s = replace_one(s,
'''    Serial.println("I,cap,packet_probe,NOT_YET_IMPLEMENTED");
    Serial.println("I,protocol,F|S|X|I|A|D|G|T|Z,DIAG");''',
'''    Serial.println("I,cap,packet_probe,ELRS_LORA_DEV1");
    Serial.println("I,cap,elrs_profiles,LORA500|LORA250|LORA150|LORA50");
    Serial.println("I,protocol,F|S|X|I|A|D|G|T|Z,DIAG|Q,ELRS|Q,X");''', "capabilities")

s = replace_one(s,
'''    if (line == "X") {
        if (switchToFixed(fixedFreqHz)) Serial.println("A,X");
        return;
    }''',
'''    if (line == "X") {
        if (runMode == RunMode::PACKET_PROBE) stopProbe("STOPPED");
        else if (switchToFixed(fixedFreqHz)) Serial.println("A,X");
        return;
    }
    if (line == "Q,X") {
        if (runMode == RunMode::PACKET_PROBE) stopProbe("STOPPED");
        else Serial.println("Q,STATE,STOPPED,NONE,0");
        return;
    }
    if (line.startsWith("Q,ELRS,")) {
        unsigned long f = 0, window = 0, timeout = 0;
        if (sscanf(line.c_str(), "Q,ELRS,%lu,%lu,%lu", &f, &window, &timeout) != 3 ||
            f < MIN_FREQ_HZ || f > MAX_FREQ_HZ) {
            Serial.println("E,PROBE_ARGS");
            return;
        }
        (void)window;
        if (!startProbe((uint32_t)f, (uint32_t)timeout)) Serial.println("E,PROBE_START");
        return;
    }''', "probe commands")

s = replace_one(s,
'''    if (runMode == RunMode::FIXED) fixedTick();
    else sweepTick();''',
'''    if (runMode == RunMode::FIXED) fixedTick();
    else if (runMode == RunMode::SWEEP) sweepTick();
    else probeTick();''', "main loop")

p.write_text(s, encoding="utf-8")


# ---------------- Android ----------------
p = Path("rf_finder/android/app/src/main/assets/index.html")
s = p.read_text(encoding="utf-8")

s = replace_one(s, '<button id="goBearing" class="btn primary" disabled>ПЕЛЕНГ</button>',
'''<button id="goBearing" class="btn primary" disabled>ПЕЛЕНГ</button><button id="elrsDetect" class="btn" disabled>ELRS DETECT</button>''', "ELRS button")

s = replace_one(s,
'''<div class="analysis"><span class="label">ФОРМА СИГНАЛА</span><strong id="signalClass">Накопление данных…</strong><small id="signalEvidence">Нужно несколько последовательных sweep</small></div>''',
'''<div class="analysis"><span class="label">ФОРМА СИГНАЛА</span><strong id="signalClass">Накопление данных…</strong><small id="signalEvidence">Нужно несколько последовательных sweep</small><div style="border-top:1px solid var(--hair);margin-top:9px;padding-top:9px"><span class="label">ELRS DETECTOR</span><strong id="elrsResult">Выбери marker</strong><small id="elrsEvidence">Packet Probe · RX-only</small></div></div>''', "ELRS status")

s = replace_one(s,
'''<div id="diagGrid" class="diagGrid"></div><pre id="log" class="log section">—</pre></details>''',
'''<div id="diagGrid" class="diagGrid"></div><div class="section"><div class="label">PACKET PROBE</div><pre id="packetLog" class="log">—</pre></div><pre id="log" class="log section">—</pre></details>''', "packet log")

s = replace_one(s,
"diag:$('diagGrid'),log:$('log'),wfCount:$('waterfallCount')",
"diag:$('diagGrid'),log:$('log'),wfCount:$('waterfallCount'),elrs:$('elrsDetect'),elrsResult:$('elrsResult'),elrsEvidence:$('elrsEvidence'),packetLog:$('packetLog')", "UI refs")

s = replace_one(s,
"let cap={bw:812500,minStep:100000,maxStep:10000000,minDwell:1,maxDwell:100,minAvg:1,maxAvg:32,maxSettle:50000,maxPoints:801},fwDiag={},lastP={duration:null,points:null};",
"let cap={bw:812500,minStep:100000,maxStep:10000000,minDwell:1,maxDwell:100,minAvg:1,maxAvg:32,maxSettle:50000,maxPoints:801,packetProbe:false},fwDiag={},lastP={duration:null,points:null},probeOn=false,packetRows=[];", "Android probe state")

s = replace_one(s,
"function chooseMarker(mhz,db){markerMHz=mhz;markerDb=Number.isFinite(db)?db:null;ui.markerF.textContent=Number.isFinite(mhz)?fmt(mhz)+' МГц':'—';ui.markerD.textContent=markerDb===null?'—':fmt(markerDb)+' dBm';ui.go.disabled=!Number.isFinite(mhz);drawSpectrum()}",
"function chooseMarker(mhz,db){markerMHz=mhz;markerDb=Number.isFinite(db)?db:null;ui.markerF.textContent=Number.isFinite(mhz)?fmt(mhz)+' МГц':'—';ui.markerD.textContent=markerDb===null?'—':fmt(markerDb)+' dBm';ui.go.disabled=!Number.isFinite(mhz)||probeOn;ui.elrs.disabled=!Number.isFinite(mhz)||!cap.packetProbe||probeOn;ui.elrsResult.textContent=Number.isFinite(mhz)?(cap.packetProbe?'Готов к проверке':'Firmware без Packet Probe'):'Выбери marker';drawSpectrum()}", "marker gating")

probe_js = r'''function renderPacketLog(){ui.packetLog.textContent=packetRows.length?packetRows.slice(-30).join('\n'):'—'}
function setProbe(on){probeOn=on;ui.elrs.textContent=on?'■ STOP ELRS':'ELRS DETECT';ui.elrs.disabled=!on&&(!Number.isFinite(markerMHz)||!cap.packetProbe);ui.go.disabled=on||!Number.isFinite(markerMHz);ui.scan.disabled=on}
function startElrs(){if(!Number.isFinite(markerMHz)||!cap.packetProbe)return;if(scanOn)stopScan();packetRows=[];renderPacketLog();setProbe(true);ui.elrsResult.textContent='ПОИСК ELRS…';ui.elrsEvidence.textContent=fmt(markerMHz)+' МГц · 80ch FHSS scan';requestTune(markerMHz);setTimeout(()=>send('Q,ELRS,'+Math.round(markerMHz*1e6)+',80000000,10000'),180)}
function stopElrs(){send('Q,X');setProbe(false)}
'''
if 'function startScan(){' not in s:
    raise RuntimeError("startScan insertion point missing")
s = s.replace('function startScan(){', probe_js + 'function startScan(){', 1)

parse_extra = """if(p[0]==='Q'&&p[1]==='STATE'){const st=p[2]||'',prof=p[3]||'';if(st==='SEARCH'){setProbe(true);ui.elrsResult.textContent='ПОИСК ELRS…';ui.elrsEvidence.textContent=prof}else if(st==='PHY_LOCK'){setProbe(true);ui.elrsResult.textContent='PHY LOCK · '+prof;ui.elrsEvidence.textContent='аппаратно демодулированный LoRa packet'}else if(st==='CONFIRMED'){setProbe(true);ui.elrsResult.textContent='ELRS ПОДТВЕРЖДЁН · '+prof;ui.elrsEvidence.textContent='3 согласованных SYNC · rate/UID evidence'}else if(st==='TIMEOUT'||st==='STOPPED'||st==='ERROR'){setProbe(false);if(st==='TIMEOUT')ui.elrsResult.textContent='ELRS НЕ ПОДТВЕРЖДЁН';else if(st==='ERROR')ui.elrsResult.textContent='Ошибка Packet Probe'}return}if(p[0]==='D'&&p.length>=10){packetRows.push(p.slice(1).join(','));renderPacketLog();return}if(p[0]==='E'&&p[1]==='ELRS'){const level=p[2],prof=p[3];ui.elrsResult.textContent=level==='CONFIRMED'?'ELRS ПОДТВЕРЖДЁН · '+prof:'ELRS НЕ ПОДТВЕРЖДЁН';ui.elrsEvidence.textContent='packets '+(p[4]||0)+' · sync '+(p[5]||0);return}"""
if "if(p[0]==='I'){" not in s:
    raise RuntimeError("I parse marker missing")
s = s.replace("if(p[0]==='I'){", parse_extra + "if(p[0]==='I'){", 1)

s = replace_one(s,
"if(p[2]==='settle_us')cap.maxSettle=Number(p[4])}",
"if(p[2]==='settle_us')cap.maxSettle=Number(p[4]);if(p[2]==='packet_probe'){cap.packetProbe=!!p[3]&&p[3]!=='NOT_YET_IMPLEMENTED';ui.elrs.disabled=!cap.packetProbe||!Number.isFinite(markerMHz)}}", "capability parser")

s = replace_one(s,
"ui.scan.onclick=()=>scanOn?stopScan():startScan();ui.go.onclick=",
"ui.scan.onclick=()=>scanOn?stopScan():startScan();ui.elrs.onclick=()=>probeOn?stopElrs():startElrs();ui.go.onclick=", "ELRS handler")

s = replace_one(s, "const s={app:'0.5.1'", "const s={app:'0.6.0-dev1'", "snapshot version")
s = replace_one(s, 'FPV Club RF Finder v0.5.1 dev · RX-only · field hotfix',
                'FPV Club RF Finder v0.6.0-dev1 · RX-only · ELRS Packet Probe', "footer")
p.write_text(s, encoding="utf-8")

# Android version
g = Path("rf_finder/android/app/build.gradle")
t = g.read_text(encoding="utf-8")
t = replace_one(t, 'versionCode 7', 'versionCode 8', 'versionCode')
t = replace_one(t, "versionName '0.5.1'", "versionName '0.6.0-dev1'", 'versionName')
g.write_text(t, encoding="utf-8")

print("v0.6.0-dev1 source patch applied")
