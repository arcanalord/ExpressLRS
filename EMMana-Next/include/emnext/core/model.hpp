#pragma once
#include "emnext/core/types.hpp"
#include <string>
#include <vector>
namespace emnext {
struct Wire {
    std::string id; Vec3 start; Vec3 end; double radius_m{}; int segments{};
    double conductivity_s_per_m{0.0};
};
struct Feed {
    std::string wire_id;
    int segment{};
    Complex voltage_v{1.0, 0.0};
    double source_span_m{0.0};
    // segment | ground-terminal-start | ground-terminal-end
    std::string mode{"segment"};
};
struct SeriesRlcLoad {
    std::string id; std::string wire_id; int segment{}; double resistance_ohm{}; double inductance_h{}; double capacitance_f{};
};
struct GroundModel {
    // free-space | pec-image-v1 | homogeneous-halfspace-image-v1
    std::string model{"free-space"};
    double plane_z_m{0.0};
    double relative_permittivity{13.0};
    double conductivity_s_per_m{0.005};
};
struct DesignVariable { std::string id; std::string kind; std::string wire_id; double min_value{}; double max_value{}; };
struct DesignConstraint { std::string id; std::string kind; std::string wire_a; std::string wire_b; double value{}; };
struct Project {
    std::string schema_version; std::string name; double frequency_hz{};
    std::vector<Wire> wires; std::vector<Feed> feeds; std::vector<SeriesRlcLoad> loads;
    GroundModel ground{};
    std::vector<DesignVariable> design_variables; std::vector<DesignConstraint> design_constraints;
};
}
