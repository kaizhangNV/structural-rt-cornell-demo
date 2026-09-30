"""Do not let the historical report relabel the new path-tracer workload."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location(
    "historical_perf_report", Path(__file__).resolve().parents[1] / "perf/report.py")
report = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(report)


class HistoricalReportTests(unittest.TestCase):
    def test_procedural_workload_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "runtime.json"
            path.write_text(json.dumps({
                "schema": report.SCHEMA, "kind": "runtime",
                "scene": "cornell-procedural-sphere-v2",
            }), encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "path-tracer result"):
                report.load_results(Path(directory))

    def test_historical_result_is_still_readable(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "runtime.json"
            path.write_text(json.dumps({
                "schema": report.SCHEMA, "kind": "runtime", "samples": [1.0],
            }), encoding="utf-8")
            results = report.load_results(Path(directory))
            self.assertEqual(len(results), 1)
            self.assertEqual(results[0]["samples"], [1.0])


if __name__ == "__main__":
    unittest.main()
