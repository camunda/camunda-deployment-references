#!/usr/bin/env python3
"""
Unit tests for check-cleanup-coverage.py.

Run with:
    python3 -m unittest discover -s .lint/cleanup-coverage
"""

import contextlib
import importlib.util
import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

MODULE_PATH = Path(__file__).with_name("check-cleanup-coverage.py")

_spec = importlib.util.spec_from_file_location("check_cleanup_coverage", MODULE_PATH)
check_cleanup_coverage = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_cleanup_coverage)

scenario_names = check_cleanup_coverage.scenario_names
read_workflow = check_cleanup_coverage.read_workflow
templated_prefixes = check_cleanup_coverage.templated_prefixes
reclaimed_prefixes = check_cleanup_coverage.reclaimed_prefixes

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

STATIC_CLEANUP = """---
name: Cleanup
env:
    S3_BACKEND_BUCKET_PREFIX: azure/kubernetes/aks-single-region/
"""

SINGLE_SCENARIO_MATRIX = """---
matrix:
    scenario:
        - name: aks-single-region
          auth_provider: keycloak-operator
"""

TWO_JOB_WORKFLOW = """---
name: Tests
jobs:
    first:
        strategy:
            matrix:
                scenario:
                    - name: aks-single-region
                    - name: aks-single-region-rdbms
        steps:
            - run: |
                  echo "S3_BACKEND_BUCKET_PREFIX=azure/kubernetes/${{ matrix.scenario.name }}/" | tee -a "$GITHUB_OUTPUT"

    second:
        strategy:
            matrix:
                scenario:
                    - name: aks-single-region
                    - name: aks-dual-region
        steps:
            - run: echo second
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

    def test_reads_every_block_not_just_the_first(self):
        """One block per job: reading only the first under-reports the file."""
        path = self.write("tests.yml", TWO_JOB_WORKFLOW)
        self.assertEqual(
            scenario_names(path),
            ["aks-single-region", "aks-single-region-rdbms", "aks-dual-region"],
        )

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


class ReclaimedPrefixesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)
        self.matrix = self.root / "test_matrix.yml"

    def write(self, name, content):
        path = self.root / name
        path.write_text(content)
        return path

    def test_fixed_prefix_cleanup_reclaims_its_tree(self):
        """A cleanup pinned to a literal prefix reclaims exactly that tree."""
        path = self.write("cleanup.yml", STATIC_CLEANUP)
        self.assertEqual(
            reclaimed_prefixes(path), {"azure/kubernetes/aks-single-region/"}
        )

    def test_fixed_cleanup_covers_a_single_scenario_workflow(self):
        self.matrix.write_text(SINGLE_SCENARIO_MATRIX)
        tests = self.write("tests.yml", TESTS_WORKFLOW.format(matrix=self.matrix))
        cleanup = self.write("cleanup.yml", STATIC_CLEANUP)
        self.assertEqual(templated_prefixes(tests) - reclaimed_prefixes(cleanup), set())

    def test_fixed_cleanup_still_misses_an_added_scenario(self):
        """Widening coverage must not blunt the #2978 detection."""
        self.matrix.write_text(TEST_MATRIX)
        tests = self.write("tests.yml", TESTS_WORKFLOW.format(matrix=self.matrix))
        cleanup = self.write("cleanup.yml", STATIC_CLEANUP)
        self.assertEqual(
            templated_prefixes(tests) - reclaimed_prefixes(cleanup),
            {"azure/kubernetes/aks-single-region-rdbms/"},
        )


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


class MainTest(unittest.TestCase):
    """`main` over a synthetic .github/workflows tree."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)
        self.workflows = self.root / "workflows"
        self.workflows.mkdir()
        self.matrix = self.root / "test_matrix.yml"
        self.matrix.write_text(TEST_MATRIX)

    def write(self, name, content):
        path = self.workflows / name
        path.write_text(content)
        return path

    def run_main(self):
        with mock.patch.object(check_cleanup_coverage, "WORKFLOWS", self.workflows):
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                return check_cleanup_coverage.main(), output.getvalue()

    def test_reports_an_uncovered_prefix(self):
        self.write("azure_tests.yml", TESTS_WORKFLOW.format(matrix=self.matrix))
        self.write("azure_daily_cleanup.yml", STATIC_CLEANUP)
        code, output = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("azure/kubernetes/aks-single-region-rdbms/", output)

    def test_covered_tree_passes(self):
        self.write("azure_tests.yml", TESTS_WORKFLOW.format(matrix=self.matrix))
        self.write("azure_daily_cleanup.yml", DERIVED_CLEANUP.format(matrix=self.matrix))
        code, output = self.run_main()
        self.assertEqual(code, 0)
        self.assertIn("2 scenario-templated state prefixes", output)

    def test_scans_a_workflow_named_off_convention(self):
        """A writer is anything that is not a cleanup, whatever it is called.

        Keying discovery off a `_tests` / `_test` suffix would let an
        off-convention name write unreclaimed state in silence — the very
        failure mode this check exists to catch.
        """
        self.write("azure_smoke_check.yml", TESTS_WORKFLOW.format(matrix=self.matrix))
        self.write("azure_daily_cleanup.yml", STATIC_CLEANUP)
        code, output = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("azure_smoke_check.yml", output)


if __name__ == "__main__":
    unittest.main()
