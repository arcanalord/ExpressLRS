#pragma once

#include "emnext/core/model.hpp"

#include <filesystem>

namespace emnext::io {

[[nodiscard]] Project load_project(const std::filesystem::path& path);
void validate_project(const Project& project);

} // namespace emnext::io
