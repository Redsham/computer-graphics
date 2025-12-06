#include <algorithm>

#include "camera.h"
#include "our_gl.h"

#include <iostream>

TGAImage            Gl_Globals::FRAME_BUFFER;
std::vector<double> Gl_Globals::Z_BUFFER;

void Gl_Globals::init(const int width, const int height, const TGAColor clear_color) {
    FRAME_BUFFER = TGAImage(width, height, TGAImage::RGB, clear_color);
    Z_BUFFER     = std::vector(width * height, -1000.);
}

TGAColor blend(const TGAColor &c1, const TGAColor &c2) {
    const float a = static_cast<float>(c1.a()) / 255.f;

    TGAColor out;
    out[2] = static_cast<uint8_t>(c1.r() * a + c2.r() * (1 - a));
    out[1] = static_cast<uint8_t>(c1.g() * a + c2.g() * (1 - a));
    out[0] = static_cast<uint8_t>(c1.b() * a + c2.b() * (1 - a));
    out[3] = 255;

    return out;
}

void rasterize(const Triangle &clip, IShader &shader, TGAImage &framebuffer, const mat4 &viewport) {
    const vec4 ndc[3]    = {clip[0] / clip[0].w, clip[1] / clip[1].w, clip[2] / clip[2].w};
    vec2       screen[3] = {(viewport * ndc[0]).xy(), (viewport * ndc[1]).xy(), (viewport * ndc[2]).xy()};

    const mat<3, 3> ABC = {
        {
            {screen[0].x, screen[0].y, 1.0f},
            {screen[1].x, screen[1].y, 1.0f},
            {screen[2].x, screen[2].y, 1.0f}
        }
    };
    if (ABC.det() < 1) return;

    auto [bbminx,bbmaxx] = std::minmax({screen[0].x, screen[1].x, screen[2].x});
    auto [bbminy,bbmaxy] = std::minmax({screen[0].y, screen[1].y, screen[2].y});

#pragma omp parallel for
    for (int x = std::max<int>(bbminx, 0); x <= std::min<int>(bbmaxx, framebuffer.width() - 1); x++) {
        for (int y = std::max<int>(bbminy, 0); y <= std::min<int>(bbmaxy, framebuffer.height() - 1); y++) {
            vec3 bc_screen = ABC.invert_transpose() * vec3{static_cast<double>(x), static_cast<double>(y), 1.};
            if (bc_screen.x < 0 || bc_screen.y < 0 || bc_screen.z < 0) continue;

            vec3 bc_clip = {bc_screen.x / clip[0].w, bc_screen.y / clip[1].w, bc_screen.z / clip[2].w};

            bc_clip = bc_clip / (bc_clip.x + bc_clip.y + bc_clip.z);

            double z = bc_screen * vec3{ndc[0].z, ndc[1].z, ndc[2].z};
            if (z <= Gl_Globals::Z_BUFFER[x + y * framebuffer.width()]) continue;

            auto [discard, color] = shader.fragment(bc_clip);
            if (discard) continue;
            Gl_Globals::Z_BUFFER[x + y * framebuffer.width()] = z;

            if (color.a() < 255) {
                TGAColor dst_color = framebuffer.get(x, y);
                color = blend(color, dst_color);
            }

            framebuffer.set(x, y, color);
        }
    }
}
