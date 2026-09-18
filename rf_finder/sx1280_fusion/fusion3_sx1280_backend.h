#pragma once
#include <cmath>
#include "fusion3_controller.h"
#include "fusion3_profiles.h"
#include "SX1280Driver.h"

namespace rf_fusion3 {

class Sx1280RangingBackend final : public RadioBackend {
public:
    Sx1280RangingBackend(SX1280Driver& radio,
                         const NodeProfile& self,
                         const RangingRadioProfile& profile,
                         uint32_t frequency_reg,
                         uint16_t calibration)
        : radio_(radio), self_(self), profile_(profile),
          frequency_reg_(frequency_reg), calibration_(calibration) {}

    bool configure() {
        if (!radio_.ConfigRanging(profile_.bandwidth,
                                  profile_.spreading_factor,
                                  profile_.coding_rate,
                                  frequency_reg_,
                                  profile_.preamble_length,
                                  profile_.header_type,
                                  profile_.payload_length,
                                  profile_.invert_iq,
                                  profile_.timeout_us)) return false;
        radio_.SetOutputPower(profile_.tx_power_dbm);
        radio_.SetDeviceRangingAddress(self_.ranging_address);
        radio_.SetRangingCalibration(calibration_);
        radio_.SetRangingFilterNumSamples(profile_.filter_samples);
        radio_.ClearRangingFilter();
        configured_ = true;
        return true;
    }

    bool enterControlMode() override {
        // Bench backend keeps the radio in ranging packet type.
        // Production control packets will be handled by a separate scheduler.
        return configured_ || configure();
    }

    bool armRangingMaster(const char* peer_id,const char* target_id) override {
        (void)target_id;
        const NodeProfile* peer = resolve(peer_id);
        if (!peer || !self_.ranging_master) return false;
        if (!configured_ && !configure()) return false;
        peer_address_ = peer->ranging_address;
        radio_.SetRangingRequestAddress(peer_address_);
        radio_.SetRangingRole(SX1280_RANGING_ROLE_MASTER);
        master_ = true;
        return true;
    }

    bool armRangingSlave(const char* peer_id,const char* target_id) override {
        (void)target_id;
        const NodeProfile* peer = resolve(peer_id);
        if (!peer || !self_.ranging_slave) return false;
        if (!configured_ && !configure()) return false;
        radio_.SetRangingRequestAddress(peer->ranging_address);
        radio_.SetRangingRole(SX1280_RANGING_ROLE_SLAVE);
        master_ = false;
        return true;
    }

    bool startRanging() override {
        if (!configured_) return false;
        radio_.ClearIrqStatus(SX1280_IRQ_RADIO_ALL, SX12XX_Radio_All);
        if (master_) radio_.StartRangingMaster();
        else radio_.StartRangingSlave();
        active_ = true;
        return true;
    }

    bool pollRange(RangeResult& out) override {
        if (!active_ || !master_) return false;
        const uint16_t irq = radio_.ConsumeRangingIrqStatus();
        if (irq & SX1280_IRQ_RANGING_MASTER_TIMEOUT) {
            radio_.ClearIrqStatus(SX1280_IRQ_RANGING_MASTER_TIMEOUT, SX12XX_Radio_1);
            active_ = false;
            return false;
        }
        if (!(irq & SX1280_IRQ_RANGING_MASTER_RESULT_VALID)) return false;

        radio_.ClearIrqStatus(SX1280_IRQ_RANGING_MASTER_RESULT_VALID, SX12XX_Radio_1);
        const double raw = radio_.GetRangingResultMeters(SX1280_RANGING_RESULT_RAW,
                                                         profile_.bandwidth_hz,
                                                         SX12XX_Radio_1);
        const double filtered = radio_.GetRangingResultMeters(SX1280_RANGING_RESULT_FILTERED,
                                                              profile_.bandwidth_hz,
                                                              SX12XX_Radio_1);
        active_ = false;
        if (!std::isfinite(filtered) || filtered <= 0.0) return false;

        out.raw_mm = std::isfinite(raw) ? static_cast<int32_t>(std::lround(raw * 1000.0)) : 0;
        out.calibrated_mm = static_cast<int32_t>(std::lround(filtered * 1000.0));
        out.sigma_mm = default_sigma_mm_;
        out.quality_milli = 700;
        out.los = LosState::Unknown;
        out.calibration_id = calibration_id_;
        return true;
    }

    void abortRanging() override {
        active_ = false;
        radio_.ClearIrqStatus(SX1280_IRQ_RADIO_ALL, SX12XX_Radio_All);
    }

    uint16_t consumeIrq() {
        return radio_.ConsumeRangingIrqStatus();
    }

    void setDefaultSigmaMm(uint32_t sigma_mm) {
        default_sigma_mm_ = sigma_mm ? sigma_mm : 1500;
    }

    void setCalibrationId(const char* id) {
        calibration_id_ = id && *id ? id : "UNCAL";
    }

private:
    static const NodeProfile* resolve(const char* id) {
        if (!id) return nullptr;
        if (id[0]=='A') return &kNodeA;
        if (id[0]=='B') return &kNodeB;
        if (id[0]=='T') return &kNodeT;
        return nullptr;
    }

    SX1280Driver& radio_;
    const NodeProfile& self_;
    RangingRadioProfile profile_;
    uint32_t frequency_reg_;
    uint32_t peer_address_ = 0;
    uint16_t calibration_;
    uint32_t default_sigma_mm_ = 1500;
    const char* calibration_id_ = "UNCAL";
    bool configured_ = false;
    bool master_ = false;
    bool active_ = false;
};

} // namespace rf_fusion3
