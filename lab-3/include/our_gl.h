#pragma once

#include <utility>
#include <vector>

#include "tgaimage.h"
#include "math/mat.h"

class Camera;

struct Gl_Globals {
    static TGAImage FRAME_BUFFER;
    static std::vector<double> Z_BUFFER;

    static void init(int width, int height, TGAColor clear_color);
};

struct IShader {
    virtual         ~IShader() = default;
    
    static TGAColor sample2D(const TGAImage &img, const vec2 &uvf) {
        return img.get(uvf[0] * img.width(), uvf[1] * img.height());
    }

    [[nodiscard]] virtual vec4 vertex(int face, int vert) = 0;
    [[nodiscard]] virtual std::pair<bool, TGAColor> fragment(vec3 bar) = 0;
};

typedef vec4 Triangle[3];
void rasterize(const Triangle &clip, IShader &shader, TGAImage &framebuffer, const mat4 &viewport);
