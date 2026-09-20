#pragma once

#include "emnext/core/model.hpp"
#include "emnext/core/types.hpp"

#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace emnext::reference {

struct Nec2FeedResult {
    int tag{};
    int segment{};
    Complex voltage_v{};
    Complex current_a{};
    Complex impedance_ohm{};
    Complex admittance_s{};
    double power_w{};
};

struct Nec2ParsedOutput {
    std::optional<double> frequency_hz;
    std::vector<Nec2FeedResult> feeds;
};

[[nodiscard]] std::string export_nec2_deck(const Project& project);
void write_nec2_deck(const Project& project, const std::filesystem::path& path);
[[nodiscard]] Nec2ParsedOutput parse_nec2_output(std::string_view text);
[[nodiscard]] Nec2ParsedOutput parse_nec2_output_file(const std::filesystem::path& path);

} // namespace emnext::reference
