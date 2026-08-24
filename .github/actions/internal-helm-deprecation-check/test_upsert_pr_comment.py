#!/usr/bin/env python3
"""
Unit tests for upsert-pr-comment.py.

Run with:
    python3 -m unittest discover -s .github/actions/internal-helm-deprecation-check
"""

import contextlib
import importlib.util
import io
import tempfile
import unittest
import unittest.mock
import urllib.error
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("upsert-pr-comment.py")

_spec = importlib.util.spec_from_file_location("upsert_pr_comment", MODULE_PATH)
upsert = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(upsert)


def raising_urlopen(status):
    """Return a urlopen stub that fails the way GitHub does for `status`."""

    def urlopen(req, *args, **kwargs):
        raise urllib.error.HTTPError(
            req.full_url,
            status,
            "boom",
            {},
            io.BytesIO(b'{"message":"Resource not accessible by integration"}'),
        )

    return urlopen


class ClassifyHttpErrorTest(unittest.TestCase):
    """A missing permission must be distinguishable from a transient failure."""

    def call_with_status(self, status):
        with unittest.mock.patch.object(upsert, "_token", lambda: "token"), (
            unittest.mock.patch.object(
                upsert.urllib.request, "urlopen", raising_urlopen(status)
            )
        ):
            upsert.gh_api("/repos/o/r/issues/1/comments", method="POST", body={})

    def test_403_raises_missing_permission(self):
        with self.assertRaises(upsert.MissingPermissionError):
            self.call_with_status(403)

    def test_other_statuses_stay_retryable(self):
        for status in (404, 422, 500, 502):
            with self.subTest(status=status):
                with self.assertRaises(RuntimeError) as ctx:
                    self.call_with_status(status)
                self.assertNotIsInstance(
                    ctx.exception,
                    upsert.MissingPermissionError,
                    f"HTTP {status} is transient and must keep its retries",
                )


class MainFailureModesTest(unittest.TestCase):
    """The comment is advisory: main() always exits 0, but must say why."""

    def setUp(self):
        findings = Path(tempfile.mkdtemp()) / "findings.md"
        findings.write_text("### finding\n")
        self.argv = [
            "upsert-pr-comment.py",
            "--pr-number", "1",
            "--repo", "o/r",
            "--workflow", "W",
            "--job", "J",
            "--release-name", "camunda",
            "--namespace", "ns",
            "--kube-context", "",
            "--section-key", "",
            "--run-url", "http://example.invalid/run",
            "--findings-file", str(findings),
        ]

    def run_main(self, failure):
        """Run main() with every upsert attempt raising `failure`."""
        attempts = []

        def attempt_upsert(**kwargs):
            attempts.append(1)
            raise failure

        stdout = io.StringIO()
        with unittest.mock.patch.object(upsert, "attempt_upsert", attempt_upsert), (
            unittest.mock.patch.object(upsert.time, "sleep", lambda _: None)
        ), unittest.mock.patch.object(upsert.sys, "argv", self.argv):
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(
                io.StringIO()
            ):
                exit_code = upsert.main()
        return exit_code, len(attempts), stdout.getvalue()

    def test_missing_permission_fails_fast_with_error_annotation(self):
        exit_code, attempts, out = self.run_main(
            upsert.MissingPermissionError("403 Resource not accessible by integration")
        )
        self.assertEqual(exit_code, 0, "the comment is advisory, it must not fail the job")
        self.assertEqual(attempts, 1, "a missing permission is deterministic")
        self.assertIn("::error::", out)
        self.assertIn("pull-requests: write", out)

    def test_transient_failure_still_retries_and_warns(self):
        exit_code, attempts, out = self.run_main(RuntimeError("500 boom"))
        self.assertEqual(exit_code, 0)
        self.assertEqual(attempts, upsert.MAX_ATTEMPTS)
        self.assertIn("::warning::", out)
        self.assertNotIn("::error::", out)


if __name__ == "__main__":
    unittest.main()
