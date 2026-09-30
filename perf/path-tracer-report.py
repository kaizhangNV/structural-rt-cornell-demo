#!/usr/bin/env python3
"""Publish a matched, complete three-platform Cornell benchmark collection.

Input: linux/windows/macos/collection.json and every result referenced by them.
The published JSON keeps every timing sample and source hash but omits machine-local
paths, command lines, hostnames, image binaries, and verbose build/compiler logs.
"""

from __future__ import annotations

import argparse
from datetime import date as calendar_date
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import statistics
import sys


PLATFORMS = {"linux": ("vulkan", "optix"), "windows": ("d3d12",), "macos": ("metal",)}
TARGETS = {"linux": {"spirv", "metal", "ptx"}, "windows": {"dxil"}, "macos": {"metal"}}
NAMES = {"spirv": "SPIR-V", "dxil": "DXIL", "ptx": "PTX", "vulkan": "Vulkan",
         "optix": "OptiX", "d3d12": "D3D12", "metal": "Metal"}
STAGES = {"RayGeneration", "PrimaryClosestHit", "ShadowClosestHit",
          "PrimarySphereClosestHit", "ShadowSphereClosestHit", "PrimarySphereIntersection",
          "ShadowSphereIntersection", "PrimaryMiss", "ShadowMiss"}
SCENE = "cornell-procedural-sphere-v2"
VIEW_MODES = {"beauty": 0, "ao": 1, "direct": 2}
SOURCE_PREFIXES = ("common/", "shaders/", "shaders-legacy/", "generated/")
HOST_SOURCES = {"scene.h", "render-settings.h", "rhi-main.cpp", "metal-main.cpp"}
OPTION_KEYS = ("rounds", "warmup", "iterations", "width", "height", "samples", "bounces",
               "seed", "views")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def read_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(value, dict), f"{path.name}: expected a JSON object")
    return value


def child_path(root: Path, name: str) -> Path:
    relative = PurePosixPath(name.replace("\\", "/"))
    require(not relative.is_absolute() and ".." not in relative.parts and ":" not in name,
            f"result reference must be relative: {name}")
    path = root / relative
    require(path.resolve().is_relative_to(root.resolve()), "result reference escapes collection")
    return path


def normalized_hashes(value: dict) -> dict:
    require(isinstance(value, dict) and bool(value), "source provenance is missing")
    result = {name.replace("\\", "/"): digest for name, digest in value.items()}
    require(len(result) == len(value), "duplicate normalized source paths")
    for name, digest in result.items():
        require(not PurePosixPath(name).is_absolute() and ".." not in PurePosixPath(name).parts
                and ":" not in name, "source paths must be repository-relative")
        require(isinstance(digest, str) and len(digest) == 64
                and all(char in "0123456789abcdef" for char in digest),
                f"invalid source SHA-256: {name}")
    return result


def source_inputs(hashes: dict) -> dict:
    return {name: digest for name, digest in hashes.items()
            if name in HOST_SOURCES or name.startswith(SOURCE_PREFIXES)}


def samples(values: object, count: int, label: str, allow_zero: bool = False) -> list[float]:
    require(isinstance(values, list) and len(values) == count, f"{label}: wrong sample count")
    require(all(isinstance(value, (int, float)) and not isinstance(value, bool)
                and math.isfinite(value) and (value >= 0 if allow_zero else value > 0)
                for value in values), f"{label}: nonfinite or invalid timings")
    return values


def summary(values: list[float], compile_percentile: bool = False) -> dict:
    require(bool(values), "cannot summarize an empty sample set")
    ordered = sorted(values)
    index = (int(0.95 * (len(ordered) - 1) + 0.5) if compile_percentile
             else math.ceil(0.95 * len(ordered)) - 1)
    return {"count": len(values), "median": statistics.median(values), "p95": ordered[index],
            "min": ordered[0], "max": ordered[-1]}


