#include "emnext/core/model.hpp"
#include "emnext/core/model_tools.hpp"
#include "emnext/io/project_io.hpp"
#include "emnext/io/result_io.hpp"
#include "emnext/physics/wire_mom.hpp"
#include "emnext/reference/nec2.hpp"

#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {
void require(bool ok, const char* message) {
    if (!ok) throw std::runtime_error(message);
}

emnext::Project horizontal_dipole(double height_m) {
    emnext::Project p;
    p.schema_version = "0.4";
    p.name = "B02A horizontal half-wave dipole over ground";
    p.frequency_hz = 299792458.0;
    p.wires.push_back(emnext::Wire{"W1", {-0.25, 0.0, height_m}, {0.25, 0.0, height_m}, 0.001, 51, 0.0});
    p.feeds.push_back(emnext::Feed{"W1", 25, {1.0, 0.0}, 0.0});
    return p;
}
} // namespace

int main() {
    const auto parsed_soil = emnext::io::load_project(
        std::filesystem::path(EMNEXT_SOURCE_DIR) / "benchmarks/B02A_horizontal_dipole_over_real_ground.emnx");
    require(parsed_soil.schema_version == "0.4", "project v0.4 parser");
    require(parsed_soil.ground.model == "homogeneous-halfspace-image-v1", "ground model parser");
    require(std::abs(parsed_soil.ground.relative_permittivity - 13.0) < 1e-12, "ground epsr parser");

    auto free_space = horizontal_dipole(0.25);
    const auto free_result = emnext::physics::solve_wire_mom_experimental(free_space);

    auto pec = horizontal_dipole(0.25);
    pec.ground.model = "pec-image-v1";
    const auto pec_result = emnext::physics::solve_wire_mom_experimental(pec);

    auto soil = horizontal_dipole(0.25);
    soil.ground.model = "homogeneous-halfspace-image-v1";
    soil.ground.relative_permittivity = 13.0;
    soil.ground.conductivity_s_per_m = 0.005;
    const auto soil_result = emnext::physics::solve_wire_mom_experimental(soil);

    auto conductive_limit = horizontal_dipole(0.25);
    conductive_limit.ground.model = "homogeneous-halfspace-image-v1";
    conductive_limit.ground.relative_permittivity = 1.0e8;
    conductive_limit.ground.conductivity_s_per_m = 1.0e8;
    const auto limit_result = emnext::physics::solve_wire_mom_experimental(conductive_limit);

    require(free_result.schema_version == "0.6", "ResultSet alpha.20 schema v0.6");
    require(std::string(emnext::model_hash_algorithm_id()) == "fnv1a64-emnext-model-v5", "model hash v4");
    require(emnext::stable_model_hash(free_space) != emnext::stable_model_hash(pec), "ground participates in physical model hash");
    require(std::abs(pec_result.power_balance_relative_error) < 1e-2, "PEC ground power balance");
    require(pec_result.ground_dissipated_power_w == 0.0, "PEC ground has no dissipative ground term");
    require(soil_result.ground_dissipated_power_w >= 0.0, "finite ground loss is nonnegative");
    require(soil_result.efficiency > 0.0 && soil_result.efficiency <= 1.0, "finite ground efficiency range");
    require(std::abs(soil_result.feeds.front().impedance_ohm - free_result.feeds.front().impedance_ohm) > 1e-3, "ground changes input impedance");
    require(std::abs(limit_result.feeds.front().impedance_ohm - pec_result.feeds.front().impedance_ohm) < 1e-4, "high-conductivity finite ground approaches PEC image limit");
    for (const auto& sample : soil_result.pattern) {
        if (sample.theta_rad > 3.14159265358979323846 / 2.0 + 1e-12) {
            require(sample.gain_linear == 0.0 && sample.directivity_linear == 0.0, "lower half-space pattern suppressed");
        }
    }

    const std::string pec_nec = emnext::reference::export_nec2_deck(pec);
    require(pec_nec.find("GE 1") != std::string::npos, "NEC2 ground geometry flag");
    require(pec_nec.find("GN 1 0 0 0") != std::string::npos, "NEC2 perfect-ground mapping");
    const std::string soil_nec = emnext::reference::export_nec2_deck(soil);
    require(soil_nec.find("GN 2 0 0 0") != std::string::npos, "NEC2 finite-ground Sommerfeld/Norton reference mapping");
    require(soil_nec.find("1.300000000e+01 5.000000000e-03") != std::string::npos, "NEC2 epsr/sigma mapping");

    const std::string json = emnext::io::result_to_json(soil_result);
    require(json.find("ground_dissipated_power_w") != std::string::npos, "ground loss serialized");
    require(json.find("homogeneous-halfspace-image-v1") != std::string::npos, "ground provenance serialized");

    std::cout << "free Zin=" << free_result.feeds.front().impedance_ohm << '\n';
    std::cout << "pec Zin=" << pec_result.feeds.front().impedance_ohm
              << " balance=" << pec_result.power_balance_relative_error << '\n';
    std::cout << "soil Zin=" << soil_result.feeds.front().impedance_ohm
              << " efficiency=" << soil_result.efficiency
              << " ground_loss=" << soil_result.ground_dissipated_power_w << '\n';
    std::cout << "conductive-limit delta-Z="
              << std::abs(limit_result.feeds.front().impedance_ohm - pec_result.feeds.front().impedance_ohm) << '\n';
    std::cout << "PASS alpha.20 ground/model/result/NEC2 gates\n";
    return 0;
}
