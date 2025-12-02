#pragma once

#include <string>
#include <vector>

#include "math/vec.h"
#include "tgaimage.h"
#include "assimp/material.h"

class Model {
    std::vector<vec4> verts;
    std::vector<vec4> norms;
    std::vector<vec2> tex;
    std::vector<int> facet_vrt;
    std::vector<int> facet_nrm;
    std::vector<int> facet_tex;

    TGAImage diffusemap;
    TGAImage normalmap;
    TGAImage specularmap;

    void load_textures(const std::string &objPath, const aiMaterial *material);

public:
    explicit Model(const std::string &filename);

    [[nodiscard]] size_t nverts() const { return verts.size(); }
    [[nodiscard]] size_t nfaces() const { return facet_vrt.size() / 3; }

    [[nodiscard]] vec4 vert(const int i) const { return verts[i]; }
    [[nodiscard]] vec4 vert(const int iface, const int nthvert) const { return verts[facet_vrt[iface * 3 + nthvert]]; }

    [[nodiscard]] vec4 normal(const int iface, const int nthvert) const { return norms[facet_nrm[iface * 3 + nthvert]]; }
    [[nodiscard]] vec4 normal(const vec2 &uv) const;

    [[nodiscard]] vec2 uv(const int iface, const int nthvert) const { return tex[facet_tex[iface * 3 + nthvert]]; }

    [[nodiscard]] const TGAImage &diffuse() const { return diffusemap; }
    [[nodiscard]] const TGAImage &specular() const { return specularmap; }
};
