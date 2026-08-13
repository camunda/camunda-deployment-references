#!/usr/bin/env python3
"""
Unit tests for check-cleanup-coverage.py.

Run with:
    python3 -m unittest discover -s .lint/cleanup-coverage
"""

import importlib.util
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("check-cleanup-coverage.py")

_spec = importlib.util.spec_from_file_location("check_cleanup_coverage", MODULE_PATH)
check_cleanup_coverage = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_cleanup_coverage)

scenario_names = check_cleanup_coverage.scenario_names
read_workflow = check_cleanup_coverage.read_workflow
templated_prefixes = check_cleanup_coverage.templated_prefixes

TEST_MATRIX = """---
matrix:
    distro:
        - name: AKS
          schedule_only: false

    scenario:
        - name: aks-single-region
          auth_provider: keycloak-operator

        - name: aks-single-region-rdbms
          auth_provider: keycloak-operator

    declination:
        - name: no-domain
        - name: domain
"""

TESTS_WORKFLOW = """---
name: Tests
env:
    CI_MATRIX_FILE: {matrix}
jobs:
    prepare:
        steps:
            - run: |
                  echo "S3_BACKEND_BUCKET_PREFIX=azure/kubernetes/${{{{ matrix.scenario.name }}}}/" | tee -a "$GITHUB_OUTPUT"
"""

DERIVED_CLEANUP = """---
name: Cleanup
env:
    CI_MATRIX_FILE: {matrix}
jobs:
    cleanup:
        steps:
            - run: |
                  echo "S3_BACKEND_BUCKET_PREFIX=azure/kubernetes/${{{{ matrix.scenario.name }}}}/" | tee -a "$GITHUB_OUTPUT"
"""

INLINE_CLEANUP = """---
name: Cleanup
jobs:
    cleanup:
        strategy:
            matrix:
                scenario:
                    - name: aks-single-region
        steps:
            - run: |
                  echo "S3_BACKEND_BUCKET_PREFIX=azure/kubernetes/${{ matrix.scenario.name }}/" | tee -a "$GITHUB_OUTPUT"
"""

STATIC_WORKFLOW = """---
name: Tests
env:
    S3_BACKEND_BUCKET_PREFIX: aws/compute/ec2-single-region/ # keep it synced
"""


class ScenarioNamesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def write(self, name, content):
        path = self.root / name
        path.write_text(content)
        return path

    def test_reads_scenario_block_only(self):
        path = self.write("test_matrix.yml", TEST_MATRIX)
        self.assertEqual(
            scenario_names(path),
            ["aks-single-region", "aks-single-region-rdbms"],
        )

    def test_ignores_distro_and_declination_names(self):
        path = self.write("test_matrix.yml", TEST_MATRIX)
        names = scenario_names(path)
        self.assertNotIn("AKS", names)
        self.assertNotIn("domain", names)

    def test_reads_inline_strategy_matrix(self):
        path = self.write("cleanup.yml", INLINE_CLEANUP)
        self.assertEqual(scenario_names(path), ["aks-single-region"])

    def test_missing_block_yields_nothing(self):
        path = self.write("plain.yml", "---\nname: Nothing\n")
        self.assertEqual(scenario_names(path), [])


class TemplatedPrefixesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)
        self.matrix = self.root / "test_matrix.yml"
        self.matrix.write_text(TEST_MATRIX)

    def write(self, name, content):
        path = self.root / name
        path.write_text(content)
        return path

    def test_expands_against_matrix_file(self):
        path = self.write("tests.yml", TESTS_WORKFLOW.format(matrix=self.matrix))
        self.assertEqual(
            templated_prefixes(path),
            {
                "azure/kubernetes/aks-single-region/",
                "azure/kubernetes/aks-single-region-rdbms/",
            },
        )

    def test_expands_against_inline_matrix(self):
        path = self.write("cleanup.yml", INLINE_CLEANUP)
        self.assertEqual(
            templated_prefixes(path), {"azure/kubernetes/aks-single-region/"}
        )

    def test_static_prefix_is_out_of_scope(self):
        path = self.write("static.yml", STATIC_WORKFLOW)
        self.assertEqual(templated_prefixes(path), set())

    def test_templated_prefix_without_scenarios_is_an_error(self):
        path = self.write(
            "broken.yml",
            "---\njobs:\n    x:\n        steps:\n"
            '            - run: echo "S3_BACKEND_BUCKET_PREFIX=a/${{ matrix.scenario.name }}/"\n',
        )
        with self.assertRaises(SystemExit):
            templated_prefixes(path)

    def test_regression_hardcoded_cleanup_misses_new_scenario(self):
        """The #2978 shape: tests templated, cleanup pinned to one scenario."""
        tests = self.write("tests.yml", TESTS_WORKFLOW.format(matrix=self.matrix))
        cleanup = self.write("cleanup.yml", INLINE_CLEANUP)
        missing = templated_prefixes(tests) - templated_prefixes(cleanup)
        self.assertEqual(missing, {"azure/kubernetes/aks-single-region-rdbms/"})

    def test_derived_cleanup_covers_every_scenario(self):
        tests = self.write("tests.yml", TESTS_WORKFLOW.format(matrix=self.matrix))
        cleanup = self.write("cleanup.yml", DERIVED_CLEANUP.format(matrix=self.matrix))
        self.assertEqual(templated_prefixes(tests) - templated_prefixes(cleanup), set())


class ReadWorkflowTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def test_env_prefix_strips_trailing_comment(self):
        path = self.root / "static.yml"
        path.write_text(STATIC_WORKFLOW)
        prefixes, _ = read_workflow(path)
        self.assertEqual(prefixes, {"aws/compute/ec2-single-region/"})

    def test_unresolvable_matrix_file_is_ignored(self):
        path = self.root / "tests.yml"
        path.write_text(TESTS_WORKFLOW.format(matrix="does/not/exist.yml"))
        _, scenarios = read_workflow(path)
        self.assertEqual(scenarios, [])


if __name__ == "__main__":
    unittest.main()
