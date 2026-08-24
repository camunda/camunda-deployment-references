#!/usr/bin/env python3
"""
Unit tests for check-path-filters.py.

Run with:
    python3 -m unittest discover -s .lint/path-filters
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

MODULE_PATH = Path(__file__).with_name("check-path-filters.py")

_spec = importlib.util.spec_from_file_location("check_path_filters", MODULE_PATH)
check_path_filters = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_path_filters)

check_file = check_path_filters.check_file
glob_to_regex = check_path_filters.glob_to_regex
is_alive = check_path_filters.is_alive
read_filters = check_path_filters.read_filters


def write_workflow(directory: Path, source: str, name: str = "workflow.yml") -> Path:
    path = directory / name
    path.write_text(source)
    return path


def patterns(source: str) -> list[str]:
    with tempfile.TemporaryDirectory() as directory:
        return [entry.pattern for entry in read_filters(write_workflow(Path(directory), source))]


def problems(source: str, files: list[str]) -> list[str]:
    with tempfile.TemporaryDirectory() as directory:
        return check_file(write_workflow(Path(directory), source), files)


PULL_REQUEST = """---
name: Tests

on:
    pull_request:
        paths:
{items}

jobs:
    test:
        runs-on: ubuntu-latest
"""


def pull_request(*items: str) -> str:
    return PULL_REQUEST.format(items="\n".join(f"            - {item}" for item in items))


class ReadFiltersTest(unittest.TestCase):
    def test_reads_the_patterns_of_a_pull_request_block(self):
        self.assertEqual(
            patterns(pull_request("generic/compute/debian/**", ".tool-versions")),
            ["generic/compute/debian/**", ".tool-versions"],
        )

    def test_a_paths_input_of_a_step_is_not_a_filter(self):
        source = """---
on:
    pull_request:
        paths:
            - generic/compute/debian/**

jobs:
    test:
        runs-on: ubuntu-latest
        steps:
            - uses: actions/upload-artifact@v4
              with:
                  paths:
                      - some/artifact/directory
"""
        self.assertEqual(patterns(source), ["generic/compute/debian/**"])

    def test_reads_paths_ignore_and_the_push_event(self):
        source = """---
on:
    push:
        paths:
            - aws/**
        paths-ignore:
            - docs/**
"""
        self.assertEqual(patterns(source), ["aws/**", "docs/**"])

    def test_a_negated_pattern_keeps_its_bang_and_loses_its_quotes(self):
        self.assertEqual(patterns(pull_request("'!aws/x/test/golden/**'")), ["!aws/x/test/golden/**"])

    def test_a_trailing_comment_is_not_part_of_the_pattern(self):
        self.assertEqual(
            patterns(pull_request("aws/x/** # keep synced with labeler.yml", "'!aws/y/**' # goldens")),
            ["aws/x/**", "!aws/y/**"],
        )

    def test_a_commented_out_filter_is_not_read(self):
        source = """---
on:
    pull_request:
        paths:
            - aws/x/**
            # - .tools-versions
"""
        self.assertEqual(patterns(source), ["aws/x/**"])

    def test_reads_a_flow_sequence(self):
        source = """---
on:
    pull_request:
        paths: [aws/x/**, .tool-versions]
"""
        self.assertEqual(patterns(source), ["aws/x/**", ".tool-versions"])

    def test_the_second_event_block_is_read_too(self):
        source = """---
on:
    push:
        paths:
            - aws/x/**
    pull_request:
        paths:
            - aws/y/**
"""
        self.assertEqual(patterns(source), ["aws/x/**", "aws/y/**"])


class GlobTest(unittest.TestCase):
    def test_a_single_star_does_not_cross_a_separator(self):
        matcher = glob_to_regex("aws/*/main.tf")
        self.assertTrue(matcher.match("aws/modules/main.tf"))
        self.assertFalse(matcher.match("aws/modules/eks/main.tf"))

    def test_a_double_star_crosses_separators(self):
        matcher = glob_to_regex("aws/**/main.tf")
        self.assertTrue(matcher.match("aws/modules/eks/main.tf"))

    def test_a_double_star_segment_also_matches_zero_directories(self):
        """`a/**/go.mod` matches `a/go.mod` on GitHub, so the file may move up a level."""
        matcher = glob_to_regex("aws/modules/.test/**/go.mod")
        self.assertTrue(matcher.match("aws/modules/.test/src/go.mod"))
        self.assertTrue(matcher.match("aws/modules/.test/go.mod"))

    def test_a_leading_double_star_segment_matches_a_file_at_the_root(self):
        matcher = glob_to_regex("**/README.md")
        self.assertTrue(matcher.match("aws/modules/README.md"))
        self.assertTrue(matcher.match("README.md"))

    def test_a_double_star_inside_a_segment_still_crosses_separators(self):
        matcher = glob_to_regex("aws/modules/**.tf")
        self.assertTrue(matcher.match("aws/modules/eks/main.tf"))

    def test_a_question_mark_matches_exactly_one_character(self):
        matcher = glob_to_regex("aws/x?.tf")
        self.assertTrue(matcher.match("aws/x1.tf"))
        self.assertFalse(matcher.match("aws/x12.tf"))

    def test_a_dot_is_literal(self):
        self.assertFalse(glob_to_regex(".tool-versions").match("xtool-versions"))

    def test_a_pattern_is_anchored_at_both_ends(self):
        matcher = glob_to_regex("aws/x/**")
        self.assertFalse(matcher.match("other/aws/x/main.tf"))