def validate_compile(data: dict, collection: dict) -> dict:
    target = data.get("target")
    native_metal = data.get("kind") == "metal_downstream_compile"
    require(data.get("schema") == "slang-ray-tracing-perf-v1" and data.get("unit") == "ms",
            "compile result schema/unit mismatch")
    require(native_metal == (collection["platform"] == "macos"), "compile result kind mismatch")
    require(native_metal or data.get("kind") == "compile", "unknown compile measurement")
    settings = collection["settings"]
    count = settings["compile_iterations"]
    require(data.get("sample_count") == count and data.get("warmup_count") == settings["compile_warmup"],
            "compile iteration/warmup mismatch")
    label = data.get("input_provenance" if native_metal else "compiler")
    require(label == collection["compiler"], "compile result compiler provenance mismatch")
    cases = data.get("cases", [])
    expected = ({"structural-generated", "native-handwritten"} if native_metal else
                {"structural"} if target == "metal" else {"structural", "legacy"})
    require(len(cases) == len(expected) and {case.get("name") for case in cases} == expected,
            "compile result has missing/duplicate comparison cases")
    if not native_metal:
        require(data.get("optimization") == "maximal", "unmatched compile optimization")
        expected_profile = {"spirv": "spirv_1_5", "dxil": "lib_6_6", "metal": "metallib_3_1",
                            "ptx": settings.get("ptx_arch")}.get(target)
        require(expected_profile is not None and data.get("profile") == expected_profile,
                "compile profile mismatch")
    for case in cases:
        if native_metal:
            samples(case.get("samples"), count, "Apple compile")
        else:
            require(case.get("entry_point_count") == 9 and set(case.get("entry_points", [])) == STAGES
                    and len(case["entry_points"]) == 9, "compile did not cover exactly nine stages")
            require(case.get("code_size_bytes", 0) > 0, "compile emitted no target code")
            total = samples(case.get("total_wall_ms", {}).get("samples"), count, "compile wall")
            residual = samples(case.get("slang_ms", {}).get("samples"), count, "Slang residual")
            downstream = samples(case.get("downstream_ms", {}).get("samples"), count,
                                 "downstream", allow_zero=target == "metal")
            require(target != "metal" or all(value == 0 for value in downstream),
                    "MSL generation unexpectedly includes a downstream compiler")
            require(all(math.isclose(wall, front + back, rel_tol=1e-7, abs_tol=1e-6)
                        for wall, front, back in zip(total, residual, downstream)),
                    "compile phase times do not sum to measured wall time")
    return data


