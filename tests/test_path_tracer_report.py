"""CPU-only checks for the benchmark publisher's comparison and rejection rules."""

import copy
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("path_tracer_report", ROOT / "perf/path-tracer-report.py")
report = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(report)


def collection(platform="linux"):
    settings = {"compile_iterations": 2, "compile_warmup": 1, "ptx_arch": "compute_120",
                "rounds": 2, "warmup": 1, "iterations": 2, "width": 512, "height": 512,
                "samples": 8, "bounces": 8, "seed": 17, "views": ["beauty", "ao"]}
    return {"schema": "cornell-benchmark-collection-v1", "status": "complete", "passed": True,
            "platform": platform, "settings": settings, "compiler": "test compiler",
            "compiler_commit": "a" * 40, "sample_commit": "b" * 40,
            "source_sha256": {"common/test.slang": "c" * 64},
            "tool_sha256": {"/private/runner/compiler": "d" * 64},
            "compile_results": [f"compile-{target}.json" for target in report.TARGETS[platform]],
            "runtime_suites": [f"runtime-{backend}" for backend in report.PLATFORMS[platform]],
            "commands": [{"returncode": 0}], "run_id": "test-run", "host": "test OS/CPU",
            "compiler_build": "optimized", "started_utc": "start", "finished_utc": "finish"}


def compile_result(target="spirv", native_metal=False):
    result = {"schema": "slang-ray-tracing-perf-v1", "kind": "compile", "target": target,
              "unit": "ms", "compiler": "test compiler", "sample_count": 2,
              "warmup_count": 1, "optimization": "maximal",
              "profile": {"spirv": "spirv_1_5", "dxil": "lib_6_6", "metal": "metallib_3_1",
                          "ptx": "compute_120"}[target], "cases": []}
    if native_metal:
        result.update(kind="metal_downstream_compile", input_provenance="test compiler",
                      cases=[{"name": name, "samples": [4, 5]}
                             for name in ("structural-generated", "native-handwritten")])
        return result
    for name in (["structural"] if target == "metal" else ["structural", "legacy"]):
        result["cases"].append({"name": name, "entry_point_count": 9,
                                "entry_points": sorted(report.STAGES), "code_size_bytes": 123,
                                "total_wall_ms": {"samples": [4, 5]},
                                "slang_ms": {"samples": [4, 5] if target == "metal" else [3, 4]},
                                "downstream_ms": {"samples": [0, 0] if target == "metal" else [1, 1]}})
    return result


class CompileEvidenceTests(unittest.TestCase):
    def test_complete_paired_stage_set(self):
        data = compile_result()
        self.assertIs(report.validate_compile(data, collection()), data)

    def test_zero_msl_downstream_is_expected(self):
        report.validate_compile(compile_result("metal"), collection())

    def test_native_metal_pair(self):
        report.validate_compile(compile_result("metal", True), collection("macos"))

    def test_missing_comparison_rejected(self):
        data = compile_result()
        data["cases"].pop()
        with self.assertRaisesRegex(ValueError, "comparison cases"):
            report.validate_compile(data, collection())

    def test_missing_stage_rejected(self):
        data = compile_result()
        data["cases"][0]["entry_points"].pop()
        with self.assertRaisesRegex(ValueError, "nine stages"):
            report.validate_compile(data, collection())

    def test_zero_downstream_rejected(self):
        data = compile_result()
        data["cases"][0]["downstream_ms"]["samples"][0] = 0
        with self.assertRaisesRegex(ValueError, "invalid timings"):
            report.validate_compile(data, collection())

    def test_bad_phase_sum_rejected(self):
        data = compile_result()
        data["cases"][0]["total_wall_ms"]["samples"][0] = 400
        with self.assertRaisesRegex(ValueError, "do not sum"):
            report.validate_compile(data, collection())

    def test_wrong_optimization_rejected(self):
        data = compile_result()
        data["optimization"] = "none"
        with self.assertRaisesRegex(ValueError, "optimization"):
            report.validate_compile(data, collection())


