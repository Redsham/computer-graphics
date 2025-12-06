#pragma once

#include <vector>
#include "model.h"

class Primitives {
public:
    static Model cube(double size = 1.0);
    static Model box(const vec3 &min, const vec3 &max);
    static Model uv_sphere(int longitudes = 32, int latitudes = 16, double radius = 1.0);
};
