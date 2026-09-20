#include "emnext/io/project_io.hpp"

#include <boost/json.hpp>
#include <boost/json/src.hpp>

#include <algorithm>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace emnext::io {
namespace json = boost::json;

namespace {

double number(const json::value& value, const char* name) {
    if (value.is_double()) return value.as_double();
    if (value.is_int64()) return static_cast<double>(value.as_int64());
    if (value.is_uint64()) return static_cast<double>(value.as_uint64());
    throw std::runtime_error(std::string("Expected number for ") + name);
}

Vec3 vec3(const json::value& value, const char* name) {
    const auto& a = value.as_array();
    if (a.size() != 3) throw std::runtime_error(std::string(name) + " must have 3 elements");
    return Vec3{number(a[0], name), number(a[1], name), number(a[2], name)};
}

bool supported_ground_model(const std::string& model) {
    return model == "free-space" || model == "pec-image-v1" || model == "homogeneous-halfspace-image-v1";
}

} // namespace

Project load_project(const std::filesystem::path& path) {
    std::ifstream in(path);
    if (!in) throw std::runtime_error("Cannot open project: " + path.string());
    std::ostringstream buffer;
    buffer << in.rdbuf();
    const json::value root = json::parse(buffer.str());
    const auto& obj = root.as_object();

    Project project;
    project.schema_version = json::value_to<std::string>(obj.at("schema_version"));
    project.name = json::value_to<std::string>(obj.at("name"));
    project.frequency_hz = number(obj.at("frequency_hz"), "frequency_hz");

    if (const auto* ground = obj.if_contains("ground")) {
        const auto& g = ground->as_object();
        project.ground.model = g.if_contains("model")
            ? json::value_to<std::string>(g.at("model"))
            : std::string{"free-space"};
        project.ground.plane_z_m = g.if_contains("plane_z_m")
            ? number(g.at("plane_z_m"), "ground.plane_z_m") : 0.0;
        project.ground.relative_permittivity = g.if_contains("relative_permittivity")
            ? number(g.at("relative_permittivity"), "ground.relative_permittivity") : 13.0;
        project.ground.conductivity_s_per_m = g.if_contains("conductivity_s_per_m")
            ? number(g.at("conductivity_s_per_m"), "ground.conductivity_s_per_m") : 0.005;
    }

    for (const auto& item : obj.at("wires").as_array()) {
        const auto& w = item.as_object();
        Wire wire;
        wire.id = json::value_to<std::string>(w.at("id"));
        wire.start = vec3(w.at("start_m"), "start_m");
        wire.end = vec3(w.at("end_m"), "end_m");
        wire.radius_m = number(w.at("radius_m"), "radius_m");
        wire.segments = static_cast<int>(w.at("segments").as_int64());
        wire.conductivity_s_per_m = w.if_contains("conductivity_s_per_m")
            ? number(w.at("conductivity_s_per_m"), "conductivity_s_per_m") : 0.0;
        project.wires.push_back(wire);
    }

    if (const auto* feeds = obj.if_contains("feeds")) {
        for (const auto& item : feeds->as_array()) {
            const auto& f = item.as_object();
            Feed feed;
            feed.wire_id = json::value_to<std::string>(f.at("wire_id"));
            feed.segment = static_cast<int>(f.at("segment").as_int64());
            const double re = f.if_contains("voltage_re_v") ? number(f.at("voltage_re_v"), "voltage_re_v") : 1.0;
            const double im = f.if_contains("voltage_im_v") ? number(f.at("voltage_im_v"), "voltage_im_v") : 0.0;
            feed.voltage_v = Complex{re, im};
            feed.source_span_m = f.if_contains("source_span_m") ? number(f.at("source_span_m"), "source_span_m") : 0.0;
            feed.mode = f.if_contains("mode") ? json::value_to<std::string>(f.at("mode")) : std::string{"segment"};
            project.feeds.push_back(feed);
        }
    }

    if (const auto* loads = obj.if_contains("loads")) {
        for (const auto& item : loads->as_array()) {
            const auto& l = item.as_object();
            SeriesRlcLoad load;
            load.id = json::value_to<std::string>(l.at("id"));
            load.wire_id = json::value_to<std::string>(l.at("wire_id"));
            load.segment = static_cast<int>(l.at("segment").as_int64());
            load.resistance_ohm = l.if_contains("resistance_ohm") ? number(l.at("resistance_ohm"), "load.resistance_ohm") : 0.0;
            load.inductance_h = l.if_contains("inductance_h") ? number(l.at("inductance_h"), "load.inductance_h") : 0.0;
            load.capacitance_f = l.if_contains("capacitance_f") ? number(l.at("capacitance_f"), "load.capacitance_f") : 0.0;
            project.loads.push_back(load);
        }
    }

    if (const auto* variables = obj.if_contains("design_variables")) {
        for (const auto& item : variables->as_array()) {
            const auto& v = item.as_object();
            DesignVariable var;
            var.id = json::value_to<std::string>(v.at("id"));
            var.kind = json::value_to<std::string>(v.at("kind"));
            var.wire_id = json::value_to<std::string>(v.at("wire_id"));
            var.min_value = number(v.at("min"), "design_variable.min");
            var.max_value = number(v.at("max"), "design_variable.max");
            project.design_variables.push_back(var);
        }
    }

    if (const auto* constraints = obj.if_contains("design_constraints")) {
        for (const auto& item : constraints->as_array()) {
            const auto& c = item.as_object();
            DesignConstraint constraint;
            constraint.id = json::value_to<std::string>(c.at("id"));
            constraint.kind = json::value_to<std::string>(c.at("kind"));
            constraint.wire_a = c.if_contains("wire_a") ? json::value_to<std::string>(c.at("wire_a")) : std::string{};
            constraint.wire_b = c.if_contains("wire_b") ? json::value_to<std::string>(c.at("wire_b")) : std::string{};
            constraint.value = number(c.at("value"), "design_constraint.value");
            project.design_constraints.push_back(constraint);
        }
    }

    validate_project(project);
    return project;
}

