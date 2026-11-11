#!/usr/bin/env python3

"""
Retrieve the OpenShift ACM versions and save them as a txt file in the docs folder
(one `<major>.<minor>` per line, newest first).

Sources, tried in order:
  1. the Red Hat documentation page (the product version selector);
  2. the `release-<major>.<minor>` branches of the upstream project
     stolostron/multiclusterhub-operator, read through the GitHub API.

The documentation page is the product's own list, so it wins when reachable. It sits
behind bot protection that blocks GitHub-hosted runners from time to time, which is
why the upstream branches exist as a fallback. They are not identical: the newest
branches can be placeholders cut before the release, so trailing branches whose tip
is older than DORMANT_DAYS are dropped (see `released_branch_versions`).

Exit codes:
  0  versions written
  1  a source answered but no versions could be parsed (the page or API changed)
  2  usage error (argparse)
  3  every source was blocked or unreachable (an upstream outage, not a bug)

The output file is never written empty.
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from html.parser import HTMLParser

EXIT_OK = 0
EXIT_NO_VERSIONS = 1
EXIT_UNREACHABLE = 3

DOCS_URL = "https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/"
GITHUB_API = "https://api.github.com"
UPSTREAM_REPO = "stolostron/multiclusterhub-operator"
DORMANT_DAYS = 90
OUTPUT = "docs/openshift_acm_versions.txt"

# docs.redhat.com returns 403 for requests advertising a browser-like ("Mozilla/...")
# User-Agent from datacenter IPs. An honest, non-browser User-Agent is allowed and the
# request is then redirected to the latest version page, which urllib follows.
USER_AGENT = (
    "camunda-deployment-references-acm-version-bot "
    "(+https://github.com/camunda/camunda-deployment-references)"
)

BRANCH_RE = re.compile(r"^release-(2\.\d+)$")


class SourceUnreachable(Exception):
    """The source could not be fetched (network error, HTTP error, timeout)."""


def http_get(url, attempts=3, backoff_seconds=10):
    headers = {"User-Agent": USER_AGENT, "Accept": "*/*"}
    token = os.environ.get("GITHUB_TOKEN")
    if token and url.startswith(GITHUB_API):
        headers["Authorization"] = f"Bearer {token}"
        headers["Accept"] = "application/vnd.github+json"
    last_error = None
    for attempt in range(1, attempts + 1):
        try:
            request = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(request, timeout=30) as response:
                return response.read().decode("utf-8", errors="replace")
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            last_error = error
            print(f"Attempt {attempt}/{attempts} failed for {url}: {error}", file=sys.stderr)
            if attempt < attempts:
                time.sleep(backoff_seconds * attempt)
    raise SourceUnreachable(f"{url}: {last_error}")


class _VersionSelect(HTMLParser):
    """Collects the option values of <select id="product_version">."""

    def __init__(self):
        super().__init__()
        self.versions = []
        self._inside = False

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "select" and attrs.get("id") == "product_version":
            self._inside = True
        elif tag == "option" and self._inside:
            value = (attrs.get("value") or "").strip()
            if value:
                self.versions.append(value)

    def handle_endtag(self, tag):
        if tag == "select":
            self._inside = False


def parse_docs(html):
    parser = _VersionSelect()
    parser.feed(html)
    return parser.versions


def version_key(version):
    return tuple(int(part) for part in version.split("."))


def released_branch_versions(branches, commit_date, now, dormant_days=DORMANT_DAYS):
    """Versions of the `release-2.N` branches, newest first.

    Walking down from the newest branch, a branch whose tip is older than
    `dormant_days` is a placeholder cut ahead of the release and is dropped; the walk
    stops at the first active branch. Older branches are kept whatever their age,
    since a released version stops receiving commits once it is out of support.
    """
    versions = sorted(
        {m.group(1) for name in branches if (m := BRANCH_RE.match(name))},
        key=version_key,
        reverse=True,
    )
    while versions:
        age = now - commit_date(f"release-{versions[0]}")
        if age.days <= dormant_days:
            break
        print(f"Dropping release-{versions[0]}: no commit for {age.days} days", file=sys.stderr)
        versions.pop(0)
    return versions


def fetch_upstream(get, now, api=GITHUB_API, repo=UPSTREAM_REPO):
    branches = []
    for page in range(1, 6):
        chunk = json.loads(get(f"{api}/repos/{repo}/branches?per_page=100&page={page}"))
        branches += [item["name"] for item in chunk]
        if len(chunk) < 100:
            break

    def commit_date(branch):
        commits = json.loads(get(f"{api}/repos/{repo}/commits?sha={branch}&per_page=1"))
        return datetime.fromisoformat(commits[0]["commit"]["committer"]["date"].replace("Z", "+00:00"))

    return released_branch_versions(branches, commit_date, now)


def collect(sources):
    """Runs the sources in order. Returns (versions, source name), or (None, reason)."""
    unparsed = []
    for name, read in sources:
        try:
            versions = read()
        except SourceUnreachable as error:
            print(f"WARNING: source '{name}' unreachable: {error}", file=sys.stderr)
            continue
        except (ValueError, KeyError, IndexError, TypeError) as error:
            print(f"WARNING: source '{name}' returned an unexpected payload: {error!r}", file=sys.stderr)
            unparsed.append(name)
            continue
        if versions:
            return versions, name
        print(f"WARNING: source '{name}' answered but no versions were found", file=sys.stderr)
        unparsed.append(name)
    return None, unparsed


def main(argv=None, get=http_get, now=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--output", default=OUTPUT)
    parser.add_argument("--docs-url", default=DOCS_URL)
    parser.add_argument("--github-api", default=GITHUB_API)
    args = parser.parse_args(argv)
    now = now or datetime.now(timezone.utc)

    sources = [
        ("docs.redhat.com", lambda: parse_docs(get(args.docs_url))),
        ("stolostron branches", lambda: fetch_upstream(get, now, api=args.github_api)),
    ]
    versions, detail = collect(sources)

    if versions is None:
        if detail:
            # A source answered but its content was not understood: a bug to fix, not
            # an outage to wait out.
            print(
                f"ERROR: no OpenShift ACM versions found (sources that answered: {', '.join(detail)}). "
                "The page or API structure may have changed; refusing to write an empty file.",
                file=sys.stderr,
            )
            return EXIT_NO_VERSIONS
        print("ERROR: every OpenShift ACM version source is blocked or unreachable.", file=sys.stderr)
        return EXIT_UNREACHABLE

    output_dir = os.path.dirname(args.output)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
    with open(args.output, "w") as f:
        for version in versions:
            f.write(f"{version}\n")
    print(f"Wrote {len(versions)} OpenShift ACM versions from {detail} to {args.output}")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
