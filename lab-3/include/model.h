#pragma once

#include <string>
#include <vector>

#include "our_gl.h"
#include "math/vec.h"
#include "tgaimage.h"
#include "assimp/material.h"

class Model {
    // --- Mesh ---
    std::vector<vec4> vertices;
    std::vector<vec4> normals;
    std::vector<vec2> uvs;

    // --- Faces ---
    std::vector<int> facet_vrt;
    std::vector<int> facet_nrm;
    std::vector<int> facet_tex;

    // --- Shaders ---
    IShader *shader = nullptr;

    TGAColor diffuse_color = {255, 255, 255, 255};
    TGAImage diffuse_map = {};
    TGAImage normal_map = {};
    TGAImage specular_map = {};

    void load_textures(const std::string &objPath, const aiMaterial *material);

public:
    explicit Model(const std::string &filename);
    Model(std::vector<vec4> v, std::vector<vec4> n, std::vector<vec2> uvs, std::vector<int> indices);

    [[nodiscard]] size_t nverts() const { return vertices.size(); }
    [[nodiscard]] size_t nfaces() const { return facet_vrt.size() / 3; }

    [[nodiscard]] vec4 vert(const int i) const { return vertices[i]; }
    [[nodiscard]] vec4 vert(const int iface, const int offset) const { return vertices[facet_vrt[iface * 3 + offset]]; }

    [[nodiscard]] vec4 normal(const int iface, const int offset) const { return normals[facet_nrm[iface * 3 + offset]]; }
    [[nodiscard]] vec4 normal(const vec2 &uv) const;

    [[nodiscard]] vec2 uv(const int iface, const int offset) const { return uvs[facet_tex[iface * 3 + offset]]; }


    void set_color(const TGAColor &c) { diffuse_color = c; }
    [[nodiscard]] const TGAColor &color() const { return diffuse_color; }

    [[nodiscard]] const TGAImage &diffuse() const { return diffuse_map; }
    [[nodiscard]] const TGAImage &specular() const { return specular_map; }

    [[nodiscard]] std::string debug_info() const;

    void bounds(vec3 &min, vec3 &max) const;

    void set_shader(IShader *s) { shader = s; }
    [[nodiscard]] bool has_shader() const { return shader != nullptr; }
    [[nodiscard]] IShader &get_shader() const { return *shader; }
};