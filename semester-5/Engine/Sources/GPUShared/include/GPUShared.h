#ifndef GPU_SHARED_H
#define GPU_SHARED_H
#ifdef __METAL_VERSION__
#include <metal_stdlib>
using namespace metal;
typedef float4x4 GPUMatrix;
typedef float4 GPUVector;
#else
#include <simd/simd.h>
typedef matrix_float4x4 GPUMatrix;
typedef vector_float4 GPUVector;
#endif

enum { GPUVertexBinding = 0, GPUFrameBinding = 1, GPUObjectBinding = 2, GPUColorTexture = 0 };
typedef struct { GPUVector position; GPUVector normal; } GPUVertex;
typedef struct {
    GPUMatrix viewProjection;
    GPUVector lightDirection;
    GPUVector lightColor;
    GPUVector parameters; // x: exposure
} GPUFrame;
typedef struct { GPUMatrix model; GPUMatrix normalMatrix; GPUVector baseColor; } GPUObject;
#endif
