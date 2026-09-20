#pragma once
#include <complex>
#include <cstddef>
#include <stdexcept>
#include <string>
#include <vector>
namespace emnext {
using Complex = std::complex<double>;
struct Vec3 { double x{}; double y{}; double z{}; };
class DenseMatrix {
public:
    DenseMatrix() = default;
    DenseMatrix(std::size_t rows, std::size_t cols): rows_(rows), cols_(cols), data_(rows * cols) {}
    [[nodiscard]] std::size_t rows() const noexcept { return rows_; }
    [[nodiscard]] std::size_t cols() const noexcept { return cols_; }
    Complex& operator()(std::size_t r, std::size_t c) { if (r >= rows_ || c >= cols_) throw std::out_of_range("DenseMatrix index out of range"); return data_[r * cols_ + c]; }
    const Complex& operator()(std::size_t r, std::size_t c) const { if (r >= rows_ || c >= cols_) throw std::out_of_range("DenseMatrix index out of range"); return data_[r * cols_ + c]; }
private:
    std::size_t rows_{}; std::size_t cols_{}; std::vector<Complex> data_;
};
}
