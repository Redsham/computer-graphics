#include "primitives.h"

#include <cmath>

// ...existing code...

Model Primitives::cube(const double size) {
    const double h = size * 0.5;
    std::vector<vec4> verts;
    std::vector<vec4> norms;
    std::vector<vec2> uvs;
    std::vector<int> indices;

    struct FaceDef { vec3 n; vec3 v0, v1, v2, v3; };
    FaceDef faces[] = {
        {{ 0,  0,  1}, {-h,-h, h}, { h,-h, h}, { h, h, h}, {-h, h, h}}, // +Z
        {{ 0,  0, -1}, { h,-h,-h}, {-h,-h,-h}, {-h, h,-h}, { h, h,-h}}, // -Z
        {{ 0,  1,  0}, {-h, h, h}, { h, h, h}, { h, h,-h}, {-h, h,-h}}, // +Y
        {{ 0, -1,  0}, {-h,-h,-h}, { h,-h,-h}, { h,-h, h}, {-h,-h, h}}, // -Y
        {{ 1,  0,  0}, { h,-h, h}, { h,-h,-h}, { h, h,-h}, { h, h, h}}, // +X
        {{-1,  0,  0}, {-h,-h,-h}, {-h,-h, h}, {-h, h, h}, {-h, h,-h}}  // -X
    };

    for (const auto &f : faces) {
        vec4 n = {f.n.x, f.n.y, f.n.z, 0.0};
        vec2 uv00 = {0.0, 0.0}, uv10 = {1.0, 0.0}, uv11 = {1.0, 1.0}, uv01 = {0.0, 1.0};
        vec4 v0 = {f.v0.x, f.v0.y, f.v0.z, 1.0};
        vec4 v1 = {f.v1.x, f.v1.y, f.v1.z, 1.0};
        vec4 v2 = {f.v2.x, f.v2.y, f.v2.z, 1.0};
        vec4 v3 = {f.v3.x, f.v3.y, f.v3.z, 1.0};

        const int base = static_cast<int>(verts.size());
        verts.push_back(v0); norms.push_back(n); uvs.push_back(uv00);
        verts.push_back(v1); norms.push_back(n); uvs.push_back(uv10);
        verts.push_back(v2); norms.push_back(n); uvs.push_back(uv11);
        verts.push_back(v3); norms.push_back(n); uvs.push_back(uv01);

        indices.push_back(base + 0);
        indices.push_back(base + 1);
        indices.push_back(base + 2);

        indices.push_back(base + 0);
        indices.push_back(base + 2);
        indices.push_back(base + 3);
    }

    Model m(std::move(verts), std::move(norms), std::move(uvs), std::move(indices));
    return m;
}

Model Primitives::box(const vec3 &min, const vec3 &max) {
    std::vector<vec4> verts;
    std::vector<vec4> norms;
    std::vector<vec2> uvs;
    std::vector<int> indices;

    // Восьмь углов
    const vec3 v000 = {min.x, min.y, min.z};
    const vec3 v100 = {max.x, min.y, min.z};
    const vec3 v110 = {max.x, max.y, min.z};
    const vec3 v010 = {min.x, max.y, min.z};
    const vec3 v001 = {min.x, min.y, max.z};
    const vec3 v101 = {max.x, min.y, max.z};
    const vec3 v111 = {max.x, max.y, max.z};
    const vec3 v011 = {min.x, max.y, max.z};

    struct FaceDef { vec3 n; vec3 v0, v1, v2, v3; };
    FaceDef faces[] = {
        {{ 0,  0,  1}, v001, v101, v111, v011}, // +Z
        {{ 0,  0, -1}, v100, v000, v010, v110}, // -Z
        {{ 0,  1,  0}, v011, v111, v110, v010}, // +Y
        {{ 0, -1,  0}, v000, v100, v101, v001}, // -Y
        {{ 1,  0,  0}, v101, v100, v110, v111}, // +X
        {{-1,  0,  0}, v000, v001, v011, v010}  // -X
    };

    for (const auto &f : faces) {
        vec4 n = {f.n.x, f.n.y, f.n.z, 0.0};
        vec2 uv00 = {0.0, 0.0}, uv10 = {1.0, 0.0}, uv11 = {1.0, 1.0}, uv01 = {0.0, 1.0};

        vec4 v0 = {f.v0.x, f.v0.y, f.v0.z, 1.0};
        vec4 v1 = {f.v1.x, f.v1.y, f.v1.z, 1.0};
        vec4 v2 = {f.v2.x, f.v2.y, f.v2.z, 1.0};
        vec4 v3 = {f.v3.x, f.v3.y, f.v3.z, 1.0};

        const int base = static_cast<int>(verts.size());
        verts.push_back(v0); norms.push_back(n); uvs.push_back(uv00);
        verts.push_back(v1); norms.push_back(n); uvs.push_back(uv10);
        verts.push_back(v2); norms.push_back(n); uvs.push_back(uv11);
        verts.push_back(v3); norms.push_back(n); uvs.push_back(uv01);

        indices.push_back(base + 0);
        indices.push_back(base + 1);
        indices.push_back(base + 2);

        indices.push_back(base + 0);
        indices.push_back(base + 2);
        indices.push_back(base + 3);
    }

    Model m(std::move(verts), std::move(norms), std::move(uvs), std::move(indices));
    return m;
}

Model Primitives::uv_sphere(int longitudes, int latitudes, const double radius) {
    if (longitudes < 3) longitudes = 3;
    if (latitudes < 2)  latitudes = 2;

    std::vector<vec4> verts;
    std::vector<vec4> norms;
    std::vector<vec2> uvs;
    std::vector<int> indices;

    for (int lat = 0; lat <= latitudes; ++lat) { const double v = static_cast<double>(lat) / latitudes;
        const double theta = v * M_PI; // [0..pi]
        const double sin_theta = std::sin(theta);
        const double cos_theta = std::cos(theta);

        for (int lon = 0; lon <= longitudes; ++lon) { const double u = static_cast<double>(lon) / longitudes;
            const double phi = u * 2.0 * M_PI; // [0..2pi]
            const double sin_phi = std::sin(phi);
            const double cos_phi = std::cos(phi);

            const double x = sin_theta * cos_phi;
            const double y = cos_theta;
            const double z = sin_theta * sin_phi;

            verts.push_back(vec4{radius * x, radius * y, radius * z, 1.0});
            norms.push_back(vec4{x, y, z, 0.0}); // normalized
            uvs.push_back(vec2{u, 1.0 - v});
        }
    }

    for (int lat = 0; lat < latitudes; ++lat) {
        for (int lon = 0; lon < longitudes; ++lon) {
            int a = lat * (longitudes + 1) + lon;
            int b = a + longitudes + 1;

            // треуг 1
            indices.push_back(a);
            indices.push_back(b);
            indices.push_back(a + 1);

            // треуг 2
            indices.push_back(a + 1);
            indices.push_back(b);
            indices.push_back(b + 1);
        }
    }

    Model m(std::move(verts), std::move(norms), std::move(uvs), std::move(indices));
    return m;
}
