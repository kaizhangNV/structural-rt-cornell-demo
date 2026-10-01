# Dynamic-schema ray-tracing performance report

Generated 2026-09-14T12:36:15-07:00 from 15 benchmark result file(s).

Structural refresh runs: `Linux: 20260914-cdecb7503-linux-isolated-v2`, `Windows: 20260914-cdecb7503-structural-final`, `macOS: 20260914-cdecb7503-metal-pair-final`.

This report compares the legacy D3D/Vulkan/OptiX pipeline ray-tracing API with the revised schema-based API. Metal instead compares generated Slang output with an equivalent hand-written native Metal implementation.

## Structural refresh runner environments

| Measurements | OS and CPU | GPU |
| --- | --- | --- |
| Linux / SPIR-V, MSL generation, Vulkan | Linux 6.8.0-139-generic x86_64 GNU/Linux; Intel(R) Core(TM) i9-14900K | NVIDIA RTX PRO 6000 Blackwell Workstation Edition |
| Windows / DXIL, D3D12 | Microsoft Windows NT 10.0.19045.0; 13th Gen Intel(R) Core(TM) i7-13800H | NVIDIA RTX 3500 Ada Generation Laptop GPU |
| Linux / OptiX runtime | Linux 6.8.0-139-generic x86_64 GNU/Linux; Intel(R) Core(TM) i9-14900K | NVIDIA RTX PRO 6000 Blackwell Workstation Edition |
| macOS / MSL library, Metal | macOS 26.6.2 arm64; Apple M4 | Apple M4 |

## Compile performance

Medians are in milliseconds. `Slang` is end-to-end API wall time from `createSession` through target extraction, less the downstream compiler timer delta. SPIR-V uses `getTargetCode`; MSL uses the ray-generation `getEntryPointCode`; DXIL uses every `getEntryPointCode` call, matching D3D12's per-entry library path. `Downstream` is Slang's built-in timer: `spirv-opt` for SPIR-V and DXC for DXIL.

| Target | Implementation | Compiler/source | Slang | Downstream | Total wall | Target bytes |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| DXIL | structural | 2024.0.7-3982-gcdecb7503; source cdecb75031c1 | 44.990 | 21.238 | 66.255 | 23472 |
| DXIL | legacy | 2024.0.7-3796-gb0f010593; source b0f010593568 | 35.892 | 18.495 | 54.596 | 19416 |
| SPIR-V | structural | 2026.17.1-156-gcdecb7503; source cdecb75031c1 | 29.212 | 3.913 | 33.122 | 7420 |
| SPIR-V | legacy | 2026.9.1-707-g978320da0; source b0f010593568 | 18.631 | 2.980 | 21.623 | 6792 |

- SPIR-V: structural vs legacy is **not directly comparable**. The retained legacy baseline uses a different compiler/source revision; the individual values remain in the table as historical context.
- DXIL: structural vs legacy is **not directly comparable**. The retained legacy baseline uses a different compiler/source revision; the individual values remain in the table as historical context.

### Metal source compilation

Metal has no legacy Slang pipeline API. Slang-to-MSL generation is therefore listed separately from Apple's synchronous `newLibrary(source)` compilation of generated and hand-written MSL. Each Apple compiler sample gets a clock-seeded unique trailing comment to avoid persistent source-hash cache hits.

| Phase/input | Compiler/source | Median (ms) | p95 (ms) |
| --- | --- | ---: | ---: |
| Slang structural source → MSL | 2026.17.1-156-gcdecb7503; source cdecb75031c1 | 29.532 | 31.331 |
| Apple compiler: native-handwritten MSL → library | hand-written MSL; retained baseline | 10.817 | 11.094 |
| Apple compiler: structural-generated MSL → library | 2026.17.1-156-gcdecb7503; source cdecb75031c1ce125985e51032c00a11c1f85492 | 21.855 | 23.162 |

- Apple compilation of generated MSL vs hand-written MSL is **not directly comparable**. The hand-written row is a retained baseline from different recorded host/toolchain provenance; both individual values remain in the table as historical context.
- Slang→MSL and Apple MSL→library are kept as separate phases because they were measured on different platform runners; their medians must not be added into a synthetic end-to-end number.

## Runtime performance

All workloads render one primary ray per 256×256 pixel and, on a hit, one shadow ray. Vulkan/D3D12/OptiX use device timestamp queries immediately around `dispatchRays`. Metal uses the command buffer's `GPUStartTime`/`GPUEndTime` around a command buffer containing one compute dispatch. Compare implementations within a backend, not absolute times across these different timestamp boundaries or machines.

