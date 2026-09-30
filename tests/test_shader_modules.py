"""CPU-only regression checks for first-party Slang module organization."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIRECTORIES = ("common", "shaders", "shaders-legacy", "tests")
COMMON_MODULES = ("path_tracing", "sphere_intersection", "scene_types")
PREPROCESSOR_INCLUDE = re.compile(r"^[ \t]*#[ \t]*include\b", re.MULTILINE)
COMMENTS_OR_STRINGS = re.compile(
    r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\''
)


def without_comments(source):
    """Keep strings and line numbers intact while ignoring commented-out code."""
    def replace(match):
        text = match.group(0)
        if text.startswith(("//", "/*")):
            return "".join("\n" if character == "\n" else " " for character in text)
        return text

    return COMMENTS_OR_STRINGS.sub(replace, source)


def has_preprocessor_include(source):
    return PREPROCESSOR_INCLUDE.search(without_comments(source)) is not None


class ShaderModuleOrganizationTest(unittest.TestCase):
    def test_include_matcher(self):
        for source in (
            '#include "shared.slang"',
            '#include <shared.slang>',
            '\t # \tinclude\t "shared.slang"',
            '\n  # include<shared.slang>\n',
            '#include SHADER_FILE',
        ):
            with self.subTest(source=source):
                self.assertTrue(has_preprocessor_include(source))

        for source in (
            '__include hit;',
            'import scene_types;',
            '// #include "old.slang"\n__include hit;',
            '/*\n#include <old.slang>\n*/\nmodule example;',
        ):
            with self.subTest(source=source):
                self.assertFalse(has_preprocessor_include(source))

    def test_first_party_slang_has_no_preprocessor_includes_or_slangh_files(self):
        for directory in SOURCE_DIRECTORIES:
            source_root = ROOT / directory
            self.assertTrue(source_root.is_dir(), f"Missing source directory: {directory}")
            self.assertEqual(
                sorted(path.relative_to(ROOT).as_posix() for path in source_root.rglob("*.slangh")),
                [],
                f"Use .slang modules instead of .slangh files in {directory}",
            )
            for path in sorted(source_root.rglob("*.slang")):
                with self.subTest(path=path.relative_to(ROOT).as_posix()):
                    self.assertFalse(
                        has_preprocessor_include(path.read_text(encoding="utf-8")),
                        "Use import or __include instead of preprocessor #include",
                    )

    def test_common_sources_are_independent_modules(self):
        for module in COMMON_MODULES:
            path = ROOT / "common" / f"{module}.slang"
            with self.subTest(module=module):
                self.assertTrue(path.is_file(), f"Missing common module: {path}")
                source = without_comments(path.read_text(encoding="utf-8"))
                self.assertRegex(
                    source,
                    rf"\A\s*module\s+{re.escape(module)}\s*;",
                    "Common shader sources must declare real modules, not implementation fragments",
                )
                self.assertNotRegex(source, r"(?m)^\s*implementing\b")
                self.assertNotRegex(source, r"\.\./shaders(?:-legacy)?(?:/|\b)")


if __name__ == "__main__":
    unittest.main()
