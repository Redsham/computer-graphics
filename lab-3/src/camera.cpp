#include "camera.h"

void Camera::lookat(const vec3 &eye, const vec3 &center, const vec3 &up) {
    const vec3 n = normalized(eye - center);
    const vec3 l = normalized(cross(up, n));
    const vec3 m = normalized(cross(n, l));
    model_view_ = mat4{{l.x, l.y, l.z, 0}, {m.x, m.y, m.z, 0}, {n.x, n.y, n.z, 0}, {0, 0, 0, 1}} *
                  mat4{{1, 0, 0, -center.x}, {0, 1, 0, -center.y}, {0, 0, 1, -center.z}, {0, 0, 0, 1}};
}

void Camera::init_perspective(const double f) {
    perspective_ = mat4{{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, -1 / f, 1}};
}

void Camera::init_viewport(const int x, const int y, const int w, const int h) {
    viewport_ = mat4{{w / 2., 0, 0, x + w / 2.}, {0, h / 2., 0, y + h / 2.}, {0, 0, 1, 0}, {0, 0, 0, 1}};
}

Camera::Camera(const vec3 &eye, const vec3 &center, const vec3 &up, const double focal) {
    lookat(eye, center, up);
    init_perspective(focal);
}
