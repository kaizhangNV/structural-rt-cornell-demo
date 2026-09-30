#!/usr/bin/env python3
"""Render and compare deterministic Cornell images; no third-party Python packages needed.

Error units are output RGB bytes (0..255), after the renderer's display transform.
These correctness checks are not linear-radiance or runtime-performance measurements.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import time


SCENE_ID = "cornell-procedural-sphere-v2"


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def input_provenance(root: Path, renderer: Path) -> dict:
    """Identify inputs, without mistaking the expected scene label for a geometry test."""
    sources = [root / name for name in (
        "scene.h", "render-settings.h", "rhi-main.cpp", "metal-main.cpp",
        "shaders/cornell-box-native.metal", "generated/cornell-box.metal",
        "generated/program-schema.txt")]
    for directory in ("shaders", "shaders-legacy"):
        sources.extend((root / directory).glob("*.slang"))
    return {
        "renderer_sha256": file_sha256(renderer) if renderer.is_file() else None,
        "source_sha256": {
            path.relative_to(root).as_posix(): file_sha256(path)
            for path in sorted(set(sources)) if path.is_file()
        },
    }


def read_ppm(path: Path) -> tuple[int, int, bytes]:
    """Read one 8-bit P6 PPM without treating whitespace-valued pixels as header."""
    contents = path.read_bytes()
    offset = 0

    def token() -> bytes:
        nonlocal offset
        while offset < len(contents):
            if contents[offset] in b" \t\r\n":
                offset += 1
            elif contents[offset] == ord("#"):
                newline = contents.find(b"\n", offset)
                if newline < 0:
                    raise ValueError(f"{path}: unterminated PPM comment")
                offset = newline + 1
            else:
                break
        start = offset
        while offset < len(contents) and contents[offset] not in b" \t\r\n#":
            offset += 1
        if start == offset:
            raise ValueError(f"{path}: incomplete PPM header")
        return contents[start:offset]

    magic, width, height, maximum = (token() for _ in range(4))
    if magic != b"P6" or maximum != b"255":
        raise ValueError(f"{path}: expected 8-bit binary P6 PPM")
    width, height = int(width), int(height)
    if width <= 0 or height <= 0 or offset >= len(contents):
        raise ValueError(f"{path}: invalid PPM size/header")
    if contents[offset] not in b" \t\r\n":
        raise ValueError(f"{path}: missing PPM raster separator")
    offset += 1
    if contents[offset - 1:offset + 1] == b"\r\n":
        offset += 1
    pixels = contents[offset:]
    if len(pixels) != width * height * 3:
        raise ValueError(f"{path}: expected {width * height * 3} bytes, got {len(pixels)}")
    return width, height, pixels


def image_stats(path: Path) -> dict:
    width, height, pixels = read_ppm(path)
    mean = sum(pixels) / len(pixels)
    variance = sum((value - mean) ** 2 for value in pixels) / len(pixels)
    return {
        "width": width,
        "height": height,
        "mean_byte": mean,
        "stddev_byte": math.sqrt(variance),
        "minimum_byte": min(pixels),
        "maximum_byte": max(pixels),
        "nonblack_pixel_fraction": sum(any(pixels[i:i + 3]) for i in range(0, len(pixels), 3)) / (width * height),
        "grayscale": all(pixels[i] == pixels[i + 1] == pixels[i + 2] for i in range(0, len(pixels), 3)),
        "raster_sha256": hashlib.sha256(pixels).hexdigest(),
        "valid_image": mean > 1.0 and variance > 1.0,
    }


def compare_images(actual: Path, reference: Path, outlier_threshold: int = 8) -> dict:
    width, height, pixels = read_ppm(actual)
    reference_width, reference_height, reference_pixels = read_ppm(reference)
    if (width, height) != (reference_width, reference_height):
        raise ValueError(f"image dimensions differ: {actual} vs {reference}")
    errors = [abs(a - b) for a, b in zip(pixels, reference_pixels)]
    count = len(errors)
    return {
        "mae_byte": sum(errors) / count,
        "rmse_byte": math.sqrt(sum(error * error for error in errors) / count),
        "maximum_byte": max(errors),
        "changed_channel_fraction": sum(error != 0 for error in errors) / count,
        "outlier_threshold_byte": outlier_threshold,
        "outlier_channel_fraction": sum(error > outlier_threshold for error in errors) / count,
    }


def parity_passes(metrics: dict, args: argparse.Namespace) -> bool:
    return (
        metrics["mae_byte"] <= args.max_mae
        and metrics["maximum_byte"] <= args.max_error
        and metrics["outlier_channel_fraction"] <= args.max_outlier_fraction
    )


def save_checkpoint(result: dict, path: Path) -> None:
    """Replace old PASS results before launching work, including crash-prone subprocesses."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def write_result(result: dict, path: Path | None) -> None:
    print(json.dumps(result, indent=2, sort_keys=True), flush=True)
    if path:
        save_checkpoint(result, path)


