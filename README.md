# Structural ray-tracing Cornell box

This is a standalone path-tracing demo for the structural ray-tracing API. It is intentionally outside
the Slang Git worktree and does not use `examples/example-base`.

The shader progressively accumulates multi-bounce diffuse lighting from a ceiling area light.
A glass sphere floats near the room's center and adds Fresnel reflection, refraction,
total internal reflection, absorption, shadows, and refractive caustics. It is an analytic
procedural sphere: AABB traversal invokes custom intersection programs, not a triangle mesh.
A separate ambient-occlusion view shows finite-radius visibility. The path loop runs
in ray generation; closest-hit returns surface data, and a small second payload handles shadow
and AO rays. See [the path-tracer report](reports/path-tracer.md) for validation and API findings.

The repository also contains equivalent baselines for performance work: the legacy Slang
`TraceRay` pipeline API under `shaders-legacy/`, and a hand-written native Metal implementation in
`shaders/cornell-box-native.metal`.

## Video

[![Cornell path tracer: glass, indirect lighting, and ambient occlusion][demo-preview]][demo-video]

Click the animated preview to play the updated 20-second video. It shows real headless Vulkan renders:
sample convergence, glass reflection/refraction, indirect versus direct-only lighting, and AO.
This is an edited offline showcase, **not** a real-time performance recording.

Full-resolution stills: [beauty, 4096 spp / eight bounces](media/cornell-pathtracer-beauty.png)
and [AO diagnostic](media/cornell-pathtracer-ao.png). Validation and reproduction commands are in
[the path-tracer report](reports/path-tracer.md).

To regenerate the video after building the Linux renderer, run
`python3 tools/render-readme-video.py --ffmpeg /path/to/ffmpeg` (requires Pillow, FFmpeg/libvpx,
and DejaVu Sans fonts). Captures and their command/hash manifest stay under `build/readme-video/`.

`ProgramSchema` declares which hit, miss, and callable programs are available, but it does not
declare an SBT layout. The host deliberately places triangle primary/shadow records at physical
indices 1/4 and sphere primary/shadow records at 9/12, leaving holes. The sphere instance adds
an SBT contribution of 8 to the selectors in `FrameData`. The structural shader uses distinct
`PrimaryPayload` and `ShadowPayload` partitions, each with triangle and procedural hit groups.

Five Cornell-box walls, two interior boxes, and a ceiling light use triangles. The sphere has
one AABB, center `(0, 0.75, 0)`, and radius `0.4` in a 2×2×2 room. It clears the floor by `0.35`
units; the larger, lower sphere gives a more concentrated floor caustic. Its intersection shader solves
the ray/sphere quadratic and reports the hit distance plus custom normal attributes. The path
integrator implements glass reflection/refraction. GLFW owns
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

The window title shows FPS and accumulated samples per pixel (spp). The interactive view adds one
sample per frame and resets accumulation when the camera moves or the window resizes.

## Rendering controls

Headless defaults are 256×256, 64 spp, eight bounces, and a glass sphere. For a cleaner image:

```bash
./run-linux.sh --headless --samples 1024 --width 512 --height 512 --output cornell-path.ppm
./run-linux.sh --view ao --ao-radius 0.75
```

Linux/macOS accept `--samples`, `--bounces`, `--view beauty|ao|direct`,
`--sphere glass|diffuse|none`, `--ao-radius`, `--ao-samples`, `--seed`, and `--exposure`.
`--width`/`--height` set headless and benchmark size; interactive windows start at 960×720.
`--samples` sets the headless total or samples per benchmark dispatch; interactive mode keeps
accumulating until stopped. Windows exposes the corresponding PowerShell parameters, for example:

```powershell
./run-windows.ps1 -SlangRepo C:/path/to/slang -Config Release `
    -Headless -Samples 1024 -Width 512 -Height 512 -View beauty -Sphere glass
```

AO is a diagnostic view, not an extra multiplier on physically traced beauty lighting. The
renderer has no denoiser; glass caustics need more samples. Direct-light visibility rays treat
glass as an occluder, while paths through glass can still sample caustics stochastically.

## Linux: slang-rhi with Vulkan or OptiX

Without overrides, the runner uses a sibling `../slang` checkout when present, then falls back to
the historical `../another-slang-rt-integration` development checkout. It uses that checkout's
Release build:

```bash
./run-linux.sh
```

Override them when needed:

```bash
SLANG_REPO=/path/to/slang \
SLANG_BUILD=/path/to/slang/build \
SLANG_CONFIG=Release \
./run-linux.sh
```

Native builds use at most eight parallel jobs by default. Set `NATIVE_BUILD_JOBS` to use a smaller
limit; the scripts do not depend on any workstation-specific build wrapper.

For a deterministic headless render instead:

```bash
./run-linux.sh --headless
```

This writes `cornell-box-vulkan.ppm`.

Select the legacy API with the same host and scene:

```bash
./run-linux.sh --api legacy --backend vulkan
```

Select headless OptiX with the same host and host-owned record layout:

```bash
./run-linux.sh --backend optix --headless
```

The headless command writes `cornell-box-optix.ppm`. The helper supplies NVRTC with the OptiX
headers from the selected Slang worktree.

Linux OptiX interactive presentation is temporarily disabled: a repeated window test crashed
Xorg inside NVIDIA's display driver during surface configuration, before the first tracing frame.
Headless OptiX rendering and benchmarking pass; use
Vulkan for the Linux interactive window. This unresolved presentation issue is separate from
the shader API and is documented in the path-tracer report.

The slang-rhi host calls `findTraceProgramSchema("ProgramSchema")`. It uses reflected payload and
attribute ABI sizes for pipeline creation, then resolves each physical record by the pair
`(payload type, schema entry type)`. Function indices are local to a payload partition and are not
physical SBT positions.

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

Run `run-linux.sh` once to generate `generated/cornell-box.metal` and
`generated/program-schema.txt`,
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

`run-linux.sh` builds `metal-artifact-generator.cpp` against the selected Slang compiler. The tool
generates MSL and serializes target-specific schema reflection, descriptor binding IDs, record
strides, per-payload function tables, intersection signatures, and compiler provenance together.
The Metal host reads this sidecar and separately builds the host-owned physical record layout. The
manifest also fingerprints the generated MSL so stale or mismatched artifact pairs fail before
pipeline compilation. It is generated ABI data, not a second shader-side SBT declaration.

The previous direct-lighting scene's checksum does not apply to the path tracer. Use
`tools/validate-pathtracer.py` for same-backend structural/reference comparisons, seeded
repeatability, and visual-effect checks. Its tolerances and results are in the path-tracer report.

## Performance measurements

The historical direct-lighting cross-platform results and their interpretation are in
[reports/performance.md](reports/performance.md). The migration checklist and design-gap assessment
are in [reports/dynamic-schema-migration.md](reports/dynamic-schema-migration.md).

Those timings do **not** describe the new path tracer. Do not combine new path-tracing results
with retained direct-lighting baselines. The legacy refresh scripts below preserve some old
baseline JSON and regenerate that historical report; a new performance campaign must measure
both implementations with identical path-tracing settings in a separate results directory.
Runtime JSON now records spp, bounce limit, view, sphere, AO, exposure, and seed.

Each platform script first renders both lanes and aborts unless their PPM files are byte-for-byte
identical. It then runs five warmups and 50 measured iterations by default:

```bash
# Linux: Slang→SPIR-V, spirv-opt, Vulkan GPU time, and OptiX GPU time
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