def validate_runtime(directory: Path, collection: dict, backend: str) -> dict:
    suite = read_json(directory / "runtime-suite.json")
    require(suite.get("schema") == "cornell-runtime-suite-v1" and suite.get("status") == "complete"
            and suite.get("passed") is True, f"{backend}: incomplete runtime suite")
    reference = "native" if backend == "metal" else "legacy"
    require(suite.get("backend") == backend and suite.get("reference") == reference
            and suite.get("kind") == ("metal" if backend == "metal" else "rhi")
            and suite.get("scene") == SCENE, f"{backend}: runtime lane/scene mismatch")
    options = suite["options"]
    for key in OPTION_KEYS:
        require(options.get(key) == collection["settings"].get(key),
                f"{backend}: runtime configuration mismatch: {key}")
    require(options.get("ao_radius") == 0.75 and options.get("ao_samples") == 8,
            f"{backend}: inconsistent AO configuration")
    provenance = suite["input_provenance"]
    require(normalized_hashes(provenance["source_sha256"]) == source_inputs(collection["source_sha256"]),
            f"{backend}: runtime shaders differ from collection inputs")
    require(provenance.get("renderer_sha256") in collection["tool_sha256"].values(),
            f"{backend}: runtime renderer differs from collected binary")
    gate = suite.get("correctness_gate", {})
    require(gate.get("passed") is True, f"{backend}: missing correctness gate")
    validation = read_json(child_path(directory, gate["result"]))
    require(validation.get("status") == "complete" and validation.get("passed") is True
            and validation.get("headless_passed") is True
            and validation.get("input_provenance") == provenance
            and validation.get("repeat", {}).get("passed") is True,
            f"{backend}: invalid correctness evidence")
    expected_parity = {"beauty-glass", "beauty-diffuse", "beauty-none", "direct-glass", "ao-glass"}
    require(set(validation.get("parity", {})) == expected_parity
            and all(case.get("passed") is True for case in validation["parity"].values()),
            f"{backend}: missing successful image comparisons")
    timed_gate = gate.get("timed_configuration", {})
    require(timed_gate.get("passed") is True
            and set(timed_gate.get("parity", {})) == set(options["views"])
            and all(case.get("passed") is True for case in timed_gate["parity"].values()),
            f"{backend}: missing/failed timed-configuration image gate")
    require(timed_gate.get("settings") == {key: options[key] for key in
            ("width", "height", "samples", "bounces", "seed", "ao_radius", "ao_samples")},
            f"{backend}: timed image-gate configuration mismatch")
    runs = suite.get("runs", [])
    require(len(runs) == options["rounds"] * len(options["views"]) * 2,
            f"{backend}: missing runtime rounds")
    seen = set()
    published_runs = []
    for run in runs:
        identity = (run["round"], run["view"], run["implementation"])
        require(identity not in seen and 1 <= run["round"] <= options["rounds"]
                and run["view"] in options["views"] and run["implementation"] in ("structural", reference)
                and run.get("status") == "complete", f"{backend}: invalid or duplicate runtime run")
        seen.add(identity)
        timings = samples(run.get("samples_ms"), options["iterations"], "runtime")
        raw_path = child_path(directory, run["raw_json"])
        require(hashlib.sha256(raw_path.read_bytes()).hexdigest() == run["raw_json_sha256"],
                f"{backend}: raw runtime evidence hash mismatch")
        raw = read_json(raw_path)
        require(raw.get("samples") == timings and raw.get("device") == suite.get("device")
                and raw.get("implementation") == run["implementation"]
                and str(raw.get("backend", "")).lower() == backend,
                f"{backend}: raw runtime data mismatch")
        expected = {"width": options["width"], "height": options["height"],
                    "samples_per_pixel": options["samples"], "max_bounces": options["bounces"],
                    "seed": options["seed"], "view_mode": VIEW_MODES[run["view"]], "sphere_mode": 0,
                    "ao_radius": options["ao_radius"], "ao_samples": options["ao_samples"],
                    "sample_count": options["iterations"], "warmup_count": options["warmup"],
                    "scene": SCENE, "sphere_geometry": "custom-intersection-aabb", "exposure": 1}
        for key, value in expected.items():
            require(raw.get(key) == value, f"{backend}: raw runtime setting mismatch: {key}")
        published_runs.append({key: run[key] for key in ("round", "view", "implementation",
                               "started_utc", "finished_utc", "samples_ms", "raw_json_sha256")})
    for round_index in range(1, options["rounds"] + 1):
        expected_order = ["structural", reference] if round_index % 2 else [reference, "structural"]
        for view in options["views"]:
            actual_order = [run["implementation"] for run in runs
                            if run["round"] == round_index and run["view"] == view]
            require(actual_order == expected_order, f"{backend}: pair-order mismatch")
    return {"backend": backend, "reference": reference, "device": suite["device"],
            "options": options, "started_utc": suite["started_utc"], "finished_utc": suite["finished_utc"],
            "method": suite["method"], "input_provenance": provenance,
            "tool_sha256": suite["tool_sha256"], "runs": published_runs,
            "correctness": {"settings": validation["settings"], "thresholds": validation["thresholds"],
                            "parity": validation["parity"], "repeat": validation["repeat"],
                            "timed_configuration": {key: timed_gate[key] for key in
                                ("settings", "thresholds", "images", "parity", "passed")}}}