def renderer_command(args: argparse.Namespace, implementation: str) -> list[str]:
    if args.kind == "metal":
        source = args.root / ("generated/cornell-box.metal" if implementation == "structural"
                              else "shaders/cornell-box-native.metal")
        command = [str(args.renderer), str(source), str(args.root / "generated/program-schema.txt"),
                   "--implementation", implementation]
    else:
        source = args.root / ("shaders" if implementation == "structural" else "shaders-legacy")
        command = [str(args.renderer), str(source), "--backend", args.backend, "--api", implementation]
        if args.optix_include:
            command += ["--optix-include", str(args.optix_include.resolve())]
    return command


def render(args: argparse.Namespace, implementation: str, name: str, view: str,
           sphere: str, samples: int | None = None) -> Path:
    result_path = args.output_dir / f"{name}-{implementation}.ppm"
    command = renderer_command(args, implementation)
    command += ["--headless", "--output", str(result_path), "--samples", str(samples or args.samples),
                "--bounces", str(args.bounces), "--view", view, "--sphere", sphere,
                "--width", str(args.width), "--height", str(args.height), "--seed", str(args.seed),
                "--ao-radius", str(args.ao_radius), "--ao-samples", str(args.ao_samples)]
    print("Render: " + subprocess.list2cmdline(command), flush=True)
    subprocess.run(command, cwd=args.root, check=True, timeout=args.timeout)
    return result_path


def run_smoke(args: argparse.Namespace, implementation: str) -> dict:
    result = {}
    if args.interactive_smoke:
        if args.kind == "rhi" and args.backend == "optix" and sys.platform.startswith("linux"):
            raise ValueError("Linux OptiX interactive smoke is disabled after an NVIDIA/Xorg "
                             "desktop crash; run headless and benchmark checks instead.")
        command = renderer_command(args, implementation) + ["--frames", "8", "--samples", "1"]
        print("Interactive smoke: " + subprocess.list2cmdline(command), flush=True)
        subprocess.run(command, cwd=args.root, check=True, timeout=60)
        result["interactive_8_frames_passed"] = True
    if args.benchmark_smoke:
        benchmark_path = args.output_dir / f"benchmark-smoke-{implementation}.json"
        command = renderer_command(args, implementation) + [
            "--headless", "--benchmark", "--warmup", "1", "--iterations", "3",
            "--benchmark-output", str(benchmark_path), "--width", "64", "--height", "64",
            "--samples", "4", "--bounces", "8", "--seed", str(args.seed)]
        print("Benchmark smoke: " + subprocess.list2cmdline(command), flush=True)
        subprocess.run(command, cwd=args.root, check=True, timeout=60)
        benchmark = json.loads(benchmark_path.read_text(encoding="utf-8"))
        result["benchmark_metadata_and_timing_passed"] = (
            benchmark["width"] == 64 and benchmark["height"] == 64
            and benchmark["samples_per_pixel"] == 4 and benchmark["max_bounces"] == 8
            and benchmark["sample_count"] == 3
            and len(benchmark["samples"]) == 3
            and all(math.isfinite(sample) and sample > 0 for sample in benchmark["samples"]))
    return result


