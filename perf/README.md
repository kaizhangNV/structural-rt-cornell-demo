# Path-tracer benchmarks

Run these commands from the demo repository root. The current report is
[performance.md](../reports/performance.md); its linked JSON contains retained samples,
correctness results, source hashes and tool hashes.

`collect.py` collects one platform, `runtime-suite.py` runs correctness-gated paired GPU
measurements, and `path-tracer-report.py` validates and publishes all three collections.
The C++ compile tools are independently reusable: they accept shader cases rather than
hard-coding Cornell shaders. The Python collector supplies this sample's entry points
and scene settings.

## Prepare the same inputs on all runners

Use the same demo snapshot and Slang source revision on Linux and Windows. Build the compiler
and slang-rhi with optimizations enabled. The September 30 report used Slang
`eb5be680b597ae547abe1f8338f223896fceaca3` and slang-rhi
`acc98559009ac5f1cc16d3ffe008797cdfd0ace9`, Linux RelWithDebInfo and Windows Release.
Initialize the demo's GLFW submodule with `git submodule update --init`.

Generate the Metal artifact/reflection pair once on Linux, then copy the same demo snapshot
to Windows and macOS, including `generated/`. Do not regenerate this pair independently
on each runner: even source-location strings can change its hash. The publisher rejects
different source hashes, compiler revisions or benchmark settings across collections.
macOS uses the generated artifact and does not need to build Slang.

Use a fresh campaign directory. The examples use `perf-results/my-campaign/PLATFORM`;
do not reuse a completed collection directory. Keep unrelated GPU jobs idle, record the
power/clock configuration, and keep both implementations under the same conditions.
All benchmark and correctness commands below are headless. Do not remove the Linux
OptiX interactive guard.

## Linux: build, then collect Vulkan and OptiX

Replace the compiler path and configuration with your built checkout. This build helper
also generates the Metal artifacts that must be copied to the other runners.

```bash
export SLANG_REPO=/path/to/slang
export SLANG_BUILD="$SLANG_REPO/build"
export SLANG_CONFIG=RelWithDebInfo

./run-linux.sh --headless --width 32 --height 32 --samples 1 \
  --output build/benchmark-build-smoke.ppm

c++ -std=c++17 -O2 -I"$SLANG_REPO/include" \
  perf/slang-compile-benchmark.cpp \
  "$SLANG_BUILD/$SLANG_CONFIG/lib/libslang-compiler.so" \
  -Wl,-rpath,"$SLANG_BUILD/$SLANG_CONFIG/lib" \
  -o build/slang-compile-benchmark

python3 perf/collect.py --platform linux \
  --renderer build/structural-rt-cornell-rhi \
  --compile-tool build/slang-compile-benchmark \
  --optix-include "$SLANG_REPO/external/optix-dev/include" \
  --ptx-arch compute_120 \
  --compiler-label "$("$SLANG_BUILD/$SLANG_CONFIG/bin/slangc" -version 2>&1)" \
  --compiler-commit "$(git -C "$SLANG_REPO" rev-parse HEAD)" \
  --compiler-build "$SLANG_CONFIG" \
  --sample-commit "$(git rev-parse HEAD)" \
  --run-id my-campaign \
  --output-dir perf-results/my-campaign/linux
```

This collects SPIR-V, PTX and MSL generation plus Vulkan/OptiX runtime. `compute_120` is
the report's Blackwell compilation target; choose a target supported by your NVRTC and
GPU when running elsewhere, and report that change. Slang's bundled downstream compiler
libraries must be available to the benchmark executable, just as to the renderer.

## Windows: build, then collect D3D12

Run in PowerShell with CMake, Visual Studio C++ build tools and Python available.
Start from the snapshot containing the Linux-generated Metal pair; the Windows helper
does not regenerate it.

