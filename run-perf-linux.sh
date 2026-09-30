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
compiler_root="${SLANG_PERF_COMPILER_ROOT:-$slang_build/Release}"
compiler="${CXX:-c++}"
native_build_jobs="${NATIVE_BUILD_JOBS:-8}"
results_dir="${PERF_RESULTS_DIR:-$demo_root/perf-results/linux}"
warmup="${PERF_WARMUP:-5}"
iterations="${PERF_ITERATIONS:-50}"
host_label="${PERF_HOST_LABEL:-$(uname -srmo); $(lscpu | sed -n 's/^Model name:[[:space:]]*//p' | head -n 1)}"

if [[ ! -f "$compiler_root/lib/libslang-compiler.so" ]]; then
    echo "release Slang compiler package is missing under $compiler_root" >&2
    exit 2
fi

mkdir -p "$demo_root/build" "$results_dir"

# Build the sample host once and validate the structural output.
SLANG_REPO="$slang_repo" SLANG_BUILD="$slang_build" SLANG_CONFIG="$config" \
    NATIVE_BUILD_JOBS="$native_build_jobs" \
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

# OptiX uses the same split structural payloads through a different native payload ABI. Keep it as
# a separate correctness and runtime lane; this caught a payload-register count regression during
# the schema migration.
for api in structural legacy; do
    shader_directory="$demo_root/shaders"
    if [[ "$api" == "legacy" ]]; then
        shader_directory="$demo_root/shaders-legacy"
    fi
    LD_LIBRARY_PATH="$runtime_library_path" "$host" \
        "$shader_directory" \
        --api "$api" \
        --backend optix \
        --optix-include "$slang_repo/external/optix-dev/include" \
        --headless \
        --output "$results_dir/cornell-optix-$api.ppm"
done
cmp "$results_dir/cornell-optix-structural.ppm" "$results_dir/cornell-optix-legacy.ppm"

"$compiler" \
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
    --legacy-entry PrimaryClosestHit closesthit
    --legacy-entry ShadowClosestHit closesthit
    --legacy-entry PrimarySphereClosestHit closesthit
    --legacy-entry ShadowSphereClosestHit closesthit
    --legacy-entry PrimarySphereIntersection intersection
    --legacy-entry ShadowSphereIntersection intersection
    --legacy-entry PrimaryMiss miss
    --legacy-entry ShadowMiss miss
)

"$compile_benchmark" \
    --target spirv \
    --output "$results_dir/compile-spirv-structural.json" \
    --case structural "$demo_root/shaders" rt_pipeline experimental ProgramSchema \
    "${common_compile_arguments[@]}"

# Metal has no legacy Slang API lane; this records only Slang-to-MSL generation.
"$compile_benchmark" \
    --target metal \
    --output "$results_dir/compile-metal-slang.json" \
    --case structural "$demo_root/shaders" rt_pipeline experimental ProgramSchema \
    "${common_compile_arguments[@]}"

LD_LIBRARY_PATH="$runtime_library_path" "$host" \
    "$demo_root/shaders" \
    --api structural \
    --backend vulkan \
    --benchmark \
    --warmup "$warmup" \
    --iterations "$iterations" \
    --benchmark-output "$results_dir/runtime-vulkan-structural.json"

for api in structural legacy; do
    shader_directory="$demo_root/shaders"
    if [[ "$api" == "legacy" ]]; then
        shader_directory="$demo_root/shaders-legacy"
    fi
    LD_LIBRARY_PATH="$runtime_library_path" "$host" \
        "$shader_directory" \
        --api "$api" \
        --backend optix \
        --optix-include "$slang_repo/external/optix-dev/include" \
        --benchmark \
        --warmup "$warmup" \
        --iterations "$iterations" \
        --benchmark-output "$results_dir/runtime-optix-$api.json"
done

python3 "$demo_root/perf/report.py" \
    --input-dir "$demo_root/perf-results" \
    --output "$demo_root/reports/performance.md"

for result in "$results_dir"/*.json; do
    echo "PERF_RESULT_BEGIN $(basename "$result")"
    sed -n '1,100000p' "$result"
    echo "PERF_RESULT_END $(basename "$result")"
done
