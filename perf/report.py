#!/usr/bin/env python3

"""Combine platform benchmark JSON files into a reviewable Markdown report."""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import pathlib
from typing import Any


SCHEMA = "slang-ray-tracing-perf-v1"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument(
        "--refresh-run",
        action="append",
        default=[],
        help="run label to record in the report; may be repeated",
    )
    return parser.parse_args()


def load_results(root: pathlib.Path) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    if not root.exists():
        return results
    for path in sorted(root.rglob("*.json")):
        try:
            result = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise RuntimeError(f"cannot read benchmark result {path}: {error}") from error
        if result.get("schema") != SCHEMA:
            continue
        result["_path"] = str(path)
        results.append(result)
    return results


def metric(case: dict[str, Any], name: str) -> float:
    return float(case[name]["summary"]["median"])


def fmt(value: float | None) -> str:
    return "—" if value is None else f"{value:.3f}"


def target_name(value: str) -> str:
    return {"spirv": "SPIR-V", "dxil": "DXIL", "metal": "Metal"}.get(value, value)


def delta(structural: float, baseline: float) -> str:
    if baseline == 0:
        return "n/a"
    value = (structural / baseline - 1.0) * 100.0
    return f"{value:+.1f}%"


def refresh_priority(result: dict[str, Any]) -> tuple[bool, str]:
    """Apply explicit *-structural refresh files after retained baseline bundles."""
    path = pathlib.Path(result.get("_path", ""))
    return ("structural" in path.stem, str(path))


def compile_cases(
    results: list[dict[str, Any]],
) -> dict[str, dict[str, tuple[dict[str, Any], dict[str, Any]]]]:
    grouped: dict[str, dict[str, tuple[dict[str, Any], dict[str, Any]]]] = {}
    for result in sorted(
        (value for value in results if value.get("kind") == "compile"),
        key=refresh_priority,
    ):
        target = str(result.get("target", ""))
        for case in result.get("cases", []):
            if refresh_priority(result)[0] and case.get("name") != "structural":
                continue
            grouped.setdefault(target, {})[str(case.get("name", ""))] = (case, result)
    return grouped


def metal_downstream_cases(
    results: list[dict[str, Any]],
) -> dict[str, tuple[dict[str, Any], dict[str, Any]]]:
    grouped: dict[str, tuple[dict[str, Any], dict[str, Any]]] = {}
    for result in sorted(
        (value for value in results if value.get("kind") == "metal_downstream_compile"),
        key=refresh_priority,
    ):
        for case in result.get("cases", []):
            if refresh_priority(result)[0] and case.get("name") != "structural-generated":
                continue
            grouped[str(case.get("name", ""))] = (case, result)
    return grouped


def runner_section(results: list[dict[str, Any]]) -> list[str]:
    compile_results = [value for value in results if value.get("kind") == "compile"]
    runtime_results = [value for value in results if value.get("kind") == "runtime"]
    metal_results = [
        value for value in results if value.get("kind") == "metal_downstream_compile"
    ]

    compile_by_target = {
        value.get("target"): value
        for value in sorted(compile_results, key=refresh_priority)
    }
    runtime_by_backend = {value.get("backend"): value for value in runtime_results}
    metal_downstream = (
        sorted(metal_results, key=refresh_priority)[-1] if metal_results else {}
    )
    rows = [
        (
            "Linux / SPIR-V, MSL generation, Vulkan",
            compile_by_target.get("spirv", {}).get("host", "unspecified"),
            runtime_by_backend.get("Vulkan", {}).get("device", "unspecified"),
        ),
        (
            "Windows / DXIL, D3D12",
            compile_by_target.get("dxil", {}).get("host", "unspecified"),
            runtime_by_backend.get("D3D12", {}).get("device", "unspecified"),
        ),
        (
            "Linux / OptiX runtime",
            compile_by_target.get("spirv", {}).get("host", "unspecified"),
            runtime_by_backend.get("OptiX", {}).get("device", "unspecified"),
        ),
        (
            "macOS / MSL library, Metal",
            metal_downstream.get("host", "unspecified"),
            runtime_by_backend.get("Metal", {}).get("device", "unspecified"),
        ),
    ]
    lines = [
        "## Structural refresh runner environments",
        "",
        "| Measurements | OS and CPU | GPU |",
        "| --- | --- | --- |",
    ]
    lines.extend(f"| {lane} | {host} | {gpu} |" for lane, host, gpu in rows)
    return lines


