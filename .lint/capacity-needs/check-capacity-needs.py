#!/usr/bin/env python3
"""Assert that each capacity slot declares every quota its Terraform creates.

`aws-capacity-slot` reserves the `needs` of a run before admitting it. A
resource type the stack creates but `needs` omits is never reserved, so two
runs can be admitted into the same last unit of quota and one fails at
`terraform apply`.

The golden plans (`terraform/*/test/golden/tfplan-golden.json`) list what each
stack creates. A workflow names its golden directories in its path filters
(`'!aws/.../test/golden/**'`), which links the two without a mapping file.

Scope: this checks resource types, not counts. Golden plans are rendered from
`golden.tfvars`, not from the CI variables (CI uses a single NAT gateway, for
example), and they miss what Kubernetes creates (ingress NLBs). Workflows that
exclude no golden directory are skipped.

Stdlib only.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

WORKFLOWS = Path(".github/workflows")

# Terraform type -> `needs` key.
QUOTAS = {
    "aws_vpc": "vpcs",
    "aws_eip": "elastic-ips",
    "aws_eks_cluster": "eks-clusters",
    "aws_rds_cluster": "rds-clusters",
    "aws_rds_cluster_instance": "rds-instances",
    "aws_db_subnet_group": "db-subnet-groups",
    "aws_opensearch_domain": "opensearch-domains",
    "aws_ec2_transit_gateway": "transit-gateways",
}
# ALBs and NLBs are separate quotas; `load_balancer_type` defaults to application.
LB_QUOTAS = {"application": "albs", "network": "nlbs"}

GOLDEN_FILTER = re.compile(r"""['"]!(?P<glob>[^'"]*/test/golden)/\*\*['"]""")
ACQUIRE = re.compile(r"""^\s+mode:\s*['"]?acquire['"]?\s*(#.*)?$""", re.M)
STEP_START = re.compile(r"^\s+- (?=\w[\w-]*:)", re.M)
NEEDS_KEY = re.compile(r"^\s+(?P<key>[a-z-]+)=\d+\s*$")


def golden_types(plan: Path) -> dict[str, str]:
    """Terraform type -> `needs` key, for resources keyed by address (`module.x.aws_vpc.this[0]`)."""
    found: dict[str, str] = {}

    def walk(node: object) -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                parts = re.sub(r"\[[^]]*\]", "", key).split(".")
                name = parts[-2] if len(parts) >= 2 else ""
                if isinstance(value, dict):
                    if name in QUOTAS:
                        found[name] = QUOTAS[name]
                    elif name == "aws_lb":
                        lb_type = (value.get("values") or {}).get("load_balancer_type") or "application"
                        if lb_type in LB_QUOTAS:
                            found[f"aws_lb ({lb_type})"] = LB_QUOTAS[lb_type]
                walk(value)

    # Walk the whole plan: child modules can sit next to `resources`, not under it.
    walk(json.loads(plan.read_text()))
    return found


def acquire_steps(text: str) -> list[str]:
    """The text of each step that acquires a slot. Each one must reserve on its own."""
    starts = [m.start() for m in STEP_START.finditer(text)] + [len(text)]
    steps = [text[a:b] for a, b in zip(starts, starts[1:])]
    return [step for step in steps if ACQUIRE.search(step)]


def declared_needs(text: str) -> set[str]:
    """Every `<resource>=<n>` key under the `needs: |` block of one step."""
    keys: set[str] = set()
    in_needs = False
    for line in text.splitlines():
        if re.match(r"^\s+needs: \|\s*$", line):
            in_needs = True
            continue
        if in_needs:
            match = NEEDS_KEY.match(line)
            if match:
                keys.add(match["key"])
            elif line.strip():
                in_needs = False
    return keys


def check(root: Path) -> list[str]:
    errors = []
    for workflow in sorted((root / WORKFLOWS).glob("*.yml")):
        text = workflow.read_text()
        steps = acquire_steps(text)
        if not steps:
            continue
        plans = [
            plan
            for match in GOLDEN_FILTER.finditer(text)
            for plan in sorted(root.glob(match["glob"] + "/tfplan-golden.json"))
        ]
        for index, step in enumerate(steps, 1):
            needs = declared_needs(step)
            for plan in plans:
                for tf_type, key in sorted(golden_types(plan).items()):
                    if key not in needs:
                        errors.append(
                            f"{workflow.relative_to(root)}: acquire step {index} does not declare "
                            f"{key}, but {plan.relative_to(root)} creates {tf_type}"
                        )
    return errors


def main() -> int:
    errors = check(Path("."))
    for error in errors:
        print(error, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
