#pragma once
#include "emnext/core/model.hpp"
#include <cstddef>
#include <string>
#include <vector>
namespace emnext::geometry {
struct Segment { std::size_t global_index{}; std::size_t wire_index{}; std::string wire_id; int local_index{}; Vec3 start; Vec3 end; Vec3 center; Vec3 tangent; double length_m{}; double radius_m{}; };
struct SegmentEndpointRef { std::size_t segment_global{}; std::size_t wire_index{}; std::string wire_id; bool at_start{}; };
struct JunctionNode { std::size_t node_index{}; Vec3 position; std::vector<SegmentEndpointRef> incident_endpoints; };
struct DiscretizedModel { std::vector<Segment> segments; std::vector<std::size_t> feed_segment_global_indices; std::vector<JunctionNode> endpoint_nodes; std::vector<std::size_t> wire_conductor_component; };
[[nodiscard]] DiscretizedModel discretize(const Project& project);
}
