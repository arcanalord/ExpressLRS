#pragma once

namespace emnext::physics {

struct HalfWaveDipoleReference {
    static double normalized_field(double theta_rad);
    static double directivity_linear();
    static double directivity_dbi();
    static double exact_halfwave_r_ohm();
    static double exact_halfwave_x_ohm();
};

} // namespace emnext::physics
