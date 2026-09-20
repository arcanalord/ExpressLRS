#include "emnext/linalg/linear_solver.hpp"
#include <algorithm>
#include <cmath>
#include <limits>
#include <stdexcept>
namespace emnext::linalg {
double normalized_residual_inf(const DenseMatrix&a,const std::vector<Complex>&x,const std::vector<Complex>&b){const std::size_t n=a.rows(); if(n==0||a.cols()!=n||x.size()!=n||b.size()!=n)throw std::invalid_argument("Residual check requires a non-empty square system"); double a_inf=0,x_inf=0,b_inf=0,r_inf=0; for(std::size_t i=0;i<n;++i){x_inf=std::max(x_inf,std::abs(x[i])); b_inf=std::max(b_inf,std::abs(b[i])); double row_sum=0; Complex ax{}; for(std::size_t j=0;j<n;++j){row_sum+=std::abs(a(i,j)); ax+=a(i,j)*x[j];} a_inf=std::max(a_inf,row_sum); r_inf=std::max(r_inf,std::abs(ax-b[i]));} const double denom=a_inf*x_inf+b_inf; if(denom<=std::numeric_limits<double>::min())return r_inf; return r_inf/denom;}
}