| Backend | Device | Implementation | Median GPU ms | p95 GPU ms | Samples |
| --- | --- | --- | ---: | ---: | ---: |
| D3D12 | NVIDIA RTX 3500 Ada Generation Laptop GPU | legacy | 0.035 | 0.037 | 50 |
| D3D12 | NVIDIA RTX 3500 Ada Generation Laptop GPU | structural | 0.035 | 0.037 | 50 |
| Metal | Apple M4 | native | 0.090 | 0.094 | 50 |
| Metal | Apple M4 | structural | 0.092 | 0.098 | 50 |
| OptiX | NVIDIA RTX PRO 6000 Blackwell Workstation Edition | legacy | 0.020 | 0.022 | 50 |
| OptiX | NVIDIA RTX PRO 6000 Blackwell Workstation Edition | structural | 0.020 | 0.021 | 50 |
| Vulkan | NVIDIA RTX PRO 6000 Blackwell Workstation Edition | legacy | 0.013 | 0.013 | 50 |
| Vulkan | NVIDIA RTX PRO 6000 Blackwell Workstation Edition | structural | 0.013 | 0.013 | 50 |

- D3D12: structural vs legacy is +0.0% in median GPU time.
- Metal: structural vs native is +1.8% in median GPU time.
- OptiX: structural vs legacy is +0.0% in median GPU time.
- Vulkan: structural vs legacy is +0.0% in median GPU time.

The retained Vulkan, D3D12, and Metal baseline JSON files do not contain a run ID or collection timestamp. Their comparisons use the same documented runner/device class but are not contemporaneous; compiler-generated baselines may also use an earlier compiler/source revision. Their percentages are historical context, not clean API-only regression estimates. This structural-only refresh preserves those baselines as requested. The new OptiX structural and legacy rows were collected together in the same run.

## Correctness gate

Each platform renders both implementations before timing. The performance script aborts unless the two PPM files are byte-for-byte identical.

| Platform | Baseline | Result | SHA-256 |
| --- | --- | --- | --- |
| Linux / Vulkan | legacy | identical | `8b00d87495c0f5b9b807c8452cd6a63e293a1468891c00ddcebc5ca77505ed26` |
| Windows / D3D12 | legacy | identical | `8b00d87495c0f5b9b807c8452cd6a63e293a1468891c00ddcebc5ca77505ed26` |
| Linux / OptiX | legacy | identical | `8b00d87495c0f5b9b807c8452cd6a63e293a1468891c00ddcebc5ca77505ed26` |
| macOS / Metal | native | identical | `8b00d87495c0f5b9b807c8452cd6a63e293a1468891c00ddcebc5ca77505ed26` |

The rendered image is also identical across all three platform runners.

## Methodology and interpretation

- Each compile sample creates a fresh Slang session. A single global session is retained so precompiled standard-module setup is not repeatedly charged to either API.
- Case order rotates each iteration to reduce persistent thermal and frequency bias. Warmups are excluded; raw samples are retained locally in the git-ignored `perf-results/` directory and are not part of the published branch.
- Compiler optimization is maximal for measured target generation. SPIR-V uses direct emission followed by Slang's configured `spirv-opt` downstream path.
- Runtime measurements exclude device, acceleration-structure, shader, pipeline, and shader-table/function-table creation. They measure steady-state dispatch only.
- Correctness renders run before timing and are compared byte-for-byte within each platform lane.
- Both lanes use the same scene, camera, image size, physical records 1 and 4, and two-ray shading algorithm. The host owns those record positions and passes the selectors to ray generation.
- The revised structural shader deliberately uses separate `PrimaryPayload` and `ShadowPayload` partitions. Hit and miss function indices restart at zero in each partition; the legacy baseline retains its original combined payload. These measurements therefore compare the complete programming models, not syntax alone.
- The legacy host preserves its historical 64-byte maximum payload setting. The revised host uses reflected payload sizes (40 bytes primary and 4 bytes shadow), so the native pipeline maximum is 40 bytes. Runtime results include this intended ABI improvement and are not a payload-size-controlled API-only experiment.
- The hand-written Metal baseline uses native `intersector.intersect` calls and inline post-trace hit/miss handling; it intentionally has no structural visible-function tables.
- Git-derived compiler build tags depend on the tags available on each runner. The recorded source commit is authoritative when their version prefixes differ.
- Slang compiler labels observed: 2024.0.7-3796-gb0f010593; source b0f010593568, 2024.0.7-3982-gcdecb7503; source cdecb75031c1, 2026.17.1-156-gcdecb7503; source cdecb75031c1, 2026.9.1-707-g978320da0; source b0f010593568.
- GPU devices observed: Apple M4, NVIDIA RTX 3500 Ada Generation Laptop GPU, NVIDIA RTX PRO 6000 Blackwell Workstation Edition.
