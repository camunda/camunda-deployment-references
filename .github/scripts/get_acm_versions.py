#!/usr/bin/env python

"""
Retrieve OpenShift ACM versions from the official documentation and save it as txt file in docs folder.
"""

import sys
import requests
from bs4 import BeautifulSoup
import os

url = "https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/"

headers = {
    "User-Agent": "Mozilla/5.0"
}

response = requests.get(url, headers=headers)
response.raise_for_status()
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
