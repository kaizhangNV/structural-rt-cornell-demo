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
manifest="$demo_root/generated/program-schema.txt"
structural_provenance="$(sed -n 's/^compiler "\([^"]*\)" "\([^"]*\)"$/\1; source \2/p' "$manifest")"
if [[ -z "$structural_provenance" ]]; then
    echo "generated schema manifest has no compiler/source provenance" >&2
    exit 1
fi

# Validate the native Metal implementation against the same scene and checksum.
"$host" \
    "$demo_root/shaders/cornell-box-native.metal" \
    "$manifest" \
    --implementation native \
    --headless \
    --output "$results_dir/cornell-native.ppm"
cmp "$results_dir/cornell-structural.ppm" "$results_dir/cornell-native.ppm"

"$demo_root/build/metal-compile-benchmark" \
    --output "$results_dir/compile-metal-downstream-structural.json" \
    --host-label "$host_label" \
    --input-provenance "$structural_provenance" \
    --warmup "$warmup" \
    --iterations "$iterations" \
    --case structural-generated "$demo_root/generated/cornell-box.metal"

"$host" \
    "$demo_root/generated/cornell-box.metal" \
    "$manifest" \
    --implementation structural \
    --benchmark \
    --warmup "$warmup" \
    --iterations "$iterations" \
    --benchmark-output "$results_dir/runtime-metal-structural.json"

for result in "$results_dir"/*.json; do
    echo "PERF_RESULT_BEGIN $(basename "$result")"
    sed -n '1,100000p' "$result"
    echo "PERF_RESULT_END $(basename "$result")"
done
