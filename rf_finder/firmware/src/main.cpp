#include <Arduino.h>
#include <SPI.h>
#include <WiFi.h>

namespace hw {
constexpr int SERIAL_RX = 20;
constexpr int SERIAL_TX = 21;
constexpr int MISO = 5;
constexpr int MOSI = 4;
constexpr int SCK = 6;
constexpr int BUSY = 3;
constexpr int DIO1 = 1;
constexpr int NSS = 7;
constexpr int RST = 2;
constexpr int RGB = 8;
constexpr int BUTTON = 9;
}

namespace lr1121 {
constexpr uint16_t SYS_GET_VERSION = 0x0101;
constexpr uint16_t SYS_CLEAR_ERRORS = 0x010E;
constexpr uint16_t SYS_SET_REGMODE = 0x0110;
constexpr uint16_t SYS_CALIBRATE_IMAGE = 0x0111;
constexpr uint16_t SYS_SET_DIO_AS_RF_SWITCH = 0x0112;
constexpr uint16_t SYS_SET_STANDBY = 0x011C;
constexpr uint16_t RADIO_GET_RSSI_INST = 0x0205;
constexpr uint16_t RADIO_SET_RX = 0x0209;
constexpr uint16_t RADIO_SET_RF_FREQUENCY = 0x020B;
constexpr uint16_t RADIO_SET_PKT_TYPE = 0x020E;
constexpr uint16_t RADIO_SET_MOD_PARAMS = 0x020F;
constexpr uint16_t RADIO_SET_PKT_PARAMS = 0x0210;
constexpr uint16_t RADIO_SET_RX_TX_FALLBACK = 0x0213;
constexpr uint16_t RADIO_SET_RX_BOOSTED = 0x0227;

constexpr uint8_t PKT_LORA = 0x02;
constexpr uint8_t LORA_SF7 = 0x07;
constexpr uint8_t LORA_BW_800 = 0x0F;
constexpr uint8_t LORA_CR_4_5 = 0x01;
constexpr uint8_t LORA_FIXED = 0x01;
constexpr uint8_t LORA_CRC_OFF = 0x00;
constexpr uint8_t LORA_IQ_STANDARD = 0x00;
}

static constexpr char FW_NAME[] = "fpvclub-rf-finder-lr1121";
static constexpr char FW_VERSION[] = "0.5.0-dev1";
static constexpr char PROTOCOL_VERSION[] = "0.5";
static constexpr uint32_t MIN_FREQ_HZ = 2400000000UL;
static constexpr uint32_t MAX_FREQ_HZ = 2480000000UL;
static constexpr uint32_t DEFAULT_FREQ_HZ = 2440000000UL;
static constexpr uint32_t SERIAL_BAUD = 115200;
static constexpr uint8_t MIN_AVG_SAMPLES = 1;
static constexpr uint8_t MAX_AVG_SAMPLES = 32;
static constexpr uint32_t MIN_STEP_HZ = 100000UL;
static constexpr uint32_t MAX_STEP_HZ = 10000000UL;
static constexpr uint32_t MIN_DWELL_MS = 1;
static constexpr uint32_t MAX_DWELL_MS = 100;
static constexpr uint32_t MAX_SETTLE_US = 50000UL;
static constexpr uint32_t MAX_SWEEP_POINTS = 801;
static constexpr uint32_t RX_BW_HZ = 812500UL;

static SPISettings radioSpi(16000000, MSBFIRST, SPI_MODE0);

enum class RunMode : uint8_t { FIXED, SWEEP };
static RunMode runMode = RunMode::FIXED;
static uint32_t fixedFreqHz = DEFAULT_FREQ_HZ;
static uint32_t activeFreqHz = DEFAULT_FREQ_HZ;
static uint32_t radioVersionWord = 0;
static uint8_t fixedAvgSamples = 8;
static uint8_t sweepAvgSamples = 4;
static uint32_t settleDelayUs = 0;
static bool rxBoosted = true;

