import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "check_capacity_needs", Path(__file__).with_name("check-capacity-needs.py")
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

PLAN = {
    "resources": {
        "module.vpc": {
            "child_modules": {
                "module.vpc.module.inner": {
                    "resources": {
                        "module.vpc.module.inner.aws_vpc.this[0]": {"identity": {}},
                        'module.vpc.module.inner.aws_eip.nat["a.b"]': {},
                        "module.vpc.module.inner.aws_subnet.private[0]": {},
                    }
                }
            }
        }
    }
}

WORKFLOW = """on:
    pull_request:
        paths:
            - '!aws/x/terraform/*/test/golden/**'
jobs:
    t:
        steps:
            - uses: ./.github/actions/aws-capacity-slot
              with:
                  mode: acquire
                  needs: |
                      {needs}
                  margin: '2'
"""


class CheckCapacityNeedsTest(unittest.TestCase):
    def run_check(self, needs: str) -> list[str]:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            golden = root / "aws/x/terraform/cluster/test/golden"
            golden.mkdir(parents=True)
            (golden / "tfplan-golden.json").write_text(json.dumps(PLAN))
            workflows = root / ".github/workflows"
            workflows.mkdir(parents=True)
            (workflows / "w.yml").write_text(WORKFLOW.replace("{needs}", needs))
            return MODULE.check(root)

    def test_all_types_declared(self):
        self.assertEqual(self.run_check("vpcs=1\n                      elastic-ips=1"), [])

    def test_missing_type_reported(self):
        errors = self.run_check("vpcs=1")
        self.assertEqual(len(errors), 1)
        self.assertIn("aws_eip", errors[0])


if __name__ == "__main__":
    unittest.main()
