#include "GPUShared.h"
_Static_assert(sizeof(GPUVertex) == 32, "GPUVertex ABI");
_Static_assert(sizeof(GPUFrame) == 112, "GPUFrame ABI");
_Static_assert(sizeof(GPUObject) == 144, "GPUObject ABI");
