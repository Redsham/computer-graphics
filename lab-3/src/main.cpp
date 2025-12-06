#include <iostream>

#include "camera.h"
#include "our_gl.h"
#include "scene.h"
#include "model.h"
#include "primitives.h"
#include "shaders/ghost_shader.h"
#include "shaders/phong_shader.h"

int main(const int argc, char **argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " obj/model.obj" << std::endl;
        return 1;
    }

    Scene scene{};
    scene.apply_camera();
    const mat4 viewport = scene.camera.viewport();

    Gl_Globals::init(scene.width, scene.height, scene.background);

    // Load models
    std::vector<Model*> models;
    for (int m = 1; m < argc; m++) {
        auto model = new Model{argv[m]};
        model->set_shader(new PhongShader{scene.light, *model, scene.camera});
        models.push_back(model);
    }

    // Procedural models
    vec3 min, max;
    models[0]->bounds(min, max);
    std::cout << "Model bounds: min(" << min.x << ", " << min.y << ", " << min.z << ") "
              << "max(" << max.x << ", " << max.y << ", " << max.z << ")" << std::endl;

    auto cube = Primitives::box(min, max);
    cube.set_shader(new GhostShader{cube, scene.camera});
    cube.set_color({0, 0, 255, 50});
    models.push_back(&cube);


    // Render models
    for (const auto model : models) {
        if (!model->has_shader()) {
            std::cerr << "Model has no shader assigned!" << std::endl;
            continue;
        }
        IShader &shader = model->get_shader();

        for (int f = 0; f < static_cast<int>(model->nfaces()); f++) {
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
