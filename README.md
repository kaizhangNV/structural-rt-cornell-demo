# Structural ray-tracing Cornell box

This is a standalone smoke demo for the structural ray-tracing API. It is intentionally outside
the Slang Git worktree and does not use `examples/example-base`.

The shader traces one primary ray per pixel. `PrimaryClosestHit` returns the surface data needed
for diffuse direct lighting, after which ray generation traces one ray toward a point light. The
shadow ray maps to `ShadowClosestHit` and `ShadowMiss`, producing a binary visibility result. There
is no path-tracing or accumulation loop.

The repository also contains equivalent baselines for performance work: the legacy Slang
`TraceRay` pipeline API under `shaders-legacy/`, and a hand-written native Metal implementation in
`shaders/cornell-box-native.metal`.

## Video

[![Cornell box ray-tracing demo][demo-preview]][demo-video]

Click the image to play the three-second screen recording with a small interactive camera pan.

`ProgramLayout` intentionally places the primary ray at logical slot 1 and the shadow ray at slot
4. Slots 0, 2, and 3 are holes. This is deliberately irregular so the demo shows the intended host
programming model: reflect the declared slots, allocate each native table through the largest
slot, and place records by reflected index rather than declaration order. A sparse layout consumes
space for its holes, and shader code must not trace to an unpopulated slot.

The scene is built from opaque triangles: five Cornell-box walls and two interior boxes. GLFW owns
the window and input on every platform; it is included as the `external/glfw` submodule. The Linux
host supports slang-rhi/Vulkan and slang-rhi/OptiX, the Windows host uses slang-rhi/D3D12, and the
macOS host presents directly with Metal-cpp.

After obtaining the demo, initialize its window dependency once:

```bash
git submodule update --init
```

The default mode is interactive:

- `W`, `A`, `S`, `D`: move horizontally.
- `Q`, `E`: move down and up.
- Left mouse drag: look around.
- Escape: close the window.

## Linux: slang-rhi with Vulkan or OptiX

The default paths point at the current structural-ray-tracing worktree and its Debug build:

```bash
./run-linux.sh
```

Override them when needed:

```bash
SLANG_REPO=/path/to/slang \
SLANG_BUILD=/path/to/slang/build \
SLANG_CONFIG=Debug \
./run-linux.sh
```

For a deterministic headless render instead:

```bash
./run-linux.sh --headless
```

This writes `cornell-box-vulkan.ppm`.

Select the legacy API with the same host and scene:

```bash
./run-linux.sh --api legacy --backend vulkan
```

Select OptiX with the same host and shader layout:

```bash
./run-linux.sh --backend optix
./run-linux.sh --backend optix --headless
```

The headless command writes `cornell-box-optix.ppm`. The helper supplies NVRTC with the OptiX
headers from the selected Slang worktree.

The slang-rhi host calls `findTraceProgramLayout("ProgramLayout")` and enumerates the reflected hit,
miss, and callable groups. Their reflected slots determine the pipeline and shader-table indices;
their reflected stage names locate synthesized entry points in `rt_pipeline`. No stage-table index
is inferred from source declaration order.

## Windows: slang-rhi and D3D12

Point the helper at a built structural-ray-tracing Slang worktree:

```powershell
./run-windows.ps1 -SlangRepo C:/path/to/slang -SlangBuild C:/path/to/slang/build
```

For a deterministic headless render:

```powershell
./run-windows.ps1 `
    -SlangRepo C:/path/to/slang `
    -SlangBuild C:/path/to/slang/build `
    -Headless
```

This writes `cornell-box-d3d12.ppm`. The Windows CMake project builds only the D3D12 portion of
slang-rhi and imports the compiler from the selected Slang build.

Pass `-Api legacy` to run the equivalent old pipeline API:

```powershell
./run-windows.ps1 `
    -SlangRepo C:/path/to/slang `
    -SlangBuild C:/path/to/slang/build `
    -Api legacy
```

## macOS: Metal-cpp

Generate `generated/cornell-box.metal` and `generated/program-layout.txt` on the Linux build host,
place Apple's `metal-cpp` headers in `metal-cpp/` (or set `METAL_CPP_DIR`), and run:

```bash
./run-macos.sh
```

The Metal host builds the same triangle acceleration structures, visible-function tables, and
structural `TraceProgramDescriptor` resources directly with Metal-cpp. Its only Objective-C++ code
attaches a `CAMetalLayer` to the native window created by GLFW.

For its deterministic headless render:

```bash
./run-macos.sh --headless
```

This writes `cornell-box-metal.ppm`.

Run the hand-written Metal baseline with:

```bash
./run-macos.sh --implementation native
```

