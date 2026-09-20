#include "emnext/linalg/linear_solver.hpp"
#include <algorithm>
#include <cmath>
#include <memory>
#include <stdexcept>
#include <string_view>
#include <utility>
namespace emnext::linalg { namespace {
class BootstrapDenseSolver final:public LinearSolver{public:[[nodiscard]]std::string_view name()const noexcept override{return "bootstrap-partial-pivot-lu";} [[nodiscard]]std::vector<Complex> solve(DenseMatrix a,std::vector<Complex>b)const override{const auto n=a.rows(); if(n==0||a.cols()!=n||b.size()!=n) throw std::invalid_argument("Linear system must be non-empty and square"); constexpr double pivot_epsilon=1e-14; for(std::size_t k=0;k<n;++k){std::size_t pivot=k; double best=std::abs(a(k,k)); for(std::size_t r=k+1;r<n;++r){const double candidate=std::abs(a(r,k)); if(candidate>best){best=candidate;pivot=r;}} if(best<pivot_epsilon) throw std::runtime_error("Singular or ill-conditioned bootstrap system"); if(pivot!=k){for(std::size_t c=k;c<n;++c)std::swap(a(k,c),a(pivot,c)); std::swap(b[k],b[pivot]);} for(std::size_t r=k+1;r<n;++r){const Complex factor=a(r,k)/a(k,k); a(r,k)=Complex{0.0,0.0}; for(std::size_t c=k+1;c<n;++c)a(r,c)-=factor*a(k,c); b[r]-=factor*b[k];}} std::vector<Complex>x(n); for(std::size_t ii=n;ii-->0;){Complex sum=b[ii]; for(std::size_t c=ii+1;c<n;++c)sum-=a(ii,c)*x[c]; x[ii]=sum/a(ii,ii);} return x;}};
}
std::unique_ptr<LinearSolver> make_bootstrap_solver(){return std::make_unique<BootstrapDenseSolver>();}
}