def load_collection(input_dir: Path) -> dict:
    bundle = {"schema": "cornell-path-tracer-published-benchmark-v1", "platforms": {}}
    common_sources = common_commit = common_sample = common_settings = None
    for platform, backends in PLATFORMS.items():
        directory = input_dir / platform
        collection = read_json(directory / "collection.json")
        require(collection.get("schema") == "cornell-benchmark-collection-v1"
                and collection.get("status") == "complete" and collection.get("passed") is True
                and collection.get("platform") == platform, f"{platform}: incomplete collection")
        collection["source_sha256"] = normalized_hashes(collection["source_sha256"])
        settings = {key: collection["settings"][key] for key in OPTION_KEYS}
        settings.update({key: collection["settings"][key]
                         for key in ("compile_iterations", "compile_warmup")})
        require(set(settings["views"]) == {"beauty", "ao"}, "report requires beauty and AO workloads")
        require(settings["rounds"] >= 2 and settings["rounds"] % 2 == 0,
                "report requires balanced odd/even runtime rounds")
        require(settings["iterations"] > 0 and settings["compile_iterations"] > 0,
                "report requires nonempty timing samples")
        if common_sources is None:
            common_sources = collection["source_sha256"]
            common_commit, common_sample = collection["compiler_commit"], collection["sample_commit"]
            common_settings = settings
        require(collection["source_sha256"] == common_sources, f"{platform}: source hash mismatch")
        require(collection["compiler_commit"] == common_commit, f"{platform}: compiler commit mismatch")
        require(collection["sample_commit"] == common_sample, f"{platform}: sample commit mismatch")
        require(settings == common_settings, f"{platform}: cross-platform measurement settings mismatch")
        require(all(command.get("returncode") == 0 for command in collection.get("commands", [])),
                f"{platform}: failed collection command")
        compiled = [validate_compile(read_json(child_path(directory, name)), collection)
                    for name in collection["compile_results"]]
        require(len(compiled) == len(TARGETS[platform])
                and {result["target"] for result in compiled} == TARGETS[platform],
                f"{platform}: incomplete compile targets")
        require(set(collection["runtime_suites"]) == {f"runtime-{backend}" for backend in backends},
                f"{platform}: incomplete runtime backends")
        runtime = {backend: validate_runtime(directory / f"runtime-{backend}", collection, backend)
                   for backend in backends}
        environment = [{"probe": PurePosixPath(item["command"][0].replace("\\", "/")).name,
                        "output": item.get("output", "unavailable"),
                        "returncode": item.get("returncode")}
                       for item in collection.get("environment", [])]
        bundle["platforms"][platform] = {
            **{key: collection[key] for key in ("run_id", "host", "compiler", "compiler_build",
                                               "started_utc", "finished_utc")},
            "tool_sha256": {PurePosixPath(name.replace("\\", "/")).name: value
                            for name, value in collection["tool_sha256"].items()},
            "environment": environment, "compile": compiled, "runtime": runtime}
    bundle.update({"compiler_commit": common_commit, "sample_commit": common_sample,
                   "source_sha256": common_sources, "settings": common_settings, "scene": SCENE})
    return bundle


def runtime_statistics(suite: dict, view: str) -> dict:
    reference = suite["reference"]
    selected = [run for run in suite["runs"] if run["view"] == view]
    result = {implementation: summary([value for run in selected
              if run["implementation"] == implementation for value in run["samples_ms"]])
              for implementation in ("structural", reference)}
    deltas = []
    for round_index in range(1, suite["options"]["rounds"] + 1):
        medians = {run["implementation"]: statistics.median(run["samples_ms"])
                   for run in selected if run["round"] == round_index}
        deltas.append((medians["structural"] / medians[reference] - 1) * 100)
    result["pooled_delta_percent"] = (result["structural"]["median"] / result[reference]["median"] - 1) * 100
    result["round_delta_percent"] = {"median": statistics.median(deltas), "min": min(deltas),
                                     "max": max(deltas), "values": deltas}
    return result


def compile_stats(case: dict, metric: str) -> dict:
    return summary(case[metric]["samples"], compile_percentile=True)


