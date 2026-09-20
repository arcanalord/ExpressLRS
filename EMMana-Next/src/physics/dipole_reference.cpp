#include "emnext/physics/dipole_reference.hpp"

#include <cmath>
#include <limits>
#include <numbers>

namespace emnext::physics {

double HalfWaveDipoleReference::normalized_field(double theta_rad) {
    const double s = std::sin(theta_rad);
    if (std::abs(s) < 1e-12) {
        return 0.0;
    }
    const double p = std::numbers::pi_v<double>;
    return std::cos((p / 2.0) * std::cos(theta_rad)) / s;
}

double HalfWaveDipoleReference::directivity_linear() {
    return 1.640922376984585;
}

double HalfWaveDipoleReference::directivity_dbi() {
    return 10.0 * std::log10(directivity_linear());
}

double HalfWaveDipoleReference::exact_halfwave_r_ohm() {
    return 73.1;
}

double HalfWaveDipoleReference::exact_halfwave_x_ohm() {
    return 42.5;
}

} // namespace emnext::physics