`run-linux.sh` also serializes that structural reflection to
`generated/program-layout.txt`, alongside the generated Metal source. This models an offline shader
build: the Metal host reads the reflected slots and inserts each visible function at that index in
the Metal function table. The manifest is generated data, not a second hand-authored description of
the SBT layout.

With the current compiler and scene, every headless backend produces checksum
`777626b0f3ca5dd9`.

## Performance measurements

The current cross-platform results and their interpretation are in
[reports/performance.md](reports/performance.md). Each platform script first renders both lanes and
aborts unless their PPM files are byte-for-byte identical. It then runs five warmups and 50 measured
iterations by default:

```bash
# Linux: Slang→SPIR-V, spirv-opt, and Vulkan GPU time
SLANG_PERF_COMPILER_ROOT=/path/to/slang/build/Release ./run-perf-linux.sh

# macOS: generated/hand-written MSL compilation and Metal GPU time
METAL_CPP_DIR=/path/to/metal-cpp ./run-perf-macos.sh
```

```powershell
# Windows: Slang→DXIL, DXC, and D3D12 GPU time
./run-perf-windows.ps1 `
    -SlangRepo C:/path/to/slang `
    -SlangBuild C:/path/to/slang/build `
    -Config Release
```

Override `PERF_WARMUP` and `PERF_ITERATIONS` on Linux/macOS, or `-Warmup` and `-Iterations` on
Windows. Linux requires a Release compiler package containing the downstream `slang-glslang`
plugin; the script rejects zero downstream time instead of silently reporting an invalid
measurement. Raw JSON and correctness images go under the ignored `perf-results/` directory. To
regenerate the checked-in report after collecting results, run:

```bash
python3 perf/report.py --input-dir perf-results --output reports/performance.md
```

The metrics have deliberately narrow boundaries:

- `total_wall_ms` creates a fresh Slang session, loads and links the module, then extracts target
  code. SPIR-V and MSL use `getTargetCode`; DXIL extracts every entry point with
  `getEntryPointCode`, matching slang-rhi's D3D12 pipeline path.
- `downstream_ms` is the delta from Slang's compiler timer. It measures `spirv-opt` for direct
  SPIR-V generation and DXC for DXIL. `slang_ms` is total wall time minus that delta.
- Metal downstream time is synchronous `MTLDevice::newLibrary(source)` wall time. Every sample adds
  a clock-seeded unique trailing source comment to avoid persistent source-hash cache hits.
- Runtime is steady-state GPU dispatch time only. Vulkan and D3D12 use timestamp queries directly
  around `dispatchRays`; Metal uses the GPU start/end timestamps of a command buffer containing one
  compute dispatch. Setup and pipeline compilation are excluded.

`perf/slang-compile-benchmark.cpp` is sample-independent: add repeated `--case` and `--entry`
arguments to benchmark another port without rewriting the timer. `perf/metal-compile-benchmark.cpp`
likewise accepts repeated named Metal source cases. Both emit the common
`slang-ray-tracing-perf-v1` JSON schema consumed by `perf/report.py`.

## Files

- `shaders/shared.slang`: imported module containing the shared payload, contexts, frame data, and
  ray construction.
- `shaders/rt_pipeline.slang`: pipeline module and short table of contents that `__include`s the
  remaining shader files.
- `shaders/hit.slang`: included primary and shadow closest-hit stages.
- `shaders/miss.slang`: included primary and shadow miss stages.
- `shaders/program_layout.slang`: included structural SBT declaration with sparse slots 1 and 4.
- `shaders/raygen.slang`: included ray-generation entry point and direct-lighting orchestration.
- `shaders-legacy/`: equivalent old-API Slang ray-generation, hit, and miss shaders.
- `shaders/cornell-box-native.metal`: equivalent hand-written native Metal intersector baseline.
- `scene.h`: shared Cornell-box geometry and surface data.
- `demo-window.h`: shared GLFW window, input, and native-window access.
- `rhi-main.cpp`: shared Vulkan, OptiX, and D3D12 slang-rhi host with interactive and headless
  modes.
- `metal-main.cpp`: interactive Metal-cpp host with a headless mode.
- `macos-metal-layer.mm`: minimal bridge attaching a Metal layer to GLFW's native macOS window.
- `run-linux.sh`, `run-windows.ps1`, and `run-macos.sh`: local build-and-run helpers.
- `perf/` and `run-perf-*`: reusable compile/runtime measurement tools, report generator, and
  platform orchestration scripts.

[demo-preview]: media/cornell-box-demo.gif
[demo-video]: https://raw.githubusercontent.com/kaizhangNV/structural-rt-cornell-demo/main/media/cornell-box-demo.webm
