#pragma once

#include "emnext/core/types.hpp"

#include <memory>
#include <string_view>
#include <vector>

namespace emnext::linalg {

class LinearSolver {
public:
    virtual ~LinearSolver() = default;
    [[nodiscard]] virtual std::string_view name() const noexcept = 0;
    [[nodiscard]] virtual std::vector<Complex> solve(DenseMatrix a, std::vector<Complex> b) const = 0;
};

[[nodiscard]] std::unique_ptr<LinearSolver> make_default_solver();
[[nodiscard]] std::unique_ptr<LinearSolver> make_bootstrap_solver();
[[nodiscard]] std::unique_ptr<LinearSolver> make_lapack_solver();
[[nodiscard]] std::unique_ptr<LinearSolver> make_eigen_solver();
[[nodiscard]] std::unique_ptr<LinearSolver> make_solver_by_name(std::string_view name);
[[nodiscard]] double normalized_residual_inf(const DenseMatrix& a, const std::vector<Complex>& x, const std::vector<Complex>& b);

} // namespace emnext::linalg