def compile_section(results: list[dict[str, Any]]) -> list[str]:
    lines = [
        "## Compile performance",
        "",
        "Medians are in milliseconds. `Slang` is end-to-end API wall time from `createSession` "
        "through target extraction, less the downstream compiler timer delta. SPIR-V uses "
        "`getTargetCode`; MSL uses the ray-generation `getEntryPointCode`; DXIL uses every "
        "`getEntryPointCode` call, matching D3D12's per-entry "
        "library path. `Downstream` is Slang's built-in timer: `spirv-opt` for SPIR-V and DXC "
        "for DXIL.",
        "",
        "| Target | Implementation | Compiler/source | Slang | Downstream | Total wall | Target bytes |",
        "| --- | --- | --- | ---: | ---: | ---: | ---: |",
    ]
    compile_results = [value for value in results if value.get("kind") == "compile"]
    grouped_compile = compile_cases(results)
    comparison_targets = [target for target in grouped_compile if target != "metal"]
    for target in sorted(comparison_targets):
        cases = grouped_compile[target]
        for case_name in sorted(cases, key=lambda name: (name != "structural", name)):
            case, result = cases[case_name]
            lines.append(
                f"| {target_name(target)} | {case['name']} | {result.get('compiler', 'unspecified')} | "
                f"{fmt(metric(case, 'slang_ms'))} | {fmt(metric(case, 'downstream_ms'))} | "
                f"{fmt(metric(case, 'total_wall_ms'))} | {case['code_size_bytes']} |"
            )
    if not comparison_targets:
        lines.append("| pending | pending | pending | — | — | — | — |")

    comparisons: list[str] = []
    for target in comparison_targets:
        by_name = grouped_compile[target]
        if "structural" not in by_name or "legacy" not in by_name:
            continue
        structural, structural_result = by_name["structural"]
        legacy, legacy_result = by_name["legacy"]
        if structural_result.get("compiler") != legacy_result.get("compiler"):
            comparisons.append(
                f"- {target_name(target)}: structural vs legacy is **not directly comparable**. "
                "The retained legacy baseline uses a different compiler/source revision; the "
                "individual values remain in the table as historical context."
            )
        else:
            comparisons.append(
                f"- {target_name(target)}: structural vs legacy is "
                f"{delta(metric(structural, 'slang_ms'), metric(legacy, 'slang_ms'))} in Slang and "
                f"{delta(metric(structural, 'downstream_ms'), metric(legacy, 'downstream_ms'))} "
                f"downstream; total wall time is "
                f"{delta(metric(structural, 'total_wall_ms'), metric(legacy, 'total_wall_ms'))}."
            )
    if comparisons:
        lines.extend(["", *comparisons])

    metal_results = [
        value for value in results if value.get("kind") == "metal_downstream_compile"
    ]
    lines.extend(
        [
            "",
            "### Metal source compilation",
            "",
            "Metal has no legacy Slang pipeline API. Slang-to-MSL generation is therefore listed "
            "separately from Apple's synchronous `newLibrary(source)` compilation of generated and "
            "hand-written MSL. Each Apple compiler sample gets a clock-seeded unique trailing "
            "comment to avoid persistent source-hash cache hits.",
            "",
            "| Phase/input | Compiler/source | Median (ms) | p95 (ms) |",
            "| --- | --- | ---: | ---: |",
        ]
    )
    metal_slang_entry = grouped_compile.get("metal", {}).get("structural")
    if metal_slang_entry:
        case, metal_slang = metal_slang_entry
        lines.append(
            f"| Slang structural source → MSL | {metal_slang.get('compiler', 'unspecified')} | "
            f"{fmt(metric(case, 'slang_ms'))} | "
            f"{fmt(float(case['slang_ms']['summary']['p95']))} |"
        )
    downstream_cases = metal_downstream_cases(results)
    for case_name in sorted(downstream_cases):
        case, result = downstream_cases[case_name]
        provenance = result.get("input_provenance")
        if not provenance:
            provenance = (
                "hand-written MSL; retained baseline"
                if case_name == "native-handwritten"
                else "unspecified retained input"
            )
        lines.append(
            f"| Apple compiler: {case['name']} MSL → library | {provenance} | "
            f"{fmt(float(case['summary']['median']))} | "
            f"{fmt(float(case['summary']['p95']))} |"
        )
    if not metal_slang_entry and not downstream_cases:
        lines.append("| pending | pending | — | — |")
    if "structural-generated" in downstream_cases and "native-handwritten" in downstream_cases:
        generated_case, generated_result = downstream_cases["structural-generated"]
        native_case, native_result = downstream_cases["native-handwritten"]
        if generated_result.get("host") != native_result.get("host"):
            apple_comparison = (
                "- Apple compilation of generated MSL vs hand-written MSL is "
                "**not directly comparable**. The hand-written row is a retained baseline from "
                "different recorded host/toolchain provenance; both individual values remain in "
                "the table as historical context."
            )
        else:
            apple_comparison = (
                "- Apple compilation of generated MSL vs hand-written MSL is "
                f"{delta(float(generated_case['summary']['median']), float(native_case['summary']['median']))} "
                "in median wall time."
            )
        lines.extend(
            [
                "",
                apple_comparison,
                "- Slang→MSL and Apple MSL→library are kept as separate phases because they "
                "were measured on different platform runners; their medians must not be "
                "added into a synthetic end-to-end number.",
            ]
        )
    return lines


