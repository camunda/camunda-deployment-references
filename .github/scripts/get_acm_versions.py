#!/usr/bin/env python

"""
Retrieve OpenShift ACM versions from the official documentation and save it as txt file in docs folder.
"""

import os

import requests
from bs4 import BeautifulSoup

url = "https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/"

headers = {"User-Agent": "Mozilla/5.0"}

response = requests.get(url, headers=headers)
soup = BeautifulSoup(response.text, "html.parser")

versions = []
select = soup.find("select", {"id": "product_version"})
if select:
    for option in select.find_all("option"):
        versions.append(option.get("value"))

os.makedirs("docs", exist_ok=True)

with open("docs/openshift_acm_versions.txt", "w") as f:
    f.writelines(f"{v}\n" for v in versions)
