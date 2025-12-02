#pragma once

#include <cassert>
#include <cmath>
#include <iosfwd>

template <int N>
struct vec {
    double data[N]{}; // zero-initialized

    double &operator[](int i) noexcept {
        assert(i >= 0 && i < N);
        return data[i];
    }

    double operator[](int i) const noexcept {
        assert(i >= 0 && i < N);
        return data[i];
    }
};

template <>
struct vec<2> {
    double x = 0;
    double y = 0;

    double &operator[](int i) noexcept {
        assert(i >= 0 && i < 2);
        return i == 0 ? x : y;
    }

    double operator[](int i) const noexcept {
        assert(i >= 0 && i < 2);
        return i == 0 ? x : y;
    }
};

template <>
struct vec<3> {
    double x = 0;
    double y = 0;
    double z = 0;

    double &operator[](int i) noexcept {
        assert(i >= 0 && i < 3);
        return i == 0 ? x : (i == 1 ? y : z);
    }

    double operator[](int i) const noexcept {
        assert(i >= 0 && i < 3);
        return i == 0 ? x : (i == 1 ? y : z);
    }
};

template <>
struct vec<4> {
    double x = 0;
    double y = 0;
    double z = 0;
    double w = 0;

    double &operator[](int i) noexcept {
        assert(i >= 0 && i < 4);
        if (i == 0) return x;
        if (i == 1) return y;
        if (i == 2) return z;
        return w;
    }

    double operator[](int i) const noexcept {
        assert(i >= 0 && i < 4);
        if (i == 0) return x;
        if (i == 1) return y;
        if (i == 2) return z;
        return w;
    }

    vec<2> xy() const noexcept { return {x, y}; }
    vec<3> xyz() const noexcept { return {x, y, z}; }
};

using vec2 = vec<2>;
using vec3 = vec<3>;
using vec4 = vec<4>;

template <int N>
 double operator*(const vec<N> &lhs, const vec<N> &rhs) noexcept {
    double ret = 0;
    for (int i = 0; i < N; ++i) {
        ret += lhs[i] * rhs[i];
    }
    return ret;
}

template <int N>
 vec<N> operator+(const vec<N> &lhs, const vec<N> &rhs) noexcept {
    vec<N> ret = lhs;
    for (int i = 0; i < N; ++i) {
        ret[i] += rhs[i];
    }
    return ret;
}

template <int N>
 vec<N> operator-(const vec<N> &lhs, const vec<N> &rhs) noexcept {
    vec<N> ret = lhs;
    for (int i = 0; i < N; ++i) {
        ret[i] -= rhs[i];
    }
    return ret;
}

template <int N>
 vec<N> operator*(const vec<N> &lhs, double rhs) noexcept {
    vec<N> ret = lhs;
    for (int i = 0; i < N; ++i) {
        ret[i] *= rhs;
    }
    return ret;
}

template <int N>
 vec<N> operator*(double lhs, const vec<N> &rhs) noexcept {
    return rhs * lhs;
}

template <int N>
 vec<N> operator/(const vec<N> &lhs, double rhs) noexcept {
    vec<N> ret = lhs;
    for (int i = 0; i < N; ++i) {
        ret[i] /= rhs;
    }
    return ret;
}

template <int N>
 std::ostream &operator<<(std::ostream &out, const vec<N> &v) {
    for (int i = 0; i < N; ++i) {
        out << v[i] << " ";
    }
    return out;
}

template <int N>
 double norm(const vec<N> &v) {
    return std::sqrt(v * v);
}

template <int N>
 vec<N> normalized(const vec<N> &v) {
    return v / norm(v);
}

inline vec3 cross(const vec3 &v1, const vec3 &v2) noexcept {
    return {v1.y * v2.z - v1.z * v2.y, v1.z * v2.x - v1.x * v2.z, v1.x * v2.y - v1.y * v2.x};
}
