#include <Arduino.h>
#include <SPI.h>
#include <ESP8266WiFi.h>
#include <math.h>

// Generic 2.4 GHz ELRS Nano RX hardware profile from official ExpressLRS Targets.
// Likely match for the photographed ESP8285 + SX1280/SX1281 + PA/LNA receiver.
// SAFETY INVARIANT: this firmware never issues any SX128x TX command and
// permanently keeps the external TX RF path disabled.
namespace hw {
constexpr int PIN_BUSY = 5;
constexpr int PIN_DIO1 = 4;
constexpr int PIN_MISO = 12;
constexpr int PIN_MOSI = 13;
constexpr int PIN_NSS = 15;
constexpr int PIN_RST = 2;
constexpr int PIN_SCK = 14;
constexpr int PIN_RXEN = 9;
constexpr int PIN_TXEN = 10;
constexpr int PIN_SERIAL_RX = 3;
constexpr int PIN_SERIAL_TX = 1;
constexpr int PIN_BUTTON = 0;
constexpr int PIN_LED = 16;
}

namespace sx128x {
constexpr uint8_t CMD_WRITE_REGISTER = 0x18;
constexpr uint8_t CMD_READ_REGISTER = 0x19;
constexpr uint8_t CMD_SET_STANDBY = 0x80;
constexpr uint8_t CMD_SET_RX = 0x82;
constexpr uint8_t CMD_SET_PACKET_TYPE = 0x8A;
constexpr uint8_t CMD_SET_RF_FREQUENCY = 0x86;
constexpr uint8_t CMD_SET_MOD_PARAMS = 0x8B;
constexpr uint8_t CMD_SET_PACKET_PARAMS = 0x8C;
constexpr uint8_t CMD_SET_REGULATOR_MODE = 0x96;
constexpr uint8_t CMD_GET_RSSI_INST = 0x1F;

constexpr uint16_t REG_FW_VERSION_MSB = 0x0153;
constexpr uint16_t REG_HIGH_SENSITIVITY = 0x0891;

constexpr uint8_t STDBY_RC = 0x00;
constexpr uint8_t USE_DCDC = 0x01;
constexpr uint8_t PACKET_TYPE_LORA = 0x01;
constexpr uint8_t LORA_SF7 = 0x70;
constexpr uint8_t LORA_BW_1600 = 0x0A;
constexpr uint8_t LORA_CR_4_5 = 0x01;
constexpr uint8_t LORA_HEADER_FIXED = 0x80;
constexpr uint8_t LORA_CRC_OFF = 0x00;
constexpr uint8_t LORA_IQ_NORMAL = 0x40;
constexpr uint8_t TICK_15_625_US = 0x00;

constexpr double XTAL_HZ = 52000000.0;
constexpr double FREQ_STEP_HZ = XTAL_HZ / 262144.0;
}

static constexpr char FW_NAME[] = "fpvclub-rf-finder-nano";
static constexpr char FW_VERSION[] = "0.3.0";
static constexpr uint32_t MIN_FREQ_HZ = 2400000000UL;
static constexpr uint32_t MAX_FREQ_HZ = 2480000000UL;
static constexpr uint32_t DEFAULT_FREQ_HZ = 2440000000UL;
static constexpr uint32_t SERIAL_BAUD = 115200;
static constexpr uint8_t FIXED_AVG_SAMPLES = 8;
static constexpr uint8_t SWEEP_AVG_SAMPLES = 4;
static constexpr uint32_t FIXED_SAMPLE_GAP_US = 900;
static constexpr uint32_t SWEEP_SAMPLE_GAP_US = 300;

static SPISettings radioSpi(10000000, MSBFIRST, SPI_MODE0);

enum class RunMode : uint8_t { FIXED, SWEEP };
static RunMode runMode = RunMode::FIXED;
static uint32_t fixedFreqHz = DEFAULT_FREQ_HZ;
static uint32_t activeFreqHz = DEFAULT_FREQ_HZ;

struct SweepConfig {
    uint32_t startHz = 2400000000UL;
    uint32_t stopHz = 2480000000UL;
    uint32_t stepHz = 1000000UL;
    uint32_t dwellMs = 2;
    uint32_t currentHz = 2400000000UL;
    float peakDbm = -200.0f;
    uint32_t peakHz = 2400000000UL;
    uint32_t sweepNumber = 0;
};
static SweepConfig sweep;

static bool waitBusy(uint32_t timeoutUs = 5000)
{
    const uint32_t start = micros();
    while (digitalRead(hw::PIN_BUSY) == HIGH) {
        digitalWrite(hw::PIN_TXEN, LOW);
        if ((uint32_t)(micros() - start) > timeoutUs) return false;
    }
    return true;
}

static void selectRadio()
{
    SPI.beginTransaction(radioSpi);
    digitalWrite(hw::PIN_NSS, LOW);
}