struct Diagnostics {
    uint32_t busyTimeout = 0;
    uint32_t commandFail = 0;
    uint32_t responseFail = 0;
    uint32_t tuneFail = 0;
    uint32_t rssiReadFail = 0;
    uint32_t rssiSamples = 0;
    uint32_t sweepPoints = 0;
    uint32_t sweepsCompleted = 0;
    uint32_t uartCommands = 0;
    uint32_t unknownCommands = 0;
    uint32_t recoveries = 0;
    uint32_t lastSweepDurationMs = 0;
};
static Diagnostics diag;

struct SweepConfig {
    uint32_t startHz = MIN_FREQ_HZ;
    uint32_t stopHz = MAX_FREQ_HZ;
    uint32_t stepHz = 1000000UL;
    uint32_t dwellMs = 2;
    uint32_t currentHz = MIN_FREQ_HZ;
    float peakDbm = -200.0f;
    uint32_t peakHz = MIN_FREQ_HZ;
    uint32_t sweepNumber = 0;
    uint32_t startedMs = 0;
    uint32_t pointsThisSweep = 0;
};
static SweepConfig sweep;

static const char *modeName()
{
    return runMode == RunMode::FIXED ? "FIXED" : "SWEEP";
}

static bool waitBusy(uint32_t timeoutUs = 4000)
{
    const uint32_t start = micros();
    while (digitalRead(hw::BUSY) == HIGH) {
        if ((uint32_t)(micros() - start) > timeoutUs) {
            ++diag.busyTimeout;
            return false;
        }
    }
    return true;
}

static void selectRadio()
{
    SPI.beginTransaction(radioSpi);
    digitalWrite(hw::NSS, LOW);
}

static void deselectRadio()
{
    digitalWrite(hw::NSS, HIGH);
    SPI.endTransaction();
}

static bool writeCommand(uint16_t cmd, const uint8_t *data = nullptr, size_t len = 0)
{
    if (!waitBusy()) { ++diag.commandFail; return false; }
    selectRadio();
    SPI.transfer((uint8_t)(cmd >> 8));
    SPI.transfer((uint8_t)(cmd & 0xFF));
    for (size_t i = 0; i < len; ++i) SPI.transfer(data[i]);
    deselectRadio();
    if (!waitBusy()) { ++diag.commandFail; return false; }
    return true;
}

static bool readResponse(uint8_t *data, size_t len)
{
    if (!waitBusy()) { ++diag.responseFail; return false; }
    selectRadio();
    for (size_t i = 0; i < len; ++i) data[i] = SPI.transfer(0x00);
    deselectRadio();
    if (!waitBusy()) { ++diag.responseFail; return false; }
    return true;
}

static void silenceWifi()
{
    WiFi.mode(WIFI_OFF);
    delay(5);
}

static bool resetRadio()
{
    digitalWrite(hw::RST, LOW);
    delay(2);
    digitalWrite(hw::RST, HIGH);
    delay(320);
    return waitBusy(10000);
}

static bool standby()
{
    const uint8_t p = 0x00;
    return writeCommand(lr1121::SYS_SET_STANDBY, &p, 1);
}

static bool configureRfSwitch()
{
    const uint8_t p[8] = {
        0b00001111,
        0b00000000,
        0b00000100,
        0b00001000,
        0b00001000,
        0b00000010,
        0,
        0b00000001
    };
    return writeCommand(lr1121::SYS_SET_DIO_AS_RF_SWITCH, p, sizeof(p));
}

static bool setFrequency(uint32_t freqHz)
{
    if (freqHz < MIN_FREQ_HZ || freqHz > MAX_FREQ_HZ) return false;
    const uint8_t p[4] = {
        (uint8_t)(freqHz >> 24),
        (uint8_t)(freqHz >> 16),
        (uint8_t)(freqHz >> 8),
        (uint8_t)freqHz
    };
    if (!writeCommand(lr1121::RADIO_SET_RF_FREQUENCY, p, sizeof(p))) return false;
    activeFreqHz = freqHz;
    return true;
}

