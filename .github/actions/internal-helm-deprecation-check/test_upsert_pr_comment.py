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


def raising_urlopen(status, body=None, headers=None):
    """Return a urlopen stub that fails the way GitHub does for `status`."""
    if body is None:
        body = b'{"message":"Resource not accessible by integration"}'

    def urlopen(req, *args, **kwargs):
        raise urllib.error.HTTPError(
            req.full_url,
            status,
            "boom",
            headers or {},
            io.BytesIO(body),
        )

    return urlopen


class ClassifyHttpErrorTest(unittest.TestCase):
    """A missing permission must be distinguishable from a transient failure."""

    def call(self, status, body=None, headers=None):
        with unittest.mock.patch.object(upsert, "_token", lambda: "token"), (
            unittest.mock.patch.object(
                upsert.urllib.request,
                "urlopen",
                raising_urlopen(status, body, headers),
            )
        ):
            upsert.gh_api("/repos/o/r/issues/1/comments", method="POST", body={})

    def assert_retryable(self, status, body=None, headers=None, why=""):
        with self.assertRaises(RuntimeError) as ctx:
            self.call(status, body, headers)
        self.assertNotIsInstance(ctx.exception, upsert.MissingPermissionError, why)

    def test_403_permission_denied_raises_missing_permission(self):
        with self.assertRaises(upsert.MissingPermissionError):
            self.call(403)

    def test_403_primary_rate_limit_stays_retryable(self):
        self.assert_retryable(
            403,
            body=b'{"message":"API rate limit exceeded for installation."}',
            headers={"x-ratelimit-remaining": "0"},
            why="a primary rate limit is transient, it must keep its retries",
        )

    def test_403_rate_limit_header_is_matched_case_insensitively(self):
        """GitHub sends `X-RateLimit-Remaining`; header names are case-insensitive.

        The body here carries the permission message on purpose: only the header
        can tell the two apart, so a case-sensitive lookup would misclassify it.
        """
        self.assert_retryable(
            403,
            body=b'{"message":"Resource not accessible by integration"}',
            headers={"X-RateLimit-Remaining": "0"},
            why="the conventional header casing must still be recognised",
        )

    def test_403_retry_after_header_is_matched_case_insensitively(self):
        self.assert_retryable(
            403,
            body=b'{"message":"Resource not accessible by integration"}',
            headers={"RETRY-AFTER": "60"},
            why="the conventional header casing must still be recognised",
        )

    def test_403_secondary_rate_limit_stays_retryable(self):
        self.assert_retryable(
            403,
            body=b'{"message":"You have exceeded a secondary rate limit."}',
            headers={"Retry-After": "60"},
            why="a secondary rate limit is transient, it must keep its retries",
        )

    def test_403_abuse_detection_stays_retryable(self):
        self.assert_retryable(
            403,
            body=b'{"message":"You have triggered an abuse detection mechanism."}',
            why="abuse detection is transient, it must keep its retries",
        )

    def test_403_of_unknown_shape_stays_retryable(self):
        self.assert_retryable(
            403,
            body=b'{"message":"Something else entirely."}',
            why="only the documented permission message may skip the retries",
        )

    def test_other_statuses_stay_retryable(self):
        for status in (404, 422, 500, 502):
            with self.subTest(status=status):
                self.assert_retryable(
                    status,
                    why=f"HTTP {status} is transient and must keep its retries",
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

    def test_error_annotation_covers_every_cause_of_a_denied_token(self):
        """The token is an input and forks are read-only, so do not blame only the job."""
        _, _, out = self.run_main(upsert.MissingPermissionError("403"))
        for cause in ("permissions:", "github-token", "fork"):
            self.assertIn(cause, out.lower(), f"guidance should mention {cause}")

    def test_transient_failure_still_retries_and_warns(self):
        exit_code, attempts, out = self.run_main(RuntimeError("500 boom"))
        self.assertEqual(exit_code, 0)
        self.assertEqual(attempts, upsert.MAX_ATTEMPTS)
        self.assertIn("::warning::", out)
        self.assertNotIn("::error::", out)


if __name__ == "__main__":
    unittest.main()
