#pragma once
#include <cstdint>
#include <cstdio>
#include <cstring>
#include "fusion3_protocol.h"
#include "fusion3_controller.h"
#include "fusion3_profiles.h"
#include "fusion3_sx1280_backend.h"

namespace rf_fusion3 {

class LineSink {
public:
    virtual ~LineSink() = default;
    virtual void writeLine(const char* line) = 0;
};

class BenchCoordinatorApp {
public:
    BenchCoordinatorApp(Sx1280RangingBackend& backend, LineSink& sink)
        : backend_(backend), controller_(backend), sink_(sink) {}

    bool begin(const char* fw_version, uint32_t now_ms) {
        fw_version_ = fw_version ? fw_version : "0";
        if (!backend_.configure()) return false;
        session_id_[0] = 'S'; session_id_[1] = '0'; session_id_[2] = '\0';
        std::snprintf(target_id_, sizeof(target_id_), "%s", kNodeT.device_id);
        emitHello();
        emitState("READY", now_ms);
        return true;
    }

    bool onHostLine(const char* line, uint32_t now_ms) {
        const HostCommand cmd = parseHostCommand(line);
        switch (cmd.type) {
            case HostCommand::Type::Hello:
                emitHello();
                return true;
            case HostCommand::Type::Session:
                std::snprintf(session_id_, sizeof(session_id_), "%s", cmd.session_id);
                std::snprintf(target_id_, sizeof(target_id_), "%s", cmd.target_id);
                emitAck("SESSION", "OK");
                emitState("READY", now_ms);
                return true;
            case HostCommand::Type::Range: {
                HostCommand local = cmd;
                if (local.from[0] == '\0') std::snprintf(local.from, sizeof(local.from), "A");
                if (local.to[0] == '\0') std::snprintf(local.to, sizeof(local.to), "T");
                if (!controller_.beginRange(local, now_ms)) {
                    emitErr("BUSY", "range controller busy");
                    return false;
                }
                emitAck("RANGE", "STARTED");
                return true;
            }
            case HostCommand::Type::Cal:
                backend_.setCalibrationId(cmd.calibration_id);
                emitAck("CAL", "OK");
                return true;
            case HostCommand::Type::Stop:
                controller_.stop();
                emitAck("STOP", "OK");
                emitState("READY", now_ms);
                return true;
            default:
                emitErr("BAD_COMMAND", "unsupported host command");
                return false;
        }
    }

    void tick(uint32_t now_ms) {
        const RangingPhase before = controller_.phase();
        controller_.tick(now_ms, [&](RangeResult rr) {
            rr.session_id = session_id_;
            rr.target_id = target_id_;
            char line[384];
            if (formatRange(line, sizeof(line), rr) > 0) sink_.writeLine(line);
        });
        const RangingPhase after = controller_.phase();
        if (after != before) {
            if (after == RangingPhase::WaitResult) emitState("RANGING", now_ms);
            if (after == RangingPhase::Idle && before != RangingPhase::Idle) emitState("READY", now_ms);
            if (after == RangingPhase::Fault) emitState("ERROR", now_ms);
        }
    }

    const char* sessionId() const { return session_id_; }
    const char* targetId() const { return target_id_; }

private:
    void emitHello() {
        char line[256];
        if (formatHello(line, sizeof(line), kNodeA.device_id, kNodeA.role, fw_version_, session_id_,
                        "RANGING|UART|MEASUREMENT_CONTRACT") > 0) sink_.writeLine(line);
    }

    void emitState(const char* state, uint32_t now_ms) {
        char line[256];
        std::snprintf(line, sizeof(line), "F3,STATE,%s,%s,%lu,%lu,%s,%s,0,0",
                      kNodeA.device_id, session_id_,
                      static_cast<unsigned long>(++state_sequence_),
                      static_cast<unsigned long>(now_ms),
                      state, target_id_);
        sink_.writeLine(line);
    }

    void emitAck(const char* command, const char* status) {
        char line[192];
        std::snprintf(line, sizeof(line), "F3,ACK,%s,%lu,%s,%s",
                      command, static_cast<unsigned long>(++host_sequence_), status, "");
        sink_.writeLine(line);
    }

    void emitErr(const char* code, const char* detail) {
        char line[192];
        std::snprintf(line, sizeof(line), "F3,ERR,%s,%lu,%s",
                      code, static_cast<unsigned long>(++host_sequence_), detail ? detail : "");
        sink_.writeLine(line);
    }

    Sx1280RangingBackend& backend_;
    Controller controller_;
    LineSink& sink_;
    const char* fw_version_ = "0";
    char session_id_[33] = {};
    char target_id_[33] = {};
    uint32_t state_sequence_ = 0;
    uint32_t host_sequence_ = 0;
};

class BenchTargetApp {
public:
    BenchTargetApp(Sx1280RangingBackend& backend, LineSink* sink = nullptr)
        : backend_(backend), sink_(sink) {}

    bool begin(const char* expected_master, uint32_t now_ms) {
        if (!backend_.configure()) return false;
        expected_master_ = expected_master && *expected_master ? expected_master : "A";
        if (!backend_.armRangingSlave(expected_master_, kNodeT.device_id)) return false;
        if (!backend_.startRanging()) return false;
        emitState("READY", now_ms);
        return true;
    }

    void tick(uint32_t now_ms) {
        const uint16_t irq = backend_.consumeIrq();
        if (!irq) return;

        if (irq & SX1280_IRQ_RANGING_SLAVE_REQUEST_VALID) {
            last_request_ms_ = now_ms;
            emitState("RANGING", now_ms);
        }

        if (irq & SX1280_IRQ_RANGING_SLAVE_RESPONSE_DONE) {
            ++response_count_;
            backend_.armRangingSlave(expected_master_, kNodeT.device_id);
            backend_.startRanging();
            emitState("READY", now_ms);
        }

        if (irq & SX1280_IRQ_RANGING_SLAVE_REQUEST_DISCARDED) {
            ++discard_count_;
            backend_.armRangingSlave(expected_master_, kNodeT.device_id);
            backend_.startRanging();
            emitState("READY", now_ms);
        }
    }

    uint32_t responseCount() const { return response_count_; }
    uint32_t discardCount() const { return discard_count_; }
    uint32_t lastRequestMs() const { return last_request_ms_; }

private:
    void emitState(const char* state, uint32_t now_ms) {
        if (!sink_) return;
        char line[192];
        std::snprintf(line, sizeof(line), "F3,STATE,%s,-,%lu,%lu,%s,%s,0,0",
                      kNodeT.device_id,
                      static_cast<unsigned long>(++sequence_),
                      static_cast<unsigned long>(now_ms),
                      state, kNodeT.device_id);
        sink_->writeLine(line);
    }

    Sx1280RangingBackend& backend_;
    LineSink* sink_;
    const char* expected_master_ = "A";
    uint32_t sequence_ = 0;
    uint32_t response_count_ = 0;
    uint32_t discard_count_ = 0;
    uint32_t last_request_ms_ = 0;
};

} // namespace rf_fusion3
