#!/usr/bin/env python3
"""Collect one platform's matched Cornell compile and runtime benchmarks.

Build the renderer/compile tools first. This driver uses the same compiler process for both
compile cases, and runtime-suite.py alternates the two implementations across fresh processes.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
STAGES = (
    ("PrimaryClosestHit", "closesthit"), ("ShadowClosestHit", "closesthit"),
    ("PrimarySphereClosestHit", "closesthit"), ("ShadowSphereClosestHit", "closesthit"),
    ("PrimarySphereIntersection", "intersection"), ("ShadowSphereIntersection", "intersection"),
    ("PrimaryMiss", "miss"), ("ShadowMiss", "miss"),
)


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def probe(command):
    try:
        result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=20)
        return {"command": command, "returncode": result.returncode, "output": result.stdout.strip()}
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"command": command, "error": str(error)}


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--platform", choices=("linux", "windows", "macos"), required=True)
    parser.add_argument("--renderer", type=Path, required=True)
    parser.add_argument("--compile-tool", type=Path)
    parser.add_argument("--metal-compile-tool", type=Path)
    parser.add_argument("--compiler-label", required=True)
    parser.add_argument("--compiler-commit", required=True)
    parser.add_argument("--sample-commit", required=True)
    parser.add_argument("--compiler-build", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--optix-include", type=Path)
    parser.add_argument("--ptx-arch", default="compute_120")
    parser.add_argument("--compile-warmup", type=int, default=5)
    parser.add_argument("--compile-iterations", type=int, default=50)
    parser.add_argument("--rounds", type=int, default=6)
    parser.add_argument("--warmup", type=int, default=10)
    parser.add_argument("--iterations", type=int, default=50)
    parser.add_argument("--width", type=int, default=512)
    parser.add_argument("--height", type=int, default=512)
    parser.add_argument("--samples", type=int, default=8)
    parser.add_argument("--bounces", type=int, default=8)
    parser.add_argument("--seed", type=int, default=17)
    parser.add_argument("--views", nargs="+", choices=("beauty", "ao", "direct"), default=["beauty", "ao"])
    args = parser.parse_args()
    for name in ("compile_iterations", "rounds", "iterations", "width", "height", "samples", "bounces"):
        if getattr(args, name) <= 0:
            parser.error(f"--{name.replace('_', '-')} must be positive")
    if args.compile_warmup < 0 or args.warmup < 0:
        parser.error("warmup counts cannot be negative")
    if args.platform == "macos" and not args.metal_compile_tool:
        parser.error("macOS needs --metal-compile-tool")
    if args.platform != "macos" and not args.compile_tool:
        parser.error("Linux/Windows need --compile-tool")
    if args.platform == "linux" and not args.optix_include:
        parser.error("Linux needs --optix-include")
    return args


def main():
    args = parse_args()
    root = args.root.resolve()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    manifest_path = output / "collection.json"
    if manifest_path.exists():
        raise RuntimeError("Use a fresh output directory; refusing to mix benchmark collections")
    host = platform.platform() + "; " + platform.processor()
    sources = [root / name for name in ("scene.h", "render-settings.h", "rhi-main.cpp", "metal-main.cpp",
               "generated/cornell-box.metal", "generated/program-schema.txt", "shaders/cornell-box-native.metal")]
    for directory in ("common", "shaders", "shaders-legacy"):
        sources.extend(path for path in (root / directory).iterdir()
                       if path.suffix == ".slang")
    sources.extend(root / name for name in (
        "perf/collect.py", "perf/runtime-suite.py", "perf/slang-compile-benchmark.cpp",
        "perf/metal-compile-benchmark.cpp", "tools/validate-pathtracer.py"))
    tool_paths = [args.renderer, args.compile_tool, args.metal_compile_tool]
    result = {
        "schema": "cornell-benchmark-collection-v1", "status": "running", "passed": False,
        "started_utc": utc_now(), "run_id": args.run_id, "platform": args.platform,
        "host": host, "compiler": args.compiler_label, "compiler_commit": args.compiler_commit,
        "compiler_build": args.compiler_build, "sample_commit": args.sample_commit,
        "settings": {key: value for key, value in vars(args).items() if not isinstance(value, Path)},
        "source_sha256": {str(path.relative_to(root)): digest(path) for path in sorted(set(sources))},
        "tool_sha256": {str(path.resolve()): digest(path) for path in tool_paths if path},
        "commands": [], "compile_results": [], "runtime_suites": [], "environment": [],
    }
    if shutil.which("nvidia-smi"):
        result["environment"].append(probe(["nvidia-smi", "--query-gpu=name,driver_version,pstate,utilization.gpu,power.draw,temperature.gpu", "--format=csv"]))
    if args.platform == "linux":
        result["environment"].append(probe(["lscpu"]))
    elif args.platform == "macos":
        result["environment"].extend([probe(["sw_vers"]), probe(["sysctl", "-n", "machdep.cpu.brand_string"]),
                                      probe(["xcrun", "clang", "--version"])])
    else:
        result["environment"].append(probe(["powershell.exe", "-NoProfile", "-Command",
            "Get-CimInstance Win32_Processor | Select-Object -ExpandProperty Name"]))

    def save():
        manifest_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")

    def run(label, command):
        command = list(map(str, command))
        log = output / f"{label}.log"
        record = {"label": label, "argv": command, "started_utc": utc_now(), "log": log.name}
        result["commands"].append(record)
        save()
        print(f"[{args.platform}] {label}", flush=True)
        with log.open("w", encoding="utf-8") as stream:
            completed = subprocess.run(command, cwd=root, stdout=stream, stderr=subprocess.STDOUT, timeout=1200)
        record.update(returncode=completed.returncode, finished_utc=utc_now())
        save()
        if completed.returncode:
            raise RuntimeError(f"{label} exited {completed.returncode}; see {log}")

    save()
    try:
        if args.platform == "macos":
            path = output / "compile-metal-downstream.json"
            run("compile-metal-downstream", [args.metal_compile_tool.resolve(), "--output", path,
                "--host-label", host, "--input-provenance", args.compiler_label,
                "--warmup", args.compile_warmup, "--iterations", args.compile_iterations,
                "--case", "structural-generated", root / "generated/cornell-box.metal",
                "--case", "native-handwritten", root / "shaders/cornell-box-native.metal"])
            result["compile_results"].append(path.name)
        else:
            targets = ["spirv", "metal", "ptx"] if args.platform == "linux" else ["dxil"]
            for target in targets:
                path = output / f"compile-{target}.json"
                command = [args.compile_tool.resolve(), "--target", target, "--output", path,
                           "--compiler-label", args.compiler_label, "--host-label", host,
                           "--warmup", args.compile_warmup, "--iterations", args.compile_iterations,
                           "--case", "structural", root / "shaders", "rt_pipeline", "experimental", "ProgramSchema",
                           "--entry", "RayGeneration", "raygeneration"]
                if target != "metal":
                    command.extend(["--case", "legacy", root / "shaders-legacy", "rt_pipeline", "standard", "-"])
                    for name, stage in STAGES:
                        command.extend(["--legacy-entry", name, stage])
                if target == "ptx":
                    command.extend(["--optix-include", args.optix_include.resolve(), "--ptx-arch", args.ptx_arch])
                run(f"compile-{target}", command)
                result["compile_results"].append(path.name)
                save()
        backends = {"linux": ["vulkan", "optix"], "windows": ["d3d12"], "macos": ["metal"]}[args.platform]
        for backend in backends:
            directory = output / f"runtime-{backend}"
            command = [sys.executable, root / "perf/runtime-suite.py", "--root", root,
                       "--renderer", args.renderer.resolve(), "--kind", "metal" if backend == "metal" else "rhi",
                       "--backend", backend, "--output-dir", directory,
                       "--rounds", args.rounds, "--warmup", args.warmup, "--iterations", args.iterations,
                       "--width", args.width, "--height", args.height, "--samples", args.samples,
                       "--bounces", args.bounces, "--seed", args.seed, "--ao-radius", "0.75", "--ao-samples", "8",
                       "--views", *args.views]
            if backend == "optix":
                command.extend(["--optix-include", args.optix_include.resolve()])
            run(f"runtime-{backend}", command)
            result["runtime_suites"].append(directory.name)
            save()
        result.update(status="complete", passed=True)
    except Exception as error:
        result.update(status="error", error=str(error))
        raise
    finally:
        result["finished_utc"] = utc_now()
        save()
    print(f"PASS: {manifest_path}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"benchmark collection failed: {error}", file=sys.stderr)
        sys.exit(1)
