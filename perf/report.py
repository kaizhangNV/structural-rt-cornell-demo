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


def runner_section(results: list[dict[str, Any]]) -> list[str]:
    compile_results = [value for value in results if value.get("kind") == "compile"]
    runtime_results = [value for value in results if value.get("kind") == "runtime"]
    metal_results = [
        value for value in results if value.get("kind") == "metal_downstream_compile"
    ]

    compile_by_target = {value.get("target"): value for value in compile_results}
    runtime_by_backend = {value.get("backend"): value for value in runtime_results}
    metal_downstream = metal_results[0] if metal_results else {}
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
            "macOS / MSL library, Metal",
            metal_downstream.get("host", "unspecified"),
            runtime_by_backend.get("Metal", {}).get("device", "unspecified"),
        ),
    ]
    lines = [
        "## Runner environments",
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
        "through target extraction, less the downstream compiler timer delta. SPIR-V/MSL use "
        "`getTargetCode`; DXIL uses every `getEntryPointCode` call, matching D3D12's per-entry "
        "library path. `Downstream` is Slang's built-in timer: `spirv-opt` for SPIR-V and DXC "
        "for DXIL.",
        "",
        "| Target | Implementation | Slang | Downstream | Total wall | Target bytes |",
        "| --- | --- | ---: | ---: | ---: | ---: |",
    ]
    compile_results = [value for value in results if value.get("kind") == "compile"]
    comparison_results = [value for value in compile_results if value.get("target") != "metal"]
    for result in sorted(comparison_results, key=lambda item: item["target"]):
        for case in result["cases"]:
            lines.append(
                f"| {target_name(result['target'])} | {case['name']} | "
                f"{fmt(metric(case, 'slang_ms'))} | {fmt(metric(case, 'downstream_ms'))} | "
                f"{fmt(metric(case, 'total_wall_ms'))} | {case['code_size_bytes']} |"
            )
    if not comparison_results:
        lines.append("| pending | pending | — | — | — | — |")

    comparisons: list[str] = []
    for result in comparison_results:
        by_name = {case["name"]: case for case in result["cases"]}
        if "structural" not in by_name or "legacy" not in by_name:
            continue
        structural = by_name["structural"]
        legacy = by_name["legacy"]
        comparisons.append(
            f"- {target_name(result['target'])}: structural vs legacy is "
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
            "| Phase/input | Median (ms) | p95 (ms) |",
            "| --- | ---: | ---: |",
        ]
    )
    metal_slang = next(
        (value for value in compile_results if value.get("target") == "metal"), None
    )
    if metal_slang:
        case = metal_slang["cases"][0]
        lines.append(
            f"| Slang structural source → MSL | {fmt(metric(case, 'slang_ms'))} | "
            f"{fmt(float(case['slang_ms']['summary']['p95']))} |"
        )
    for result in metal_results:
        for case in result["cases"]:
            lines.append(
                f"| Apple compiler: {case['name']} MSL → library | "
                f"{fmt(float(case['summary']['median']))} | "
                f"{fmt(float(case['summary']['p95']))} |"
            )
    if not metal_slang and not metal_results:
        lines.append("| pending | — | — |")
    for result in metal_results:
        by_name = {case["name"]: case for case in result["cases"]}
        if "structural-generated" in by_name and "native-handwritten" in by_name:
            generated = float(by_name["structural-generated"]["summary"]["median"])
            native = float(by_name["native-handwritten"]["summary"]["median"])
            lines.extend(
                [
                    "",
                    f"- Apple compilation of generated MSL vs hand-written MSL is "
                    f"{delta(generated, native)} in median wall time.",
                    "- Slang→MSL and Apple MSL→library are kept as separate phases because they "
                    "were measured on different platform runners; their medians must not be "
                    "added into a synthetic end-to-end number.",
                ]
            )
            break
    return lines


def runtime_section(results: list[dict[str, Any]]) -> list[str]:
    lines = [
        "## Runtime performance",
        "",
        "All workloads render one primary ray per 256×256 pixel and, on a hit, one shadow ray. "
        "Vulkan/D3D12 use device timestamp queries immediately around `dispatchRays`. Metal uses "
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
        lines.extend(["", *comparisons])
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
    compilers = sorted(
        {value.get("compiler", "") for value in results if value.get("compiler")}
    )
    devices = sorted({value.get("device", "") for value in results if value.get("device")})
    lines = [
        "## Methodology and interpretation",
        "",
        "- Each compile sample creates a fresh Slang session. A single global session is retained "
        "so precompiled standard-module setup is not repeatedly charged to either API.",
        "- Case order rotates each iteration to reduce persistent thermal and frequency bias. "
        "Warmups are excluded, raw samples remain in `perf-results/`.",
        "- Compiler optimization is maximal for measured target generation. SPIR-V uses direct "
        "emission followed by Slang's configured `spirv-opt` downstream path.",
        "- Runtime measurements exclude device, acceleration-structure, shader, pipeline, and "
        "shader-table/function-table creation. They measure steady-state dispatch only.",
        "- Correctness renders run before timing and are compared byte-for-byte within each "
        "platform lane.",
        "- The legacy shader and structural shader use the same entry-point names, sparse logical "
        "slots (1 and 4), payload, scene, camera, image size, and two-ray shading algorithm.",
        "- The hand-written Metal baseline uses native `intersector.intersect` calls and inline "
        "post-trace hit/miss handling; it intentionally has no structural visible-function tables.",
    ]
    if compilers:
        lines.append(f"- Slang compiler labels observed: {', '.join(compilers)}.")
    if devices:
        lines.append(f"- GPU devices observed: {', '.join(devices)}.")
    return lines


def main() -> None:
    args = parse_args()
    results = load_results(args.input_dir)
    lines = [
        "# Structural ray-tracing performance report",
        "",
        f"Generated {datetime.datetime.now().astimezone().isoformat(timespec='seconds')} from "
        f"{len(results)} benchmark result file(s).",
        "",
        "This report compares the legacy D3D/Vulkan pipeline ray-tracing API with the structural "
        "API. Metal instead compares structural Slang output with an equivalent hand-written "
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
