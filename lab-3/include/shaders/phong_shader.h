#pragma once

#include <algorithm>
#include <cmath>

#include "../model.h"
#include "../camera.h"
#include "../our_gl.h"

struct PhongShader : IShader {
    const Model & model;
    const Camera &camera;
    vec4          l;
    vec2          varying_uv[3];
    vec4          varying_nrm[3];
    vec4          tri[3];

    PhongShader(const vec3 &light, const Model &m, const Camera &cam) : model(m), camera(cam) { l = normalized((camera.model_view() * vec4{light.x, light.y, light.z, 0.})); }

    virtual vec4 vertex(const int face, const int vert) {
        varying_uv[vert]       = model.uv(face, vert);
        varying_nrm[vert]      = camera.model_view().invert_transpose() * model.normal(face, vert);
        const vec4 gl_Position = camera.model_view() * model.vert(face, vert);
        tri[vert]              = gl_Position;
        return camera.perspective() * gl_Position;
    }

    [[nodiscard]] std::pair<bool, TGAColor> fragment(const vec3 bar) const override {
        const mat<2, 4> E = {tri[1] - tri[0], tri[2] - tri[0]};
        const mat<2, 2> U = {varying_uv[1] - varying_uv[0], varying_uv[2] - varying_uv[0]};
        const mat<2, 4> T = U.invert() * E;
        const mat<4, 4> D = {
            normalized(T[0]),
            normalized(T[1]),
            normalized(varying_nrm[0] * bar[0] + varying_nrm[1] * bar[1] + varying_nrm[2] * bar[2]),
            {0, 0, 0, 1}
        };


        const vec2 uv = varying_uv[0] * bar[0] + varying_uv[1] * bar[1] + varying_uv[2] * bar[2];
        const vec4 n  = normalized(D.transpose() * model.normal(uv));
        const vec4 r  = normalized(n * (n * l) * 2 - l);

        constexpr double ambient  = 0.4;
        const double     diffuse  = 1.0 * std::max(0., n * l);
        const double     specular = (.5 + 2. * sample2D(model.specular(), uv)[0] / 255.) * std::pow(std::max(r.z, 0.), 35);

        TGAColor gl_FragColor = sample2D(model.diffuse(), uv);
        for (const int channel: {0, 1, 2})
            gl_FragColor[channel] = std::min<int>(255, static_cast<int>(gl_FragColor[channel] * (ambient + diffuse + specular)));

        return {false, gl_FragColor};
    }
};