def runtime_section(results: list[dict[str, Any]]) -> list[str]:
    lines = [
        "## Runtime performance",
        "",
        "All workloads render one primary ray per 256×256 pixel and, on a hit, one shadow ray. "
        "Vulkan/D3D12/OptiX use device timestamp queries immediately around `dispatchRays`. Metal uses "
        "the command buffer's `GPUStartTime`/`GPUEndTime` around a command buffer containing one "
        "compute dispatch. Compare implementations within a backend, not absolute times across "
        "these different timestamp boundaries or machines.",
        "",
        "| Backend | Device | Implementation | Median GPU ms | p95 GPU ms | Samples |",
        "| --- | --- | --- | ---: | ---: | ---: |",
    ]
    runtime_results = [value for value in results if value.get("kind") == "runtime"]
    for result in sorted(
        runtime_results,
        key=lambda item: (item["backend"], item["implementation"]),
    ):
        lines.append(
            f"| {result['backend']} | {result['device']} | {result['implementation']} | "
            f"{fmt(float(result['summary']['median']))} | "
            f"{fmt(float(result['summary']['p95']))} | {result['sample_count']} |"
        )
    if not runtime_results:
        lines.append("| pending | pending | pending | — | — | — |")

    grouped: dict[str, dict[str, dict[str, Any]]] = {}
    for result in runtime_results:
        grouped.setdefault(result["backend"], {})[result["implementation"]] = result
    comparisons: list[str] = []
    for backend, implementations in sorted(grouped.items()):
        baseline_name = "native" if backend == "Metal" else "legacy"
        if "structural" not in implementations or baseline_name not in implementations:
            continue
        structural = float(implementations["structural"]["summary"]["median"])
        baseline = float(implementations[baseline_name]["summary"]["median"])
        comparisons.append(
            f"- {backend}: structural vs {baseline_name} is {delta(structural, baseline)} "
            "in median GPU time."
        )
    if comparisons:
        lines.extend(
            [
                "",
                *comparisons,
                "",
                "The retained Vulkan, D3D12, and Metal baseline JSON files do not contain "
                "a run ID or collection timestamp. Their comparisons use the same documented "
                "runner/device class but are not contemporaneous; compiler-generated baselines "
                "may also use an earlier compiler/source revision. Their percentages are "
                "historical context, not clean API-only regression estimates. This "
                "structural-only refresh preserves those baselines as requested. The new OptiX "
                "structural and legacy rows were collected together in the same run.",
            ]
        )
    return lines


