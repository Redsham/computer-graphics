#include "model.h"

#include <assimp/Importer.hpp>
#include <assimp/scene.h>
#include <assimp/postprocess.h>

#include <iostream>

static std::string parentDir(const std::string &path) {
    const size_t slash = path.find_last_of("/\\");
    if (slash == std::string::npos) return "";
    return path.substr(0, slash + 1);
}

static bool load_tga(const std::string &directory, const aiString &path, TGAImage &img) {
    if (path.length == 0) return false;

    const std::string filepath = directory + std::string(path.C_Str());

    if (img.read_tga_file(filepath)) {
        return true;
    }

    std::cerr << "Failed to load texture: " << filepath << std::endl;
    return false;
}

void Model::load_textures(const std::string &objPath, const aiMaterial *material) {
    aiString path;
    const std::string dir = parentDir(objPath);

    // Diffuse map
    if (material->GetTexture(aiTextureType_DIFFUSE, 0, &path) == AI_SUCCESS)
        load_tga(dir, path, diffuse_map);

    // Normal map
    if (material->GetTexture(aiTextureType_NORMALS, 0, &path) == AI_SUCCESS ||
        material->GetTexture(aiTextureType_HEIGHT, 0, &path) == AI_SUCCESS)
        load_tga(dir, path, normal_map);

    // Specular map
    if (material->GetTexture(aiTextureType_SPECULAR, 0, &path) == AI_SUCCESS)
        load_tga(dir, path, specular_map);
}

Model::Model(const std::string &filename) {
    Assimp::Importer importer;

    const aiScene *scene = importer.ReadFile(
        filename,
        aiProcess_Triangulate |
        aiProcess_GenNormals |
        aiProcess_CalcTangentSpace |
        aiProcess_JoinIdenticalVertices
    );

    if (!scene || !scene->mRootNode || scene->mFlags & AI_SCENE_FLAGS_INCOMPLETE) {
        std::cerr << "Assimp error: " << importer.GetErrorString() << std::endl;
        return;
    }

    const aiMesh *mesh = scene->mMeshes[0];

    // Allocate memory
    vertices.reserve(mesh->mNumVertices);
    normals.reserve(mesh->mNumVertices);
    uvs.reserve(mesh->mNumVertices);

    // Vertices, normals, texture coordinates
    for (unsigned i = 0; i < mesh->mNumVertices; i++) {
        const aiVector3D v = mesh->mVertices[i];
        vertices.push_back(vec4{v.x, v.y, v.z, 1.0f});

        const aiVector3D n = mesh->mNormals[i];
        normals.push_back(normalized(vec4{n.x, n.y, n.z}));

        if (mesh->mTextureCoords[0]) {
            const aiVector3D uv = mesh->mTextureCoords[0][i];
            uvs.push_back({uv.x, 1.f - uv.y});
        } else {
            uvs.push_back({0, 0});
        }
    }

    // Faces
    for (unsigned i = 0; i < mesh->mNumFaces; i++) {
        const aiFace &f = mesh->mFaces[i];
        for (unsigned k = 0; k < 3; k++) {
            int idx = static_cast<int>(f.mIndices[k]);
            facet_vrt.push_back(idx);
            facet_nrm.push_back(idx);
            facet_tex.push_back(idx);
        }
    }

    // Textures
    if (scene->mNumMaterials > 0) {
        load_textures(filename, scene->mMaterials[mesh->mMaterialIndex]);
    }

    std::cout << "Loaded model: " << filename << " (" << debug_info() << ")" << std::endl;
}

vec4 Model::normal(const vec2 &uv) const {
    if (normal_map.width() == 0 || normal_map.height() == 0)
        return vec4{0, 0, 1, 0 };

    TGAColor c = normal_map.get(uv.x * normal_map.width(), uv.y * normal_map.height());
    return normalized(vec4{
        static_cast<double>(c[2]) * 2.0 / 255.0 - 1.0,
        static_cast<double>(c[1]) * 2.0 / 255.0 - 1.0,
        static_cast<double>(c[0]) * 2.0 / 255.0 - 1.0,
        0.0f
    });
}

std::string Model::debug_info() const {
    std::string str = "vertices: " + std::to_string(vertices.size()) +
                      ", normals: " + std::to_string(normals.size()) +
                      ", uvs: " + std::to_string(uvs.size()) +
                      ", faces: " + std::to_string(nfaces()) +
                      ", diffuse map: " + (diffuse_map.width() > 0 ? "yes" : "no") +
                      ", normal map: " + (normal_map.width() > 0 ? "yes" : "no") +
                      ", specular map: " + (specular_map.width() > 0 ? "yes" : "no");
    return str;
}
