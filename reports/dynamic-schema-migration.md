# Dynamic-schema migration report

## Outcome

The Cornell box now uses the revised shader schema and a host-owned SBT layout. Primary and shadow
rays use different payload types, while the rendered algorithm and legacy/native baselines remain
unchanged.

## Change checklist

- [x] Replace `ITraceProgramLayout` with `ITraceProgramSchema`.
- [x] Remove shader-side hit/miss slot declarations.
- [x] Split `RayPayload` into `PrimaryPayload` and `ShadowPayload`.
- [x] Give each hit and miss stage its payload-specific context.
- [x] Pass physical hit and miss record selectors through `FrameData`.
- [x] Keep sparse host records: primary at 1, shadow at 4.
- [x] Discover structural stages through schema reflection.
- [x] Resolve records by `(payload type, schema entry type)`, not a global function index.
- [x] Size native payload and attribute pipeline limits from target reflection.
- [x] Preserve the legacy `TraceRay` shader and hand-written Metal baseline.
- [x] Generate MSL and its target-specific reflection sidecar from the same compiler invocation.
- [x] Emit repository-relative generated-MSL `#line` paths instead of workstation paths.
- [x] Persist compiler build/source provenance, Metal descriptor IDs, record strides, per-payload
  table sizes, intersection signatures, and a generated-MSL content fingerprint.
- [x] Build Metal function tables per payload partition and construct the physical records buffer
  independently.
- [x] Make the compile benchmark discover structural stages from a schema while retaining explicit
  legacy entries.
- [x] Refresh structural performance files without overwriting retained legacy/native baselines.
- [x] Add Vulkan/OptiX, D3D12, and Metal correctness gates to their platform scripts.

## Reflected model

`PrimaryHitGroup` and `PrimaryMiss` are function index 0 in the `PrimaryPayload` partition.
`ShadowHitGroup` and `ShadowMiss` are also function index 0, but in the `ShadowPayload` partition.
The host maps those entries to physical records 1 and 4. This is the intended separation:
reflection describes available programs and payload-local ABI; the host describes record count,
placement, duplication, and selection.

## Resolved design concerns

- Payload is no longer fixed per whole program layout. Stage contexts choose `PrimaryPayload` or
  `ShadowPayload`, and schema reflection exposes two independent partitions.
- Runtime scene/SBT policy is no longer encoded in shader slot aliases. `FrameData` carries the
  selectors chosen by the host, so the same schema entry may be duplicated or moved without
  rebuilding the shader schema.
- A function index is no longer confused with record identity. Both payload partitions validly use
  function index 0 while their physical records remain 1 and 4.

## Gaps and integration findings

No Cornell-box requirement exposed a shader API design gap in the revised proposal.

The following boundaries still require host care:

- Slang cannot validate the contents of a host-created SBT. The host must map a runtime selector to
  an entry from the matching payload partition. This follows from making SBT layout runtime-owned;
  it is not a missing shader declaration.
- The standalone Metal executable does not embed Slang. Its build therefore carries a generated
  MSL file and reflection sidecar. The sidecar prevents the host from guessing compiler-owned
  argument-buffer IDs, record strides, table sizes, or function names, and the host rejects a
  sidecar whose generated-MSL fingerprint does not match.
- Compiler and adapter contract tests show that Metal any-hit and intersection source stages do not
  have independent bindable symbols. They are composed by source type, while reflected
  intersection-function dispatchers populate the IFT. Closest-hit uses the group-level physical
  symbol so a synthesized `NoClosestHit` entry is not lost. The Cornell runtime itself does not
  exercise any-hit, custom intersection, or `NoClosestHit`.

Two compiler implementation bugs were found outside the API design:

- On OptiX, the split 40-byte primary payload initially reflected a 10-register pipeline
  requirement while generated `optixTrace` code passed 16 payload values. Slang revision
  `f0ae84e7f330a3436aa7e38a26b3e67eda91569b` fixes the prelude and adds a regression test. The
  Cornell host continues to use the reflected value rather than hiding the bug with a 64-byte
  constant.
- On D3D12, a schema descriptor retained by global-parameter layout metadata could leak as raw
  Slang `ParameterBlock` syntax into the HLSL sent to DXC. Final revision
  `cdecb75031c1ce125985e51032c00a11c1f85492` erases this zero-storage descriptor for D3D targets,
  preserves the source shape required by CUDA/OptiX lowering, and carries focused HLSL/DXIL
  regression coverage.

With that final revision, Vulkan, OptiX, and D3D12 render the split-payload schema byte-identically
to legacy; generated Metal is byte-identical to the hand-written native baseline.

## Workarounds and intentional omissions

- The legacy shader mirrors the four new `FrameData` selector fields but does not read them. This
  keeps one host constant-buffer ABI without changing legacy tracing behavior.
- The Metal sidecar is an offline integration mechanism for a host that intentionally does not
  link Slang at runtime. It contains reflected compiler ABI rather than hand-authored layout data.
- No structural host-side 64-byte payload override is used to hide the OptiX bug; doing so would
  make the reflection API appear correct while bypassing it. The legacy lane's independent,
  historical 64-byte setting is retained as baseline behavior.
- The sample exercises triangle closest-hit/miss dispatch and two payload partitions. Callable
  shaders, custom intersection/any-hit behavior, motion, curves/LSS, SER, inline ray queries, and
  application record data remain outside this Cornell-box validation scope.

## Validation provenance

- Implementation and measured-results revision: `616893dab11a693b9a28608348ca77bf452efd3d` on
  `codex/dynamic-schema-migration`.
- Compiler source: `cdecb75031c1ce125985e51032c00a11c1f85492`; Linux build tag
  `2026.17.1-156-gcdecb7503`.
- Linux isolated run: `20260914-cdecb7503-linux-isolated-v2`.
- Windows run: `20260914-cdecb7503-structural-final`.
- macOS artifact-pair run: `20260914-cdecb7503-metal-pair-final`.

Each performance lane used five warmups and 50 measured samples. Vulkan, OptiX, D3D12, and Metal
all passed their byte-identical correctness gate.

## Performance interpretation

The revised structural lane uses two payload partitions; the retained legacy lane uses its
original combined payload. Both render the same scene with the same primary-plus-shadow algorithm
and physical record selectors. Results therefore compare the complete old and revised programming
models, not a source-syntax-only transformation. The historical legacy host reserves a 64-byte
maximum payload, while reflection sizes the revised primary and shadow payloads at 40 and 4 bytes
and therefore sets a 40-byte pipeline maximum. Runtime results include that intended ABI
improvement. Compile rows carry their compiler/source revision; when a retained baseline comes
from an older revision, the report labels the comparison as not directly comparable and does not
present an API-only percentage.
