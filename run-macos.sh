#!/usr/bin/env bash

set -euo pipefail

demo_root="$(cd "$(dirname "$0")" && pwd)"
metal_cpp_dir="${METAL_CPP_DIR:-$demo_root/metal-cpp}"
export CMAKE_BUILD_PARALLEL_LEVEL=8
export MAX_JOBS=8
export MAKEFLAGS=-j8

implementation="structural"
for ((argument_index = 1; argument_index <= $#; ++argument_index)); do
    if [[ "${!argument_index}" == "--implementation" ]]; then
        value_index=$((argument_index + 1))
        implementation="${!value_index}"
    fi
done
if [[ "$implementation" != "structural" && "$implementation" != "native" ]]; then
    echo "--implementation must be structural or native" >&2
    exit 2
fi
metal_source="$demo_root/generated/cornell-box.metal"
if [[ "$implementation" == "native" ]]; then
    metal_source="$demo_root/shaders/cornell-box-native.metal"
fi

mkdir -p "$demo_root/build"

glfw_source_dir="$demo_root/external/glfw"
glfw_build_dir="$demo_root/build/glfw"
mkdir -p "$glfw_build_dir"
glfw_sources=(
    context.c init.c input.c monitor.c platform.c vulkan.c window.c
    egl_context.c osmesa_context.c null_init.c null_monitor.c null_window.c null_joystick.c
    macos_time.c posix_module.c posix_thread.c
    cocoa_init.m cocoa_joystick.m cocoa_monitor.m cocoa_window.m nsgl_context.m
)
glfw_objects=()
for source in "${glfw_sources[@]}"; do
    object="$glfw_build_dir/${source%.*}.o"
    xcrun clang \
        -std=c99 \
        -D_GLFW_COCOA \
        -I"$glfw_source_dir/include" \
        -I"$glfw_source_dir/src" \
        -c "$glfw_source_dir/src/$source" \
        -o "$object"
    glfw_objects+=("$object")
done
xcrun libtool -static -o "$glfw_build_dir/libglfw3.a" "${glfw_objects[@]}"

xcrun clang++ \
    -std=c++17 \
    -O2 \
    -fobjc-arc \
    -I"$metal_cpp_dir" \
    -I"$demo_root/external/glfw/include" \
    "$demo_root/metal-main.cpp" \
    "$demo_root/macos-metal-layer.mm" \
    "$glfw_build_dir/libglfw3.a" \
    -framework Cocoa \
    -framework Foundation \
    -framework IOKit \
    -framework Metal \
    -framework QuartzCore \
    -o "$demo_root/build/structural-rt-cornell-metal"

xcrun clang++ \
    -std=c++17 \
    -O2 \
    -fobjc-arc \
    -I"$metal_cpp_dir" \
    "$demo_root/perf/metal-compile-benchmark.cpp" \
    -framework Foundation \
    -framework Metal \
    -o "$demo_root/build/metal-compile-benchmark"

"$demo_root/build/structural-rt-cornell-metal" \
    "$metal_source" \
    "$demo_root/generated/program-layout.txt" \
    "$@"
