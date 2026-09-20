#pragma once

#include "emnext/core/model.hpp"
#include "emnext/core/sweep.hpp"
#include "emnext/physics/wire_mom.hpp"

namespace emnext::physics {

[[nodiscard]] SweepResult solve_frequency_sweep(
    const Project& project,
    double start_frequency_hz,
    double stop_frequency_hz,
    int points,
    const WireMomSettings& settings = {});

} // namespace emnext::physics
