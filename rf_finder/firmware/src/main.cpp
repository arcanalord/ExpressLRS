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
static constexpr char FW_VERSION[] = "0.4.0";
static constexpr uint32_t MIN_FREQ_HZ = 2400000000UL;
static constexpr uint32_t MAX_FREQ_HZ = 2480000000UL;
static constexpr uint32_t DEFAULT_FREQ_HZ = 2440000000UL;
static constexpr uint32_t SERIAL_BAUD = 115200;
static constexpr uint8_t FIXED_AVG_SAMPLES = 8;
static constexpr uint8_t SWEEP_AVG_SAMPLES = 4;

static SPISettings radioSpi(16000000, MSBFIRST, SPI_MODE0);

enum class RunMode : uint8_t { FIXED, SWEEP };
static RunMode runMode = RunMode::FIXED;
static uint32_t fixedFreqHz = DEFAULT_FREQ_HZ;
static uint32_t activeFreqHz = DEFAULT_FREQ_HZ;

struct SweepConfig {
    uint32_t startHz = MIN_FREQ_HZ;
    uint32_t stopHz = MAX_FREQ_HZ;
    uint32_t stepHz = 1000000UL;
    uint32_t dwellMs = 2;
    uint32_t currentHz = MIN_FREQ_HZ;
    float peakDbm = -200.0f;
    uint32_t peakHz = MIN_FREQ_HZ;
    uint32_t sweepNumber = 0;
};
static SweepConfig sweep;

