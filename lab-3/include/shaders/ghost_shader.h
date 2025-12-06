#pragma once

#include "../model.h"
#include "../camera.h"
#include "../our_gl.h"

struct GhostShader final : IShader {
    const Model &model;
    const Camera &camera;

    GhostShader(const Model &m, const Camera &cam) : model(m), camera(cam) {}

    vec4 vertex(const int face, const int vert) override {
        const vec4 v = camera.model_view() * model.vert(face, vert);
        return camera.perspective() * v;
    }

    [[nodiscard]] std::pair<bool, TGAColor> fragment(const vec3 bar) override { return {false, model.color()}; }
};
