#pragma once

#include "tgaimage.h"
#include "math/vector.h"

void lookat(vec3 eye, vec3 center, vec3 up);
void init_perspective(double f);
void init_viewport(int x, int y, int w, int h);
void init_zbuffer(int width, int height);

struct IShader {
    static TGAColor sample2D(const TGAImage &img, const vec2 &uvf) {
        return img.get(uvf[0] * img.width(), uvf[1] * img.height());
    }
    virtual std::pair<bool,TGAColor> fragment(vec3 bar) const = 0;
};

typedef vec4 Triangle[3]; // a triangle primitive is made of three ordered points
void rasterize(const Triangle &clip, const IShader &shader, TGAImage &framebuffer);