def validation_section(root: pathlib.Path) -> list[str]:
    comparisons = [
        (
            "Linux / Vulkan",
            root / "linux/cornell-structural.ppm",
            root / "linux/cornell-legacy.ppm",
        ),
        (
            "Windows / D3D12",
            root / "windows/cornell-structural.ppm",
            root / "windows/cornell-legacy.ppm",
        ),
        (
            "Linux / OptiX",
            root / "linux/cornell-optix-structural.ppm",
            root / "linux/cornell-optix-legacy.ppm",
        ),
        (
            "macOS / Metal",
            root / "macos/cornell-structural.ppm",
            root / "macos/cornell-native.ppm",
        ),
    ]
    lines = [
        "## Correctness gate",
        "",
        "Each platform renders both implementations before timing. The performance script aborts "
        "unless the two PPM files are byte-for-byte identical.",
        "",
        "| Platform | Baseline | Result | SHA-256 |",
        "| --- | --- | --- | --- |",
    ]
    observed_hashes: list[str] = []
    for platform, structural_path, baseline_path in comparisons:
        if not structural_path.exists() or not baseline_path.exists():
            continue
        structural = structural_path.read_bytes()
        baseline = baseline_path.read_bytes()
        if structural != baseline:
            raise RuntimeError(f"correctness images differ for {platform}")
        digest = hashlib.sha256(structural).hexdigest()
        observed_hashes.append(digest)
        baseline_name = "native" if platform.endswith("Metal") else "legacy"
        lines.append(f"| {platform} | {baseline_name} | identical | `{digest}` |")
    if not observed_hashes:
        lines.append("| pending | pending | — | — |")
    elif len(set(observed_hashes)) == 1 and len(observed_hashes) == len(comparisons):
        lines.extend(
            [
                "",
                "The rendered image is also identical across all three platform runners.",
            ]
        )
    return lines


def methodology_section(results: list[dict[str, Any]]) -> list[str]:
    selected_compile_cases = compile_cases(results)
    compilers = sorted(
        {
            result.get("compiler", "")
            for cases in selected_compile_cases.values()
            for _, result in cases.values()
            if result.get("compiler")
        }
    )
    devices = sorted({value.get("device", "") for value in results if value.get("device")})
    lines = [
        "## Methodology and interpretation",
        "",
        "- Each compile sample creates a fresh Slang session. A single global session is retained "
        "so precompiled standard-module setup is not repeatedly charged to either API.",
        "- Case order rotates each iteration to reduce persistent thermal and frequency bias. "
        "Warmups are excluded; raw samples are retained locally in the git-ignored "
        "`perf-results/` directory and are not part of the published branch.",
        "- Compiler optimization is maximal for measured target generation. SPIR-V uses direct "
        "emission followed by Slang's configured `spirv-opt` downstream path.",
        "- Runtime measurements exclude device, acceleration-structure, shader, pipeline, and "
        "shader-table/function-table creation. They measure steady-state dispatch only.",
        "- Correctness renders run before timing and are compared byte-for-byte within each "
        "platform lane.",
        "- Both lanes use the same scene, camera, image size, physical records 1 and 4, and "
        "two-ray shading algorithm. The host owns those record positions and passes the selectors "
        "to ray generation.",
        "- The revised structural shader deliberately uses separate `PrimaryPayload` and "
        "`ShadowPayload` partitions. Hit and miss function indices restart at zero in each "
        "partition; the legacy baseline retains its original combined payload. These measurements "
        "therefore compare the complete programming models, not syntax alone.",
        "- The legacy host preserves its historical 64-byte maximum payload setting. The revised "
        "host uses reflected payload sizes (40 bytes primary and 4 bytes shadow), so the native "
        "pipeline maximum is 40 bytes. Runtime results include this intended ABI improvement and "
        "are not a payload-size-controlled API-only experiment.",
        "- The hand-written Metal baseline uses native `intersector.intersect` calls and inline "
        "post-trace hit/miss handling; it intentionally has no structural visible-function tables.",
        "- Git-derived compiler build tags depend on the tags available on each runner. The "
        "recorded source commit is authoritative when their version prefixes differ.",
    ]
    if compilers:
        lines.append(f"- Slang compiler labels observed: {', '.join(compilers)}.")
    if devices:
        lines.append(f"- GPU devices observed: {', '.join(devices)}.")
    return lines


def main() -> None:
    args = parse_args()
    results = load_results(args.input_dir)
    run_lines = []
    if args.refresh_run:
        run_lines = [
            "Structural refresh runs: "
            + ", ".join(f"`{run}`" for run in args.refresh_run)
            + ".",
            "",
        ]
    lines = [
        "# Dynamic-schema ray-tracing performance report",
        "",
        f"Generated {datetime.datetime.now().astimezone().isoformat(timespec='seconds')} from "
        f"{len(results)} benchmark result file(s).",
        "",
        *run_lines,
        "This report compares the legacy D3D/Vulkan/OptiX pipeline ray-tracing API with the revised "
        "schema-based API. Metal instead compares generated Slang output with an equivalent hand-written "
        "native Metal implementation.",
        "",
        *runner_section(results),
        "",
        *compile_section(results),
        "",
        *runtime_section(results),
        "",
        *validation_section(args.input_dir),
        "",
        *methodology_section(results),
        "",
    ]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
