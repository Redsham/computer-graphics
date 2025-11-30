cmake_minimum_required(VERSION 3.31)
project(tiny-renderer LANGUAGES CXX)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

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