static bool enterContinuousRx()
{
    const uint8_t p[3] = {0xFF, 0xFF, 0xFF};
    return writeCommand(lr1121::RADIO_SET_RX, p, sizeof(p));
}

static bool tuneRx(uint32_t freqHz)
{
    if (!standby() || !setFrequency(freqHz) || !enterContinuousRx()) {
        ++diag.tuneFail;
        return false;
    }
    return true;
}

static void waitSettle()
{
    if (settleDelayUs == 0) return;
    if (settleDelayUs >= 1000) delay(settleDelayUs / 1000);
    const uint32_t tail = settleDelayUs % 1000;
    if (tail) delayMicroseconds(tail);
}

static bool setBoosted(bool enabled)
{
    if (!standby()) return false;
    const uint8_t p = enabled ? 1 : 0;
    if (!writeCommand(lr1121::RADIO_SET_RX_BOOSTED, &p, 1)) return false;
    if (!enterContinuousRx()) return false;
    rxBoosted = enabled;
    return true;
}

static bool initRadio(uint32_t &versionWord)
{
    if (!resetRadio() || !standby()) return false;

    if (!writeCommand(lr1121::SYS_GET_VERSION)) return false;
    uint8_t ver[5] = {0};
    if (!readResponse(ver, sizeof(ver))) return false;
    versionWord = ((uint32_t)ver[1] << 24) | ((uint32_t)ver[2] << 16) | ((uint32_t)ver[3] << 8) | ver[4];
    if ((ver[1] == 0 && ver[2] == 0 && ver[3] == 0 && ver[4] == 0) ||
        (ver[1] == 0xFF && ver[2] == 0xFF && ver[3] == 0xFF && ver[4] == 0xFF)) return false;

    if (!writeCommand(lr1121::SYS_CLEAR_ERRORS)) return false;

    const uint8_t fallback = 0x03;
    if (!writeCommand(lr1121::RADIO_SET_RX_TX_FALLBACK, &fallback, 1)) return false;

    const uint8_t boosted = 1;
    if (!writeCommand(lr1121::RADIO_SET_RX_BOOSTED, &boosted, 1)) return false;
    rxBoosted = true;

    if (!configureRfSwitch()) return false;

    const uint8_t regulator = 1;
    if (!writeCommand(lr1121::SYS_SET_REGMODE, &regulator, 1)) return false;

    const uint8_t cal[2] = {
        (uint8_t)(((MIN_FREQ_HZ / 1000000UL) - 1) / 4),
        (uint8_t)(1 + ((MAX_FREQ_HZ / 1000000UL) + 1) / 4)
    };
    if (!writeCommand(lr1121::SYS_CALIBRATE_IMAGE, cal, sizeof(cal))) return false;

    const uint8_t pktType = lr1121::PKT_LORA;
    if (!writeCommand(lr1121::RADIO_SET_PKT_TYPE, &pktType, 1)) return false;

    const uint8_t mod[4] = {lr1121::LORA_SF7, lr1121::LORA_BW_800, lr1121::LORA_CR_4_5, 0x00};
    if (!writeCommand(lr1121::RADIO_SET_MOD_PARAMS, mod, sizeof(mod))) return false;

    const uint8_t pkt[6] = {0x00, 12, lr1121::LORA_FIXED, 8, lr1121::LORA_CRC_OFF, lr1121::LORA_IQ_STANDARD};
    if (!writeCommand(lr1121::RADIO_SET_PKT_PARAMS, pkt, sizeof(pkt))) return false;

    return tuneRx(fixedFreqHz);
}

static bool readRssiDbm(float &dbm)
{
    if (!writeCommand(lr1121::RADIO_GET_RSSI_INST)) { ++diag.rssiReadFail; return false; }
    uint8_t status[2] = {0};
    if (!readResponse(status, sizeof(status))) { ++diag.rssiReadFail; return false; }
    dbm = -0.5f * (float)status[1];
    if (dbm > 0.0f || dbm < -180.0f) { ++diag.rssiReadFail; return false; }
    ++diag.rssiSamples;
    return true;
}

