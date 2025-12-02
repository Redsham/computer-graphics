cmake_minimum_required(VERSION 3.31)
project(tiny-renderer LANGUAGES CXX)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# Fetch content
include(FetchContent)

FetchContent_Declare(
        assimp
        GIT_REPOSITORY https://github.com/assimp/assimp.git
        GIT_TAG v6.0.2
        GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(assimp)

# Automatically grab all files in the src directory
file(GLOB_RECURSE SOURCES CONFIGURE_DEPENDS
        src/*.cpp
)

# Set the include directories
include_directories(
        include
)

add_executable(tiny-renderer ${SOURCES})
target_compile_features(tiny-renderer PRIVATE cxx_std_17)
target_link_libraries(tiny-renderer PRIVATE assimp)