class IsAliveTest(unittest.TestCase):
    def test_a_wildcard_free_pattern_accepts_a_tracked_directory(self):
        self.assertTrue(is_alive("generic/compute/debian", ["generic/compute/debian/procedure/install.sh"]))

    def test_a_wildcard_free_pattern_accepts_an_exact_file(self):
        self.assertTrue(is_alive(".tool-versions", [".tool-versions"]))

    def test_a_prefix_that_is_not_a_directory_boundary_does_not_count(self):
        self.assertFalse(is_alive("generic/deb", ["generic/debian/install.sh"]))

    def test_a_negation_is_judged_on_what_it_excludes(self):
        self.assertTrue(is_alive("!aws/x/test/golden/**", ["aws/x/test/golden/plan.tf"]))
        self.assertFalse(is_alive("!aws/x/test/golden/**", ["aws/x/terraform/test/golden/plan.tf"]))


class CheckFileTest(unittest.TestCase):
    def test_regression_a_filter_left_behind_by_a_directory_move(self):
        """The #3220 shape: procedures moved, the filter did not, the suite stopped running."""
        found = problems(
            pull_request("generic/debian/**"),
            ["generic/compute/debian/procedure/camunda-install.sh"],
        )
        self.assertEqual(len(found), 1)
        self.assertIn("generic/debian/**", found[0])
        self.assertIn("workflow.yml:7", found[0])
        self.assertIn("on.pull_request.paths", found[0])

    def test_a_live_filter_is_not_reported(self):
        found = problems(
            pull_request("generic/compute/debian/**"),
            ["generic/compute/debian/procedure/camunda-install.sh"],
        )
        self.assertEqual(found, [])

    def test_a_golden_exclusion_that_excludes_nothing_is_reported(self):
        """A stale negation is the inverse waste: golden-only diffs launch the full suite."""
        found = problems(
            pull_request("'!aws/x/test/golden/**'"),
            ["aws/x/terraform/cluster/test/golden/plan.tf"],
        )
        self.assertEqual(len(found), 1)
        self.assertIn("!aws/x/test/golden/**", found[0])

    def test_the_escape_hatch_silences_a_path_that_does_not_exist_yet(self):
        found = problems(
            pull_request("aws/not-yet/** # lint: future-path"),
            ["aws/x/main.tf"],
        )
        self.assertEqual(found, [])

    def test_every_dead_pattern_is_reported_not_just_the_first(self):
        found = problems(
            pull_request("aws/gone/**", "aws/x/**", ".tools-versions"),
            ["aws/x/main.tf", ".tool-versions"],
        )
        self.assertEqual(len(found), 2)


class MainTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.workflows = Path(self.tmp.name)

    def run_main(self, files):
        with mock.patch.object(check_path_filters, "WORKFLOWS", self.workflows):
            with mock.patch.object(check_path_filters, "tracked_files", lambda: files):
                stderr = io.StringIO()
                with contextlib.redirect_stderr(stderr):
                    return check_path_filters.main(), stderr.getvalue()

    def test_passes_when_every_filter_matches(self):
        write_workflow(self.workflows, pull_request("aws/x/**"), "tests.yml")
        status, output = self.run_main(["aws/x/main.tf"])
        self.assertEqual(status, 0)
        self.assertEqual(output, "")

    def test_fails_and_counts_the_dead_filters(self):
        write_workflow(self.workflows, pull_request("aws/gone/**"), "tests.yml")
        write_workflow(self.workflows, pull_request("aws/also-gone/**"), "cleanup.yml")
        status, output = self.run_main(["aws/x/main.tf"])
        self.assertEqual(status, 1)
        self.assertIn("2 path filter(s) matching nothing.", output)


if __name__ == "__main__":
    unittest.main()
