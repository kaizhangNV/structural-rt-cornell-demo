#!/usr/bin/env bash

set -euo pipefail

demo_root="$(cd "$(dirname "$0")" && pwd)"
slang_repo="${SLANG_REPO:-$demo_root/../another-slang-rt-recovery}"
slang_build="${SLANG_BUILD:-$slang_repo/build}"
config="${SLANG_CONFIG:-Debug}"
compiler_root="${SLANG_PERF_COMPILER_ROOT:-$slang_build/Release}"
compiler="${CXX:-c++}"
limited_build="${LIMITED_BUILD_WRAPPER:-$HOME/.codex/skills/limit-cpp-build-parallelism/scripts/run-limited-build.sh}"
results_dir="${PERF_RESULTS_DIR:-$demo_root/perf-results/linux}"
warmup="${PERF_WARMUP:-5}"
iterations="${PERF_ITERATIONS:-50}"
host_label="${PERF_HOST_LABEL:-$(uname -srmo); $(lscpu | sed -n 's/^Model name:[[:space:]]*//p' | head -n 1)}"

if [[ ! -x "$limited_build" ]]; then
    echo "native build limiter is not executable: $limited_build" >&2
    exit 2
fi
if [[ ! -f "$compiler_root/lib/libslang-compiler.so" ]]; then
    echo "release Slang compiler package is missing under $compiler_root" >&2
    exit 2
fi

mkdir -p "$demo_root/build" "$results_dir"

# Build the sample host once and validate the structural output.
SLANG_REPO="$slang_repo" SLANG_BUILD="$slang_build" SLANG_CONFIG="$config" \
    "$demo_root/run-linux.sh" \
    --api structural \
    --backend vulkan \
    --headless \
    --output "$results_dir/cornell-structural.ppm"

host="$demo_root/build/structural-rt-cornell-rhi"
runtime_library_path="$slang_build/$config/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Validate that the equivalent legacy shader renders the same image.
LD_LIBRARY_PATH="$runtime_library_path" "$host" \
    "$demo_root/shaders-legacy" \
    --api legacy \
    --backend vulkan \
    --headless \
    --output "$results_dir/cornell-legacy.ppm"
cmp "$results_dir/cornell-structural.ppm" "$results_dir/cornell-legacy.ppm"

NATIVE_BUILD_JOBS=8 "$limited_build" "$compiler" \
    -std=c++17 \
    -O2 \
    -I"$compiler_root/include" \
    "$demo_root/perf/slang-compile-benchmark.cpp" \
    "$compiler_root/lib/libslang-compiler.so" \
    -Wl,-rpath,"$compiler_root/lib" \
    -o "$demo_root/build/slang-compile-benchmark"

compiler_label="$("$compiler_root/bin/slangc" -version 2>&1); source $(git -C "$slang_repo" rev-parse --short=12 HEAD 2>/dev/null || true)"
compile_benchmark="$demo_root/build/slang-compile-benchmark"
common_compile_arguments=(
    --compiler-label "$compiler_label"
    --host-label "$host_label"
    --warmup "$warmup"
    --iterations "$iterations"
    --entry RayGeneration raygeneration
    --entry PrimaryClosestHit closesthit
    --entry ShadowClosestHit closesthit
    --entry PrimaryMiss miss
    --entry ShadowMiss miss
)

"$compile_benchmark" \
    --target spirv \
    --output "$results_dir/compile-spirv.json" \
    --case structural "$demo_root/shaders" rt_pipeline experimental \
    --case legacy "$demo_root/shaders-legacy" rt_pipeline standard \
    "${common_compile_arguments[@]}"

# Metal has no legacy Slang API lane; this records only Slang-to-MSL generation.
"$compile_benchmark" \
    --target metal \
    --output "$results_dir/compile-metal-slang.json" \
    --case structural "$demo_root/shaders" rt_pipeline experimental \
    "${common_compile_arguments[@]}"

for api in structural legacy; do
    shader_directory="$demo_root/shaders"
    if [[ "$api" == "legacy" ]]; then
        shader_directory="$demo_root/shaders-legacy"
    fi
    LD_LIBRARY_PATH="$runtime_library_path" "$host" \
        "$shader_directory" \
        --api "$api" \
        --backend vulkan \
        --benchmark \
        --warmup "$warmup" \
        --iterations "$iterations" \
        --benchmark-output "$results_dir/runtime-vulkan-$api.json"
done

python3 "$demo_root/perf/report.py" \
    --input-dir "$demo_root/perf-results" \
    --output "$demo_root/reports/performance.md"
