#!/usr/bin/env bash

set -euo pipefail

demo_root="$(cd "$(dirname "$0")" && pwd)"
if [[ -n "${SLANG_REPO:-}" ]]; then
    slang_repo="$SLANG_REPO"
elif [[ -d "$demo_root/../slang" ]]; then
    slang_repo="$demo_root/../slang"
else
    slang_repo="$demo_root/../another-slang-rt-integration"
fi
slang_build="${SLANG_BUILD:-$slang_repo/build}"
config="${SLANG_CONFIG:-Release}"
compiler="${CXX:-c++}"
native_build_jobs="${NATIVE_BUILD_JOBS:-8}"
export CMAKE_BUILD_PARALLEL_LEVEL="$native_build_jobs"

api="structural"
for ((argument_index = 1; argument_index <= $#; ++argument_index)); do
    if [[ "${!argument_index}" == "--api" ]]; then
        value_index=$((argument_index + 1))
        api="${!value_index}"
    fi
done
if [[ "$api" != "structural" && "$api" != "legacy" ]]; then
    echo "--api must be structural or legacy" >&2
    exit 2
fi
shader_directory="$demo_root/shaders"
if [[ "$api" == "legacy" ]]; then
    shader_directory="$demo_root/shaders-legacy"
fi

mkdir -p "$demo_root/build" "$demo_root/generated"

cmake \
    -S "$demo_root/external/glfw" \
    -B "$demo_root/build/glfw" \
    -DGLFW_BUILD_DOCS=OFF \
    -DGLFW_BUILD_EXAMPLES=OFF \
    -DGLFW_BUILD_TESTS=OFF \
    -DGLFW_BUILD_WAYLAND=OFF \
    -DGLFW_BUILD_X11=ON
cmake --build "$demo_root/build/glfw" --parallel "$native_build_jobs"

"$compiler" \
    -std=c++17 \
    -O2 \
    -I"$slang_repo/include" \
    "$demo_root/metal-artifact-generator.cpp" \
    "$slang_build/$config/lib/libslang-compiler.so" \
    -Wl,-rpath,"$slang_build/$config/lib" \
    -o "$demo_root/build/structural-rt-metal-artifact-generator"

(
    cd "$demo_root"
    LD_LIBRARY_PATH="$slang_build/$config/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        build/structural-rt-metal-artifact-generator \
        shaders \
        rt_pipeline \
        RayGeneration \
        ProgramSchema \
        generated/cornell-box.metal \
        generated/program-schema.txt \
        "$(git -C "$slang_repo" rev-parse HEAD)"
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
    "$shader_directory" \
    --optix-include "$slang_repo/external/optix-dev/include" \
    "$@"
