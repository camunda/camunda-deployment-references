#!/usr/bin/env python

"""
Retrieve OpenShift ACM versions from the official documentation and save it as txt file in docs folder.
"""

import os
import sys
import time

import requests
from bs4 import BeautifulSoup

url = "https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/"

# docs.redhat.com sits behind bot protection that returns 403 for requests
# advertising a browser-like ("Mozilla/...") User-Agent from datacenter IPs
# (such as GitHub-hosted runners). An honest, non-browser User-Agent is allowed
# and the request is then redirected to the latest version page, so we identify
# ourselves plainly and let requests follow the redirect.
headers = {
    "User-Agent": "camunda-deployment-references-acm-version-bot "
                  "(+https://github.com/camunda/camunda-deployment-references)"
}


def fetch(target_url, attempts=3, backoff_seconds=5):
    last_error = None
    for attempt in range(1, attempts + 1):
        try:
            response = requests.get(target_url, headers=headers, timeout=30)
            response.raise_for_status()
            return response
        except requests.RequestException as error:
            last_error = error
            print(f"Attempt {attempt}/{attempts} failed: {error}", file=sys.stderr)
            if attempt < attempts:
                time.sleep(backoff_seconds * attempt)
    raise SystemExit(f"ERROR: could not fetch {target_url}: {last_error}")


response = fetch(url)
soup = BeautifulSoup(response.text, "html.parser")

versions = []
select = soup.find("select", {"id": "product_version"})
if select:
    for option in select.find_all("option"):
        value = option.get("value")
        if value and value.strip():
            versions.append(value.strip())

# Fail loudly instead of overwriting the artifact with an empty list when the
# documentation page structure changed or the request was throttled/blocked.
if not versions:
    sys.exit(
        f"ERROR: no OpenShift ACM versions found at {url}. "
        "The page structure may have changed; refusing to write an empty file."
    )

os.makedirs("docs", exist_ok=True)

with open("docs/openshift_acm_versions.txt", "w") as f:
    for v in versions:
        f.write(f"{v}\n")

print(f"Wrote {len(versions)} OpenShift ACM versions to docs/openshift_acm_versions.txt")
