"""Offline tests for get_acm_versions.py: `python3 -m unittest discover -s .github/scripts -p 'test_*.py'`."""

import contextlib
import io
import os
import sys
import tempfile
import unittest
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import get_acm_versions as acm  # noqa: E402

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "acm_versions")
NOW = datetime(2026, 11, 8, tzinfo=timezone.utc)


def fixture(name):
    with open(os.path.join(FIXTURES, name)) as f:
        return f.read()


EXPECTED = fixture("expected.txt")


def fake_get(docs="ok", github="ok"):
    """Serves the saved fixtures. `docs`/`github` are "ok", "down" or "garbage"."""

    def get(url):
        mode = docs if url == acm.DOCS_URL else github
        if mode == "down":
            raise acm.SourceUnreachable(f"{url}: HTTP Error 403: Forbidden")
        if mode == "garbage":
            return "<html><body>Access denied</body></html>" if url == acm.DOCS_URL else "{}"
        if url == acm.DOCS_URL:
            return fixture("docs.html")
        if "/branches" in url:
            return fixture("branches.json")
        if "sha=release-2.17" in url:
            return fixture("commits-release-2.17.json")
        if "sha=release-2.18" in url:
            return fixture("commits-release-2.18.json")
        raise AssertionError(f"unexpected request {url}")

    return get


class GetAcmVersionsTest(unittest.TestCase):
    def run_main(self, **modes):
        with tempfile.TemporaryDirectory() as tmp:
            output = os.path.join(tmp, "docs", "openshift_acm_versions.txt")
            with contextlib.redirect_stderr(io.StringIO()):
                with contextlib.redirect_stdout(io.StringIO()):
                    code = acm.main(["--output", output], get=fake_get(**modes), now=NOW)
            content = None
            if os.path.exists(output):
                with open(output) as f:
                    content = f.read()
        return code, content

    def test_docs_source_reproduces_the_published_file(self):
        code, content = self.run_main()
        self.assertEqual(code, acm.EXIT_OK)
        self.assertEqual(content, EXPECTED)

    def test_upstream_fallback_reproduces_the_published_file(self):
        # release-2.18 is a placeholder branch (no commit since April), release-5.x,
        # release-9.9 and release-1.0.0 are not 2.x: none may leak into the list.
        code, content = self.run_main(docs="down")
        self.assertEqual(code, acm.EXIT_OK)
        self.assertEqual(content, EXPECTED)

    def test_upstream_fallback_when_docs_page_has_no_selector(self):
        code, content = self.run_main(docs="garbage")
        self.assertEqual(code, acm.EXIT_OK)
        self.assertEqual(content, EXPECTED)

    def test_active_newest_branch_is_kept(self):
        recent = datetime(2026, 10, 30, tzinfo=timezone.utc)
        names = ["release-2.17", "release-2.18", "release-1.0.0", "main"]
        versions = acm.released_branch_versions(names, lambda b: recent, NOW)
        self.assertEqual(versions, ["2.18", "2.17"])

    def test_versions_sort_numerically(self):
        recent = datetime(2026, 10, 30, tzinfo=timezone.utc)
        names = ["release-2.9", "release-2.10", "release-2.2"]
        self.assertEqual(acm.released_branch_versions(names, lambda b: recent, NOW), ["2.10", "2.9", "2.2"])

    def test_every_source_unreachable_exits_3_and_writes_nothing(self):
        code, content = self.run_main(docs="down", github="down")
        self.assertEqual(code, acm.EXIT_UNREACHABLE)
        self.assertIsNone(content)

    def test_parsed_but_empty_exits_1_and_writes_nothing(self):
        code, content = self.run_main(docs="garbage", github="garbage")
        self.assertEqual(code, acm.EXIT_NO_VERSIONS)
        self.assertIsNone(content)

    def test_one_source_unreachable_one_unparsable_exits_1(self):
        # A structure change must not be mistaken for an outage.
        code, content = self.run_main(docs="down", github="garbage")
        self.assertEqual(code, acm.EXIT_NO_VERSIONS)
        self.assertIsNone(content)

    def test_exit_codes_are_distinct(self):
        self.assertEqual(len({acm.EXIT_OK, acm.EXIT_NO_VERSIONS, acm.EXIT_UNREACHABLE, 2}), 4)


if __name__ == "__main__":
    unittest.main()