static void deselectRadio()
{
    digitalWrite(hw::PIN_NSS, HIGH);
    SPI.endTransaction();
}

static bool writeCommand(uint8_t cmd, const uint8_t *data, size_t len)
{
    if (!waitBusy()) return false;
    selectRadio();
    SPI.transfer(cmd);
    for (size_t i = 0; i < len; ++i) SPI.transfer(data[i]);
    deselectRadio();
    return waitBusy();
}

static bool readCommand(uint8_t cmd, uint8_t *data, size_t len)
{
    if (!waitBusy()) return false;
    selectRadio();
    SPI.transfer(cmd);
    SPI.transfer(0x00);
    for (size_t i = 0; i < len; ++i) data[i] = SPI.transfer(0x00);
    deselectRadio();
    return waitBusy();
}

static bool readRegister(uint16_t address, uint8_t &value)
{
    if (!waitBusy()) return false;
    selectRadio();
    SPI.transfer(sx128x::CMD_READ_REGISTER);
    SPI.transfer((address >> 8) & 0xFF);
    SPI.transfer(address & 0xFF);
    SPI.transfer(0x00);
    value = SPI.transfer(0x00);
    deselectRadio();
    return waitBusy();
}

static bool writeRegister(uint16_t address, uint8_t value)
{
    if (!waitBusy()) return false;
    selectRadio();
    SPI.transfer(sx128x::CMD_WRITE_REGISTER);
    SPI.transfer((address >> 8) & 0xFF);
    SPI.transfer(address & 0xFF);
    SPI.transfer(value);
    deselectRadio();
    return waitBusy();
}

static void rfFrontEndOff()
{
    digitalWrite(hw::PIN_TXEN, LOW);
    digitalWrite(hw::PIN_RXEN, LOW);
}

static void rfFrontEndRx()
{
    digitalWrite(hw::PIN_TXEN, LOW);
    digitalWrite(hw::PIN_RXEN, HIGH);
}

static void silenceLocalRadios()
{
    WiFi.persistent(false);
    WiFi.mode(WIFI_OFF);
    WiFi.forceSleepBegin();
    delay(1);
}

static bool resetRadio()
{
    rfFrontEndOff();
    digitalWrite(hw::PIN_RST, LOW);
    delay(50);
    digitalWrite(hw::PIN_RST, HIGH);
    delay(50);
    return waitBusy(10000);
}

static bool standby()
{
    const uint8_t p = sx128x::STDBY_RC;
    return writeCommand(sx128x::CMD_SET_STANDBY, &p, 1);
}

static bool programFrequency(uint32_t freqHz)
{
    if (freqHz < MIN_FREQ_HZ || freqHz > MAX_FREQ_HZ) return false;
    const uint32_t reg = (uint32_t)llround((double)freqHz / sx128x::FREQ_STEP_HZ);
    const uint8_t p[3] = {
        (uint8_t)((reg >> 16) & 0xFF),
        (uint8_t)((reg >> 8) & 0xFF),
        (uint8_t)(reg & 0xFF)
    };
    if (!writeCommand(sx128x::CMD_SET_RF_FREQUENCY, p, sizeof(p))) return false;
    activeFreqHz = freqHz;
    return true;
}

static bool enterContinuousRx()
{
    rfFrontEndRx();
    const uint8_t p[3] = { sx128x::TICK_15_625_US, 0xFF, 0xFF };
    return writeCommand(sx128x::CMD_SET_RX, p, sizeof(p));
}

static bool tuneRx(uint32_t freqHz)
{
    rfFrontEndOff();
    if (!standby()) return false;
    if (!programFrequency(freqHz)) return false;
    return enterContinuousRx();
}

static bool initRadio(uint16_t &firmwareRev)
{
    if (!resetRadio()) return false;
    if (!standby()) return false;

    uint8_t fwMsb = 0, fwLsb = 0;
    if (!readRegister(sx128x::REG_FW_VERSION_MSB, fwMsb) ||
        !readRegister(sx128x::REG_FW_VERSION_MSB + 1, fwLsb)) return false;
    firmwareRev = ((uint16_t)fwMsb << 8) | fwLsb;
    if (firmwareRev == 0x0000 || firmwareRev == 0xFFFF) return false;

    uint8_t sensitivity = 0;
    if (!readRegister(sx128x::REG_HIGH_SENSITIVITY, sensitivity)) return false;
    if (!writeRegister(sx128x::REG_HIGH_SENSITIVITY, sensitivity | 0xC0)) return false;

    const uint8_t regulator = sx128x::USE_DCDC;
    if (!writeCommand(sx128x::CMD_SET_REGULATOR_MODE, &regulator, 1)) return false;

    const uint8_t packetType = sx128x::PACKET_TYPE_LORA;
    if (!writeCommand(sx128x::CMD_SET_PACKET_TYPE, &packetType, 1)) return false;

    const uint8_t mod[3] = { sx128x::LORA_SF7, sx128x::LORA_BW_1600, sx128x::LORA_CR_4_5 };
    if (!writeCommand(sx128x::CMD_SET_MOD_PARAMS, mod, sizeof(mod))) return false;

    const uint8_t pkt[7] = {
        12, sx128x::LORA_HEADER_FIXED, 8, sx128x::LORA_CRC_OFF,
        sx128x::LORA_IQ_NORMAL, 0x00, 0x00
    };
    if (!writeCommand(sx128x::CMD_SET_PACKET_PARAMS, pkt, sizeof(pkt))) return false;

    return tuneRx(fixedFreqHz);
}

