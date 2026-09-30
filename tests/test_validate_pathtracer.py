"""CPU-only checks for image parsing, input provenance, and validation safety."""

import argparse
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


TOOL_PATH = Path(__file__).resolve().parents[1] / "tools" / "validate-pathtracer.py"
SPEC = importlib.util.spec_from_file_location("validate_pathtracer", TOOL_PATH)
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


class ValidationBookkeepingTest(unittest.TestCase):
    def test_old_pass_is_replaced_before_rendering(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "validation.json"
            output.write_text('{"passed": true}', encoding="utf-8")
            args = argparse.Namespace(
                root=root, renderer=root / "renderer", output_dir=root,
                kind="rhi", backend="vulkan", samples=64, bounces=8,
                width=192, height=192, seed=17, ao_radius=0.75, ao_samples=8,
                max_mae=1, max_error=32, outlier_threshold=8, max_outlier_fraction=0.01,
            )

            def interrupted_render(*unused):
                checkpoint = json.loads(output.read_text(encoding="utf-8"))
                self.assertFalse(checkpoint["passed"])
                self.assertEqual(checkpoint["status"], "running")
                self.assertEqual(checkpoint["validation_schema_version"], 2)
                self.assertEqual(checkpoint["expected_scene"]["id"], validator.SCENE_ID)
                self.assertEqual(checkpoint["expected_scene"]["sphere_center"], [0.0, 0.75, 0.0])
                self.assertEqual(checkpoint["expected_scene"]["sphere_radius"], 0.40)
                raise OSError("simulated renderer failure")

            with patch.object(validator, "render", side_effect=interrupted_render):
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertFalse(validator.run_suite(args))
            result = json.loads(output.read_text(encoding="utf-8"))
            self.assertFalse(result["passed"])
            self.assertEqual(result["status"], "error")
            self.assertIn("simulated renderer failure", result["error"])

    def test_linux_optix_smoke_does_not_launch_process(self):
        args = argparse.Namespace(interactive_smoke=True, kind="rhi", backend="optix")
        with patch.object(validator.sys, "platform", "linux"):
            with patch.object(validator.subprocess, "run") as run:
                with self.assertRaisesRegex(ValueError, "interactive smoke is disabled"):
                    validator.run_smoke(args, "structural")
                run.assert_not_called()


class ImageAndProvenanceTest(unittest.TestCase):
    def test_ppm_keeps_whitespace_and_hash_valued_pixels(self):
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "image.ppm"
            pixels = b"\n\r #\t\x00"
            image.write_bytes(b"P6\n# header comment\n2 1\n255\n" + pixels)
            self.assertEqual(validator.read_ppm(image), (2, 1, pixels))
            image.write_bytes(b"P6\r\n2 1\r\n255\r\n" + pixels)
            self.assertEqual(validator.read_ppm(image), (2, 1, pixels))

    def test_ppm_rejects_truncated_raster(self):
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "image.ppm"
            image.write_bytes(b"P6\n1 1\n255\n\x00\x01")
            with self.assertRaisesRegex(ValueError, "expected 3 bytes, got 2"):
                validator.read_ppm(image)

    def test_provenance_changes_with_renderer_or_common_shaders(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            renderer = root / "renderer"
            renderer.write_bytes(b"host version 1")
            (root / "common").mkdir()
            shaders = [root / "common" / name for name in
                       ("sphere_intersection.slang", "path_tracing.slang", "scene_types.slang")]
            for shader in shaders:
                shader.write_text("shader version 1", encoding="utf-8")
            before = validator.input_provenance(root, renderer)
            renderer.write_bytes(b"host version 2")
            for shader in shaders:
                shader.write_text("shader version 2", encoding="utf-8")
            after = validator.input_provenance(root, renderer)
            self.assertNotEqual(before["renderer_sha256"], after["renderer_sha256"])
            for shader in shaders:
                key = shader.relative_to(root).as_posix()
                self.assertNotEqual(before["source_sha256"][key], after["source_sha256"][key])


if __name__ == "__main__":
    unittest.main()
