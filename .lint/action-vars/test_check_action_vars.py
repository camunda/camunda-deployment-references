#!/usr/bin/env python3
"""
Unit tests for check-action-vars.py.

Run with:
    python3 -m unittest discover -s .lint/action-vars
"""

import importlib.util
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("check-action-vars.py")

_spec = importlib.util.spec_from_file_location("check_action_vars", MODULE_PATH)
check_action_vars = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_action_vars)

check_file = check_action_vars.check_file
read_steps = check_action_vars.read_steps


def findings(source: str) -> list[str]:
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "action.yml"
        path.write_text(source)
        return check_file(path)


COMPOSITE = """---
name: Test
runs:
    using: composite
    steps:
{steps}
"""


def composite(steps: str) -> str:
    return COMPOSITE.format(steps=steps)


class TestParsing(unittest.TestCase):
    def test_reads_name_env_and_script_of_every_step(self):
        steps = read_steps(
            composite(
                """        - name: First
          shell: bash
          env:
              INPUTS_ONE: ${{ inputs.one }}
          run: |
              echo "${INPUTS_ONE}"

        - name: Second
          uses: ./.github/actions/other
          with:
              raw-tags: ${{ inputs.tags }}
"""
            ).splitlines()
        )
        self.assertEqual([step.name for step in steps], ["First", "Second"])
        self.assertEqual([entry.key for entry in steps[0].env], ["INPUTS_ONE"])
        self.assertIn("${INPUTS_ONE}", steps[0].scripts[0])
        self.assertEqual([entry.key for entry in steps[1].with_], ["raw-tags"])

    def test_reports_the_line_of_the_offending_value_not_of_the_step(self):
        source = composite(
            """        - name: Install
          uses: redhat-actions/openshift-tools-installer@abc # v1
          with:
              oc: ${INPUTS_OPENSHIFT_VERSION}
"""
        )
        problem = findings(source)[0]
        offending = source.splitlines().index("              oc: ${INPUTS_OPENSHIFT_VERSION}") + 1
        self.assertIn(f":{offending}:", problem)

    def test_a_commented_key_still_opens_its_block(self):
        problems = findings(
            composite(
                """        - name: Plan
          shell: bash
          env: # the caller sets these
              INPUTS_RH_TOKEN: ${{ inputs.rh-token }}
          run: |
              echo hello
"""
            )
        )
        self.assertEqual(len(problems), 1)
        self.assertIn("declares INPUTS_RH_TOKEN but never reads it", problems[0])

    def test_yaml_written_by_a_script_is_text_and_not_structure(self):
        source = composite(
            """        - name: Apply
          shell: bash
          run: |
              cat <<'EOF' | kubectl apply -f -
              spec:
                  steps:
                      - name: Ghost
                        env:
                            BAD: ${SOME_VALUE}
              EOF
"""
        )
        self.assertEqual(findings(source), [])
        self.assertEqual([step.name for step in read_steps(source.splitlines())], ["Apply"])


