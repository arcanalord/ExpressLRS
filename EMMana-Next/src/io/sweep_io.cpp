#include "emnext/io/sweep_io.hpp"

#include <boost/json.hpp>

#include <fstream>
#include <stdexcept>

namespace emnext::io {
namespace json = boost::json;
namespace {

json::object complex_json(const Complex& v) {
    return {{"re", v.real()}, {"im", v.imag()}};
}

} // namespace

std::string sweep_to_json(const SweepResult& sweep) {
    json::object root;
    root["schema_version"] = sweep.schema_version;
    root["solver_id"] = sweep.solver_id;
    root["solver_version"] = sweep.solver_version;
    root["solver_settings_id"] = sweep.solver_settings_id;
    root["linear_solver_backend"] = sweep.linear_solver_backend;
    root["max_linear_residual_relative"] = sweep.max_linear_residual_relative;
    root["execution_workers"] = sweep.execution_workers;
    root["model_hash_algorithm"] = sweep.model_hash_algorithm;
    root["source_model_hash"] = sweep.source_model_hash;
    root["start_frequency_hz"] = sweep.start_frequency_hz;
    root["stop_frequency_hz"] = sweep.stop_frequency_hz;
    root["requested_points"] = sweep.requested_points;
    root["resonance_frequency_hz"] = sweep.resonance_frequency_hz;
    root["min_s11_frequency_hz"] = sweep.min_s11_frequency_hz;
    root["min_s11_db"] = sweep.min_s11_db;
    root["bandwidth_10db_hz"] = sweep.bandwidth_10db_hz;

    json::array samples;
    for (const auto& p : sweep.samples) {
        json::array warnings;
        for (const auto& w : p.warnings) warnings.emplace_back(w);
        samples.emplace_back(json::object{
            {"frequency_hz", p.frequency_hz},
            {"model_hash", p.model_hash},
            {"impedance_ohm", complex_json(p.impedance_ohm)},
            {"s11", complex_json(p.s11)},
            {"vswr", p.vswr},
            {"dmax_dbi", p.dmax_dbi},
            {"efficiency", p.efficiency},
            {"power_balance_relative_error", p.power_balance_relative_error},
            {"linear_residual_relative", p.linear_residual_relative},
            {"warnings", std::move(warnings)}
        });
    }
    root["samples"] = std::move(samples);
    return json::serialize(root);
}

void write_sweep_json(const SweepResult& sweep, const std::filesystem::path& path) {
    std::ofstream out(path);
    if (!out) throw std::runtime_error("Cannot create sweep result file: " + path.string());
    out << sweep_to_json(sweep) << '\n';
}

} // namespace emnext::io
