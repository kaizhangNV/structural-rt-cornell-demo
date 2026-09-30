"""CPU-only tests: the paired runtime runner must never launch a real renderer."""

import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


TOOL = Path(__file__).resolve().parents[1] / "perf" / "runtime-suite.py"
SPEC = importlib.util.spec_from_file_location("runtime_suite", TOOL)
runtime = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runtime)


def options(root: Path, *extra):
    return runtime.parse_args([
        "--renderer", str(root / "renderer"), "--root", str(root), "--kind", "rhi",
        "--backend", "vulkan", "--output-dir", str(root / "results"), *extra])


def benchmark(args, implementation="structural", view="beauty"):
    return {
        "schema": "slang-ray-tracing-perf-v1", "kind": "runtime", "unit": "ms",
        "backend": args.backend.upper(), "device": "Test GPU", "implementation": implementation,
        "metric": runtime.METAL_METRIC if args.kind == "metal" else runtime.RHI_METRIC,
        "width": args.width, "height": args.height, "samples_per_pixel": args.samples,
        "max_bounces": args.bounces, "seed": args.seed, "view_mode": runtime.VIEW_MODES[view],
        "sphere_mode": 0, "scene": runtime.validator.SCENE_ID,
        "sphere_geometry": "custom-intersection-aabb", "ao_samples": args.ao_samples,
        "ao_radius": args.ao_radius, "exposure": 1.0, "warmup_count": args.warmup,
        "sample_count": args.iterations, "samples": [2.0] * args.iterations,
    }


def validation(args, provenance):
    return {
        "validation_schema_version": 2, "status": "complete", "passed": True,
        "headless_passed": True, "kind": args.kind, "backend": args.backend,
        "settings": {"width": 192, "height": 192, "samples": 64,
                     "bounces": args.bounces, "seed": args.seed,
                     "ao_radius": args.ao_radius, "ao_samples": args.ao_samples},
        "input_provenance": provenance, "repeat": {"passed": True},
        "parity": {name: {"passed": True} for name in (
            "beauty-glass", "beauty-diffuse", "beauty-none", "direct-glass", "ao-glass")},
    }