static bool readAverageRssi(uint8_t samples, uint32_t gapUs, float &avg)
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
}

static void printDiagnostics()
{
    Serial.printf("I,diag,busy_timeout,%lu\n", diag.busyTimeout);
    Serial.printf("I,diag,command_fail,%lu\n", diag.commandFail);
    Serial.printf("I,diag,response_fail,%lu\n", diag.responseFail);
    Serial.printf("I,diag,tune_fail,%lu\n", diag.tuneFail);
    Serial.printf("I,diag,rssi_fail,%lu\n", diag.rssiReadFail);
    Serial.printf("I,diag,rssi_samples,%lu\n", diag.rssiSamples);
    Serial.printf("I,diag,sweep_points,%lu\n", diag.sweepPoints);
    Serial.printf("I,diag,sweeps,%lu\n", diag.sweepsCompleted);
    Serial.printf("I,diag,uart_commands,%lu\n", diag.uartCommands);
    Serial.printf("I,diag,unknown_commands,%lu\n", diag.unknownCommands);
    Serial.printf("I,diag,recoveries,%lu\n", diag.recoveries);
    Serial.printf("I,diag,last_sweep_ms,%lu\n", diag.lastSweepDurationMs);
}

static void printInfo()
{
    Serial.printf("I,%s,%s,LR1121,RX_ONLY\n", FW_NAME, FW_VERSION);
    Serial.printf("I,range,%lu,%lu\n", MIN_FREQ_HZ, MAX_FREQ_HZ);
    Serial.printf("I,fixed,%lu\n", fixedFreqHz);
    Serial.printf("I,mode,%s\n", modeName());
    Serial.printf("I,config,avg_fixed,%u\n", fixedAvgSamples);
    Serial.printf("I,config,avg_sweep,%u\n", sweepAvgSamples);
    Serial.printf("I,config,settle_us,%lu\n", settleDelayUs);
    Serial.printf("I,config,gain,%s\n", rxBoosted ? "BOOSTED" : "NORMAL");
    Serial.printf("I,cap,protocol,%s\n", PROTOCOL_VERSION);
    Serial.printf("I,cap,step_hz,%lu,%lu\n", MIN_STEP_HZ, MAX_STEP_HZ);
    Serial.printf("I,cap,dwell_ms,%lu,%lu\n", MIN_DWELL_MS, MAX_DWELL_MS);
    Serial.printf("I,cap,avg_samples,%u,%u\n", MIN_AVG_SAMPLES, MAX_AVG_SAMPLES);
    Serial.printf("I,cap,settle_us,0,%lu\n", MAX_SETTLE_US);
    Serial.printf("I,cap,max_points,%lu\n", MAX_SWEEP_POINTS);
    Serial.printf("I,cap,bw_hz,%lu\n", RX_BW_HZ);
    Serial.println("I,cap,gain,NORMAL|BOOSTED");
    Serial.println("I,cap,packet_probe,NOT_YET_IMPLEMENTED");
    Serial.println("I,protocol,F|S|X|I|A|D|G|T|Z,DIAG");
    printDiagnostics();
}

static bool switchToFixed(uint32_t freqHz)
{
    if (!tuneRx(freqHz)) {
        Serial.println("E,FREQ_SET");
        return false;
    }
    fixedFreqHz = freqHz;
    runMode = RunMode::FIXED;
    Serial.printf("A,F,%lu\n", fixedFreqHz);
    return true;
}

static bool parseSweep(const String &line, SweepConfig &cfg)
{
    unsigned long start = 0, stop = 0, step = 0, dwell = 0;
    if (sscanf(line.c_str(), "S,%lu,%lu,%lu,%lu", &start, &stop, &step, &dwell) != 4) return false;
    if (start < MIN_FREQ_HZ || stop > MAX_FREQ_HZ || start >= stop) return false;
    if (step < MIN_STEP_HZ || step > MAX_STEP_HZ) return false;
    if (dwell < MIN_DWELL_MS || dwell > MAX_DWELL_MS) return false;
    const uint32_t points = ((uint32_t)stop - (uint32_t)start) / (uint32_t)step + 1;
    if (points < 2 || points > MAX_SWEEP_POINTS) return false;
    cfg.startHz = (uint32_t)start;
    cfg.stopHz = (uint32_t)stop;
    cfg.stepHz = (uint32_t)step;
    cfg.dwellMs = (uint32_t)dwell;
    cfg.currentHz = cfg.startHz;
    cfg.peakDbm = -200.0f;
    cfg.peakHz = cfg.startHz;
    cfg.sweepNumber = 0;
    cfg.startedMs = 0;
    cfg.pointsThisSweep = 0;
    return true;
}

