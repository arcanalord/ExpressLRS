#pragma once

#include "emnext/core/sweep.hpp"

#include <filesystem>
#include <string>

namespace emnext::io {

[[nodiscard]] std::string sweep_to_json(const SweepResult& sweep);
void write_sweep_json(const SweepResult& sweep, const std::filesystem::path& path);

} // namespace emnext::io
