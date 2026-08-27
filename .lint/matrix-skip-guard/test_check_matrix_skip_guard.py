#!/usr/bin/env python3
"""
Unit tests for check-matrix-skip-guard.py.

Run with:
    python3 -m unittest discover -s .lint/matrix-skip-guard
"""

import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest import mock

MODULE_PATH = Path(__file__).with_name("check-matrix-skip-guard.py")

_spec = importlib.util.spec_from_file_location("check_matrix_skip_guard", MODULE_PATH)
check_matrix_skip_guard = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_matrix_skip_guard)

offenders = check_matrix_skip_guard.offenders
job_blocks = check_matrix_skip_guard.job_blocks
job_condition = check_matrix_skip_guard.job_condition


def workflow(cleanup_if: str, matrix_source: str = "needs.clusters-info.outputs.platform-matrix") -> str:
    """A workflow shaped like the repository's test suites."""
    condition = f"        if: {cleanup_if}\n" if cleanup_if else ""
    return f"""---
name: Example

on:
    pull_request:

jobs:
    triage:
        runs-on: ubuntu-latest
        steps:
            - run: echo triage

    clusters-info:
        needs:
            - triage
        if: needs.triage.outputs.should_skip == 'false'
        runs-on: ubuntu-latest
        outputs:
            platform-matrix: ${{{{ steps.matrix.outputs.platform_matrix }}}}
        steps:
            - id: matrix
              run: echo matrix

    cleanup-clusters:
        runs-on: ubuntu-latest
{condition}        needs:
            - clusters-info
        strategy:
            fail-fast: false
            matrix:
                distro: ${{{{ fromJson({matrix_source}).distro }}}}
        steps:
            - name: Clean
              if: always()
              run: echo clean
"""


class OffendersTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.workflows = Path(self.tmp.name) / "workflows"
        self.workflows.mkdir()
        patcher = mock.patch.object(check_matrix_skip_guard, "WORKFLOWS", self.workflows)
        patcher.start()
        self.addCleanup(patcher.stop)

    def write(self, content: str, name: str = "example.yml") -> None:
        (self.workflows / name).write_text(content)

    def test_bare_always_is_reported(self):
        self.write(workflow("always()"))
        found = offenders()
        self.assertEqual(len(found), 1)
        self.assertIn("cleanup-clusters", found[0])
        self.assertIn("clusters-info", found[0])

    def test_guarded_always_is_accepted(self):
        self.write(workflow("always() && needs.clusters-info.result != 'skipped'"))
        self.assertEqual(offenders(), [])

    def test_always_with_extra_conditions_still_needs_the_guard(self):
        self.write(workflow("always() && (needs.integration-tests.result == 'success')"))
        self.assertEqual(len(offenders()), 1)

    def test_always_with_extra_conditions_and_the_guard_is_accepted(self):
        self.write(
            workflow(
                "always() && needs.clusters-info.result != 'skipped' "
                "&& (needs.integration-tests.result == 'success')"
            )
        )
        self.assertEqual(offenders(), [])

    def test_no_condition_is_accepted(self):
        """Without `if:`, a skipped producer already skips the consumer."""
        self.write(workflow(""))
        self.assertEqual(offenders(), [])

    def test_condition_without_always_is_accepted(self):
        self.write(workflow("github.event_name == 'schedule'"))
        self.assertEqual(offenders(), [])

    def test_matrix_not_built_from_a_producer_is_ignored(self):
        self.write(workflow("always()", matrix_source="vars.STATIC_MATRIX"))
        self.assertEqual(offenders(), [])

    def test_every_workflow_is_inspected(self):
        self.write(workflow("always()"), name="one.yml")
        self.write(workflow("always()"), name="two.yml")
        self.assertEqual(len(offenders()), 2)


class ParserTest(unittest.TestCase):
    def test_job_blocks_finds_every_job(self):
        lines = workflow("always()").splitlines(keepends=True)
        self.assertEqual(
            [name for name, _ in job_blocks(lines)],
            ["triage", "clusters-info", "cleanup-clusters"],
        )

    def test_job_condition_ignores_step_level_if(self):
        """The cleanup step carries `if: always()`; the job here carries none."""
        lines = workflow("").splitlines(keepends=True)
        body = dict(job_blocks(lines))["cleanup-clusters"]
        self.assertIsNone(job_condition(body))

    def test_job_condition_reads_the_job_level_if(self):
        lines = workflow("always() && needs.clusters-info.result != 'skipped'").splitlines(keepends=True)
        body = dict(job_blocks(lines))["cleanup-clusters"]
        self.assertEqual(job_condition(body), "always() && needs.clusters-info.result != 'skipped'")

    def test_job_condition_joins_a_folded_value(self):
        """yamlfmt folds long conditions, and the guard can land on a later line."""
        lines = workflow(
            "always() && (needs.integration-tests.result == 'success' ||\n"
            "            needs.clusters-info.result != 'skipped')"
        ).splitlines(keepends=True)
        body = dict(job_blocks(lines))["cleanup-clusters"]
        self.assertEqual(
            job_condition(body),
            "always() && (needs.integration-tests.result == 'success' || "
            "needs.clusters-info.result != 'skipped')",
        )


class FoldedConditionTest(OffendersTest):
    def test_guard_on_a_folded_line_is_accepted(self):
        self.write(
            workflow(
                "always() && (needs.integration-tests.result == 'success' ||\n"
                "            needs.clusters-info.result != 'skipped')"
            )
        )
        self.assertEqual(offenders(), [])

    def test_folded_condition_without_the_guard_is_reported(self):
        self.write(
            workflow(
                "always() && (needs.integration-tests.result == 'success' ||\n"
                "            fromJson(github.run_attempt) >= 3)"
            )
        )
        self.assertEqual(len(offenders()), 1)


if __name__ == "__main__":
    unittest.main()
