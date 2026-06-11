#!/usr/bin/env python3
"""Print the failed/errored JUnit testcase names (comma-separated, sorted).

CI-only helper for the EC2 single-region workflow: it lets the job tolerate the one
known upstream flake (TestCamundaUpgrade on a SNAPSHOT build) while still failing for
any other test. Not part of the customer-facing reference procedure.

Usage: print-failed-tests.py [junit.xml]   (defaults to tests.xml)
On any parse error it prints nothing (callers then treat it as "not tolerable").
"""
import sys
import xml.etree.ElementTree as ET


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else "tests.xml"
    try:
        root = ET.parse(path).getroot()
    except Exception:
        return 0
    failed = {
        tc.get("name", "")
        for tc in root.iter("testcase")
        if tc.find("failure") is not None or tc.find("error") is not None
    }
    print(",".join(sorted(name for name in failed if name)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
