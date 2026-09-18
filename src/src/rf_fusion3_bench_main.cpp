#if defined(RF_FUSION3_BENCH)

#include <Arduino.h>
#include "targets.h"
#include "SX1280Driver.h"
#include "fusion3_profiles.h"
#include "fusion3_sx1280_backend.h"
#include "fusion3_bench_node.h"

using namespace rf_fusion3;

SX1280Driver Radio;

namespace {

constexpr uint32_t kFrequencyHz = 2440000000UL;
// Calibration is intentionally zero for first SPI/ranging bring-up.
// Do not treat filtered output as calibrated distance until bench calibration.
constexpr uint16_t kInitialCalibration = 0;
const uint32_t kFrequencyReg = (uint32_t)((double)kFrequencyHz / (double)FREQ_STEP);

class SerialLineSink final : public LineSink {
public:
    void writeLine(const char* line) override {
        if (line) Serial.println(line);
    }
};

SerialLineSink sink;

#if defined(RF_FUSION3_NODE_A)
Sx1280RangingBackend backend(Radio, kNodeA, kBenchFast, kFrequencyReg, kInitialCalibration);
BenchCoordinatorApp app(backend, sink);
#elif defined(RF_FUSION3_NODE_T)
Sx1280RangingBackend backend(Radio, kNodeT, kBenchFast, kFrequencyReg, kInitialCalibration);
BenchTargetApp app(backend, &sink);
#else
#error "Define RF_FUSION3_NODE_A or RF_FUSION3_NODE_T"
#endif

char inputLine[256];
size_t inputLen = 0;

void printBootError(const char* code) {
    Serial.print("F3,ERR,");
    Serial.print(code);
    Serial.println(",0,boot");
}

#if defined(RF_FUSION3_NODE_A)
void pollHostUart() {
    while (Serial.available() > 0) {
        const int ch = Serial.read();
        if (ch < 0) break;
        if (ch == '\r') continue;
        if (ch == '\n') {
            inputLine[inputLen] = '\0';
            if (inputLen > 0) app.onHostLine(inputLine, millis());
            inputLen = 0;
            continue;
        }
        if (inputLen + 1 < sizeof(inputLine)) {
            inputLine[inputLen++] = (char)ch;
        } else {
            inputLen = 0;
            Serial.println("F3,ERR,UART_LINE_TOO_LONG,0,discarded");
        }
    }
}
#endif

} // namespace

void setup() {
    Serial.begin(115200);
    delay(800);

    if (!Radio.Begin()) {
        printBootError("SX1280_BEGIN");
        return;
    }

    backend.setDefaultSigmaMm(1500);
    backend.setCalibrationId("UNCAL");

#if defined(RF_FUSION3_NODE_A)
    if (!app.begin("0.1.0-benchA", millis())) {
        printBootError("A_BEGIN");
        return;
    }
    Serial.println("F3,ACK,BOOT,0,READY,A");
#elif defined(RF_FUSION3_NODE_T)
    if (!app.begin("A", millis())) {
        printBootError("T_BEGIN");
        return;
    }
    Serial.println("F3,ACK,BOOT,0,READY,T");
#endif
}

void loop() {
#if defined(RF_FUSION3_NODE_A)
    pollHostUart();
    app.tick(millis());
#elif defined(RF_FUSION3_NODE_T)
    app.tick(millis());
#endif
    delay(1);
}

#endif // RF_FUSION3_BENCH