class TestLiteralValues(unittest.TestCase):
    def test_rejects_a_shell_variable_under_with(self):
        problems = findings(
            composite(
                """        - name: Install
          uses: redhat-actions/openshift-tools-installer@abc # v1
          with:
              oc: ${INPUTS_OPENSHIFT_VERSION}
"""
            )
        )
        self.assertEqual(len(problems), 1)
        self.assertIn("literal string '${INPUTS_OPENSHIFT_VERSION}'", problems[0])

    def test_rejects_a_shell_variable_under_env(self):
        problems = findings(
            composite(
                """        - name: Plan
          shell: bash
          env:
              RHCS_TOKEN: ${INPUTS_RH_TOKEN}
          run: |
              terraform plan
"""
            )
        )
        self.assertEqual(len(problems), 1)
        self.assertIn("RHCS_TOKEN", problems[0])

    def test_rejects_the_unbraced_form_when_it_is_the_whole_value(self):
        problems = findings(
            composite(
                """        - name: Plan
          uses: ./.github/actions/other
          with:
              token: $INPUTS_RH_TOKEN
"""
            )
        )
        self.assertEqual(len(problems), 1)

    def test_rejects_the_unbraced_form_in_either_quote_style(self):
        for quoted in ('"$INPUTS_RH_TOKEN"', "'$INPUTS_RH_TOKEN'"):
            with self.subTest(value=quoted):
                problems = findings(
                    composite(
                        f"""        - name: Plan
          uses: ./.github/actions/other
          with:
              token: {quoted}
"""
                    )
                )
                self.assertEqual(len(problems), 1)
                self.assertIn("literal string '${INPUTS_RH_TOKEN}'", problems[0])

    def test_accepts_the_unbraced_form_when_it_is_only_part_of_the_value(self):
        self.assertEqual(
            findings(
                composite(
                    """        - name: Plan
          uses: ./.github/actions/other
          with:
              bucket: $INPUTS_PREFIX-tfstate
"""
                )
            ),
            [],
        )

    def test_ignores_a_reference_that_only_appears_in_a_trailing_comment(self):
        self.assertEqual(
            findings(
                composite(
                    """        - name: Plan
          uses: ./.github/actions/other
          with:
              token: real-value # was ${INPUTS_RH_TOKEN}
"""
                )
            ),
            [],
        )

    def test_rejects_a_reference_quoted_inside_the_value(self):
        problems = findings(
            composite(
                """        - name: Plan
          uses: ./.github/actions/other
          with:
              message: "planning with ${INPUTS_RH_TOKEN}"
"""
            )
        )
        self.assertEqual(len(problems), 1)

    def test_an_escaped_quote_does_not_reopen_the_value_over_the_comment(self):
        self.assertEqual(
            findings(
                composite(
                    """        - name: Plan
          uses: ./.github/actions/other
          with:
              message: "say \\"hello\\"" # was ${INPUTS_RH_TOKEN}
"""
                )
            ),
            [],
        )

    def test_a_comment_after_a_plain_scalar_is_not_part_of_the_script(self):
        self.assertEqual(
            findings(
                composite(
                    """        - name: Plan
          shell: bash
          run: echo hello # once read ${INPUTS_RH_TOKEN}
"""
                )
            ),
            [],
        )

    def test_a_hash_inside_a_quoted_scalar_belongs_to_the_value(self):
        problems = findings(
            composite(
                """        - name: Plan
          uses: ./.github/actions/other
          with:
              message: "planning # with ${INPUTS_RH_TOKEN}"
"""
            )
        )
        self.assertEqual(len(problems), 1)
        self.assertIn("literal string '${INPUTS_RH_TOKEN}'", problems[0])

    def test_the_script_exemption_does_not_extend_to_env(self):
        problems = findings(
            composite(
                """        - name: Retry
          shell: bash
          env:
              script: ${INPUTS_COMMAND}
          run: |
              echo hello
"""
            )
        )
        self.assertEqual(len(problems), 1)
        self.assertIn("literal string '${INPUTS_COMMAND}'", problems[0])

    def test_rejects_a_shell_variable_in_a_job_level_env(self):
        problems = findings(
            """---
name: Test
jobs:
    build:
        env:
            RHCS_TOKEN: ${INPUTS_RH_TOKEN}
        steps:
            - name: Plan
              run: |
                  terraform plan
"""
        )
        self.assertEqual(len(problems), 1)
        self.assertIn("env block", problems[0])
        self.assertIn("literal string '${INPUTS_RH_TOKEN}'", problems[0])

    def test_the_literal_escape_hatch_silences_an_outer_env_finding(self):
        self.assertEqual(
            findings(
                """---
name: Test
env:
    PATH_PREFIX: ${HOME}/bin # lint: literal-var
jobs:
    build:
        steps:
            - name: Plan
              run: |
                  terraform plan
"""
            ),
            [],
        )

    def test_accepts_a_github_expression(self):
        self.assertEqual(
            findings(
                composite(
                    """        - name: Install
          uses: redhat-actions/openshift-tools-installer@abc # v1
          with:
              oc: ${{ inputs.openshift-version }}
"""
                )
            ),
            [],
        )

    def test_accepts_lower_case_templating_of_the_called_action(self):
        self.assertEqual(
            findings(
                composite(
                    """        - name: Backport
          uses: korthout/backport-action@abc # v3
          with:
              pull_description: |
                  Backport of #${pull_number} to `${target_branch}`.
"""
                )
            ),
            [],
        )

    def test_accepts_a_shell_variable_inside_a_script_input(self):
        self.assertEqual(
            findings(
                composite(
                    """        - name: Retry
          uses: nick-fields/retry@abc # v3
          env:
              INPUTS_NAME: ${{ inputs.name }}
          with:
              command: |
                  echo "${INPUTS_NAME}"
"""
                )
            ),
            [],
        )

    def test_the_literal_escape_hatch_silences_the_finding(self):
        self.assertEqual(
            findings(
                composite(
                    """        - name: Install
          uses: ./.github/actions/other
          with:
              path: ${HOME}/bin # lint: literal-var
"""
                )
            ),
            [],
        )


