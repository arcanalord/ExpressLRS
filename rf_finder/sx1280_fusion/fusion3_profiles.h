#pragma once
#include <cstdint>

namespace rf_fusion3 {

enum class NodeProfileId : uint8_t { A=1, B=2, T=3 };

struct NodeProfile {
    NodeProfileId id;
    const char* device_id;
    const char* role;
    uint32_t ranging_address;
    bool usb_host;
    bool ranging_master;
    bool ranging_slave;
    bool reports_to_android;
};

static constexpr NodeProfile kNodeA{
    NodeProfileId::A, "A-001", "COORDINATOR", 0xA0010001UL,
    true, true, true, true
};

static constexpr NodeProfile kNodeB{
    NodeProfileId::B, "B-001", "ANCHOR", 0xB0010001UL,
    false, true, true, false
};

static constexpr NodeProfile kNodeT{
    NodeProfileId::T, "T-001", "TARGET", 0x70010001UL,
    false, false, true, false
};

inline const NodeProfile& profile(NodeProfileId id) {
    switch (id) {
        case NodeProfileId::A: return kNodeA;
        case NodeProfileId::B: return kNodeB;
        default: return kNodeT;
    }
}

struct RangingRadioProfile {
    uint8_t bandwidth;
    uint32_t bandwidth_hz;
    uint8_t spreading_factor;
    uint8_t coding_rate;
    uint8_t preamble_length;
    uint8_t header_type;
    uint8_t payload_length;
    bool invert_iq;
    uint32_t timeout_us;
    uint8_t filter_samples;
    int8_t tx_power_dbm;
};

// Conservative bench profile. The highest-bandwidth / SF10 profile is kept
// separate so accuracy-vs-time-on-air can be measured rather than assumed.
static constexpr RangingRadioProfile kBenchFast{
    0x18, 812500UL, 0x80, 0x01, 12, 0x00, 8, false, 120000UL, 8, 0
};

static constexpr RangingRadioProfile kBenchAccuracy{
    0x0A, 1625000UL, 0xA0, 0x01, 12, 0x00, 8, false, 180000UL, 8, 0
};

} // namespace rf_fusion3
