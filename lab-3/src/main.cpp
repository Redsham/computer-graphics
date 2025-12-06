#include <iostream>

#include "camera.h"
#include "our_gl.h"
#include "scene.h"
#include "model.h"
#include "shaders/phong_shader.h"

int main(const int argc, char **argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " obj/model.obj" << std::endl;
        return 1;
    }

    Scene scene{};
    scene.apply_camera();
    const mat4 viewport = scene.camera.viewport();

    Gl_Globals::init(scene.width, scene.height);

    for (int m = 1; m < argc; m++) {
        Model model(argv[m]);
        PhongShader shader(scene.light, model, scene.camera);

        for (int f = 0; f < model.nfaces(); f++) {
            Triangle clip = {
                shader.vertex(f, 0),
                shader.vertex(f, 1),
                shader.vertex(f, 2)
            };

            rasterize(clip, shader, Gl_Globals::FRAME_BUFFER, viewport);
        }
    }

    return Gl_Globals::FRAME_BUFFER.write_tga_file("framebuffer.tga") ? 0 : 1;
}