static bool readRssiDbm(float &dbm)
{
    uint8_t raw = 0;
    if (!readCommand(sx128x::CMD_GET_RSSI_INST, &raw, 1)) return false;
    dbm = -0.5f * (float)raw;
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
    Serial.printf("I,%s,%s,SX128X,RX_ONLY\n", FW_NAME, FW_VERSION);
    Serial.printf("I,range,%lu,%lu\n", MIN_FREQ_HZ, MAX_FREQ_HZ);
    Serial.printf("I,fixed,%lu\n", fixedFreqHz);
    Serial.printf("I,mode,%s\n", runMode == RunMode::FIXED ? "FIXED" : "SWEEP");
    Serial.println("I,protocol,F|S|X|I");
}

static void switchToFixed(uint32_t freqHz)
{
    if (!tuneRx(freqHz)) {
        rfFrontEndOff();
        Serial.println("E,FREQ_SET");
        return;
    }
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

    if (line == "I") {
        printInfo();
        return;
    }

    if (line == "X") {
        switchToFixed(fixedFreqHz);
        Serial.println("A,X");
        return;
    }

    if (line.startsWith("F,")) {
        const uint32_t requested = (uint32_t)strtoul(line.c_str() + 2, nullptr, 10);
        if (requested < MIN_FREQ_HZ || requested > MAX_FREQ_HZ) {
            Serial.println("E,FREQ_RANGE");
            return;
        }
        switchToFixed(requested);
        return;
    }

    if (line.startsWith("S,")) {
        SweepConfig next;
        if (!parseSweep(line, next)) {
            Serial.println("E,SWEEP_ARGS");
            return;
        }
        sweep = next;
        runMode = RunMode::SWEEP;
        Serial.printf("A,S,%lu,%lu,%lu,%lu\n", sweep.startHz, sweep.stopHz, sweep.stepHz, sweep.dwellMs);
        return;
    }

    Serial.println("E,UNKNOWN_CMD");
}

static void pollSerial()
{
    while (Serial.available()) {
        const String line = Serial.readStringUntil('\n');
        handleCommand(line);
    }
}

static void fixedTick()
{
    float rssi = 0.0f;
    if (readAverageRssi(FIXED_AVG_SAMPLES, FIXED_SAMPLE_GAP_US, rssi)) {
        Serial.printf("R,%lu,%.1f,%lu\n", activeFreqHz, rssi, millis());
    } else {
        Serial.println("E,RSSI_READ");
    }
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
    if (!readAverageRssi(SWEEP_AVG_SAMPLES, SWEEP_SAMPLE_GAP_US, rssi)) {
        Serial.printf("E,SWEEP_RSSI,%lu\n", f);
    } else {
        Serial.printf("S,%lu,%.1f,%lu,%lu\n", f, rssi, millis(), sweep.sweepNumber);
        if (rssi > sweep.peakDbm) {
            sweep.peakDbm = rssi;
            sweep.peakHz = f;
        }
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
    pinMode(hw::PIN_BUSY, INPUT);
    pinMode(hw::PIN_DIO1, INPUT);
    pinMode(hw::PIN_NSS, OUTPUT);
    pinMode(hw::PIN_RST, OUTPUT);
    pinMode(hw::PIN_RXEN, OUTPUT);
    pinMode(hw::PIN_TXEN, OUTPUT);

    digitalWrite(hw::PIN_NSS, HIGH);
    digitalWrite(hw::PIN_RST, HIGH);
    rfFrontEndOff();
    silenceLocalRadios();

    Serial.begin(SERIAL_BAUD);
    Serial.setTimeout(20);
    delay(250);
    Serial.printf("B,%s,%s\n", FW_NAME, FW_VERSION);
    Serial.println("A,SELF_RF_OFF");

    SPI.begin();

    uint16_t radioFw = 0;
    if (!initRadio(radioFw)) {
        rfFrontEndOff();
        Serial.println("E,RADIO_INIT");
        while (true) {
            digitalWrite(hw::PIN_TXEN, LOW);
            delay(1000);
        }
    }

    Serial.printf("A,RADIO_INIT,0x%04X\n", radioFw);
    printInfo();
}

void loop()
{
    digitalWrite(hw::PIN_TXEN, LOW);

    pollSerial();
    if (runMode == RunMode::FIXED) fixedTick();
    else sweepTick();
}
