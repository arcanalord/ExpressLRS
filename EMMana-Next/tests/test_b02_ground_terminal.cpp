#include "emnext/core/model.hpp"
#include "emnext/core/model_tools.hpp"
#include "emnext/io/project_io.hpp"
#include "emnext/physics/wire_mom.hpp"
#include "emnext/reference/nec2.hpp"

#include <cmath>
#include <filesystem>
#include <iostream>
#include <stdexcept>

namespace {
void require(bool ok, const char* message) {
    if (!ok) throw std::runtime_error(message);
}
}

int main() {
    using namespace emnext;
    const auto mono = io::load_project(std::filesystem::path(EMNEXT_SOURCE_DIR) / "benchmarks/B02_quarterwave_monopole_over_pec.emnx");
    require(mono.schema_version == "0.5", "B02 project schema v0.5");
    require(mono.ground.model == "pec-image-v1", "B02 uses PEC ground");
    require(mono.feeds.size() == 1 && mono.feeds.front().mode == "ground-terminal-start", "B02 ground-terminal feed parsed");
    require(std::string(model_hash_algorithm_id()) == "fnv1a64-emnext-model-v5", "model hash v5");

    const auto mr = physics::solve_wire_mom_experimental(mono);
    require(mr.linear_system_size == 25, "B02 half-rooftop adds one terminal current unknown");
    require(mr.linear_residual_relative < 1e-10, "B02 linear residual");
    require(std::abs(mr.power_balance_relative_error) < 1e-4, "B02 PEC power balance");
    require(mr.ground_dissipated_power_w == 0.0, "B02 PEC ground is lossless");
    require(mr.solver_settings_id.find("feed=ground-terminal-start") != std::string::npos, "B02 source provenance");

    // Image-theory gate: the PEC monopole impedance should be one half of the
    // corresponding symmetric free-space half-wave dipole, within the residual
    // delta caused by the different practical source discretizations.
    Project dipole;
    dipole.schema_version = "0.5";
    dipole.name = "B02 image-theory symmetric dipole reference";
    dipole.frequency_hz = mono.frequency_hz;
    dipole.wires.push_back(Wire{"D", {0.0, 0.0, -0.25}, {0.0, 0.0, 0.25}, 0.001, 50, 0.0});
    Feed df;
    df.wire_id = "D";
    df.segment = 24;
    df.mode = "segment";
    df.voltage_v = {1.0, 0.0};
    dipole.feeds.push_back(df);
    const auto dr = physics::solve_wire_mom_experimental(dipole);
    const Complex expected = 0.5 * dr.feeds.front().impedance_ohm;
    const double image_delta = std::abs(mr.feeds.front().impedance_ohm - expected);
    require(image_delta < 1.0, "B02 image-theory impedance relation");

    const std::string deck = reference::export_nec2_deck(mono);
    require(deck.find("GE 1") != std::string::npos, "B02 NEC2 ground geometry flag");
    require(deck.find("GN 1 0 0 0") != std::string::npos, "B02 NEC2 perfect ground");
    require(deck.find("EX 0 1 1 0") != std::string::npos, "B02 NEC2 base segment source");

    auto invalid = mono;
    invalid.ground.model = "homogeneous-halfspace-image-v1";
    bool rejected = false;
    try { io::validate_project(invalid); } catch (const std::exception&) { rejected = true; }
    require(rejected, "ground-terminal feed is PEC-only until finite-ground terminal semantics are validated");

    std::cout << "B02 Zin=" << mr.feeds.front().impedance_ohm
              << " image_expected=" << expected
              << " delta=" << image_delta
              << " balance=" << mr.power_balance_relative_error << "\n";
    std::cout << "PASS B02 PEC ground-terminal/image-theory gates\n";
    return 0;
}
