#pragma once
#include "emnext/core/types.hpp"
#include <string>
#include <vector>
namespace emnext {
struct FeedResult { std::string wire_id; int segment{}; Complex impedance_ohm{}; Complex admittance_s{}; Complex s11{}; double vswr{}; };
struct PatternSample { double theta_rad{}; double phi_rad{}; double gain_linear{}; double directivity_linear{}; };
struct ResultSet {
    std::string schema_version{"0.6"};
    std::string solver_id; std::string solver_version; std::string solver_settings_id; std::string linear_solver_backend;
    int linear_system_size{}; double linear_residual_relative{}; double junction_kcl_max_relative_error{};
    std::string model_hash_algorithm; std::string model_hash; double frequency_hz{};
    std::string environment_model{"free-space"};
    double ground_plane_z_m{}; double ground_relative_permittivity{}; double ground_conductivity_s_per_m{};
    std::vector<Complex> segment_currents_a; std::vector<FeedResult> feeds; std::vector<PatternSample> pattern;
    double accepted_power_w{}; double radiated_power_w{}; double dissipated_power_w{}; double ground_dissipated_power_w{};
    double efficiency{}; double power_balance_relative_error{};
    std::vector<std::string> warnings;
};
}
