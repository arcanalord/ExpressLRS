#include "emnext/linalg/linear_solver.hpp"

#if EMNEXT_HAS_EIGEN
#include <Eigen/Dense>

#include <memory>
#include <stdexcept>
#include <string_view>

namespace emnext::linalg {
namespace {

class EigenDenseSolver final : public LinearSolver {
public:
    [[nodiscard]] std::string_view name() const noexcept override {
        return "eigen-partial-piv-lu";
    }

    [[nodiscard]] std::vector<Complex> solve(
        DenseMatrix a,
        std::vector<Complex> b) const override {
        const auto n = a.rows();
        if (n == 0 || a.cols() != n || b.size() != n) {
            throw std::invalid_argument("Linear system must be non-empty and square");
        }

        Eigen::MatrixXcd matrix(static_cast<Eigen::Index>(n), static_cast<Eigen::Index>(n));
        Eigen::VectorXcd rhs(static_cast<Eigen::Index>(n));
        for (std::size_t r = 0; r < n; ++r) {
            rhs(static_cast<Eigen::Index>(r)) = b[r];
            for (std::size_t c = 0; c < n; ++c) {
                matrix(static_cast<Eigen::Index>(r), static_cast<Eigen::Index>(c)) = a(r, c);
            }
        }

        const auto lu = matrix.partialPivLu();
        const Eigen::VectorXcd solution = lu.solve(rhs);
        std::vector<Complex> out(n);
        for (std::size_t i = 0; i < n; ++i) {
            out[i] = solution(static_cast<Eigen::Index>(i));
        }
        return out;
    }
};

} // namespace

std::unique_ptr<LinearSolver> make_eigen_solver() {
    return std::make_unique<EigenDenseSolver>();
}

} // namespace emnext::linalg
#endif
