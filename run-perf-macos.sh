#!/usr/bin/env bash

set -euo pipefail

demo_root="$(cd "$(dirname "$0")" && pwd)"
results_dir="${PERF_RESULTS_DIR:-$demo_root/perf-results/macos}"
warmup="${PERF_WARMUP:-5}"
iterations="${PERF_ITERATIONS:-50}"
host_label="${PERF_HOST_LABEL:-$(sw_vers -productName) $(sw_vers -productVersion) $(uname -m); $(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)}"

mkdir -p "$results_dir"

# Build both Metal benchmark binaries and validate the generated structural shader.
"$demo_root/run-macos.sh" \
    --implementation structural \
    --headless \
    --output "$results_dir/cornell-structural.ppm"

host="$demo_root/build/structural-rt-cornell-metal"
layout="$demo_root/generated/program-layout.txt"

# Validate the native Metal implementation against the same scene and checksum.
"$host" \
    "$demo_root/shaders/cornell-box-native.metal" \
    "$layout" \
    --implementation native \
    --headless \
    --output "$results_dir/cornell-native.ppm"
cmp "$results_dir/cornell-structural.ppm" "$results_dir/cornell-native.ppm"

"$demo_root/build/metal-compile-benchmark" \
    --output "$results_dir/compile-metal-downstream.json" \
    --host-label "$host_label" \
    --warmup "$warmup" \
    --iterations "$iterations" \
    --case structural-generated "$demo_root/generated/cornell-box.metal" \
    --case native-handwritten "$demo_root/shaders/cornell-box-native.metal"

for implementation in structural native; do
    source="$demo_root/generated/cornell-box.metal"
    if [[ "$implementation" == "native" ]]; then
        source="$demo_root/shaders/cornell-box-native.metal"
    fi
    "$host" \
        "$source" \
        "$layout" \
        --implementation "$implementation" \
        --benchmark \
        --warmup "$warmup" \
        --iterations "$iterations" \
        --benchmark-output "$results_dir/runtime-metal-$implementation.json"
done

for result in "$results_dir"/*.json; do
    echo "PERF_RESULT_BEGIN $(basename "$result")"
    sed -n '1,100000p' "$result"
    echo "PERF_RESULT_END $(basename "$result")"
done
