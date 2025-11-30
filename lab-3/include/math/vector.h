#pragma once

#include <cassert>
#include <cmath>
#include <cstddef>

// =====================
// === Vector types  ===
// =====================

template<std::size_t N>
struct vec {
    double data[N]{};

    static constexpr std::size_t size() noexcept { return N; }

    constexpr double &operator[](std::size_t i) noexcept {
        assert(i < N);
        return data[i];
    }

    constexpr double operator[](std::size_t i) const noexcept {
        assert(i < N);
        return data[i];
    }
};

// --- Specialization: vec<2> ---
template<>
struct vec<2> {
    double x{0.0};
    double y{0.0};

    static constexpr std::size_t size() noexcept { return 2; }

    constexpr double &operator[](std::size_t i) noexcept {
        assert(i < 2);
        return (i == 0) ? x : y;
    }

    constexpr double operator[](std::size_t i) const noexcept {
        assert(i < 2);
        return (i == 0) ? x : y;
    }
};

// --- Specialization: vec<3> ---
template<>
struct vec<3> {
    double x{0.0};
    double y{0.0};
    double z{0.0};

    static constexpr std::size_t size() noexcept { return 3; }

    constexpr double &operator[](std::size_t i) noexcept {
        assert(i < 3);
        if (i == 0) return x;
        if (i == 1) return y;
        return z;
    }

    constexpr double operator[](std::size_t i) const noexcept {
        assert(i < 3);
        if (i == 0) return x;
        if (i == 1) return y;
        return z;
    }
};

// --- Specialization: vec<4> ---
template<>
struct vec<4> {
    double x{0.0};
    double y{0.0};
    double z{0.0};
    double w{0.0};

    static constexpr std::size_t size() noexcept { return 4; }

    constexpr double &operator[](std::size_t i) noexcept {
        assert(i < 4);
        switch (i) {
            case 0: return x;
            case 1: return y;
            case 2: return z;
            default: return w;
        }
    }

    constexpr double operator[](std::size_t i) const noexcept {
        assert(i < 4);
        switch (i) {
            case 0: return x;
            case 1: return y;
            case 2: return z;
            default: return w;
        }
    }

    [[nodiscard]] constexpr vec<2> xy() const noexcept { return {x, y}; }
    [[nodiscard]] constexpr vec<3> xyz() const noexcept { return {x, y, z}; }
};

// =====================
// === Vec helpers   ===
// =====================

template<std::size_t N>
[[nodiscard]] double dot(const vec<N> &lhs, const vec<N> &rhs) noexcept {
    double result = 0.0;
    for (std::size_t i = 0; i < N; ++i) {
        result += lhs[i] * rhs[i];
    }
    return result;
}

template<std::size_t N>
[[nodiscard]] double operator*(const vec<N> &lhs, const vec<N> &rhs) noexcept {
    return dot(lhs, rhs);
}

template<std::size_t N>
[[nodiscard]] vec<N> operator+(vec<N> lhs, const vec<N> &rhs) noexcept {
    for (std::size_t i = 0; i < N; ++i) {
        lhs[i] += rhs[i];
    }
    return lhs;
}

template<std::size_t N>
[[nodiscard]] vec<N> operator-(vec<N> lhs, const vec<N> &rhs) noexcept {
    for (std::size_t i = 0; i < N; ++i) {
        lhs[i] -= rhs[i];
    }
    return lhs;
}

template<std::size_t N>
[[nodiscard]] vec<N> operator*(vec<N> lhs, double rhs) noexcept {
    for (std::size_t i = 0; i < N; ++i) {
        lhs[i] *= rhs;
    }
    return lhs;
}

template<std::size_t N>
[[nodiscard]] vec<N> operator*(double lhs, const vec<N> &rhs) noexcept {
    return rhs * lhs;
}

template<std::size_t N>
[[nodiscard]] vec<N> operator/(vec<N> lhs, double rhs) noexcept {
    for (std::size_t i = 0; i < N; ++i) {
        lhs[i] /= rhs;
    }
    return lhs;
}

template<std::size_t N>
 std::ostream &operator<<(std::ostream &out, const vec<N> &v) {
    for (std::size_t i = 0; i < N; ++i) {
        out << v[i] << ' ';
    }
    return out;
}

template<std::size_t N>
[[nodiscard]] double norm(const vec<N> &v) noexcept {
    return std::sqrt(v * v);
}

template<std::size_t N>
[[nodiscard]] vec<N> normalized(const vec<N> &v) noexcept {
    return v / norm(v);
}

// only for 3D vectors
[[nodiscard]] inline vec<3> cross(const vec<3> &v1, const vec<3> &v2) noexcept {
    return {
        v1.y * v2.z - v1.z * v2.y,
        v1.z * v2.x - v1.x * v2.z,
        v1.x * v2.y - v1.y * v2.x
    };
}

// Type aliases (backwards-compatible)
using vec2 = vec<2>;
using vec3 = vec<3>;
using vec4 = vec<4>;
