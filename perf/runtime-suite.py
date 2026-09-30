#!/usr/bin/env python3
"""Run correctness-gated, paired headless GPU dispatch benchmarks.

Each timed process performs its own warmup. Pair order alternates by round to
expose ordering/drift effects; samples are not independent statistical trials.
Reported GPU durations exclude host compilation, pipeline/AS creation, image
readback, and presentation. This tool makes no FPS or significance claims.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import importlib.util
import json
import math
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import time


REPO_ROOT = Path(__file__).resolve().parents[1]
VALIDATOR_SPEC = importlib.util.spec_from_file_location(
    "cornell_runtime_validator", REPO_ROOT / "tools" / "validate-pathtracer.py")
validator = importlib.util.module_from_spec(VALIDATOR_SPEC)
VALIDATOR_SPEC.loader.exec_module(validator)

VIEW_MODES = {"beauty": 0, "ao": 1, "direct": 2}
RHI_METRIC = "GPU timestamp duration around one dispatch"
METAL_METRIC = ("MTLCommandBuffer GPUStartTime to GPUEndTime for one dispatch at "
                "samples_per_pixel; accumulation restarts for each dispatch")


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def summarize(values: list[float]) -> dict:
    """P95 uses nearest rank: sorted[ceil(0.95 * count) - 1]."""
    if not values or not all(math.isfinite(value) for value in values):
        raise ValueError("summary requires nonempty finite samples")
    ordered = sorted(values)
    return {"count": len(values), "median": statistics.median(ordered),
            "p95": ordered[math.ceil(0.95 * len(ordered)) - 1],
            "min": ordered[0], "max": ordered[-1]}


def git_metadata(root: Path) -> dict:
    try:
        revision = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=root, check=True, capture_output=True,
            text=True, timeout=10).stdout.strip()
        status = subprocess.run(
            ["git", "status", "--porcelain=v1", "--untracked-files=all"], cwd=root,
            check=True, capture_output=True, text=True, timeout=10).stdout
        return {"revision": revision, "dirty": bool(status), "status_porcelain": status}
    except (OSError, subprocess.SubprocessError) as error:
        return {"revision": None, "dirty": None, "unavailable_reason": str(error)}


def run_logged(command: list[str], root: Path, log: Path, timeout: int) -> None:
    print("Run: " + subprocess.list2cmdline(command), flush=True)
    with log.open("w", encoding="utf-8") as stream:
        stream.write("Command: " + subprocess.list2cmdline(command) + "\n")
        stream.flush()
        subprocess.run(command, cwd=root, check=True, timeout=timeout,
                       stdout=stream, stderr=subprocess.STDOUT)


def validation_command(args: argparse.Namespace) -> list[str]:
    command = [sys.executable, str(REPO_ROOT / "tools" / "validate-pathtracer.py"),
               "suite", "--renderer", str(args.renderer), "--root", str(args.root),
               "--kind", args.kind, "--output-dir", str(args.output_dir / "validation"),
               "--width", "192", "--height", "192", "--samples", "64", "--repeat",
               "--bounces", str(args.bounces), "--seed", str(args.seed),
               "--ao-radius", str(args.ao_radius), "--ao-samples", str(args.ao_samples),
               "--timeout", str(args.timeout)]
    if args.kind == "rhi":
        command += ["--backend", args.backend]
    if args.optix_include:
        command += ["--optix-include", str(args.optix_include)]
    return command


def check_validation(result: dict, args: argparse.Namespace, provenance: dict) -> None:
    required_settings = {"width": 192, "height": 192, "samples": 64,
                         "bounces": args.bounces, "seed": args.seed,
                         "ao_radius": args.ao_radius, "ao_samples": args.ao_samples}
    if (result.get("validation_schema_version") != 2
            or result.get("status") != "complete" or result.get("passed") is not True
            or result.get("headless_passed") is not True
            or result.get("kind") != args.kind or result.get("backend") != args.backend
            or result.get("settings") != required_settings
            or result.get("input_provenance") != provenance
            or result.get("repeat", {}).get("passed") is not True):
        raise ValueError("correctness gate failed or has mismatched settings/input provenance")
    required_cases = {"beauty-glass", "beauty-diffuse", "beauty-none", "direct-glass", "ao-glass"}
    if (set(result.get("parity", {})) != required_cases
            or not all(case.get("passed") is True for case in result["parity"].values())):
        raise ValueError("correctness gate lacks successful parity cases")


def render_arguments(args: argparse.Namespace, view: str) -> list[str]:
    return [
        "--width", str(args.width), "--height", str(args.height),
        "--samples", str(args.samples), "--bounces", str(args.bounces),
        "--seed", str(args.seed), "--ao-radius", str(args.ao_radius),
        "--ao-samples", str(args.ao_samples), "--view", view,
        "--sphere", "glass", "--exposure", "1"]


def benchmark_command(args: argparse.Namespace, implementation: str,
                      view: str, output: Path) -> list[str]:
    return validator.renderer_command(args, implementation) + [
        "--headless", "--benchmark", "--benchmark-output", str(output),
        "--warmup", str(args.warmup), "--iterations", str(args.iterations),
    ] + render_arguments(args, view)


def timed_configuration_gate(args: argparse.Namespace, reference: str, result: dict) -> None:
    """Check images at the measured settings, before timed processes begin."""
    directory = args.output_dir / "validation-benchmark"
    directory.mkdir()
    thresholds = argparse.Namespace(max_mae=1.0, max_error=32,
                                    outlier_threshold=8, max_outlier_fraction=0.01)
    result.update({"passed": False, "thresholds": vars(thresholds),
                   "settings": {key: getattr(args, key) for key in (
                       "width", "height", "samples", "bounces", "seed", "ao_radius", "ao_samples")},
                   "images": {}, "parity": {}, "commands": []})
    for view in args.views:
        paths = {}
        for implementation in ("structural", reference):
            image = directory / f"{view}-{implementation}.ppm"
            log = args.output_dir / f"validation-benchmark-{view}-{implementation}.log"
            command = validator.renderer_command(args, implementation) + [
                "--headless", "--output", str(image)] + render_arguments(args, view)
            result["commands"].append({"command": command, "log": log.name})
            run_logged(command, args.root, log, args.timeout)
            stats = validator.image_stats(image)
            result["images"][image.relative_to(args.output_dir).as_posix()] = stats
            if (not stats["valid_image"] or stats["width"] != args.width
                    or stats["height"] != args.height or (view == "ao" and not stats["grayscale"])):
                raise ValueError(f"invalid measured-configuration {view}/{implementation} image")
            paths[implementation] = image
        comparison = validator.compare_images(paths["structural"], paths[reference], thresholds.outlier_threshold)
        comparison["passed"] = validator.parity_passes(comparison, thresholds)
        result["parity"][view] = comparison
        if not comparison["passed"]:
            raise ValueError(f"measured-configuration parity failed for {view}")
    result["passed"] = True


def check_benchmark(result: dict, args: argparse.Namespace,
                    implementation: str, view: str) -> list[float]:
    expected = {
        "schema": "slang-ray-tracing-perf-v1", "kind": "runtime", "unit": "ms",
        "implementation": implementation, "width": args.width, "height": args.height,
        "samples_per_pixel": args.samples, "max_bounces": args.bounces,
        "seed": args.seed, "ao_samples": args.ao_samples, "view_mode": VIEW_MODES[view],
        "sphere_mode": 0, "scene": validator.SCENE_ID,
        "sphere_geometry": "custom-intersection-aabb", "exposure": 1,
        "warmup_count": args.warmup, "sample_count": args.iterations,
        "metric": METAL_METRIC if args.kind == "metal" else RHI_METRIC,
    }
    for key, value in expected.items():
        if result.get(key) != value:
            raise ValueError(f"benchmark metadata mismatch for {key}: "
                             f"expected {value!r}, got {result.get(key)!r}")
    if str(result.get("backend", "")).lower() != args.backend:
        raise ValueError("benchmark backend does not match requested backend")
    if not isinstance(result.get("device"), str) or not result["device"]:
        raise ValueError("benchmark is missing device identification")
    radius = result.get("ao_radius")
    if (not isinstance(radius, (int, float)) or isinstance(radius, bool)
            or not math.isfinite(radius)
            or not math.isclose(radius, args.ao_radius, rel_tol=1e-6, abs_tol=1e-9)):
        raise ValueError("benchmark AO radius does not match requested radius")
    samples = result.get("samples")
    if (not isinstance(samples, list) or len(samples) != args.iterations
            or not all(isinstance(value, (float, int)) and not isinstance(value, bool)
                       and math.isfinite(value) and value > 0 for value in samples)):
        raise ValueError("benchmark must have the requested count of positive finite GPU timings")
    return samples


def aggregate(runs: list[dict], views: list[str], reference: str, rounds: int) -> dict:
    cases = {}
    paired = {}
    for view in views:
        for implementation in ("structural", reference):
            matching = [run for run in runs if run["view"] == view
                        and run["implementation"] == implementation]
            cases[f"{view}/{implementation}"] = {
                "pooled_gpu_ms": summarize([sample for run in matching for sample in run["samples_ms"]]),
                "round_medians_gpu_ms": summarize([run["summary_gpu_ms"]["median"] for run in matching]),
            }
        pairs = []
        for round_index in range(rounds):
            matches = {run["implementation"]: run for run in runs
                       if run["view"] == view and run["round"] == round_index + 1}
            structural = matches["structural"]["summary_gpu_ms"]["median"]
            baseline = matches[reference]["summary_gpu_ms"]["median"]
            pairs.append({"round": round_index + 1,
                          "order": [run["implementation"] for run in runs
                                    if run["view"] == view and run["round"] == round_index + 1],
                          "structural_median_ms": structural, "reference_median_ms": baseline,
                          "delta_ms": structural - baseline,
                          "delta_percent": (structural / baseline - 1) * 100})
        paired[view] = {"reference": reference, "rounds": pairs,
                        "delta_ms": summarize([pair["delta_ms"] for pair in pairs]),
                        "delta_percent": summarize([pair["delta_percent"] for pair in pairs])}
    return {"cases": cases, "paired_round_deltas": paired}


def run_suite(args: argparse.Namespace) -> bool:
    args.root = args.root.resolve()
    args.renderer = args.renderer.resolve()
    args.output_dir = args.output_dir.resolve()
    if args.optix_include:
        args.optix_include = args.optix_include.resolve()
    if not args.renderer.is_file():
        raise ValueError(f"renderer does not exist: {args.renderer}")
    if args.output_dir.exists() and any(args.output_dir.iterdir()):
        raise ValueError("output directory must be empty to prevent mixing benchmark runs")
    metadata = git_metadata(args.root)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    result_path = args.output_dir / "runtime-suite.json"
    reference = "native" if args.kind == "metal" else "legacy"
    result = {
        "schema": "cornell-runtime-suite-v1", "status": "running", "passed": False,
        "started_utc": utc_now(), "finished_utc": None,
        "kind": args.kind, "backend": args.backend, "reference": reference,
        "scene": validator.SCENE_ID,
        "platform": {"system": platform.system(), "release": platform.release(),
                     "version": platform.version(), "machine": platform.machine(),
                     "processor": platform.processor(), "hostname": platform.node(),
                     "python": platform.python_version()},
        "git": metadata,
        "options": {key: getattr(args, key) for key in (
            "rounds", "warmup", "iterations", "width", "height", "samples", "bounces",
            "seed", "ao_radius", "ao_samples", "views", "timeout")},
        "paths": {"root": str(args.root), "renderer": str(args.renderer),
                  "optix_include": str(args.optix_include) if args.optix_include else None},
        "method": {
            "pair_order": "structural/reference on odd rounds, reference/structural on even rounds",
            "processes": "sequential; one fresh host process with its own warmup per view/implementation/round",
            "unit": "ms", "p95": "nearest rank: sorted[ceil(0.95 * count) - 1]",
            "gpu_metric": METAL_METRIC if args.kind == "metal" else RHI_METRIC,
            "excluded": "host compilation, pipeline/AS creation, readback, presentation; not FPS",
            "workload": "one dispatch at the requested samples per pixel; same seed and accumulation reset per dispatch",
            "interpretation": "positive paired delta means structural is slower; descriptive statistics only, no significance claim",
        },
        "runs": [],
    }
    validator.save_checkpoint(result, result_path)
    started = time.monotonic()
    try:
        provenance = validator.input_provenance(args.root, args.renderer)
        result["input_provenance"] = provenance
        result["tool_sha256"] = {
            "perf/runtime-suite.py": validator.file_sha256(Path(__file__)),
            "tools/validate-pathtracer.py": validator.file_sha256(REPO_ROOT / "tools" / "validate-pathtracer.py"),
        }
        gate_command = validation_command(args)
        result["correctness_gate"] = {"command": gate_command, "log": "validation.log",
                                      "result": "validation/validation.json", "passed": False}
        validator.save_checkpoint(result, result_path)
        run_logged(gate_command, args.root, args.output_dir / "validation.log", args.timeout * 12)
        gate = json.loads((args.output_dir / "validation" / "validation.json").read_text(encoding="utf-8"))
        check_validation(gate, args, provenance)
        result["correctness_gate"]["timed_configuration"] = {}
        timed_configuration_gate(args, reference, result["correctness_gate"]["timed_configuration"])
        if validator.input_provenance(args.root, args.renderer) != provenance:
            raise ValueError("shader/host/renderer inputs changed during correctness gate")
        result["correctness_gate"]["passed"] = True
        validator.save_checkpoint(result, result_path)
        device = None
        for round_index in range(args.rounds):
            order = ("structural", reference) if round_index % 2 == 0 else (reference, "structural")
            for view in args.views:
                for implementation in order:
                    basename = f"round-{round_index + 1:02d}-{view}-{implementation}"
                    raw_path = args.output_dir / f"{basename}.json"
                    command = benchmark_command(args, implementation, view, raw_path)
                    run = {"round": round_index + 1, "view": view, "implementation": implementation,
                           "command": command, "started_utc": utc_now(), "finished_utc": None,
                           "raw_json": raw_path.name, "log": f"{basename}.log", "status": "running"}
                    result["runs"].append(run)
                    validator.save_checkpoint(result, result_path)
                    run_logged(command, args.root, args.output_dir / run["log"], args.timeout)
                    raw = json.loads(raw_path.read_text(encoding="utf-8"))
                    samples = check_benchmark(raw, args, implementation, view)
                    if device is not None and raw["device"] != device:
                        raise ValueError("GPU device changed between benchmark processes")
                    device = raw["device"]
                    result["device"] = device
                    run.update({"finished_utc": utc_now(), "status": "complete",
                                "samples_ms": samples, "summary_gpu_ms": summarize(samples),
                                "raw_json_sha256": validator.file_sha256(raw_path)})
                    validator.save_checkpoint(result, result_path)
        if validator.input_provenance(args.root, args.renderer) != provenance:
            raise ValueError("shader/host/renderer inputs changed during timed measurements")
        result.update(aggregate(result["runs"], args.views, reference, args.rounds))
        result.update({"status": "complete", "passed": True})
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        result.update({"status": "error", "error": str(error)})
    finally:
        result["finished_utc"] = utc_now()
        result["elapsed_seconds"] = time.monotonic() - started
        validator.save_checkpoint(result, result_path)
    print(f"Runtime suite {'PASS' if result['passed'] else 'FAIL'}: {result_path}", flush=True)
    if not result["passed"]:
        print(result.get("error", "suite did not complete"), file=sys.stderr)
    return result["passed"]


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--renderer", type=Path, required=True)
    parser.add_argument("--kind", choices=("rhi", "metal"), required=True)
    parser.add_argument("--backend", choices=("vulkan", "optix", "d3d12", "metal"), required=True)
    parser.add_argument("--root", type=Path, default=REPO_ROOT)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--optix-include", type=Path)
    for name, default in (("rounds", 6), ("warmup", 10), ("iterations", 50),
                          ("width", 512), ("height", 512), ("samples", 8),
                          ("bounces", 8), ("seed", 17), ("ao-samples", 8), ("timeout", 300)):
        parser.add_argument("--" + name, type=int, default=default)
    parser.add_argument("--ao-radius", type=float, default=0.75)
    parser.add_argument("--views", nargs="+", choices=tuple(VIEW_MODES), default=["beauty", "ao"])
    args = parser.parse_args(argv)
    if (args.kind == "metal") != (args.backend == "metal"):
        parser.error("--kind metal requires --backend metal; --kind rhi requires a non-Metal backend")
    for name, maximum in (("rounds", None), ("warmup", None), ("iterations", None),
                          ("width", 4096), ("height", 4096), ("samples", 65536),
                          ("bounces", 64), ("seed", 4294967295), ("ao_samples", 256), ("timeout", None)):
        value = getattr(args, name)
        minimum = 0 if name == "seed" else 1
        if value < minimum or (maximum is not None and value > maximum):
            parser.error(f"--{name.replace('_', '-')} must be >= {minimum}"
                         + (f" and <= {maximum}" if maximum is not None else ""))
    if not math.isfinite(args.ao_radius) or not 0 < args.ao_radius <= 1000:
        parser.error("--ao-radius must be finite and in (0, 1000]")
    if len(set(args.views)) != len(args.views):
        parser.error("--views must not contain duplicates")
    return args


def main() -> int:
    try:
        return 0 if run_suite(parse_args()) else 1
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
