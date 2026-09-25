#!/usr/bin/env python3
"""Unit tests for check-action-filter-coverage.py."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "check_action_filter_coverage",
    Path(__file__).parent / "check-action-filter-coverage.py",
)
mod = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(mod)


class CheckFileTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        (self.root / ".github" / "actions" / "alpha").mkdir(parents=True)
        (self.root / ".github" / "actions" / "beta").mkdir(parents=True)
        (self.root / ".github" / "workflows").mkdir(parents=True)
        self._orig = mod.ACTIONS
        mod.ACTIONS = self.root / ".github" / "actions"
        self.addCleanup(self._restore)

    def _restore(self) -> None:
        mod.ACTIONS = self._orig
        self._tmp.cleanup()

    def write(self, body: str) -> Path:
        path = self.root / ".github" / "workflows" / "w.yml"
        path.write_text(body)
        return path

    def test_filtered_action_is_accepted(self) -> None:
        path = self.write(
            "on:\n"
            "    pull_request:\n"
            "        paths:\n"
            "            - .github/actions/alpha/**\n"
            "jobs:\n"
            "    a:\n"
            "        steps:\n"
            "            - uses: ./.github/actions/alpha\n"
        )
        self.assertEqual(mod.check_file(path), [])

    def test_unfiltered_action_is_reported(self) -> None:
        path = self.write(
            "on:\n"
            "    pull_request:\n"
            "        paths:\n"
            "            - .github/actions/alpha/**\n"
            "jobs:\n"
            "    a:\n"
            "        steps:\n"
            "            - uses: ./.github/actions/beta\n"
        )
        problems = mod.check_file(path)
        self.assertEqual(len(problems), 1)
        self.assertIn("beta", problems[0])

    def test_workflow_without_any_filter_is_not_reported(self) -> None:
        path = self.write(
            "on:\n"
            "    workflow_dispatch:\n"
            "jobs:\n"
            "    a:\n"
            "        steps:\n"
            "            - uses: ./.github/actions/beta\n"
        )
        self.assertEqual(mod.check_file(path), [])

    def test_remote_action_is_ignored(self) -> None:
        path = self.write(
            "on:\n"
            "    pull_request:\n"
            "        paths:\n"
            "            - .github/actions/alpha/**\n"
            "jobs:\n"
            "    a:\n"
            "        steps:\n"
            "            - uses: camunda/other/.github/actions/beta@main\n"
        )
        self.assertEqual(mod.check_file(path), [])

    def test_unknown_action_directory_is_ignored(self) -> None:
        path = self.write(
            "on:\n"
            "    pull_request:\n"
            "        paths:\n"
            "            - .github/actions/alpha/**\n"
            "jobs:\n"
            "    a:\n"
            "        steps:\n"
            "            - uses: ./.github/actions/does-not-exist\n"
        )
        self.assertEqual(mod.check_file(path), [])

    def test_escape_comment_suppresses_the_report(self) -> None:
        path = self.write(
            "on:\n"
            "    pull_request:\n"
            "        paths:\n"
            "            - .github/actions/alpha/**\n"
            "jobs:\n"
            "    a:\n"
            "        steps:\n"
            "            - uses: ./.github/actions/beta # lint: unfiltered-action\n"
        )
        self.assertEqual(mod.check_file(path), [])

    def test_negated_filter_does_not_count_as_filtering(self) -> None:
        path = self.write(
            "on:\n"
            "    pull_request:\n"
            "        paths:\n"
            "            - '!.github/actions/beta/**'\n"
            "jobs:\n"
            "    a:\n"
            "        steps:\n"
            "            - uses: ./.github/actions/beta\n"
        )
        problems = mod.check_file(path)
        self.assertEqual(len(problems), 1)
        self.assertIn("beta", problems[0])

    def test_shared_plumbing_is_exempt(self) -> None:
        (self.root / ".github" / "actions" / "internal-triage-skip").mkdir()
        path = self.write(
            "on:\n"
            "    pull_request:\n"
            "        paths:\n"
            "            - .github/actions/alpha/**\n"
            "jobs:\n"
            "    a:\n"
            "        steps:\n"
            "            - uses: ./.github/actions/internal-triage-skip\n"
        )
        self.assertEqual(mod.check_file(path), [])

    def test_deployment_action_is_not_exempt(self) -> None:
        (self.root / ".github" / "actions" / "kubernetes-eck-operator").mkdir()
        path = self.write(
            "on:\n"
            "    pull_request:\n"
            "        paths:\n"
            "            - .github/actions/alpha/**\n"
            "jobs:\n"
            "    a:\n"
            "        steps:\n"
            "            - uses: ./.github/actions/kubernetes-eck-operator\n"
        )
        problems = mod.check_file(path)
        self.assertEqual(len(problems), 1)
        self.assertIn("kubernetes-eck-operator", problems[0])

    def test_transitive_dependency_must_be_filtered(self) -> None:
        (self.root / ".github" / "actions" / "alpha" / "action.yml").write_text(
            "runs:\n"
            "    using: composite\n"
            "    steps:\n"
            "        - uses: ./.github/actions/beta\n"
        )
        path = self.write(
            "on:\n"
            "    pull_request:\n"
            "        paths:\n"
            "            - .github/actions/alpha/**\n"
            "jobs:\n"
            "    a:\n"
            "        steps:\n"
            "            - uses: ./.github/actions/alpha\n"
        )
        problems = mod.check_file(path)
        self.assertEqual(len(problems), 1)
        self.assertIn("beta", problems[0])

    def test_transitive_dependency_that_is_filtered_passes(self) -> None:
        (self.root / ".github" / "actions" / "alpha" / "action.yml").write_text(
            "runs:\n"
            "    using: composite\n"
            "    steps:\n"
            "        - uses: ./.github/actions/beta\n"
        )
        path = self.write(
            "on:\n"
            "    pull_request:\n"
            "        paths:\n"
            "            - .github/actions/alpha/**\n"
            "            - .github/actions/beta/**\n"
            "jobs:\n"
            "    a:\n"
            "        steps:\n"
            "            - uses: ./.github/actions/alpha\n"
        )
        self.assertEqual(mod.check_file(path), [])

    def test_step_input_named_paths_is_not_a_filter(self) -> None:
        path = self.write(
            "on:\n"
            "    workflow_dispatch:\n"
            "jobs:\n"
            "    a:\n"
            "        steps:\n"
            "            - uses: ./.github/actions/beta\n"
            "            - uses: some/reporter@v1\n"
            "              with:\n"
            "                  paths: /tmp/testreports/**/*.xml\n"
        )
        self.assertEqual(mod.check_file(path), [])

    def test_paths_ignore_only_is_not_a_positive_filter(self) -> None:
        path = self.write(
            "on:\n"
            "    pull_request:\n"
            "        paths-ignore:\n"
            "            - docs/**\n"
            "jobs:\n"
            "    a:\n"
            "        steps:\n"
            "            - uses: ./.github/actions/beta\n"
        )
        self.assertEqual(mod.check_file(path), [])

    def test_paths_under_a_non_filter_event_is_ignored(self) -> None:
        path = self.write(
            "on:\n"
            "    workflow_call:\n"
            "        paths:\n"
            "            - .github/actions/alpha/**\n"
            "jobs:\n"
            "    a:\n"
            "        steps:\n"
            "            - uses: ./.github/actions/beta\n"
        )
        self.assertEqual(mod.check_file(path), [])


if __name__ == "__main__":
    unittest.main()