static bool waitBusy(uint32_t timeoutUs = 4000)
{
    const uint32_t start = micros();
    while (digitalRead(hw::BUSY) == HIGH) {
        if ((uint32_t)(micros() - start) > timeoutUs) return false;
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
    if (!waitBusy()) return false;
    selectRadio();
    SPI.transfer((uint8_t)(cmd >> 8));
    SPI.transfer((uint8_t)(cmd & 0xFF));
    for (size_t i = 0; i < len; ++i) SPI.transfer(data[i]);
    deselectRadio();
    return waitBusy();
}

static bool readResponse(uint8_t *data, size_t len)
{
    if (!waitBusy()) return false;
    selectRadio();
    for (size_t i = 0; i < len; ++i) data[i] = SPI.transfer(0x00);
    deselectRadio();
    return waitBusy();
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
    if (!standby()) return false;
    if (!setFrequency(freqHz)) return false;
    return enterContinuousRx();
}

static bool initRadio(uint32_t &versionWord)
{
    if (!resetRadio()) return false;
    if (!standby()) return false;

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
    if (!writeCommand(lr1121::RADIO_GET_RSSI_INST)) return false;
    uint8_t status[2] = {0};
    if (!readResponse(status, sizeof(status))) return false;
    dbm = -0.5f * (float)status[1];
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

static void printInfo()
{
    Serial.printf("I,%s,%s,LR1121,RX_ONLY\n", FW_NAME, FW_VERSION);
    Serial.printf("I,range,%lu,%lu\n", MIN_FREQ_HZ, MAX_FREQ_HZ);
    Serial.printf("I,fixed,%lu\n", fixedFreqHz);
    Serial.printf("I,mode,%s\n", runMode == RunMode::FIXED ? "FIXED" : "SWEEP");
    Serial.println("I,protocol,F|S|X|I");
}

static void switchToFixed(uint32_t freqHz)
{
    if (!tuneRx(freqHz)) { Serial.println("E,FREQ_SET"); return; }
    fixedFreqHz = freqHz;
    runMode = RunMode::FIXED;
    Serial.printf("A,F,%lu\n", fixedFreqHz);
}

static bool parseSweep(const String &line, SweepConfig &cfg)
{
    unsigned long start = 0, stop = 0, step = 0, dwell = 0;
    if (sscanf(line.c_str(), "S,%lu,%lu,%lu,%lu", &start, &stop, &step, &dwell) != 4) return false;
    if (start < MIN_FREQ_HZ || stop > MAX_FREQ_HZ || start >= stop) return false;
    if (step < 100000UL || step > 10000000UL) return false;
    if (dwell < 1 || dwell > 100) return false;
    const uint32_t points = ((uint32_t)stop - (uint32_t)start) / (uint32_t)step + 1;
    if (points < 2 || points > 801) return false;
    cfg.startHz = (uint32_t)start;
    cfg.stopHz = (uint32_t)stop;
    cfg.stepHz = (uint32_t)step;
    cfg.dwellMs = (uint32_t)dwell;
    cfg.currentHz = cfg.startHz;
    cfg.peakDbm = -200.0f;
    cfg.peakHz = cfg.startHz;
    cfg.sweepNumber = 0;
    return true;
}

static void handleCommand(String line)
{
    line.trim();
    if (line.length() == 0) return;
    if (line == "I") { printInfo(); return; }
    if (line == "X") { switchToFixed(fixedFreqHz); Serial.println("A,X"); return; }
    if (line.startsWith("F,")) {
        const uint32_t f = strtoul(line.c_str() + 2, nullptr, 10);
        if (f < MIN_FREQ_HZ || f > MAX_FREQ_HZ) { Serial.println("E,FREQ_RANGE"); return; }
        switchToFixed(f);
        return;
    }
    if (line.startsWith("S,")) {
        SweepConfig next;
        if (!parseSweep(line, next)) { Serial.println("E,SWEEP_ARGS"); return; }
        sweep = next;
        runMode = RunMode::SWEEP;
        Serial.printf("A,S,%lu,%lu,%lu,%lu\n", sweep.startHz, sweep.stopHz, sweep.stepHz, sweep.dwellMs);
        return;
    }
    Serial.println("E,UNKNOWN_CMD");
}

static void pollSerial()
{
    while (Serial.available()) handleCommand(Serial.readStringUntil('\n'));
}

static void fixedTick()
{
    float rssi = 0.0f;
    if (readAverageRssi(FIXED_AVG_SAMPLES, 900, rssi))
        Serial.printf("R,%lu,%.1f,%lu\n", activeFreqHz, rssi, millis());
    else
        Serial.println("E,RSSI_READ");
}

static void sweepTick()
{
    const uint32_t f = sweep.currentHz;
    if (!tuneRx(f)) {
        Serial.printf("E,SWEEP_TUNE,%lu\n", f);
        switchToFixed(fixedFreqHz);
        return;
    }
    delay(sweep.dwellMs);
    float rssi = -200.0f;
    if (readAverageRssi(SWEEP_AVG_SAMPLES, 300, rssi)) {
        Serial.printf("S,%lu,%.1f,%lu,%lu\n", f, rssi, millis(), sweep.sweepNumber);
        if (rssi > sweep.peakDbm) { sweep.peakDbm = rssi; sweep.peakHz = f; }
    } else {
        Serial.printf("E,SWEEP_RSSI,%lu\n", f);
    }
    if (f >= sweep.stopHz || (sweep.stopHz - f) < sweep.stepHz) {
        Serial.printf("P,%lu,%.1f,%lu,%lu\n", sweep.peakHz, sweep.peakDbm, millis(), sweep.sweepNumber);
        ++sweep.sweepNumber;
        sweep.currentHz = sweep.startHz;
        sweep.peakDbm = -200.0f;
        sweep.peakHz = sweep.startHz;
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
    uint32_t radioVersion = 0;
    if (!initRadio(radioVersion)) {
        Serial.println("E,RADIO_INIT");
        while (true) delay(1000);
    }
    Serial.printf("A,RADIO_INIT,0x%08lX\n", radioVersion);
    printInfo();
}

void loop()
{
    pollSerial();
    if (runMode == RunMode::FIXED) fixedTick();
    else sweepTick();
}
