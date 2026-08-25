# Structural ray-tracing Cornell box

This is a standalone smoke demo for the structural ray-tracing API. It is intentionally outside
the Slang Git worktree and does not use `examples/example-base`.

The shader traces one primary ray per pixel. `PrimaryClosestHit` returns the surface data needed
for diffuse direct lighting, after which ray generation traces one ray toward a point light. The
shadow ray maps to `ShadowClosestHit` and `ShadowMiss`, producing a binary visibility result. There
is no path-tracing or accumulation loop.

`ProgramLayout` intentionally places the primary ray at logical slot 1 and the shadow ray at slot
4. Slots 0, 2, and 3 are holes. This is deliberately irregular so the demo shows the intended host
programming model: reflect the declared slots, allocate each native table through the largest
slot, and place records by reflected index rather than declaration order. A sparse layout consumes
space for its holes, and shader code must not trace to an unpopulated slot.

The scene is built from opaque triangles: five Cornell-box walls and two interior boxes. GLFW owns
the window and input on both platforms; it is included as the `external/glfw` submodule. The Linux
renderer uses slang-rhi/Vulkan, while the macOS renderer presents directly with Metal-cpp.

After obtaining the demo, initialize its window dependency once:

```bash
git submodule update --init
```

The default mode is interactive:

- `W`, `A`, `S`, `D`: move horizontally.
- `Q`, `E`: move down and up.
- Left mouse drag: look around.
- Escape: close the window.

## Linux: slang-rhi and Vulkan

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

The slang-rhi host calls `findTraceProgramLayout("ProgramLayout")` and enumerates the reflected hit,
miss, and callable groups. Their reflected slots determine the pipeline and shader-table indices;
their reflected stage names locate synthesized entry points in `rt_pipeline`. No stage-table index
is inferred from source declaration order.

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

`run-linux.sh` also serializes that structural reflection to
`generated/program-layout.txt`, alongside the generated Metal source. This models an offline shader
build: the Metal host reads the reflected slots and inserts each visible function at that index in
the Metal function table. The manifest is generated data, not a second hand-authored description of
the SBT layout.

With the current compiler and scene, both headless hosts produce checksum `777626b0f3ca5dd9`.

## Files

- `shaders/shared.slang`: imported module containing the shared payload, contexts, frame data, and
  ray construction.
- `shaders/rt_pipeline.slang`: pipeline module and short table of contents that `__include`s the
  remaining shader files.
- `shaders/hit.slang`: included primary and shadow closest-hit stages.
- `shaders/miss.slang`: included primary and shadow miss stages.
- `shaders/program_layout.slang`: included structural SBT declaration with sparse slots 1 and 4.
- `shaders/raygen.slang`: included ray-generation entry point and direct-lighting orchestration.
- `scene.h`: shared Cornell-box geometry and surface data.
- `demo-window.h`: shared GLFW window, input, and native-window access.
- `rhi-main.cpp`: interactive slang-rhi/Vulkan host with a headless mode.
- `metal-main.cpp`: interactive Metal-cpp host with a headless mode.
- `macos-metal-layer.mm`: minimal bridge attaching a Metal layer to GLFW's native macOS window.
- `run-linux.sh` and `run-macos.sh`: local build-and-run helpers.
