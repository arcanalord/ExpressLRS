#pragma once

#include "emnext/optimization/optimizer.hpp"

#include <filesystem>
#include <string>

namespace emnext::io {

[[nodiscard]] std::string optimizer_to_json(const optimization::OptimizerResult& result);
void write_optimizer_json(const optimization::OptimizerResult& result, const std::filesystem::path& path);

} // namespace emnext::io
