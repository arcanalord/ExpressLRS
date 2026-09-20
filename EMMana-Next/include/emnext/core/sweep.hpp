#pragma once

#include "emnext/core/types.hpp"

#include <string>
#include <vector>

namespace emnext {

struct SweepPoint {
    double frequency_hz{};
    std::string model_hash;
    Complex impedance_ohm{};
    Complex s11{};
    double vswr{};
    double dmax_dbi{};
    double efficiency{};
    double power_balance_relative_error{};
    double linear_residual_relative{};
    std::vector<std::string> warnings;
};

struct SweepResult {
    std::string schema_version{"0.3"};
    std::string solver_id;
    std::string solver_version;
    std::string solver_settings_id;
    std::string linear_solver_backend;
    double max_linear_residual_relative{};
    int execution_workers{1};
    std::string model_hash_algorithm;
    std::string source_model_hash;
    double start_frequency_hz{};
    double stop_frequency_hz{};
    int requested_points{};
    std::vector<SweepPoint> samples;
    double resonance_frequency_hz{};
    double min_s11_frequency_hz{};
    double min_s11_db{};
    double bandwidth_10db_hz{};
};

} // namespace emnext
