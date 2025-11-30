#pragma once

#include <cassert>
#include <ostream>


// Forward declaration of determinant helper
template<int N>
struct dt;

// =====================
// === Matrix type   ===
// =====================

template<int nrows, int ncols>
struct mat {
    vec<ncols> rows[nrows]{};

    static constexpr int rows_count = nrows;
    static constexpr int cols_count = ncols;

    constexpr vec<ncols>& operator[](int idx) noexcept {
        assert(idx >= 0 && idx < nrows);
        return rows[idx];
    }

    constexpr const vec<ncols>& operator[](int idx) const noexcept {
        assert(idx >= 0 && idx < nrows);
        return rows[idx];
    }

    [[nodiscard]] double det() const {
        static_assert(nrows == ncols, "det() only defined for square matrices");
        return dt<ncols>::det(*this);
    }

    [[nodiscard]] double cofactor(int row, int col) const {
        static_assert(nrows == ncols, "cofactor() only defined for square matrices");

        mat<nrows - 1, ncols - 1> submatrix{};
        for (int i = 0; i < nrows - 1; ++i) {
            for (int j = 0; j < ncols - 1; ++j) {
                const int src_i = i + static_cast<int>(i >= row);
                const int src_j = j + static_cast<int>(j >= col);
                submatrix[i][j] = rows[src_i][src_j];
            }
        }

        const double sign = ((row + col) % 2) ? -1.0 : 1.0;
        return sign * submatrix.det();
    }

    [[nodiscard]] mat invert_transpose() const {
        static_assert(nrows == ncols, "invert_transpose() only defined for square matrices");

        mat adjugate_transpose{};
        for (int i = 0; i < nrows; ++i) {
            for (int j = 0; j < ncols; ++j) {
                adjugate_transpose[i][j] = cofactor(i, j);
            }
        }

        const double determinant = adjugate_transpose[0] * rows[0];
        return adjugate_transpose / determinant;
    }

    [[nodiscard]] mat invert() const {
        return invert_transpose().transpose();
    }

    [[nodiscard]] mat<ncols, nrows> transpose() const {
        mat<ncols, nrows> result{};
        for (int i = 0; i < ncols; ++i) {
            for (int j = 0; j < nrows; ++j) {
                result[i][j] = rows[j][i];
            }
        }
        return result;
    }
};

// =====================
// === Mat operations ===
// =====================

template<int nrows, int ncols>
[[nodiscard]] vec<ncols> operator*(const vec<nrows>& lhs,
                                   const mat<nrows, ncols>& rhs) {
    // treat lhs as 1 x nrows matrix
    mat<1, nrows> temp{};
    temp[0] = lhs;
    return (temp * rhs)[0];
}

template<int nrows, int ncols>
[[nodiscard]] vec<nrows> operator*(const mat<nrows, ncols>& lhs,
                                   const vec<ncols>& rhs) {
    vec<nrows> result{};
    for (int i = 0; i < nrows; ++i) {
        result[i] = lhs[i] * rhs;
    }
    return result;
}

template<int R1, int C1, int C2>
[[nodiscard]] mat<R1, C2> operator*(const mat<R1, C1>& lhs,
                                    const mat<C1, C2>& rhs) {
    mat<R1, C2> result{};
    for (int i = 0; i < R1; ++i) {
        for (int j = 0; j < C2; ++j) {
            double value = 0.0;
            for (int k = 0; k < C1; ++k) {
                value += lhs[i][k] * rhs[k][j];
            }
            result[i][j] = value;
        }
    }
    return result;
}

template<int nrows, int ncols>
[[nodiscard]] mat<nrows, ncols> operator*(const mat<nrows, ncols>& lhs,
                                          double val) {
    mat<nrows, ncols> result{};
    for (int i = 0; i < nrows; ++i) {
        result[i] = lhs[i] * val;
    }
    return result;
}

template<int nrows, int ncols>
[[nodiscard]] mat<nrows, ncols> operator/(const mat<nrows, ncols>& lhs,
                                          double val) {
    mat<nrows, ncols> result{};
    for (int i = 0; i < nrows; ++i) {
        result[i] = lhs[i] / val;
    }
    return result;
}

template<int nrows, int ncols>
[[nodiscard]] mat<nrows, ncols> operator+(const mat<nrows, ncols>& lhs,
                                          const mat<nrows, ncols>& rhs) {
    mat<nrows, ncols> result{};
    for (int i = 0; i < nrows; ++i) {
        for (int j = 0; j < ncols; ++j) {
            result[i][j] = lhs[i][j] + rhs[i][j];
        }
    }
    return result;
}

template<int nrows, int ncols>
[[nodiscard]] mat<nrows, ncols> operator-(const mat<nrows, ncols>& lhs,
                                          const mat<nrows, ncols>& rhs) {
    mat<nrows, ncols> result{};
    for (int i = 0; i < nrows; ++i) {
        for (int j = 0; j < ncols; ++j) {
            result[i][j] = lhs[i][j] - rhs[i][j];
        }
    }
    return result;
}

template<int nrows, int ncols>
 std::ostream& operator<<(std::ostream& out,
                                const mat<nrows, ncols>& m) {
    for (int i = 0; i < nrows; ++i) {
        out << m[i] << '\n';
    }
    return out;
}

// =====================
// === Determinant   ===
// =====================

template<int N>
struct dt {
    static double det(const mat<N, N>& src) {
        double result = 0.0;
        for (int i = 0; i < N; ++i) {
            result += src[0][i] * src.cofactor(0, i);
        }
        return result;
    }
};

template<>
struct dt<1> {
    static double det(const mat<1, 1>& src) {
        return src[0][0];
    }
};

using mat4 = mat<4, 4>;
using mat3 = mat<3, 3>;
using mat2 = mat<2, 2>;