static void resetDiagnostics()
{
    diag = Diagnostics{};
    Serial.println("A,Z,DIAG");
}

static void selfTest()
{
    if (runMode != RunMode::FIXED) {
        Serial.println("T,FAIL,MODE_NOT_FIXED");
        return;
    }
    Serial.printf("T,BEGIN,%lu\n", millis());
    Serial.printf("T,RADIO_VERSION,0x%08lX\n", radioVersionWord);
    Serial.printf("T,BUSY,%d\n", digitalRead(hw::BUSY));
    Serial.printf("T,DIO1,%d\n", digitalRead(hw::DIO1));
    Serial.printf("T,FREQ,%lu\n", activeFreqHz);
    Serial.printf("T,GAIN,%s\n", rxBoosted ? "BOOSTED" : "NORMAL");
    Serial.printf("T,BW,%lu\n", RX_BW_HZ);
    float rssi = 0.0f;
    if (readRssiDbm(rssi)) Serial.printf("T,RSSI,OK,%.1f\n", rssi);
    else Serial.println("T,RSSI,FAIL");
    Serial.printf("T,UPTIME_MS,%lu\n", millis());
    Serial.printf("T,FREE_HEAP,%u\n", ESP.getFreeHeap());
    Serial.printf("T,END,%s\n", diag.busyTimeout == 0 ? "PASS" : "WARN_BUSY_TIMEOUT");
}

static void handleCommand(String line)
{
    line.trim();
    if (line.length() == 0) return;
    ++diag.uartCommands;

    if (line == "I") { printInfo(); return; }
    if (line == "T") { selfTest(); return; }
    if (line == "Z,DIAG") { resetDiagnostics(); return; }
    if (line == "X") {
        if (switchToFixed(fixedFreqHz)) Serial.println("A,X");
        return;
    }
    if (line.startsWith("F,")) {
        const uint32_t f = strtoul(line.c_str() + 2, nullptr, 10);
        if (f < MIN_FREQ_HZ || f > MAX_FREQ_HZ) { Serial.println("E,FREQ_RANGE"); return; }
        switchToFixed(f);
        return;
    }
    if (line.startsWith("A,")) {
        unsigned long a = 0, b = 0;
        const int n = sscanf(line.c_str(), "A,%lu,%lu", &a, &b);
        if (n < 1 || a < MIN_AVG_SAMPLES || a > MAX_AVG_SAMPLES ||
            (n == 2 && (b < MIN_AVG_SAMPLES || b > MAX_AVG_SAMPLES))) {
            Serial.println("E,AVG_ARGS");
            return;
        }
        fixedAvgSamples = (uint8_t)a;
        sweepAvgSamples = (uint8_t)(n == 2 ? b : a);
        Serial.printf("A,AVG,%u,%u\n", fixedAvgSamples, sweepAvgSamples);
        return;
    }
    if (line.startsWith("D,")) {
        const uint32_t us = strtoul(line.c_str() + 2, nullptr, 10);
        if (us > MAX_SETTLE_US) { Serial.println("E,SETTLE_RANGE"); return; }
        settleDelayUs = us;
        Serial.printf("A,SETTLE,%lu\n", settleDelayUs);
        return;
    }
    if (line == "G,NORMAL" || line == "G,BOOSTED") {
        const bool boosted = line.endsWith("BOOSTED");
        if (!setBoosted(boosted)) { Serial.println("E,GAIN_SET"); return; }
        Serial.printf("A,GAIN,%s\n", rxBoosted ? "BOOSTED" : "NORMAL");
        return;
    }
    if (line.startsWith("S,")) {
        SweepConfig next;
        if (!parseSweep(line, next)) { Serial.println("E,SWEEP_ARGS"); return; }
        sweep = next;
        runMode = RunMode::SWEEP;
        Serial.printf("A,S,%lu,%lu,%lu,%lu,%u,%lu\n",
                      sweep.startHz, sweep.stopHz, sweep.stepHz, sweep.dwellMs,
                      sweepAvgSamples, settleDelayUs);
        return;
    }

    ++diag.unknownCommands;
    Serial.println("E,UNKNOWN_CMD");
}