class RuntimeValidationTest(unittest.TestCase):
    def test_defaults_and_input_constraints(self):
        args = options(Path("/tmp/example"))
        self.assertEqual((args.rounds, args.warmup, args.iterations), (6, 10, 50))
        self.assertEqual(args.views, ["beauty", "ao"])
        self.assertEqual(args.seed, 17)
        for extra in (("--kind", "metal"), ("--warmup", "0"), ("--iterations", "0"),
                      ("--ao-radius", "nan"), ("--views", "ao", "ao"), ("--width", "4097")):
            with self.subTest(extra=extra), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    options(Path("/tmp/example"), *extra)

    def test_summary_documents_nearest_rank_p95(self):
        result = runtime.summarize(list(range(1, 21)))
        self.assertEqual(result, {"count": 20, "median": 10.5, "p95": 19, "min": 1, "max": 20})
        self.assertEqual(runtime.summarize([-2.0, 0.0])["median"], -1.0)
        for samples in ([], [float("inf")]):
            with self.assertRaises(ValueError):
                runtime.summarize(samples)

    def test_metadata_and_sample_validation(self):
        args = options(Path("/tmp/example"), "--iterations", "3")
        valid = benchmark(args)
        self.assertEqual(runtime.check_benchmark(valid, args, "structural", "beauty"), [2.0] * 3)
        invalid = (("samples", [2, 0, 2]), ("samples", [True, 2, 2]),
                   ("samples", [float("nan"), 2, 2]), ("samples", [2]),
                   ("backend", "Metal"), ("implementation", "legacy"),
                   ("width", 192), ("warmup_count", 0), ("ao_radius", 0.5),
                   ("scene", "old-scene"), ("view_mode", 1))
        for key, value in invalid:
            with self.subTest(key=key, value=value):
                result = copy.deepcopy(valid)
                result[key] = value
                with self.assertRaises(ValueError):
                    runtime.check_benchmark(result, args, "structural", "beauty")

    def test_gate_requires_backend_repeat_and_matching_provenance(self):
        args = options(Path("/tmp/example"))
        provenance = {"renderer_sha256": "renderer1", "source_sha256": {"common/test.slang": "v1"}}
        result = validation(args, provenance)
        runtime.check_validation(result, args, provenance)
        for key, value in (("backend", "metal"), ("passed", False), ("repeat", {}),
                           ("input_provenance", {}), ("parity", {})):
            invalid = copy.deepcopy(result)
            invalid[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                runtime.check_validation(invalid, args, provenance)

    def test_commands_are_headless_for_rhi_and_metal(self):
        root = Path("/tmp/example")
        args = options(root, "--backend", "optix", "--optix-include", str(root / "optix"))
        command = runtime.benchmark_command(args, "legacy", "ao", root / "raw.json")
        self.assertIn("--headless", command)
        self.assertIn("--benchmark", command)
        self.assertIn(str(root / "shaders-legacy"), command)
        self.assertIn("--optix-include", command)
        self.assertNotIn("--interactive-smoke", runtime.validation_command(args))
        self.assertNotIn("--benchmark-smoke", runtime.validation_command(args))
        args = options(root, "--kind", "metal", "--backend", "metal")
        command = runtime.benchmark_command(args, "native", "beauty", root / "raw.json")
        self.assertIn(str(root / "shaders" / "cornell-box-native.metal"), command)
        self.assertIn("--headless", command)
        self.assertNotIn("--backend", runtime.validation_command(args))


class RuntimeSuiteTest(unittest.TestCase):
    def mocked_run(self, args, commands, fail_gate=False, change_source=False):
        def run(command, root, log, timeout):
            commands.append(command)
            log.write_text("mock process output\n", encoding="utf-8")
            checkpoint = json.loads((args.output_dir / "runtime-suite.json").read_text())
            self.assertFalse(checkpoint["passed"])
            self.assertEqual(checkpoint["status"], "running")
            if "suite" in command:
                gate_dir = args.output_dir / "validation"
                gate_dir.mkdir()
                result = validation(args, runtime.validator.input_provenance(args.root, args.renderer))
                result["passed"] = not fail_gate
                (gate_dir / "validation.json").write_text(json.dumps(result), encoding="utf-8")
                return
            if "--output" in command:
                image = Path(command[command.index("--output") + 1])
                image.write_bytes(f"P6\n{args.width} {args.height}\n255\n".encode()
                                  + b"\x00\x00\x00\xff\xff\xff" * (args.width * args.height // 2))
                return
            implementation_flag = "--implementation" if args.kind == "metal" else "--api"
            implementation = command[command.index(implementation_flag) + 1]
            view = command[command.index("--view") + 1]
            result = benchmark(args, implementation, view)
            result["samples"] = ([3.0] if implementation == "structural" else [2.0]) * args.iterations
            Path(command[command.index("--benchmark-output") + 1]).write_text(json.dumps(result), encoding="utf-8")
            if change_source:
                (args.root / "scene.h").write_text("modified while running", encoding="utf-8")
        return run

    def test_full_suite_alternates_pairs_and_aggregates(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "renderer").write_bytes(b"fake renderer")
            args = options(root, "--rounds", "2", "--iterations", "3")
            commands = []
            with patch.object(runtime, "run_logged", side_effect=self.mocked_run(args, commands)), \
                    patch.object(runtime, "git_metadata", return_value={"revision": "abc", "dirty": False}), \
                    contextlib.redirect_stdout(io.StringIO()):
                self.assertTrue(runtime.run_suite(args))
            result = json.loads((args.output_dir / "runtime-suite.json").read_text())
            self.assertEqual(len(commands), 13)  # One full gate, four matched images, eight timed runs.
            self.assertEqual([run["implementation"] for run in result["runs"]],
                             ["structural", "legacy", "structural", "legacy",
                              "legacy", "structural", "legacy", "structural"])
            self.assertEqual(result["cases"]["beauty/structural"]["pooled_gpu_ms"]["count"], 6)
            self.assertEqual(result["paired_round_deltas"]["beauty"]["delta_percent"]["median"], 50.0)
            self.assertEqual(result["paired_round_deltas"]["ao"]["delta_ms"]["median"], 1.0)
            self.assertEqual(result["device"], "Test GPU")
            self.assertTrue(result["correctness_gate"]["passed"])
            self.assertTrue(result["correctness_gate"]["timed_configuration"]["passed"])
            self.assertTrue(result["finished_utc"])
            self.assertTrue(result["passed"])
            self.assertTrue(all("--headless" in command for command in commands[1:]))
            with self.assertRaisesRegex(ValueError, "must be empty"):
                runtime.run_suite(args)

    def test_failed_gate_blocks_all_timing_runs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "renderer").write_bytes(b"fake renderer")
            args = options(root)
            commands = []
            with patch.object(runtime, "run_logged", side_effect=self.mocked_run(args, commands, fail_gate=True)), \
                    patch.object(runtime, "git_metadata", return_value={}), \
                    contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                self.assertFalse(runtime.run_suite(args))
            self.assertEqual(len(commands), 1)
            result = json.loads((args.output_dir / "runtime-suite.json").read_text())
            self.assertEqual(result["status"], "error")
            self.assertFalse(result["passed"])
            self.assertEqual(result["runs"], [])

    def test_metal_uses_native_reference(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "renderer").write_bytes(b"fake renderer")
            args = options(root, "--kind", "metal", "--backend", "metal", "--rounds", "2",
                           "--iterations", "1", "--views", "ao")
            commands = []
            with patch.object(runtime, "run_logged", side_effect=self.mocked_run(args, commands)), \
                    patch.object(runtime, "git_metadata", return_value={}), \
                    contextlib.redirect_stdout(io.StringIO()):
                self.assertTrue(runtime.run_suite(args))
            result = json.loads((args.output_dir / "runtime-suite.json").read_text())
            self.assertEqual(result["reference"], "native")
            self.assertEqual([run["implementation"] for run in result["runs"]],
                             ["structural", "native", "native", "structural"])
            self.assertEqual(result["method"]["gpu_metric"], runtime.METAL_METRIC)

    def test_invalid_measured_configuration_image_blocks_timing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "renderer").write_bytes(b"fake renderer")
            args = options(root)
            commands = []
            image = {"valid_image": False, "width": 512, "height": 512, "grayscale": True}
            with patch.object(runtime, "run_logged", side_effect=self.mocked_run(args, commands)), \
                    patch.object(runtime.validator, "image_stats", return_value=image), \
                    patch.object(runtime, "git_metadata", return_value={}), \
                    contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                self.assertFalse(runtime.run_suite(args))
            self.assertFalse(any("--benchmark" in command for command in commands))
            result = json.loads((args.output_dir / "runtime-suite.json").read_text())
            self.assertFalse(result["passed"])
            self.assertIn("invalid measured-configuration", result["error"])

    def test_source_mutation_invalidates_run(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "renderer").write_bytes(b"fake renderer")
            (root / "scene.h").write_text("original", encoding="utf-8")
            args = options(root, "--rounds", "1", "--iterations", "1", "--views", "beauty")
            commands = []
            with patch.object(runtime, "run_logged", side_effect=self.mocked_run(args, commands, change_source=True)), \
                    patch.object(runtime, "git_metadata", return_value={}), \
                    contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                self.assertFalse(runtime.run_suite(args))
            result = json.loads((args.output_dir / "runtime-suite.json").read_text())
            self.assertFalse(result["passed"])
            self.assertIn("inputs changed", result["error"])


if __name__ == "__main__":
    unittest.main()
