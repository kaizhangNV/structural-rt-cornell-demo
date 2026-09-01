# Structural ray-tracing performance report

Generated 2026-09-01T11:05:15-07:00 from 10 benchmark result file(s).

This report compares the legacy D3D/Vulkan pipeline ray-tracing API with the structural API. Metal instead compares structural Slang output with an equivalent hand-written native Metal implementation.

## Runner environments

| Measurements | OS and CPU | GPU |
| --- | --- | --- |
| Linux / SPIR-V, MSL generation, Vulkan | Linux 6.8.0-138-generic x86_64 GNU/Linux; Intel(R) Core(TM) i9-14900K | NVIDIA RTX PRO 6000 Blackwell Workstation Edition |
| Windows / DXIL, D3D12 | Microsoft Windows NT 10.0.19045.0; 13th Gen Intel(R) Core(TM) i7-13800H | NVIDIA RTX 3500 Ada Generation Laptop GPU |
| macOS / MSL library, Metal | macOS 26.5.2 arm64; Apple M4 | Apple M4 |

## Compile performance

Medians are in milliseconds. `Slang` is end-to-end API wall time from `createSession` through target extraction, less the downstream compiler timer delta. SPIR-V/MSL use `getTargetCode`; DXIL uses every `getEntryPointCode` call, matching D3D12's per-entry library path. `Downstream` is Slang's built-in timer: `spirv-opt` for SPIR-V and DXC for DXIL.

| Target | Implementation | Slang | Downstream | Total wall | Target bytes |
| --- | --- | ---: | ---: | ---: | ---: |
| DXIL | structural | 53.930 | 24.403 | 78.386 | 23236 |
| DXIL | legacy | 35.892 | 18.495 | 54.596 | 19416 |
| SPIR-V | structural | 28.017 | 3.655 | 31.674 | 6792 |
| SPIR-V | legacy | 18.631 | 2.980 | 21.623 | 6792 |

- SPIR-V: structural vs legacy is +50.4% in Slang and +22.6% downstream; total wall time is +46.5%.
- DXIL: structural vs legacy is +50.3% in Slang and +31.9% downstream; total wall time is +43.6%.

### Metal source compilation

Metal has no legacy Slang pipeline API. Slang-to-MSL generation is therefore listed separately from Apple's synchronous `newLibrary(source)` compilation of generated and hand-written MSL. Each Apple compiler sample gets a clock-seeded unique trailing comment to avoid persistent source-hash cache hits.

| Phase/input | Median (ms) | p95 (ms) |
| --- | ---: | ---: |
| Slang structural source → MSL | 30.531 | 31.356 |
| Apple compiler: structural-generated MSL → library | 19.287 | 19.667 |
| Apple compiler: native-handwritten MSL → library | 10.817 | 11.094 |

- Apple compilation of generated MSL vs hand-written MSL is +78.3% in median wall time.
- Slang→MSL and Apple MSL→library are kept as separate phases because they were measured on different platform runners; their medians must not be added into a synthetic end-to-end number.

## Runtime performance

All workloads render one primary ray per 256×256 pixel and, on a hit, one shadow ray. Vulkan/D3D12 use device timestamp queries immediately around `dispatchRays`. Metal uses the command buffer's `GPUStartTime`/`GPUEndTime` around a command buffer containing one compute dispatch. Compare implementations within a backend, not absolute times across these different timestamp boundaries or machines.

| Backend | Device | Implementation | Median GPU ms | p95 GPU ms | Samples |
| --- | --- | --- | ---: | ---: | ---: |
| D3D12 | NVIDIA RTX 3500 Ada Generation Laptop GPU | legacy | 0.035 | 0.037 | 50 |
| D3D12 | NVIDIA RTX 3500 Ada Generation Laptop GPU | structural | 0.035 | 0.037 | 50 |
| Metal | Apple M4 | native | 0.090 | 0.094 | 50 |
| Metal | Apple M4 | structural | 0.088 | 0.092 | 50 |
| Vulkan | NVIDIA RTX PRO 6000 Blackwell Workstation Edition | legacy | 0.013 | 0.013 | 50 |
| Vulkan | NVIDIA RTX PRO 6000 Blackwell Workstation Edition | structural | 0.013 | 0.013 | 50 |

- D3D12: structural vs legacy is +0.0% in median GPU time.
- Metal: structural vs native is -2.3% in median GPU time.
- Vulkan: structural vs legacy is +0.0% in median GPU time.

## Correctness gate

Each platform renders both implementations before timing. The performance script aborts unless the two PPM files are byte-for-byte identical.

| Platform | Baseline | Result | SHA-256 |
| --- | --- | --- | --- |
| Linux / Vulkan | legacy | identical | `8b00d87495c0f5b9b807c8452cd6a63e293a1468891c00ddcebc5ca77505ed26` |
| Windows / D3D12 | legacy | identical | `8b00d87495c0f5b9b807c8452cd6a63e293a1468891c00ddcebc5ca77505ed26` |
| macOS / Metal | native | identical | `8b00d87495c0f5b9b807c8452cd6a63e293a1468891c00ddcebc5ca77505ed26` |

The rendered image is also identical across all three platform runners.

## Methodology and interpretation

- Each compile sample creates a fresh Slang session. A single global session is retained so precompiled standard-module setup is not repeatedly charged to either API.
- Case order rotates each iteration to reduce persistent thermal and frequency bias. Warmups are excluded, raw samples remain in `perf-results/`.
- Compiler optimization is maximal for measured target generation. SPIR-V uses direct emission followed by Slang's configured `spirv-opt` downstream path.
- Runtime measurements exclude device, acceleration-structure, shader, pipeline, and shader-table/function-table creation. They measure steady-state dispatch only.
- Correctness renders run before timing and are compared byte-for-byte within each platform lane.
- The legacy shader and structural shader use the same entry-point names, sparse logical slots (1 and 4), payload, scene, camera, image size, and two-ray shading algorithm.
- The hand-written Metal baseline uses native `intersector.intersect` calls and inline post-trace hit/miss handling; it intentionally has no structural visible-function tables.
- Slang compiler labels observed: 2024.0.7-3796-gb0f010593; source b0f010593568, 2026.9.1-707-g978320da0; source b0f010593568.
- GPU devices observed: Apple M4, NVIDIA RTX 3500 Ada Generation Laptop GPU, NVIDIA RTX PRO 6000 Blackwell Workstation Edition.
