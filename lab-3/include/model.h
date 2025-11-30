#pragma once

#include <string>
#include <vector>

#include "math/vec.h"
#include "tgaimage.h"

class Model {
    std::vector<vec4> verts = {};
    std::vector<vec4> norms = {};
    std::vector<vec2> tex = {};
    std::vector<int> facet_vrt = {};
    std::vector<int> facet_nrm = {};
    std::vector<int> facet_tex = {};
    TGAImage diffusemap = {};
    TGAImage normalmap = {};
    TGAImage specularmap = {};
public:
    explicit Model(std::string filename);
    int nverts() const;
    int nfaces() const;
    vec4 vert(int i) const;
    vec4 vert(int iface, int nthvert) const;
    vec4 normal(int iface, int nthvert) const;
    vec4 normal(const vec2 &uv) const;
    vec2 uv(int iface, int nthvert) const;
    const TGAImage &diffuse() const;
    const TGAImage &specular() const;
};
