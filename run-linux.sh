#!/usr/bin/env bash

set -euo pipefail

demo_root="$(cd "$(dirname "$0")" && pwd)"
slang_repo="${SLANG_REPO:-$demo_root/../another-slang-rt-recovery}"
slang_build="${SLANG_BUILD:-$slang_repo/build}"
config="${SLANG_CONFIG:-Debug}"
compiler="${CXX:-c++}"

mkdir -p "$demo_root/build" "$demo_root/generated"

CMAKE_BUILD_PARALLEL_LEVEL=8 cmake \
    -S "$demo_root/external/glfw" \
    -B "$demo_root/build/glfw" \
    -DGLFW_BUILD_DOCS=OFF \
    -DGLFW_BUILD_EXAMPLES=OFF \
    -DGLFW_BUILD_TESTS=OFF \
    -DGLFW_BUILD_WAYLAND=OFF \
    -DGLFW_BUILD_X11=ON
CMAKE_BUILD_PARALLEL_LEVEL=8 cmake --build "$demo_root/build/glfw" --parallel 8

(
    cd "$demo_root"
    "$slang_build/$config/bin/slangc" \
        shaders/rt_pipeline.slang \
        -experimental-feature \
        -entry RayGeneration \
        -stage raygeneration \
        -target metal \
        -o generated/cornell-box.metal
)

"$compiler" \
    -std=c++17 \
    -O2 \
    -I"$slang_repo/include" \
    -I"$slang_repo/external/slang-rhi/include" \
    -I"$slang_build/external/slang-rhi/include" \
    -I"$demo_root/external/glfw/include" \
    "$demo_root/rhi-main.cpp" \
    -Wl,--start-group \
    "$slang_build/external/slang-rhi/$config/libslang-rhi.a" \
    "$slang_build/$config/lib/libcore.a" \
    "$slang_build/external/miniz/$config/libminiz.a" \
    "$slang_build/external/lz4/build/cmake/$config/liblz4.a" \
    "$slang_build/external/slang-rhi/$config/libslang-rhi-vma.a" \
    "$slang_build/external/slang-rhi/$config/libslang-rhi-resources.a" \
    "$demo_root/build/glfw/src/libglfw3.a" \
    -Wl,--end-group \
    "$slang_build/$config/lib/libslang-compiler.so" \
    -L/usr/local/cuda/targets/x86_64-linux/lib/stubs \
    -lcuda \
    -lX11 \
    -ldl \
    -lpthread \
    -lrt \
    -Wl,-rpath,"$slang_build/$config/lib" \
    -o "$demo_root/build/structural-rt-cornell-rhi"

LD_LIBRARY_PATH="$slang_build/$config/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "$demo_root/build/structural-rt-cornell-rhi" \
    "$demo_root/shaders" \
    --reflection-output "$demo_root/generated/program-layout.txt" \
    --optix-include "$slang_repo/external/optix-dev/include" \
    "$@"
