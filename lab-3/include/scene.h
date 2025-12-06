#pragma once

#include "camera.h"
#include "math/vec.h"
#include "tgaimage.h"

struct Scene {

    // --- Image parameters ---
    int width = 800;
    int height = 800;

    // --- Light parameters ---
    vec3 light{1, 1, 1};
    TGAColor background{0, 0, 40, 255};

    // --- Camera parameters ---
    vec3 eye{-10, 5, 10};
    vec3 center{0, 0, 0};
    vec3 up{0, 1, 0};

    Camera camera{};

    void apply_camera() {
        camera = Camera{eye, center, up, 3.0f};
        camera.init_viewport(width / 16, height / 16, width * 7 / 8, height * 7 / 8);
    }
};
