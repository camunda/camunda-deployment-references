#!/usr/bin/env python3
"""
Unit tests for check-reporter-coverage.py.

Run with:
    python3 -m unittest discover -s .lint/reporter-coverage
"""

import contextlib
import importlib.util
import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

MODULE_PATH = Path(__file__).with_name("check-reporter-coverage.py")

_spec = importlib.util.spec_from_file_location("check_reporter_coverage", MODULE_PATH)
check_reporter_coverage = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_reporter_coverage)

workflow_name = check_reporter_coverage.workflow_name
watched_workflows = check_reporter_coverage.watched_workflows
observed_suites = check_reporter_coverage.observed_suites

REPORTER = """---
name: Internal - Global - CI Events to Google Sheet

on:
    workflow_run:
        types:
            - completed
        workflows:
            - Tests - Integration - Alpha
            # a comment inside the list must not end it
            - Tests - Integration - Beta
    workflow_dispatch:

permissions:
    contents: read

jobs:
    report:
        runs-on: ubuntu-latest
        steps:
            - name: Tests - Integration - Not A Watched Entry
              run: echo hi
"""

SUITE = """---
name: {name}

on:
    pull_request:

jobs:
    build:
        runs-on: ubuntu-latest
        steps:
            - name: some step
              run: echo hi
"""


class WorkflowNameTest(unittest.TestCase):
    def test_reads_the_top_level_name(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "w.yml"
            p.write_text(SUITE.format(name="Tests - Integration - Alpha"))
            self.assertEqual(workflow_name(p), "Tests - Integration - Alpha")

    def test_a_step_name_is_not_the_workflow_name(self):
        """`- name:` is indented; only column zero is the workflow's own name."""
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "w.yml"
            p.write_text("---\njobs:\n    b:\n        steps:\n            - name: nope\n")
            self.assertIsNone(workflow_name(p))

    def test_trailing_whitespace_is_stripped(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "w.yml"
            p.write_text("---\nname: Tests - Integration - Alpha   \n")
            self.assertEqual(workflow_name(p), "Tests - Integration - Alpha")


class WatchedWorkflowsTest(unittest.TestCase):
    def _reporter(self, tmp, body=REPORTER):
        p = Path(tmp) / "internal_global_ci_events_reporter.yml"
        p.write_text(body)
        return p

    def test_reads_every_entry(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(
                watched_workflows(self._reporter(tmp)),
                ["Tests - Integration - Alpha", "Tests - Integration - Beta"],
            )

    def test_stops_at_the_end_of_the_list(self):
        """A step's `- name:` further down the file must not be read as an entry."""
        with tempfile.TemporaryDirectory() as tmp:
            names = watched_workflows(self._reporter(tmp))
            # The expected string carries the `name: ` prefix on purpose:
            # LIST_ENTRY captures everything after the dash, so a step line read
            # by mistake arrives as `name: Tests - ...`, not as a bare title.
            # Drop the guard that ends the list and this is the value that
            # appears.
            self.assertNotIn("name: Tests - Integration - Not A Watched Entry", names)
            self.assertEqual(len(names), 2)

    def test_a_missing_list_fails_loudly(self):
        """Silently returning nothing would mark every suite unwatched."""
        with tempfile.TemporaryDirectory() as tmp:
            p = self._reporter(tmp, "---\nname: no workflow_run here\non:\n    push:\n")
            with self.assertRaises(SystemExit):
                watched_workflows(p)


class ObservedSuitesTest(unittest.TestCase):
    def test_only_integration_suites_are_collected(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            (d / "a.yml").write_text(SUITE.format(name="Tests - Integration - Alpha"))
            (d / "b.yml").write_text(SUITE.format(name="Internal - Global - Lint"))
            (d / "c.yml").write_text(SUITE.format(name="Tests - Daily Cleanup - Alpha"))
            self.assertEqual(
                sorted(observed_suites(d)), ["Tests - Integration - Alpha"]
            )


class MainTest(unittest.TestCase):
    """The end-to-end verdict, which is what the hook actually reports."""

    def _run(self, suite_names, watched_body=REPORTER):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            reporter = d / "internal_global_ci_events_reporter.yml"
            reporter.write_text(watched_body)
            for i, name in enumerate(suite_names):
                (d / f"suite{i}.yml").write_text(SUITE.format(name=name))
            out = io.StringIO()
            with mock.patch.object(check_reporter_coverage, "WORKFLOWS", d), \
                 mock.patch.object(check_reporter_coverage, "REPORTER", reporter), \
                 contextlib.redirect_stdout(out):
                rc = check_reporter_coverage.main()
            return rc, out.getvalue()

    def test_passes_when_every_suite_is_watched(self):
        rc, out = self._run(
            ["Tests - Integration - Alpha", "Tests - Integration - Beta"]
        )
        self.assertEqual(rc, 0, out)
        self.assertIn("all watched", out)

    def test_fails_and_names_the_unwatched_suite(self):
        """The regression this check exists for: a suite added, nothing observing it."""
        rc, out = self._run(
            [
                "Tests - Integration - Alpha",
                "Tests - Integration - Beta",
                "Tests - Integration - Gamma",
            ]
        )
        self.assertEqual(rc, 1)
        self.assertIn("Tests - Integration - Gamma", out)
        self.assertNotIn("Tests - Integration - Alpha'", out)

    def test_a_watched_name_with_no_workflow_is_reported_but_not_fatal(self):
        """The reporter legitimately watches suites that live only on a stable branch."""
        rc, out = self._run(["Tests - Integration - Alpha"])
        self.assertEqual(rc, 0, out)
        self.assertIn("Tests - Integration - Beta", out)


if __name__ == "__main__":
    unittest.main()
