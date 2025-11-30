#pragma once

#include <cassert>
#include <iosfwd>

#include "math/vec.h"

template <int N>
struct dt;

template <int R, int C>
struct mat {
    vec<C> R[R] = {};

    vec<C> &operator[](int idx) {
        assert(idx >= 0 && idx < R);
        return R[idx];
    }

    const vec<C> &operator[](int idx) const {
        assert(idx >= 0 && idx < R);
        return R[idx];
    }

    double det() const {
        static_assert(R == C, "determinant requires square matrix");
        return dt<C>::det(*this);
    }

    double cofactor(int row, int col) const {
        mat<R - 1, C - 1> submatrix;
        for (int i = 0, si = 0; i < R; ++i) {
            if (i == row) continue;
            for (int j = 0, sj = 0; j < C; ++j) {
                if (j == col) continue;
                submatrix[si][sj] = R[i][j];
                ++sj;
            }
            ++si;
        }
        const double sign = ((row + col) % 2 == 0) ? 1.0 : -1.0;
        return sign * submatrix.det();
    }

    mat<R, C> invert_transpose() const {
        mat<R, C> adjugate_transpose;
        for (int i = 0; i < R; ++i) {
            for (int j = 0; j < C; ++j) {
                adjugate_transpose[i][j] = cofactor(i, j);
            }
        }
        return adjugate_transpose / (adjugate_transpose[0] * R[0]);
    }

    mat<R, C> invert() const {
        return invert_transpose().transpose();
    }

    mat<C, R> transpose() const {
        mat<C, R> ret;
        for (int i = 0; i < C; ++i) {
            for (int j = 0; j < R; ++j) {
                ret[i][j] = R[j][i];
            }
        }
        return ret;
    }
};

template <int R, int C>
inline vec<C> operator*(const vec<R> &lhs, const mat<R, C> &rhs) {
    return (mat<1, R>{{lhs}} * rhs)[0];
}

template <int R, int C>
inline vec<R> operator*(const mat<R, C> &lhs, const vec<C> &rhs) {
    vec<R> ret;
    for (int i = 0; i < R; ++i) {
        ret[i] = lhs[i] * rhs;
    }
    return ret;
}

template <int R1, int C1, int C2>
inline mat<R1, C2> operator*(const mat<R1, C1> &lhs, const mat<C1, C2> &rhs) {
    mat<R1, C2> result;
    for (int i = 0; i < R1; ++i) {
        for (int j = 0; j < C2; ++j) {
            double sum = 0;
            for (int k = 0; k < C1; ++k) {
                sum += lhs[i][k] * rhs[k][j];
            }
            result[i][j] = sum;
        }
    }
    return result;
}

template <int R, int C>
inline mat<R, C> operator*(const mat<R, C> &lhs, double val) {
    mat<R, C> result;
    for (int i = 0; i < R; ++i) {
        result[i] = lhs[i] * val;
    }
    return result;
}

template <int R, int C>
inline mat<R, C> operator/(const mat<R, C> &lhs, double val) {
    mat<R, C> result;
    for (int i = 0; i < R; ++i) {
        result[i] = lhs[i] / val;
    }
    return result;
}

template <int R, int C>
inline mat<R, C> operator+(const mat<R, C> &lhs, const mat<R, C> &rhs) {
    mat<R, C> result;
    for (int i = 0; i < R; ++i) {
        for (int j = 0; j < C; ++j) {
            result[i][j] = lhs[i][j] + rhs[i][j];
        }
    }
    return result;
}

template <int R, int C>
inline mat<R, C> operator-(const mat<R, C> &lhs, const mat<R, C> &rhs) {
    mat<R, C> result;
    for (int i = 0; i < R; ++i) {
        for (int j = 0; j < C; ++j) {
            result[i][j] = lhs[i][j] - rhs[i][j];
        }
    }
    return result;
}

template <int R, int C>
inline std::ostream &operator<<(std::ostream &out, const mat<R, C> &m) {
    for (int i = 0; i < R; ++i) {
        out << m[i] << std::endl;
    }
    return out;
}

template <int N>
struct dt {
    static double det(const mat<N, N> &src) {
        double ret = 0;
        for (int i = 0; i < N; ++i) {
            ret += src[0][i] * src.cofactor(0, i);
        }
        return ret;
    }
};

template <>
struct dt<1> {
    static double det(const mat<1, 1> &src) {
        return src[0][0];
    }
};

using mat2 = mat<2, 2>;
using mat3 = mat<3, 3>;
using mat4 = mat<4, 4>;
