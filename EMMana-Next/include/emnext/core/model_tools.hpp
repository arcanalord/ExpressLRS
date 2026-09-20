#pragma once
#include "emnext/core/model.hpp"
#include <cstdint>
#include <string>
#include <vector>
namespace emnext {
struct ModelCheck { std::vector<std::string> errors; std::vector<std::string> warnings; [[nodiscard]] bool ok() const noexcept { return errors.empty(); } };
[[nodiscard]] double wire_length_m(const Wire& wire);
[[nodiscard]] double wavelength_m(double frequency_hz);
[[nodiscard]] ModelCheck check_model(const Project& project);
[[nodiscard]] const char* model_hash_algorithm_id() noexcept;
[[nodiscard]] std::string stable_model_hash(const Project& project);
}
