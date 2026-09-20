#include "emnext/linalg/linear_solver.hpp"

#if EMNEXT_HAS_LAPACK

#include <complex>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string_view>
#include <vector>

extern "C" {
void zgesv_(const int* n, const int* nrhs, std::complex<double>* a, const int* lda,
            int* ipiv, std::complex<double>* b, const int* ldb, int* info);
}

namespace emnext::linalg {
namespace {

class LapackDenseSolver final : public LinearSolver {
public:
    [[nodiscard]] std::string_view name() const noexcept override { return "lapack-zgesv"; }

    [[nodiscard]] std::vector<Complex> solve(DenseMatrix a, std::vector<Complex> b) const override {
        const std::size_t n_size = a.rows();
        if (n_size == 0 || a.cols() != n_size || b.size() != n_size) {
            throw std::invalid_argument("Linear system must be non-empty and square");
        }
        if (n_size > static_cast<std::size_t>(std::numeric_limits<int>::max())) {
            throw std::overflow_error("Linear system is too large for LAPACK integer interface");
        }
        const int n = static_cast<int>(n_size);
        const int nrhs = 1;
        const int lda = n;
        const int ldb = n;
        int info = 0;
        std::vector<Complex> column_major(n_size * n_size);
        for (std::size_t r = 0; r < n_size; ++r) {
            for (std::size_t c = 0; c < n_size; ++c) {
                column_major[c * n_size + r] = a(r, c);
            }
        }
        std::vector<int> pivots(n_size);
        zgesv_(&n, &nrhs, column_major.data(), &lda, pivots.data(), b.data(), &ldb, &info);
        if (info < 0) throw std::runtime_error("LAPACK zgesv rejected argument " + std::to_string(-info));
        if (info > 0) throw std::runtime_error("LAPACK zgesv detected a singular matrix at pivot " + std::to_string(info));
        return b;
    }
};

} // namespace

std::unique_ptr<LinearSolver> make_lapack_solver() { return std::make_unique<LapackDenseSolver>(); }

} // namespace emnext::linalg
#endif
