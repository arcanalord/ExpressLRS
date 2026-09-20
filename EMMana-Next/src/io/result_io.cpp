#include "emnext/io/result_io.hpp"

#include <boost/json.hpp>

#include <fstream>
#include <stdexcept>

namespace emnext::io {
namespace json = boost::json;
namespace {
json::object complex_json(const Complex& v) { return {{"re", v.real()}, {"im", v.imag()}}; }
}

std::string result_to_json(const ResultSet& result) {
    json::object root;
    root["schema_version"] = result.schema_version;
    root["solver_id"] = result.solver_id;
    root["solver_version"] = result.solver_version;
    root["solver_settings_id"] = result.solver_settings_id;
    root["linear_solver_backend"] = result.linear_solver_backend;
    root["linear_system_size"] = result.linear_system_size;
    root["linear_residual_relative"] = result.linear_residual_relative;
    root["junction_kcl_max_relative_error"] = result.junction_kcl_max_relative_error;
    root["model_hash_algorithm"] = result.model_hash_algorithm;
    root["model_hash"] = result.model_hash;
    root["frequency_hz"] = result.frequency_hz;
    root["environment_model"] = result.environment_model;
    root["ground_plane_z_m"] = result.ground_plane_z_m;
    root["ground_relative_permittivity"] = result.ground_relative_permittivity;
    root["ground_conductivity_s_per_m"] = result.ground_conductivity_s_per_m;

    json::array currents;
    for (const auto& current : result.segment_currents_a) currents.emplace_back(complex_json(current));
    root["segment_currents_a"] = std::move(currents);

    json::array feeds;
    for (const auto& f : result.feeds) {
        feeds.emplace_back(json::object{
            {"wire_id", f.wire_id}, {"segment", f.segment},
            {"impedance_ohm", complex_json(f.impedance_ohm)},
            {"admittance_s", complex_json(f.admittance_s)},
            {"s11", complex_json(f.s11)}, {"vswr", f.vswr}
        });
    }
    root["feeds"] = std::move(feeds);

    json::array pattern;
    for (const auto& p : result.pattern) {
        pattern.emplace_back(json::object{
            {"theta_rad", p.theta_rad}, {"phi_rad", p.phi_rad},
            {"gain_linear", p.gain_linear}, {"directivity_linear", p.directivity_linear}
        });
    }
    root["pattern"] = std::move(pattern);

    root["accepted_power_w"] = result.accepted_power_w;
    root["radiated_power_w"] = result.radiated_power_w;
    root["dissipated_power_w"] = result.dissipated_power_w;
    root["ground_dissipated_power_w"] = result.ground_dissipated_power_w;
    root["efficiency"] = result.efficiency;
    root["power_balance_relative_error"] = result.power_balance_relative_error;

    json::array warnings;
    for (const auto& w : result.warnings) warnings.emplace_back(w);
    root["warnings"] = std::move(warnings);
    return json::serialize(root);
}

void write_result_json(const ResultSet& result, const std::filesystem::path& path) {
    std::ofstream out(path);
    if (!out) throw std::runtime_error("Cannot create result file: " + path.string());
    out << result_to_json(result) << '\n';
}

} // namespace emnext::io
