#pragma once

#include <utility>

#include "tgaimage.h"
#include "math/mat.h"

class Camera;

void init_zbuffer(int width, int height);

struct IShader {
    static TGAColor sample2D(const TGAImage &img, const vec2 &uvf) {
        return img.get(uvf[0] * img.width(), uvf[1] * img.height());
    }
    virtual std::pair<bool, TGAColor> fragment(vec3 bar) const = 0;
};

typedef vec4 Triangle[3];
void rasterize(const Triangle &clip, const IShader &shader, TGAImage &framebuffer, const Camera &camera);
