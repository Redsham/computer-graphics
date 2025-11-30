#include <iostream>

#include "camera.h"
#include "our_gl.h"
#include "scene.h"
#include "model.h"

extern std::vector<double> zbuffer;

struct PhongShader : IShader {
    const Model &model;
    const Camera &camera;
    vec4 l; // light direction in eye coordinates
    vec2 varying_uv[3]; // triangle uv coordinates, written by the vertex shader, read by the fragment shader
    vec4 varying_nrm[3]; // normal per vertex to be interpolated by the fragment shader
    vec4 tri[3]; // triangle in view coordinates

    PhongShader(const vec3 &light, const Model &m, const Camera &cam) : model(m), camera(cam) {
        l = normalized((camera.model_view() * vec4{light.x, light.y, light.z, 0.}));
        // transform the light vector to view coordinates
    }

    virtual vec4 vertex(const int face, const int vert) {
        varying_uv[vert] = model.uv(face, vert);
        varying_nrm[vert] = camera.model_view().invert_transpose() * model.normal(face, vert);
        vec4 gl_Position = camera.model_view() * model.vert(face, vert);
        tri[vert] = gl_Position;
        return camera.perspective() * gl_Position; // in clip coordinates
    }

    virtual std::pair<bool, TGAColor> fragment(const vec3 bar) const {
        mat<2, 4> E = {tri[1] - tri[0], tri[2] - tri[0]};
        mat<2, 2> U = {varying_uv[1] - varying_uv[0], varying_uv[2] - varying_uv[0]};
        mat<2, 4> T = U.invert() * E;
        mat<4, 4> D = {
            normalized(T[0]), // tangent vector
            normalized(T[1]), // bitangent vector
            normalized(varying_nrm[0] * bar[0] + varying_nrm[1] * bar[1] + varying_nrm[2] * bar[2]),
            // interpolated normal
            {0, 0, 0, 1}
        }; // Darboux frame
        vec2 uv = varying_uv[0] * bar[0] + varying_uv[1] * bar[1] + varying_uv[2] * bar[2];
        vec4 n = normalized(D.transpose() * model.normal(uv));
        vec4 r = normalized(n * (n * l) * 2 - l); // reflected light direction
        double ambient = .4; // ambient light intensity
        double diffuse = 1. * std::max(0., n * l); // diffuse light intensity
        double specular = (.5 + 2. * sample2D(model.specular(), uv)[0] / 255.) * std::pow(std::max(r.z, 0.), 35);
        // specular intensity, note that the camera lies on the z-axis (in eye coordinates), therefore simple r.z, since (0,0,1)*(r.x, r.y, r.z) = r.z
        TGAColor gl_FragColor = sample2D(model.diffuse(), uv);
        for (int channel: {0, 1, 2})
            gl_FragColor[channel] = std::min<int>(255, gl_FragColor[channel] * (ambient + diffuse + specular));
        return {false, gl_FragColor}; // do not discard the pixel
    }
};

int main(int argc, char **argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " obj/model.obj" << std::endl;
        return 1;
    }

    Scene scene{};
    scene.apply_camera();

    init_zbuffer(scene.width, scene.height);
    TGAImage framebuffer(scene.width, scene.height, TGAImage::RGB, scene.background);

    for (int m = 1; m < argc; m++) {
        Model model(argv[m]);
        PhongShader shader(scene.light, model, scene.camera);

        for (int f = 0; f < model.nfaces(); f++) {

            Triangle clip = {
                shader.vertex(f, 0),
                shader.vertex(f, 1),
                shader.vertex(f, 2)
            };

            rasterize(clip, shader, framebuffer, scene.camera);
        }
    }

    return framebuffer.write_tga_file("framebuffer.tga") ? 0 : 1;
}
