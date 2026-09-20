#pragma once
#include "emnext/core/model.hpp"
#include "emnext/core/result.hpp"
namespace emnext::physics {
enum class WireKernelMode { Reduced, CircumferentialExactStraight };
struct WireMomSettings { int quadrature_order{8}; double reference_impedance_ohm{50.0}; WireKernelMode kernel_mode{WireKernelMode::Reduced}; };
[[nodiscard]] ResultSet solve_wire_mom_experimental(const Project& project, const WireMomSettings& settings = {});
}
