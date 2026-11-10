#pragma once

#include "math/mat.h"
#include "math/vec.h"

class Camera {
public:
    Camera() = default;
    Camera(const vec3 &eye, const vec3 &center, const vec3 &up, double focal);

    [[nodiscard]] const mat4 &model_view() const { return model_view_; }
    [[nodiscard]] const mat4 &perspective() const { return perspective_; }
    [[nodiscard]] const mat4 &viewport() const { return viewport_; }

    void lookat(const vec3 &eye, const vec3 &center, const vec3 &up);
    void init_perspective(double f);
    void init_viewport(int x, int y, int w, int h);

private:
    mat4 model_view_{};
    mat4 perspective_{};
    mat4 viewport_{};
};
