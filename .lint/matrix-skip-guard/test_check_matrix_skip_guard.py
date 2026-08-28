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
strip_comment = check_matrix_skip_guard.strip_comment
guards_against_skip = check_matrix_skip_guard.guards_against_skip


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


class CommentTest(OffendersTest):
    """A comment mentioning the guard must never stand in for the guard."""

    def test_guard_named_only_in_a_trailing_comment_is_reported(self):
        self.write(workflow("always()  # needs.clusters-info.result is handled downstream"))
        self.assertEqual(len(offenders()), 1)

    def test_guard_named_only_in_a_folded_comment_line_is_reported(self):
        self.write(
            workflow(
                "always() &&\n"
                "            # unlike needs.clusters-info.result, this is prose\n"
                "            github.event_name == 'schedule'"
            )
        )
        self.assertEqual(len(offenders()), 1)

    def test_real_guard_with_a_trailing_comment_is_accepted(self):
        self.write(
            workflow("always() && needs.clusters-info.result != 'skipped'  # triage skips the suite")
        )
        self.assertEqual(offenders(), [])

    def test_hash_inside_quotes_is_not_a_comment(self):
        self.assertEqual(
            strip_comment("contains(labels, '# needs.clusters-info.result') && always()"),
            "contains(labels, '# needs.clusters-info.result') && always()",
        )

    def test_hash_without_leading_whitespace_is_not_a_comment(self):
        self.assertEqual(strip_comment("needs.x.result != 'a#b'"), "needs.x.result != 'a#b'")


class BareReferenceTest(OffendersTest):
    """Mentioning the producer is not guarding on it.

    `needs.<job>.result` is a non-empty string for every outcome, `skipped`
    included, so a bare reference is true in exactly the case it is meant to
    exclude. Only a comparison can be false for a skipped producer.
    """

    def test_bare_result_reference_is_reported(self):
        self.write(workflow("always() && needs.clusters-info.result"))
        self.assertEqual(len(offenders()), 1)

    def test_bare_reference_inside_a_larger_condition_is_reported(self):
        self.write(
            workflow("always() && (needs.clusters-info.result || github.event_name == 'schedule')")
        )
        self.assertEqual(len(offenders()), 1)

    def test_equality_against_success_is_accepted(self):
        self.write(workflow("always() && needs.clusters-info.result == 'success'"))
        self.assertEqual(offenders(), [])

    def test_double_quoted_comparison_is_accepted(self):
        self.write(workflow('always() && needs.clusters-info.result != "skipped"'))
        self.assertEqual(offenders(), [])

    def test_whitespace_around_the_operator_is_tolerated(self):
        self.write(workflow("always() && needs.clusters-info.result   !=   'skipped'"))
        self.assertEqual(offenders(), [])


class FalseGuardTest(OffendersTest):
    """Comparing the result is not the same as excluding `skipped`.

    A comparison only guards when it is FALSE for a skipped producer. Half of
    them are not: `!= 'failure'` and `== 'skipped'` read like guards and leave
    the job scheduled on exactly the run they were meant to protect.
    """

    def test_not_equal_failure_is_reported(self):
        self.write(workflow("always() && needs.clusters-info.result != 'failure'"))
        self.assertEqual(len(offenders()), 1)

    def test_not_equal_success_is_reported(self):
        self.write(workflow("always() && needs.clusters-info.result != 'success'"))
        self.assertEqual(len(offenders()), 1)

    def test_equal_skipped_is_reported(self):
        self.write(workflow("always() && needs.clusters-info.result == 'skipped'"))
        self.assertEqual(len(offenders()), 1)

    def test_equal_failure_is_accepted(self):
        """False for a skipped producer, so cleanup is not scheduled."""
        self.write(workflow("always() && needs.clusters-info.result == 'failure'"))
        self.assertEqual(offenders(), [])

    def test_a_real_guard_beside_a_false_one_is_accepted(self):
        self.write(
            workflow(
                "always() && needs.clusters-info.result != 'skipped' "
                "&& needs.clusters-info.result != 'failure'"
            )
        )
        self.assertEqual(offenders(), [])

    def test_the_truth_table_directly(self):
        cases = {
            ("!=", "skipped"): True,
            ("!=", "failure"): False,
            ("!=", "success"): False,
            ("==", "skipped"): False,
            ("==", "success"): True,
            ("==", "failure"): True,
        }
        for (op, value), expected in cases.items():
            with self.subTest(op=op, value=value):
                self.assertEqual(guards_against_skip(op, value), expected)


if __name__ == "__main__":
    unittest.main()
