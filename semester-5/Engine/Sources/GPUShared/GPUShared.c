#include "GPUShared.h"
#include <stddef.h>
_Static_assert(sizeof(GPUVertex) == 32, "GPUVertex ABI");
_Static_assert(sizeof(GPUFrame) == 112, "GPUFrame ABI");
_Static_assert(sizeof(GPUObject) == 144, "GPUObject ABI");
_Static_assert(_Alignof(GPUVertex) == 16, "GPUVertex alignment");
_Static_assert(_Alignof(GPUFrame) == 16, "GPUFrame alignment");
_Static_assert(_Alignof(GPUObject) == 16, "GPUObject alignment");
_Static_assert(offsetof(GPUVertex, normal) == 16, "GPUVertex.normal ABI");
_Static_assert(offsetof(GPUFrame, lightDirection) == 64, "GPUFrame.lightDirection ABI");
_Static_assert(offsetof(GPUFrame, lightColor) == 80, "GPUFrame.lightColor ABI");
_Static_assert(offsetof(GPUFrame, parameters) == 96, "GPUFrame.parameters ABI");
_Static_assert(offsetof(GPUObject, normalMatrix) == 64, "GPUObject.normalMatrix ABI");
_Static_assert(offsetof(GPUObject, baseColor) == 128, "GPUObject.baseColor ABI");