Use the repeatable `--refresh-run "platform: run-id"` option when the results came from saved
build-farm runs and should carry those run IDs into the report.

The metrics have deliberately narrow boundaries:

- `total_wall_ms` creates a fresh Slang session, loads and links the module, then extracts target
  code. SPIR-V uses `getTargetCode`, MSL uses the ray-generation `getEntryPointCode`, and DXIL
  extracts every entry point with `getEntryPointCode`, matching slang-rhi's D3D12 pipeline path.
- `downstream_ms` is the delta from Slang's compiler timer. It measures `spirv-opt` for direct
  SPIR-V generation and DXC for DXIL. `slang_ms` is total wall time minus that delta.
- Metal downstream time is synchronous `MTLDevice::newLibrary(source)` wall time. Every sample adds
  a clock-seeded unique trailing source comment to avoid persistent source-hash cache hits.
- Runtime is steady-state GPU dispatch time only. Vulkan, OptiX, and D3D12 use timestamp queries
  directly around `dispatchRays`; Metal uses the GPU start/end timestamps of a command buffer
  containing one compute dispatch. Setup and pipeline compilation are excluded.

`perf/slang-compile-benchmark.cpp` is reusable: each `--case` supplies an optional reflected schema
name, `--entry` supplies ordinary roots such as ray generation, and `--legacy-entry` supplies only
the explicit stages needed by old pipeline shaders. The tool discovers structural stages from the
schema. `perf/metal-compile-benchmark.cpp` likewise accepts repeated named Metal source cases. Both emit the common
`slang-ray-tracing-perf-v1` JSON schema consumed by `perf/report.py`.

The refresh scripts write new structural-only result files and retain existing legacy/native
baseline JSON. The report shows compiler/source provenance per compile row and labels comparisons
that cross compiler revisions.

## Files

- `shaders/shared.slang`: imported module containing the two payloads, contexts, frame data, and
  ray construction.
- `shaders/rt_pipeline.slang`: pipeline module and short table of contents that `__include`s the
  remaining shader files.
- `shaders/hit.slang`: included primary and shadow closest-hit stages.
- `shaders/miss.slang`: included primary and shadow miss stages.
- `shaders/program_schema.slang`: included shader-program schema; it contains no SBT positions.
- `shaders/raygen.slang`: included ray-generation entry point and structural trace adapters.
- `shaders/path_tracing.slangh`: shared Slang integrator, materials, sampling, and display mapping.
- `shaders/sphere_intersection.slangh`: shared analytic sphere roots and custom hit attributes.
- `shaders-legacy/`: equivalent old-API Slang ray-generation, hit, and miss shaders.
- `shaders/cornell-box-native.metal`: equivalent hand-written native Metal intersector baseline.
- `scene.h`: shared Cornell-box geometry and surface data.
- `render-settings.h`: common validated rendering options and frame ABI setup.
- `tools/validate-pathtracer.py`: deterministic image comparisons and feature/convergence checks.
- `tools/render-readme-video.py`: reproducible headless capture and README video encoding.
- `demo-window.h`: shared GLFW window, input, and native-window access.
- `rhi-main.cpp`: shared Vulkan, OptiX, and D3D12 slang-rhi host with interactive and headless
  modes.
- `metal-main.cpp`: interactive Metal-cpp host with a headless mode.
- `metal-artifact-generator.cpp`: compiler-API tool that emits MSL plus its reflected Metal ABI
  sidecar.
- `macos-metal-layer.mm`: minimal bridge attaching a Metal layer to GLFW's native macOS window.
- `run-linux.sh`, `run-windows.ps1`, and `run-macos.sh`: local build-and-run helpers.
- `perf/` and `run-perf-*`: reusable compile/runtime measurement tools, report generator, and
  platform orchestration scripts.

[demo-preview]: media/cornell-box-demo.gif
[demo-video]: media/cornell-box-demo.webm?raw=true