def table_cell(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def render_report(bundle: dict, data_link: str, date: str) -> str:
    platforms = bundle["platforms"]
    runtimes = {backend: suite for platform in platforms.values()
                for backend, suite in platform["runtime"].items()}
    compiled = {result["target"]: result for platform in platforms.values()
                for result in platform["compile"] if result["kind"] == "compile"}
    apple = platforms["macos"]["compile"][0]
    settings = bundle["settings"]
    deltas = {}
    for target in ("spirv", "dxil", "ptx"):
        cases = {case["name"]: case for case in compiled[target]["cases"]}
        deltas[target] = (compile_stats(cases["structural"], "total_wall_ms")["median"] /
                          compile_stats(cases["legacy"], "total_wall_ms")["median"] - 1) * 100
    runtime_results = {(backend, view): runtime_statistics(suite, view)
                       for backend, suite in runtimes.items() for view in settings["views"]}
    largest = max(runtime_results, key=lambda key: abs(runtime_results[key]["pooled_delta_percent"]))
    largest_value = runtime_results[largest]["pooled_delta_percent"]
    lines = ["# Cornell path-tracer performance", "", f"Measured {date} (America/Los_Angeles).",
             "", "These are fresh measurements of the path tracer with a procedural glass sphere and AO, "
             "not the old direct-lighting demo. Both implementations were measured together on each runner "
             "with the same compiler revision and source snapshot. "
             "[September 14 direct-lighting results](performance-direct-lighting-20260914.md) are archived separately.",
             "", "## Results at a glance", "",
             "- Slang + downstream median compile-time change, new API versus legacy: " +
             "; ".join(f"{NAMES[target]} **{deltas[target]:+.1f}%**" for target in ("spirv", "dxil", "ptx")) + ".",
             f"- Largest observed absolute runtime median difference: **{NAMES[largest[0]]} {largest[1]}, "
             f"{largest_value:+.1f}%**. See paired-round ranges below before interpreting this as a regression.",
             "- Positive percentages mean the new API is slower. These are complete-implementation comparisons; "
             "they do not isolate API syntax, and the timings alone do not explain a difference.", "",
             "## What was measured", "",
             f"- Sample base: [`{bundle['sample_commit'][:12]}`](https://github.com/kaizhangNV/structural-rt-cornell-demo/commit/{bundle['sample_commit']}); "
             "benchmark-tool changes are identified by the published source hashes.",
             f"- Slang source: [`{bundle['compiler_commit'][:12]}`](https://github.com/kaizhangNV/slang/commit/{bundle['compiler_commit']}). "
             "Build tags can differ across runners; this full source commit is authoritative.",
             f"- Scene `{SCENE}`: triangle room plus custom-intersection AABB sphere, center `(0, 0.75, 0)`, "
             "radius `0.4`, glass enabled, exposure `1`.",
             f"- Runtime: **{settings['width']}×{settings['height']}, {settings['samples']} samples/pixel**, "
             f"seed `{settings['seed']}`, at most `{settings['bounces']}` beauty-path bounces. AO is a separate "
             "view with up to 8 occlusion rays per camera sample and radius `0.75`; primary misses skip "
             "occlusion rays, and AO does not use the bounce loop.",
             f"- Each runtime lane: {settings['rounds']} fresh-process paired rounds, "
             f"{settings['warmup']} warmups + {settings['iterations']} timed dispatches per process "
             f"({settings['rounds'] * settings['iterations']} retained samples per implementation/view). "
             "Each dispatch resets accumulation and repeats the same seeded workload.",
             f"- Compilation: {settings['compile_warmup']} warmups + {settings['compile_iterations']} retained "
             "samples per case, alternating case order in one process.", "",
             "| Runner | OS / CPU | GPU | Compiler build |", "| --- | --- | --- | --- |"]
    for name, platform in platforms.items():
        devices = sorted({suite["device"] for suite in platform["runtime"].values()})
        cpu = next((item["output"].strip() for item in platform["environment"]
                    if item["probe"] == "sysctl"), "")
        if name == "linux":
            cpu = next((line.split(":", 1)[1].strip() for item in platform["environment"]
                        for line in item["output"].splitlines() if line.startswith("Model name:")), "")
        elif name == "windows":
            cpu = next((item["output"].strip() for item in platform["environment"]
                        if item["probe"].lower() == "powershell.exe"), "")
        lines.append(f"| {name} | {table_cell(platform['host'] + ('; ' + cpu if cpu else ''))} | "
                     f"{table_cell(', '.join(devices))} | {table_cell(platform['compiler_build'])} |")
    lines += ["", "## Compile time", "", "All values are milliseconds. `Slang` is the inclusive wall-time "
              "residual from session creation through output extraction, minus Slang's downstream timer. "
              "It includes source loading, reflection, composition/linking and code generation; it is not "
              "an isolated code-generation pass. `Downstream` includes the compiler adapter around the "
              "in-process optimizer/compiler call.", "",
              "| Target | Implementation | Slang median | Downstream median | Total median | Total p95 | Output bytes | Total change |",
              "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for target in ("spirv", "dxil", "ptx"):
        cases = {case["name"]: case for case in compiled[target]["cases"]}
        for implementation in ("legacy", "structural"):
            case = cases[implementation]
            front, back, total = [compile_stats(case, metric) for metric in
                                  ("slang_ms", "downstream_ms", "total_wall_ms")]
            change = "baseline" if implementation == "legacy" else f"{deltas[target]:+.1f}%"
            lines.append(f"| {NAMES[target]} | {'new API' if implementation == 'structural' else 'legacy'} | "
                         f"{front['median']:.3f} | {back['median']:.3f} | {total['median']:.3f} | "
                         f"{total['p95']:.3f} | {case['code_size_bytes']} | {change} |")
    lines += ["", "- SPIR-V 1.5: direct Slang emission, then Slang's bundled `spirv-opt` path; one whole-program output.",
              "- DXIL `lib_6_6`: nine separately emitted stage libraries; downstream is their summed DXC time.",
              f"- PTX `{compiled['ptx']['profile']}`: nine separately emitted stage libraries; downstream is their summed NVRTC time. "
              "OptiX driver compilation/JIT is not included.",
              "- Both APIs cover one raygen, four closest-hit, two intersection and two miss stages. "
              "New-API schema reflection is included; legacy explicitly selects the equivalent stages.",
              "- Compile benchmarks use maximal optimization. Runtime uses the renderer/RHI's normal defaults; "
              "both implementations have matching settings within each comparison.",
              "- Output bytes mean optimized SPIR-V, or the sum of all DXIL/PTX blobs (including repeated "
              "per-stage boilerplate), not final GPU machine code. Separately computed medians need not add up.",
              "", "### Metal compilation", "", "Metal has no legacy Slang pipeline lane. Linux Slang→MSL "
              "generation and macOS MSL→library compilation are separate measurements on different machines; "
              "do not add their medians into a synthetic end-to-end value.", "",
              "| Phase / input | Median ms | p95 ms | Change |", "| --- | ---: | ---: | ---: |"]
    msl = compile_stats(compiled["metal"]["cases"][0], "total_wall_ms")
    lines.append(f"| Slang new API → MSL (Linux) | {msl['median']:.3f} | {msl['p95']:.3f} | no legacy lane |")
    apple_cases = {case["name"]: summary(case["samples"], compile_percentile=True) for case in apple["cases"]}
    apple_delta = (apple_cases["structural-generated"]["median"] / apple_cases["native-handwritten"]["median"] - 1) * 100
    for name, label in (("native-handwritten", "Hand-written MSL → Metal library"),
                        ("structural-generated", "Generated MSL → Metal library")):
        case = apple_cases[name]
        change = "baseline" if name == "native-handwritten" else f"{apple_delta:+.1f}%"
        lines.append(f"| {label} | {case['median']:.3f} | {case['p95']:.3f} | {change} |")
    lines += ["", "Apple compilation measures synchronous `MTLDevice.newLibrary(source)` with Metal 3.1, "
              "excluding source-file I/O and pipeline creation. Unique trailing comments avoid identical "
              "source hashes, but do not flush Apple's internal caches or guarantee cold compilation. "
              "The Slang→MSL benchmark uses maximal optimization; Apple compilation/runtime uses the checked-in "
              "generated artifact built with the normal generator defaults. This is not one timed artifact chain; "
              "the published hash identifies the exact Apple input.",
              "", "## Runtime", "", "GPU duration of one dispatch, not interactive frame time/FPS. Compare "
              "within a backend, not absolute times across machines or timestamp mechanisms. The range "
              "is the minimum/maximum new-versus-baseline percentage from each paired round's medians.", "",
              "| Backend / view | Baseline median / p95 ms | New API median / p95 ms | Pooled median change | Paired-round median change range |",
              "| --- | ---: | ---: | ---: | ---: |"]
    for backend in ("vulkan", "d3d12", "optix", "metal"):
        for view in settings["views"]:
            value = runtime_results[backend, view]
            base, new, paired = value[runtimes[backend]["reference"]], value["structural"], value["round_delta_percent"]
            lines.append(f"| {NAMES[backend]} / {view} | {base['median']:.4f} / {base['p95']:.4f} | "
                         f"{new['median']:.4f} / {new['p95']:.4f} | {value['pooled_delta_percent']:+.1f}% | "
                         f"{paired['min']:+.1f}% to {paired['max']:+.1f}% |")
    lines += ["", "Vulkan/D3D12/OptiX use GPU timestamp queries around `dispatchRays`; Metal uses "
              "`GPUStartTime`→`GPUEndTime` of a command buffer containing one compute dispatch. "
              "Shader compilation, device/pipeline/SBT/acceleration-structure construction, image readback "
              "and presentation are excluded. Runs are sequential with AB/BA order balanced across rounds. "
              "Samples within one process are correlated: these are descriptive statistics, not independent "
              "trials or a statistical-significance claim.", "",
              "GPU/CPU clocks and power states were not locked, and these are shared machines rather than "
              "isolated benchmark appliances. Initial environment snapshots do not establish constant "
              "temperature, power or background load during the run.", ""]
    crossing = [f"{NAMES[backend]} {view}" for (backend, view), value in runtime_results.items()
                if value["round_delta_percent"]["min"] < 0 < value["round_delta_percent"]["max"]]
    if crossing:
        lines += ["**Ordering/drift caution:** " + ", ".join(crossing) +
                  " have paired-round ranges crossing zero. Their pooled median improvements are not "
                  "evidence of a consistently repeatable speedup.", ""]
    d3d_ao = [run for run in runtimes["d3d12"]["runs"] if run["view"] == "ao"]
    d3d_baseline = runtimes["d3d12"]["reference"]
    odd_baseline = statistics.median([statistics.median(run["samples_ms"]) for run in d3d_ao
                                     if run["implementation"] == d3d_baseline and run["round"] % 2])
    even_baseline = statistics.median([statistics.median(run["samples_ms"]) for run in d3d_ao
                                      if run["implementation"] == d3d_baseline and not run["round"] % 2])
    new_median = runtime_results["d3d12", "ao"]["structural"]["median"]
    pooled_delta = runtime_results["d3d12", "ao"]["pooled_delta_percent"]
    if abs(odd_baseline / even_baseline - 1) > 0.1:
        new_rounds = [statistics.median(run["samples_ms"]) for run in d3d_ao
                      if run["implementation"] == "structural"]
        new_description = (f"stays near {new_median:.3f} ms" if max(new_rounds) / min(new_rounds) < 1.05
                           else f"has pooled median {new_median:.3f} ms")
        lines += [f"**D3D12 AO order dependence:** legacy round medians are about {odd_baseline:.3f} ms "
                  f"in structural-first odd rounds versus {even_baseline:.3f} ms in legacy-first even rounds; "
                  f"the new-API lane {new_description}. The effect magnitude correlates with "
                  f"process order, so the pooled {pooled_delta:+.1f}% is not a stable single speedup estimate. "
                  "The cause has not been established.", ""]
    lines += ["## Correctness and comparison limits", "",
              "All four backends passed the five-case 192×192, 64-spp image suite (glass/diffuse/no sphere, "
              "direct light and AO), seeded repeatability, and an image comparison at the timed resolution "
              "and sample count. Exact error values and thresholds are preserved in the data bundle.", "",
              "- The shared integrator is the same Slang module for legacy and new APIs, and both use custom "
              "intersection programs. The procedural sphere is not replaced by a triangle mesh.",
              "- This compares complete implementations. Legacy uses one 36-byte logical payload and a "
              "64-byte configured pipeline maximum; the new API separates primary/shadow payloads and "
              "uses target-reflected native sizes (logical fields total 32/4 bytes). New-API runtime SBT selectors also differ from "
              "legacy constants. These are not payload-size/ABI-controlled experiments.",
              "- Hand-written Metal directly performs native intersection and inline post-trace shading; "
              "generated Metal uses reflected intersection/visible-function tables. The native baseline "
              "also avoids a triangle-normal normalization present in the generated path. Timings include "
              "these implementation differences, not just the shader API abstraction.",
              "- Warm global Slang session, fresh per-sample session; OS file and compiler/plugin caches "
              "are not flushed. Global-session initialization and teardown are excluded. No cold-start or "
              "driver pipeline-compilation performance claim is made.",
              "- Provenance records source snapshot hashes, renderer/benchmark executable hashes and "
              "compiler revision labels, but not hashes of the loaded Slang/downstream shared libraries. "
              "Revision labels alone are not proof of binary identity.",
              "- Compile p95 uses the existing C++ tool's rounded `0.95×(N−1)` index; runtime p95 uses "
              "nearest rank `ceil(0.95×N)−1`. Reported percentages use unrounded samples.", "",
              "## Raw data and reproduction", "",
              f"[Published timing samples and source/tool SHA-256 hashes]({data_link}) include every retained "
              "compile and runtime timing, per-round order, correctness metrics, runner identifiers, "
              "compiler build labels and collection timestamps. Local paths, images and verbose logs are omitted.", "",
              "Build the renderer and benchmark tools with the pinned compiler, then run "
              "[`perf/collect.py`](../perf/collect.py) once per platform into fresh `linux`, `windows` and "
              "`macos` output directories. Each collection records all requested settings and refuses mixed "
              "output directories. See the [full reproduction instructions](../perf/README.md). "
              "Generate this report and its bundle with:", "", "```bash",
              f"python3 perf/path-tracer-report.py --date {date} --input-dir <collection-directory> \\",
              "  --output reports/performance.md \\",
              f"  --data-output reports/data/path-tracer-{date}.json", "```", "",
              "The publisher rejects incomplete lanes, failed correctness gates, changed source hashes, "
              "mismatched compiler/sample revisions, inconsistent settings, missing runtime samples and "
              "runtime raw-file hash mismatches. Compile timings are checked for completeness and phase "
              "consistency; their original result files have no separately recorded integrity hash.", ""]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--data-output", type=Path, required=True)
    parser.add_argument("--date", required=True, help="Measurement date in America/Los_Angeles (YYYY-MM-DD)")
    args = parser.parse_args(argv)
    calendar_date.fromisoformat(args.date)
    bundle = load_collection(args.input_dir)
    bundle["measurement_date"] = args.date
    bundle["timezone"] = "America/Los_Angeles"
    data_link = Path(os.path.relpath(args.data_output, args.output.parent)).as_posix()
    report = render_report(bundle, data_link, args.date)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.data_output.parent.mkdir(parents=True, exist_ok=True)
    args.data_output.write_text(json.dumps(bundle, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    args.output.write_text(report, encoding="utf-8")
    print(f"Published {args.output} and {args.data_output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, KeyError, TypeError, ValueError) as error:
        print(f"benchmark report failed: {error}", file=sys.stderr)
        raise SystemExit(1)
