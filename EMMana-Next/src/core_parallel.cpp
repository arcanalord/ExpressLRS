#include "emnext/core/parallel.hpp"

#include <cstdlib>
#include <stdexcept>
#include <string>
#include <thread>

namespace emnext {

int configured_parallel_workers() {
    if (const char* env = std::getenv("EMNEXT_PARALLEL_WORKERS")) {
        if (*env != '\0' && std::string(env) != "auto") {
            const int value = std::stoi(env);
            if (value < 1 || value > 64) {
                throw std::runtime_error("EMNEXT_PARALLEL_WORKERS must be in [1,64] or 'auto'");
            }
            return value;
        }
    }
    const unsigned hw = std::thread::hardware_concurrency();
    if (hw == 0) return 2;
    return static_cast<int>(std::min<unsigned>(4, hw));
}

} // namespace emnext