def run_suite(args: argparse.Namespace) -> bool:
    args.root = args.root.resolve()
    args.renderer = args.renderer.resolve()
    args.output_dir = args.output_dir.resolve()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    result = {
        "validation_schema_version": 2,
        "expected_scene": {
            "id": SCENE_ID,
            "sphere_geometry": "analytic sphere in a procedural AABB",
            "sphere_center": [0.0, 0.75, 0.0],
            "sphere_radius": 0.40,
        },
        "kind": args.kind,
        "backend": "metal" if args.kind == "metal" else args.backend,
        "settings": {key: getattr(args, key) for key in (
            "samples", "bounces", "width", "height", "seed", "ao_radius", "ao_samples")},
        "thresholds": {key: getattr(args, key) for key in (
            "max_mae", "max_error", "outlier_threshold", "max_outlier_fraction")},
        "images": {}, "parity": {}, "ablations": {}, "passed": False, "status": "running",
    }
    output_json = args.output_dir / "validation.json"
    save_checkpoint(result, output_json)
    started = time.monotonic()
    try:
        result["input_provenance"] = input_provenance(args.root, args.renderer)
        save_checkpoint(result, output_json)
        reference = "native" if args.kind == "metal" else "legacy"
        cases = [("beauty-glass", "beauty", "glass"), ("beauty-diffuse", "beauty", "diffuse"),
                 ("beauty-none", "beauty", "none"), ("direct-glass", "direct", "glass"),
                 ("ao-glass", "ao", "glass")]
        paths = {}
        for name, view, sphere in cases:
            for implementation in ("structural", reference):
                path = render(args, implementation, name, view, sphere)
                paths[name, implementation] = path
                result["images"][path.name] = image_stats(path)
            metrics = compare_images(paths[name, "structural"], paths[name, reference], args.outlier_threshold)
            metrics["passed"] = parity_passes(metrics, args)
            result["parity"][name] = metrics
        for alternate in ("beauty-diffuse", "beauty-none", "direct-glass", "ao-glass"):
            metrics = compare_images(paths["beauty-glass", "structural"], paths[alternate, "structural"])
            # Each control must actually change the image, not merely accept the CLI option.
            metrics["passed"] = metrics["mae_byte"] > 0.25
            result["ablations"][alternate] = metrics
        ao_stats = result["images"][paths["ao-glass", "structural"].name]
        result["ao_is_grayscale"] = ao_stats["grayscale"]
        if args.repeat:
            repeated = render(args, "structural", "beauty-repeat", "beauty", "glass")
            metrics = compare_images(paths["beauty-glass", "structural"], repeated)
            metrics["passed"] = metrics["maximum_byte"] == 0
            result["repeat"] = metrics
        if args.convergence:
            # Evidence in display-space: each higher-sample estimate uses the same seeded sequence.
            convergence_paths = {}
            for samples in (16, 64, 256, 1024):
                convergence_paths[samples] = render(args, "structural", f"convergence-{samples}", "beauty", "glass", samples)
            result["convergence"] = {
                str(samples): compare_images(convergence_paths[samples], convergence_paths[1024])
                for samples in (16, 64, 256)
            }
            result["convergence_improves"] = (
                result["convergence"]["256"]["rmse_byte"] < result["convergence"]["64"]["rmse_byte"]
                < result["convergence"]["16"]["rmse_byte"])
        result["headless_passed"] = (
            all(stats["valid_image"] for stats in result["images"].values())
            and all(metrics["passed"] for metrics in result["parity"].values())
            and all(metrics["passed"] for metrics in result["ablations"].values())
            and result["ao_is_grayscale"]
            and result.get("repeat", {"passed": True})["passed"]
            and result.get("convergence_improves", True)
        )
        save_checkpoint(result, output_json)
        if args.interactive_smoke or args.benchmark_smoke:
            result["smoke"] = {
                implementation: run_smoke(args, implementation)
                for implementation in ("structural", reference)
            }
        result["passed"] = (
            result["headless_passed"]
            and all(all(checks.values()) for checks in result.get("smoke", {}).values())
        )
        result["status"] = "complete"
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        result["error"] = str(error)
        result["status"] = "error"
    result["validation_elapsed_seconds"] = time.monotonic() - started
    write_result(result, output_json)
    return result["passed"]


def add_tolerances(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--max-mae", type=float, default=1.0, help="Maximum mean absolute RGB byte error")
    parser.add_argument("--max-error", type=int, default=32, help="Maximum error in any channel")
    parser.add_argument("--outlier-threshold", type=int, default=8, help="Channel error above this counts as an outlier")
    parser.add_argument("--max-outlier-fraction", type=float, default=0.01)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    inspect = commands.add_parser("inspect", help="Reject black/constant/invalid output images")
    inspect.add_argument("image", type=Path)
    inspect.add_argument("--json", type=Path)
    compare = commands.add_parser("compare", help="Compare existing images with explicit tolerances")
    compare.add_argument("actual", type=Path)
    compare.add_argument("reference", type=Path)
    compare.add_argument("--json", type=Path)
    add_tolerances(compare)
    suite = commands.add_parser("suite", help="Render parity, material, lighting, and AO cases")
    suite.add_argument("--renderer", type=Path, required=True)
    suite.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    suite.add_argument("--kind", choices=("rhi", "metal"), default="rhi")
    suite.add_argument("--backend", choices=("vulkan", "d3d12", "optix"), default="vulkan")
    suite.add_argument("--optix-include", type=Path, help="Directory containing the OptiX device headers")
    suite.add_argument("--output-dir", type=Path, required=True)
    suite.add_argument("--width", type=int, default=192)
    suite.add_argument("--height", type=int, default=192)
    suite.add_argument("--samples", type=int, default=64)
    suite.add_argument("--bounces", type=int, default=8)
    suite.add_argument("--seed", type=int, default=17)
    suite.add_argument("--ao-radius", type=float, default=0.75)
    suite.add_argument("--ao-samples", type=int, default=8)
    suite.add_argument("--timeout", type=int, default=300, help="Seconds allowed per renderer invocation")
    suite.add_argument("--repeat", action="store_true", help="Also assert seeded repeatability")
    suite.add_argument("--convergence", action="store_true", help="Also check 16/64/256 samples against a 1024-sample reference")
    suite.add_argument("--interactive-smoke", action="store_true", help="Open each implementation for eight frames (needs a desktop)")
    suite.add_argument("--benchmark-smoke", action="store_true", help="Check a short GPU timestamp run and its metadata")
    add_tolerances(suite)
    args = parser.parse_args()
    try:
        if args.command == "suite":
            return 0 if run_suite(args) else 1
        if args.command == "inspect":
            result = image_stats(args.image)
            write_result(result, args.json)
            return 0 if result["valid_image"] else 1
        result = compare_images(args.actual, args.reference, args.outlier_threshold)
        result["passed"] = parity_passes(result, args)
        write_result(result, args.json)
        return 0 if result["passed"] else 1
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
