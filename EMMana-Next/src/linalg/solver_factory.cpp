#include "emnext/linalg/linear_solver.hpp"

#include <cstdlib>
#include <stdexcept>
#include <string>

namespace emnext::linalg {

std::unique_ptr<LinearSolver> make_solver_by_name(std::string_view name) {
    if (name == "bootstrap" || name == "bootstrap-partial-pivot-lu") return make_bootstrap_solver();
#if EMNEXT_HAS_EIGEN
    if (name == "eigen" || name == "eigen-partial-piv-lu") return make_eigen_solver();
#endif
#if EMNEXT_HAS_LAPACK
    if (name == "lapack" || name == "lapack-zgesv") return make_lapack_solver();
#endif
    throw std::runtime_error("Requested linear backend is unavailable: " + std::string(name));
}

std::unique_ptr<LinearSolver> make_default_solver() {
    if (const char* env = std::getenv("EMNEXT_LINEAR_BACKEND")) {
        if (*env != '\0' && std::string_view(env) != "auto") return make_solver_by_name(env);
    }
#if EMNEXT_HAS_EIGEN
    return make_eigen_solver();
#elif EMNEXT_HAS_LAPACK
    return make_lapack_solver();
#else
    return make_bootstrap_solver();
#endif
}

} // namespace emnext::linalg