class TestUndeclaredReads(unittest.TestCase):
    def test_rejects_a_read_with_no_declaration_in_scope(self):
        problems = findings(
            composite(
                """        - name: Set AWS Region
          shell: bash
          run: |
              echo "AWS_REGION=${INPUTS_AWS_REGION}"
"""
            )
        )
        self.assertEqual(len(problems), 1)
        self.assertIn("reads ${INPUTS_AWS_REGION}", problems[0])

    def test_a_declaration_on_the_next_step_does_not_count(self):
        problems = findings(
            composite(
                """        - name: Reader
          shell: bash
          run: |
              echo "${INPUTS_AWS_REGION}"

        - name: Holder
          shell: bash
          env:
              INPUTS_AWS_REGION: ${{ inputs.aws-region }}
          run: |
              echo hello
"""
            )
        )
        self.assertEqual(len(problems), 2)
        self.assertIn("reads ${INPUTS_AWS_REGION}", problems[0])
        self.assertIn("declares INPUTS_AWS_REGION but never reads it", problems[1])

    def test_accepts_a_workflow_level_declaration(self):
        self.assertEqual(
            findings(
                """---
name: Test
env:
    INPUTS_AWS_REGION: eu-west-1
jobs:
    build:
        steps:
            - name: Reader
              run: |
                  echo "${INPUTS_AWS_REGION}"
"""
            ),
            [],
        )

    def test_accepts_a_job_level_declaration_inside_that_job(self):
        self.assertEqual(
            findings(
                """---
name: Test
jobs:
    build:
        env:
            INPUTS_AWS_REGION: eu-west-1
        steps:
            - name: Reader
              run: |
                  echo "${INPUTS_AWS_REGION}"
"""
            ),
            [],
        )

    def test_accepts_a_job_level_declaration_written_after_the_steps(self):
        self.assertEqual(
            findings(
                """---
name: Test
jobs:
    build:
        steps:
            - name: Reader
              run: |
                  echo "${INPUTS_AWS_REGION}"
        env:
            INPUTS_AWS_REGION: eu-west-1
"""
            ),
            [],
        )

    def test_one_job_env_does_not_reach_the_next_job(self):
        problems = findings(
            """---
name: Test
jobs:
    build:
        env:
            INPUTS_AWS_REGION: eu-west-1
        steps:
            - name: Reader
              run: |
                  echo "${INPUTS_AWS_REGION}"

    publish:
        steps:
            - name: Outsider
              run: |
                  echo "${INPUTS_AWS_REGION}"
"""
        )
        self.assertEqual(len(problems), 1)
        self.assertIn("Outsider", problems[0])
        self.assertIn("reads ${INPUTS_AWS_REGION}", problems[0])

    def test_a_later_job_env_does_not_reach_back_to_an_earlier_one(self):
        problems = findings(
            """---
name: Test
jobs:
    build:
        steps:
            - name: Reader
              run: |
                  echo "${INPUTS_AWS_REGION}"

    publish:
        env:
            INPUTS_AWS_REGION: eu-west-1
        steps:
            - name: Owner
              run: |
                  echo "${INPUTS_AWS_REGION}"
"""
        )
        self.assertEqual(len(problems), 1)
        self.assertIn("Reader", problems[0])


class TestDeadDeclarations(unittest.TestCase):
    def test_rejects_a_declaration_the_step_never_reads(self):
        problems = findings(
            composite(
                """        - name: Delete
          shell: bash
          env:
              INPUTS_OPENSHIFT_VERSION: ${{ inputs.openshift-version }}
          run: |
              echo hello
"""
            )
        )
        self.assertEqual(len(problems), 1)
        self.assertIn("declares INPUTS_OPENSHIFT_VERSION but never reads it", problems[0])

    def test_ignores_names_outside_the_inputs_convention(self):
        self.assertEqual(
            findings(
                composite(
                    """        - name: Apply
          shell: bash
          env:
              RHCS_TOKEN: ${{ inputs.rh-token }}
          run: |
              terraform apply
"""
                )
            ),
            [],
        )

    def test_the_external_escape_hatch_silences_the_finding(self):
        self.assertEqual(
            findings(
                composite(
                    """        - name: Delete
          shell: bash
          env:
              INPUTS_TARGET: ${{ inputs.target }} # lint: external-var
          run: |
              ./scripts/destroy.sh
"""
                )
            ),
            [],
        )


if __name__ == "__main__":
    unittest.main()