static void pollSerial()
{
    while (Serial.available()) handleCommand(Serial.readStringUntil('\n'));
}

static void fixedTick()
{
    float rssi = 0.0f;
    if (readAverageRssi(fixedAvgSamples, 900, rssi))
        Serial.printf("R,%lu,%.1f,%lu\n", activeFreqHz, rssi, millis());
    else
        Serial.println("E,RSSI_READ");
}

static void recoverFixed()
{
    ++diag.recoveries;
    switchToFixed(fixedFreqHz);
}

static void sweepTick()
{
    const uint32_t f = sweep.currentHz;
    if (sweep.pointsThisSweep == 0) sweep.startedMs = millis();

    if (!tuneRx(f)) {
        Serial.printf("E,SWEEP_TUNE,%lu\n", f);
        recoverFixed();
        return;
    }
    waitSettle();
    delay(sweep.dwellMs);

    float rssi = -200.0f;
    if (readAverageRssi(sweepAvgSamples, 300, rssi)) {
        Serial.printf("S,%lu,%.1f,%lu,%lu\n", f, rssi, millis(), sweep.sweepNumber);
        if (rssi > sweep.peakDbm) { sweep.peakDbm = rssi; sweep.peakHz = f; }
    } else {
        Serial.printf("E,SWEEP_RSSI,%lu\n", f);
    }
    ++sweep.pointsThisSweep;
    ++diag.sweepPoints;

    if (f >= sweep.stopHz || (sweep.stopHz - f) < sweep.stepHz) {
        diag.lastSweepDurationMs = millis() - sweep.startedMs;
        ++diag.sweepsCompleted;
        Serial.printf("P,%lu,%.1f,%lu,%lu,%lu,%lu\n",
                      sweep.peakHz, sweep.peakDbm, millis(), sweep.sweepNumber,
                      diag.lastSweepDurationMs, sweep.pointsThisSweep);
        ++sweep.sweepNumber;
        sweep.currentHz = sweep.startHz;
        sweep.peakDbm = -200.0f;
        sweep.peakHz = sweep.startHz;
        sweep.startedMs = 0;
        sweep.pointsThisSweep = 0;
    } else {
        sweep.currentHz = f + sweep.stepHz;
    }
}

void setup()
{
    pinMode(hw::BUSY, INPUT);
    pinMode(hw::DIO1, INPUT);
    pinMode(hw::NSS, OUTPUT);
    pinMode(hw::RST, OUTPUT);
    digitalWrite(hw::NSS, HIGH);
    digitalWrite(hw::RST, HIGH);

    silenceWifi();
    Serial.begin(SERIAL_BAUD, SERIAL_8N1, hw::SERIAL_RX, hw::SERIAL_TX);
    Serial.setTimeout(25);
    delay(100);

    SPI.begin(hw::SCK, hw::MISO, hw::MOSI, hw::NSS);

    Serial.printf("B,%s,%s\n", FW_NAME, FW_VERSION);
    if (!initRadio(radioVersionWord)) {
        Serial.println("E,RADIO_INIT");
        while (true) delay(1000);
    }
    Serial.printf("A,RADIO_INIT,0x%08lX\n", radioVersionWord);
    printInfo();
}

void loop()
{
    pollSerial();
    if (runMode == RunMode::FIXED) fixedTick();
    else sweepTick();
}
