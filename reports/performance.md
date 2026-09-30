# Cornell path-tracer performance

Measured 2026-09-30 (America/Los_Angeles).

These are fresh measurements of the path tracer with a procedural glass sphere and AO, not the old direct-lighting demo. Both implementations were measured together on each runner with the same compiler revision and source snapshot. [September 14 direct-lighting results](performance-direct-lighting-20260914.md) are archived separately.

## Results at a glance

- Slang + downstream median compile-time change, new API versus legacy: SPIR-V **+35.1%**; DXIL **+53.5%**; PTX **+12.7%**.
- Largest observed absolute runtime median difference: **Metal beauty, +107.1%**. See paired-round ranges below before interpreting this as a regression.
- Positive percentages mean the new API is slower. These are complete-implementation comparisons; they do not isolate API syntax, and the timings alone do not explain a difference.

## What was measured

- Sample base: [`da91a8efe5a1`](https://github.com/kaizhangNV/structural-rt-cornell-demo/commit/da91a8efe5a1856a2d47d16381f9faece048da65); benchmark-tool changes are identified by the published source hashes.
- Slang source: [`eb5be680b597`](https://github.com/kaizhangNV/slang/commit/eb5be680b597ae547abe1f8338f223896fceaca3). Build tags can differ across runners; this full source commit is authoritative.
- Scene `cornell-procedural-sphere-v2`: triangle room plus custom-intersection AABB sphere, center `(0, 0.75, 0)`, radius `0.4`, glass enabled, exposure `1`.
- Runtime: **512×512, 8 samples/pixel**, seed `17`, at most `8` beauty-path bounces. AO is a separate view with up to 8 occlusion rays per camera sample and radius `0.75`; primary misses skip occlusion rays, and AO does not use the bounce loop.
- Each runtime lane: 6 fresh-process paired rounds, 10 warmups + 50 timed dispatches per process (300 retained samples per implementation/view). Each dispatch resets accumulation and repeats the same seeded workload.
- Compilation: 5 warmups + 50 retained samples per case, alternating case order in one process.

| Runner | OS / CPU | GPU | Compiler build |
| --- | --- | --- | --- |
| linux | Linux-6.8.0-146-generic-x86_64-with-glibc2.39; x86_64; Intel(R) Core(TM) i9-14900K | NVIDIA RTX PRO 6000 Blackwell Workstation Edition | RelWithDebInfo (-O2 -g -DNDEBUG) |
| windows | Windows-10-10.0.19045-SP0; Intel64 Family 6 Model 186 Stepping 2, GenuineIntel; 13th Gen Intel(R) Core(TM) i7-13800H | NVIDIA RTX 3500 Ada Generation Laptop GPU | Release |
| macos | macOS-26.7-arm64-arm-64bit; arm; Apple M4 | Apple M4 | MSL generated with Linux RelWithDebInfo; Apple Metal 3.1 library compiler |

## Compile time

All values are milliseconds. `Slang` is the inclusive wall-time residual from session creation through output extraction, minus Slang's downstream timer. It includes source loading, reflection, composition/linking and code generation; it is not an isolated code-generation pass. `Downstream` includes the compiler adapter around the in-process optimizer/compiler call.

| Target | Implementation | Slang median | Downstream median | Total median | Total p95 | Output bytes | Total change |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| SPIR-V | legacy | 66.334 | 17.286 | 83.655 | 89.455 | 25760 | baseline |
| SPIR-V | new API | 93.803 | 19.240 | 113.007 | 123.163 | 26160 | +35.1% |
| DXIL | legacy | 97.455 | 65.554 | 163.457 | 167.919 | 42492 | baseline |
| DXIL | new API | 163.918 | 86.550 | 250.934 | 256.096 | 49504 | +53.5% |
| PTX | legacy | 86.485 | 342.847 | 429.282 | 481.597 | 146326 | baseline |
| PTX | new API | 136.834 | 346.088 | 483.898 | 522.728 | 158268 | +12.7% |

- SPIR-V 1.5: direct Slang emission, then Slang's bundled `spirv-opt` path; one whole-program output.
- DXIL `lib_6_6`: nine separately emitted stage libraries; downstream is their summed DXC time.
- PTX `compute_120`: nine separately emitted stage libraries; downstream is their summed NVRTC time. OptiX driver compilation/JIT is not included.
- Both APIs cover one raygen, four closest-hit, two intersection and two miss stages. New-API schema reflection is included; legacy explicitly selects the equivalent stages.
- Compile benchmarks use maximal optimization. Runtime uses the renderer/RHI's normal defaults; both implementations have matching settings within each comparison.
- Output bytes mean optimized SPIR-V, or the sum of all DXIL/PTX blobs (including repeated per-stage boilerplate), not final GPU machine code. Separately computed medians need not add up.

### Metal compilation

Metal has no legacy Slang pipeline lane. Linux Slang→MSL generation and macOS MSL→library compilation are separate measurements on different machines; do not add their medians into a synthetic end-to-end value.

| Phase / input | Median ms | p95 ms | Change |
| --- | ---: | ---: | ---: |
| Slang new API → MSL (Linux) | 91.284 | 95.046 | no legacy lane |
| Hand-written MSL → Metal library | 22.585 | 23.780 | baseline |
| Generated MSL → Metal library | 45.779 | 47.564 | +102.7% |

Apple compilation measures synchronous `MTLDevice.newLibrary(source)` with Metal 3.1, excluding source-file I/O and pipeline creation. Unique trailing comments avoid identical source hashes, but do not flush Apple's internal caches or guarantee cold compilation. The Slang→MSL benchmark uses maximal optimization; Apple compilation/runtime uses the checked-in generated artifact built with the normal generator defaults. This is not one timed artifact chain; the published hash identifies the exact Apple input.

## Runtime

GPU duration of one dispatch, not interactive frame time/FPS. Compare within a backend, not absolute times across machines or timestamp mechanisms. The range is the minimum/maximum new-versus-baseline percentage from each paired round's medians.

| Backend / view | Baseline median / p95 ms | New API median / p95 ms | Pooled median change | Paired-round median change range |
| --- | ---: | ---: | ---: | ---: |
| Vulkan / beauty | 0.6237 / 0.6408 | 0.5284 / 0.5420 | -15.3% | -16.7% to -14.4% |
| Vulkan / ao | 0.3111 / 0.3258 | 0.2887 / 0.3020 | -7.2% | -7.5% to -6.6% |
| D3D12 / beauty | 2.6020 / 3.6116 | 2.3665 / 3.2840 | -9.1% | -34.6% to +26.2% |
| D3D12 / ao | 1.5580 / 1.9446 | 1.3384 / 1.3507 | -14.1% | -30.8% to -3.6% |
| OptiX / beauty | 1.4365 / 1.8250 | 1.3275 / 1.8560 | -7.6% | -15.7% to +4.8% |
| OptiX / ao | 0.4220 / 0.6080 | 0.4030 / 0.5680 | -4.5% | -5.2% to -3.5% |
| Metal / beauty | 11.0287 / 11.2298 | 22.8434 / 23.2645 | +107.1% | +106.5% to +107.5% |
| Metal / ao | 4.8398 / 4.9120 | 8.1405 / 8.3020 | +68.2% | +67.7% to +68.6% |

Vulkan/D3D12/OptiX use GPU timestamp queries around `dispatchRays`; Metal uses `GPUStartTime`→`GPUEndTime` of a command buffer containing one compute dispatch. Shader compilation, device/pipeline/SBT/acceleration-structure construction, image readback and presentation are excluded. Runs are sequential with AB/BA order balanced across rounds. Samples within one process are correlated: these are descriptive statistics, not independent trials or a statistical-significance claim.

GPU/CPU clocks and power states were not locked, and these are shared machines rather than isolated benchmark appliances. Initial environment snapshots do not establish constant temperature, power or background load during the run.

**Ordering/drift caution:** OptiX beauty, D3D12 beauty have paired-round ranges crossing zero. Their pooled median improvements are not evidence of a consistently repeatable speedup.

**D3D12 AO order dependence:** legacy round medians are about 1.932 ms in structural-first odd rounds versus 1.394 ms in legacy-first even rounds; the new-API lane stays near 1.338 ms. The effect magnitude correlates with process order, so the pooled -14.1% is not a stable single speedup estimate. The cause has not been established.

## Correctness and comparison limits

All four backends passed the five-case 192×192, 64-spp image suite (glass/diffuse/no sphere, direct light and AO), seeded repeatability, and an image comparison at the timed resolution and sample count. Exact error values and thresholds are preserved in the data bundle.

- The shared integrator is the same Slang module for legacy and new APIs, and both use custom intersection programs. The procedural sphere is not replaced by a triangle mesh.
- This compares complete implementations. Legacy uses one 36-byte logical payload and a 64-byte configured pipeline maximum; the new API separates primary/shadow payloads and uses target-reflected native sizes (logical fields total 32/4 bytes). New-API runtime SBT selectors also differ from legacy constants. These are not payload-size/ABI-controlled experiments.
- Hand-written Metal directly performs native intersection and inline post-trace shading; generated Metal uses reflected intersection/visible-function tables. The native baseline also avoids a triangle-normal normalization present in the generated path. Timings include these implementation differences, not just the shader API abstraction.
- Warm global Slang session, fresh per-sample session; OS file and compiler/plugin caches are not flushed. Global-session initialization and teardown are excluded. No cold-start or driver pipeline-compilation performance claim is made.
- Provenance records source snapshot hashes, renderer/benchmark executable hashes and compiler revision labels, but not hashes of the loaded Slang/downstream shared libraries. Revision labels alone are not proof of binary identity.
- Compile p95 uses the existing C++ tool's rounded `0.95×(N−1)` index; runtime p95 uses nearest rank `ceil(0.95×N)−1`. Reported percentages use unrounded samples.

## Raw data and reproduction

[Published timing samples and source/tool SHA-256 hashes](data/path-tracer-2026-09-30.json) include every retained compile and runtime timing, per-round order, correctness metrics, runner identifiers, compiler build labels and collection timestamps. Local paths, images and verbose logs are omitted.

Build the renderer and benchmark tools with the pinned compiler, then run [`perf/collect.py`](../perf/collect.py) once per platform into fresh `linux`, `windows` and `macos` output directories. Each collection records all requested settings and refuses mixed output directories. See the [full reproduction instructions](../perf/README.md). Generate this report and its bundle with:

```bash
python3 perf/path-tracer-report.py --date 2026-09-30 --input-dir <collection-directory> \
  --output reports/performance.md \
  --data-output reports/data/path-tracer-2026-09-30.json
```

The publisher rejects incomplete lanes, failed correctness gates, changed source hashes, mismatched compiler/sample revisions, inconsistent settings, missing runtime samples and runtime raw-file hash mismatches. Compile timings are checked for completeness and phase consistency; their original result files have no separately recorded integrity hash.