void validate_project(const Project& project) {
    if (project.schema_version != "0.1" && project.schema_version != "0.2" &&
        project.schema_version != "0.3" && project.schema_version != "0.4" && project.schema_version != "0.5") {
        throw std::runtime_error("Unsupported schema_version: " + project.schema_version);
    }
    if (!(project.frequency_hz > 0.0)) throw std::runtime_error("frequency_hz must be positive");
    if (project.wires.empty()) throw std::runtime_error("Project must contain at least one wire");
    if (!supported_ground_model(project.ground.model)) {
        throw std::runtime_error("Unsupported ground model: " + project.ground.model);
    }
    if (project.ground.model == "homogeneous-halfspace-image-v1") {
        if (!(project.ground.relative_permittivity >= 1.0)) {
            throw std::runtime_error("ground.relative_permittivity must be >= 1");
        }
        if (project.ground.conductivity_s_per_m < 0.0) {
            throw std::runtime_error("ground.conductivity_s_per_m must be >= 0");
        }
    }

    for (const auto& wire : project.wires) {
        if (wire.id.empty()) throw std::runtime_error("Wire id must not be empty");
        if (!(wire.radius_m > 0.0)) throw std::runtime_error("Wire radius_m must be positive");
        if (wire.segments < 3) throw std::runtime_error("Wire segments must be >= 3");
        if (wire.conductivity_s_per_m < 0.0) throw std::runtime_error("Wire conductivity_s_per_m must be >= 0");
        if (project.ground.model != "free-space") {
            const bool start_terminal = std::any_of(project.feeds.begin(), project.feeds.end(), [&](const Feed& feed) {
                return feed.wire_id == wire.id && feed.mode == "ground-terminal-start";
            });
            const bool end_terminal = std::any_of(project.feeds.begin(), project.feeds.end(), [&](const Feed& feed) {
                return feed.wire_id == wire.id && feed.mode == "ground-terminal-end";
            });
            const auto endpoint_ok = [&](double z, bool terminal) {
                const double dz = z - project.ground.plane_z_m;
                if (terminal) return std::abs(dz) <= 1e-9;
                return dz > wire.radius_m;
            };
            if (!endpoint_ok(wire.start.z, start_terminal) || !endpoint_ok(wire.end.z, end_terminal)) {
                throw std::runtime_error("Ground-enabled wire endpoint violates plane clearance/terminal semantics: " + wire.id);
            }
        }
    }

    for (const auto& feed : project.feeds) {
        if (feed.source_span_m < 0.0) throw std::runtime_error("Feed source_span_m must be >= 0");
        if (feed.mode != "segment" && feed.mode != "ground-terminal-start" && feed.mode != "ground-terminal-end") {
            throw std::runtime_error("Unsupported feed mode: " + feed.mode);
        }
        const auto wit = std::find_if(project.wires.begin(), project.wires.end(), [&](const Wire& w) { return w.id == feed.wire_id; });
        if (wit == project.wires.end()) throw std::runtime_error("Feed references unknown wire: " + feed.wire_id);
        if (feed.mode == "segment") {
            if (feed.segment < 0 || feed.segment >= wit->segments) throw std::runtime_error("Feed segment index is outside wire: " + feed.wire_id);
        } else {
            if (project.ground.model != "pec-image-v1") {
                throw std::runtime_error("Ground-terminal feed currently requires pec-image-v1 ground");
            }
            const double endpoint_z = feed.mode == "ground-terminal-start" ? wit->start.z : wit->end.z;
            if (std::abs(endpoint_z - project.ground.plane_z_m) > 1e-9) {
                throw std::runtime_error("Ground-terminal feed endpoint must lie on ground plane: " + feed.wire_id);
            }
        }
    }

    std::vector<std::string> load_ids;
    for (const auto& load : project.loads) {
        if (load.id.empty()) throw std::runtime_error("Load id must not be empty");
        if (std::find(load_ids.begin(), load_ids.end(), load.id) != load_ids.end()) throw std::runtime_error("Duplicate load id: " + load.id);
        load_ids.push_back(load.id);
        const auto wit = std::find_if(project.wires.begin(), project.wires.end(), [&](const Wire& w) { return w.id == load.wire_id; });
        if (wit == project.wires.end()) throw std::runtime_error("Load references unknown wire: " + load.wire_id);
        if (load.segment < 0 || load.segment >= wit->segments) throw std::runtime_error("Load segment index is outside wire: " + load.id);
        if (load.resistance_ohm < 0.0 || load.inductance_h < 0.0 || load.capacitance_f < 0.0) {
            throw std::runtime_error("Load R/L/C values must be >= 0: " + load.id);
        }
        if (!(load.resistance_ohm > 0.0 || load.inductance_h > 0.0 || load.capacitance_f > 0.0)) {
            throw std::runtime_error("Load must contain at least one positive R/L/C value: " + load.id);
        }
    }

    std::vector<std::string> variable_ids;
    for (const auto& var : project.design_variables) {
        if (var.id.empty()) throw std::runtime_error("Design variable id must not be empty");
        if (std::find(variable_ids.begin(), variable_ids.end(), var.id) != variable_ids.end()) throw std::runtime_error("Duplicate design variable id: " + var.id);
        variable_ids.push_back(var.id);
        if (var.kind != "wire_length_m" && var.kind != "wire_center_x_m") throw std::runtime_error("Unsupported design variable kind: " + var.kind);
        if (var.wire_id.empty()) throw std::runtime_error("Design variable wire_id must not be empty");
        const auto wit = std::find_if(project.wires.begin(), project.wires.end(), [&](const Wire& w) { return w.id == var.wire_id; });
        if (wit == project.wires.end()) throw std::runtime_error("Design variable references unknown wire: " + var.wire_id);
        if (!(var.max_value > var.min_value)) throw std::runtime_error("Design variable max must be greater than min: " + var.id);
        if (var.kind == "wire_length_m" && !(var.min_value > 0.0)) throw std::runtime_error("wire_length_m design variable min must be positive: " + var.id);
    }

    std::vector<std::string> constraint_ids;
    const auto wire_exists = [&](const std::string& id) {
        return std::find_if(project.wires.begin(), project.wires.end(), [&](const Wire& w) { return w.id == id; }) != project.wires.end();
    };
    for (const auto& c : project.design_constraints) {
        if (c.id.empty()) throw std::runtime_error("Design constraint id must not be empty");
        if (std::find(constraint_ids.begin(), constraint_ids.end(), c.id) != constraint_ids.end()) throw std::runtime_error("Duplicate design constraint id: " + c.id);
        constraint_ids.push_back(c.id);
        if (c.kind != "min_center_x_gap_m" && c.kind != "wire_length_order_min_delta_m" && c.kind != "max_boom_length_m") {
            throw std::runtime_error("Unsupported design constraint kind: " + c.kind);
        }
        if (!(c.value >= 0.0)) throw std::runtime_error("Design constraint value must be >= 0: " + c.id);
        if (c.kind == "max_boom_length_m") {
            if (!(c.value > 0.0)) throw std::runtime_error("max_boom_length_m must be > 0: " + c.id);
        } else {
            if (c.wire_a.empty() || c.wire_b.empty()) throw std::runtime_error("Constraint requires wire_a and wire_b: " + c.id);
            if (!wire_exists(c.wire_a) || !wire_exists(c.wire_b)) throw std::runtime_error("Constraint references unknown wire: " + c.id);
            if (c.wire_a == c.wire_b) throw std::runtime_error("Constraint wire_a and wire_b must differ: " + c.id);
        }
    }
}

} // namespace emnext::io
