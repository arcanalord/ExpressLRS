#pragma once

#include "emnext/core/result.hpp"

#include <filesystem>
#include <string>

namespace emnext::io {

[[nodiscard]] std::string result_to_json(const ResultSet& result);
void write_result_json(const ResultSet& result, const std::filesystem::path& path);

} // namespace emnext::io