class CollectionTests(unittest.TestCase):
    def load(self, mutation=None):
        collections = {name: collection(name) for name in report.PLATFORMS}
        if mutation:
            mutation(collections)

        def read(path):
            platform = path.parent.name
            if path.name == "collection.json":
                return copy.deepcopy(collections[platform])
            target = path.stem.split("-", 1)[1]
            return compile_result(target, platform == "macos")

        with patch.object(report, "read_json", side_effect=read), \
                patch.object(report, "validate_runtime", return_value={"device": "test GPU"}):
            return report.load_collection(Path("/unused-fixture"))

    def test_matched_collection_and_redacted_tool_path(self):
        bundle = self.load()
        self.assertEqual(set(bundle["platforms"]), set(report.PLATFORMS))
        self.assertEqual(bundle["platforms"]["linux"]["tool_sha256"], {"compiler": "d" * 64})

    def test_incomplete_collection_rejected(self):
        with self.assertRaisesRegex(ValueError, "incomplete collection"):
            self.load(lambda data: data["windows"].update(status="running"))

    def test_compiler_mismatch_rejected(self):
        with self.assertRaisesRegex(ValueError, "compiler commit mismatch"):
            self.load(lambda data: data["windows"].update(compiler_commit="e" * 40))

    def test_sample_mismatch_rejected(self):
        with self.assertRaisesRegex(ValueError, "sample commit mismatch"):
            self.load(lambda data: data["macos"].update(sample_commit="f" * 40))

    def test_shader_mismatch_rejected(self):
        with self.assertRaisesRegex(ValueError, "source hash mismatch"):
            self.load(lambda data: data["windows"]["source_sha256"].update({"common/test.slang": "f" * 64}))

    def test_runtime_settings_mismatch_rejected(self):
        with self.assertRaisesRegex(ValueError, "settings mismatch"):
            self.load(lambda data: data["windows"]["settings"].update(samples=16))

    def test_missing_backend_rejected(self):
        with self.assertRaisesRegex(ValueError, "incomplete runtime backends"):
            self.load(lambda data: data["linux"]["runtime_suites"].pop())


class StatisticsTests(unittest.TestCase):
    def test_percentile_methods_explicit(self):
        self.assertEqual(report.summary(list(range(12)))["p95"], 11)
        self.assertEqual(report.summary(list(range(12)), compile_percentile=True)["p95"], 10)

    def test_paired_range_can_cross_zero_despite_pooled_speedup(self):
        suite = {"reference": "legacy", "options": {"rounds": 2}, "runs": []}
        for index, new, old in ((1, 1.0, 2.0), (2, 1.5, 1.0)):
            for name, value in (("structural", new), ("legacy", old)):
                suite["runs"].append({"round": index, "view": "beauty", "implementation": name,
                                      "samples_ms": [value, value]})
        value = report.runtime_statistics(suite, "beauty")
        self.assertLess(value["pooled_delta_percent"], 0)
        self.assertEqual(value["round_delta_percent"]["min"], -50)
        self.assertEqual(value["round_delta_percent"]["max"], 50)

    def test_nonfinite_and_nonpositive_samples_rejected(self):
        for value in (float("nan"), float("inf"), -1, 0, True):
            with self.assertRaises(ValueError):
                report.samples([value], 1, "test")

    def test_windows_source_paths_normalized(self):
        self.assertEqual(report.normalized_hashes({"common\\a.slang": "a" * 64}),
                         {"common/a.slang": "a" * 64})

    def test_result_cannot_escape_collection(self):
        for value in ("../bad.json", "/private/bad.json", "C:\\bad.json"):
            with self.assertRaises(ValueError):
                report.child_path(Path("/results"), value)


if __name__ == "__main__":
    unittest.main()