```powershell
$SlangRepo = "C:/path/to/slang"
./run-windows.ps1 -SlangRepo $SlangRepo -Config Release `
  -Headless -Width 32 -Height 32 -Samples 1 -Output build/benchmark-build-smoke.ppm

python perf/collect.py --platform windows `
  --renderer build/windows/Release/structural-rt-cornell-rhi.exe `
  --compile-tool build/windows/Release/slang-compile-benchmark.exe `
  --compiler-label "$(git -C $SlangRepo describe --always --tags)" `
  --compiler-commit "$(git -C $SlangRepo rev-parse HEAD)" `
  --compiler-build Release `
  --sample-commit "$(git rev-parse HEAD)" `
  --run-id my-campaign `
  --output-dir perf-results/my-campaign/windows
```

## macOS: build, then collect Metal

Install the Apple command-line build tools and provide the Metal-cpp headers. The
manifest records the generating compiler; its source revision must match Linux/Windows.

```bash
export METAL_CPP_DIR=/path/to/metal-cpp
./run-macos.sh --headless --width 32 --height 32 --samples 1 \
  --output build/benchmark-build-smoke.ppm

python3 perf/collect.py --platform macos \
  --renderer build/structural-rt-cornell-metal \
  --metal-compile-tool build/metal-compile-benchmark \
  --compiler-label "Slang eb5be680b597; Metal 3.1" \
  --compiler-commit eb5be680b597ae547abe1f8338f223896fceaca3 \
  --compiler-build "MSL generated with Linux RelWithDebInfo; Apple Metal 3.1 library compiler" \
  --sample-commit "$(git rev-parse HEAD)" \
  --run-id my-campaign \
  --output-dir perf-results/my-campaign/macos
```

Update the compiler metadata above if you regenerate with another revision. This measures
generated versus handwritten MSL, not new versus legacy Slang. Metal generation on Linux
and Apple library compilation on macOS are separate metrics, not an end-to-end sum.

## Publish and interpret

Copy each platform's complete result directory back under the same campaign directory.
Keep the raw JSON files: the publisher checks their hashes and sample counts rather than
trusting only summary statistics. Then run:

```bash
python3 perf/path-tracer-report.py --input-dir perf-results/my-campaign \
  --date 2026-09-30 \
  --output reports/performance.md \
  --data-output reports/data/path-tracer-2026-09-30.json

python3 -m unittest discover -s tests -p 'test_*.py'
```

Set the measurement date and choose a new data filename for a later campaign. Local images and detailed logs stay in
`perf-results/`; the published bundle omits workstation paths and contains the retained
timings and provenance needed to inspect the reported comparison.

Default collection settings:

- Compile: five warmups and 50 retained samples per case. A fresh Slang session per sample
  inside one warmed global session; paired case order alternates. Maximal optimization.
- Runtime: 512×512, eight samples/pixel, eight maximum beauty bounces, seed 17; beauty and
  AO measured separately. AO uses eight rays and radius 0.75.
- Six paired fresh-process rounds, balanced AB/BA order; ten warmups and 50 retained
  dispatches per process. Three hundred timings per implementation/view, but six rounds
  are the replicate unit. No outlier filtering.
- Before timing: five-case 192×192/64-spp parity suite and seeded repeat, then image parity
  at the exact benchmark settings. Failed correctness prevents timing.

`--help` lists collection controls. To measure only one backend during development,
use `runtime-suite.py` directly, for example:

```bash
python3 perf/runtime-suite.py --kind rhi --backend vulkan \
  --renderer build/structural-rt-cornell-rhi \
  --output-dir perf-results/vulkan-check
```

GPU times exclude setup and presentation and are not application FPS. Compare only
within the same backend/device. Payload layouts, selectors and the native Metal baseline
differ, so results do not isolate API overhead. The old `run-perf-*` scripts and
`perf/report.py` belong to the archived direct-lighting workflow; do not use them to refresh
this path-tracer report or compare the different workloads as a regression.
