#!/usr/bin/env python3
"""
Unit tests for validate-unknown-keys.py.

Run with:
    python3 -m unittest discover -s .github/actions/internal-helm-deprecation-check
"""

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("validate-unknown-keys.py")

_spec = importlib.util.spec_from_file_location("validate_unknown_keys", MODULE_PATH)
validate_unknown_keys = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(validate_unknown_keys)

make_schema_strict = validate_unknown_keys.make_schema_strict
find_unknown_keys = validate_unknown_keys.find_unknown_keys


def check(schema, values):
    """Run the full pipeline the action runs, and return the sorted findings."""
    return sorted(find_unknown_keys(make_schema_strict(schema), values))


class MakeSchemaStrictTest(unittest.TestCase):
    def test_enumerating_object_becomes_strict(self):
        schema = {"type": "object", "properties": {"known": {"type": "string"}}}
        self.assertIs(make_schema_strict(schema)["additionalProperties"], False)

    def test_explicit_true_is_preserved(self):
        schema = {
            "type": "object",
            "additionalProperties": True,
            "properties": {"known": {"type": "string"}},
        }
        self.assertIs(make_schema_strict(schema)["additionalProperties"], True)

    def test_explicit_subschema_is_preserved(self):
        schema = {"type": "object", "additionalProperties": {"type": "string"}}
        self.assertEqual(
            make_schema_strict(schema)["additionalProperties"], {"type": "string"}
        )

    def test_explicit_false_is_kept(self):
        schema = {"type": "object", "additionalProperties": False, "properties": {}}
        self.assertIs(make_schema_strict(schema)["additionalProperties"], False)

    def test_object_without_members_is_left_alone(self):
        schema = {"type": "object"}
        self.assertNotIn("additionalProperties", make_schema_strict(schema))

    def test_pattern_properties_object_becomes_strict(self):
        schema = {"type": "object", "patternProperties": {"^x-": {"type": "string"}}}
        self.assertIs(make_schema_strict(schema)["additionalProperties"], False)

    def test_nested_objects_are_processed(self):
        schema = {
            "type": "object",
            "properties": {
                "outer": {
                    "type": "object",
                    "properties": {"inner": {"type": "object", "properties": {}}},
                }
            },
        }
        strict = make_schema_strict(schema)
        outer = strict["properties"]["outer"]
        self.assertIs(outer["additionalProperties"], False)
        self.assertIs(outer["properties"]["inner"]["additionalProperties"], False)


class FindUnknownKeysTest(unittest.TestCase):
    def test_typo_in_enumerated_object_is_reported(self):
        schema = {
            "type": "object",
            "properties": {"orchestration": {"type": "object", "properties": {}}},
        }
        self.assertEqual(check(schema, {"orchestraton": {}}), ["orchestraton"])

    def test_known_key_is_not_reported(self):
        schema = {
            "type": "object",
            "properties": {"orchestration": {"type": "object", "properties": {}}},
        }
        self.assertEqual(check(schema, {"orchestration": {}}), [])

    def test_free_form_map_keys_are_not_reported(self):
        """podAnnotations / commonLabels shape: type object, no members."""
        schema = {
            "type": "object",
            "properties": {"podAnnotations": {"type": "object"}},
        }
        values = {"podAnnotations": {"team": "infra", "cost-center": "42"}}
        self.assertEqual(check(schema, values), [])

    def test_explicit_additional_properties_true_is_honoured(self):
        """camundaHub.* shape: enumerated members plus declared free-form extras."""
        schema = {
            "type": "object",
            "properties": {
                "camundaHub": {
                    "type": "object",
                    "additionalProperties": True,
                    "properties": {"enabled": {"type": "boolean"}},
                }
            },
        }
        values = {"camundaHub": {"enabled": True, "restapi": {"replicas": 2}}}
        self.assertEqual(check(schema, values), [])

    def test_subschema_additional_properties_is_honoured(self):
        """ingress.annotations shape: map of string to string."""
        schema = {
            "type": "object",
            "properties": {
                "annotations": {
                    "type": "object",
                    "additionalProperties": {"type": "string"},
                }
            },
        }
        values = {"annotations": {"nginx.ingress.kubernetes.io/backend-protocol": "GRPC"}}
        self.assertEqual(check(schema, values), [])

    def test_explicit_additional_properties_false_is_enforced(self):
        schema = {
            "type": "object",
            "properties": {
                "component": {
                    "type": "object",
                    "additionalProperties": False,
                    "properties": {"enabled": {"type": "boolean"}},
                }
            },
        }
        values = {"component": {"enabled": True, "enabledd": False}}
        self.assertEqual(check(schema, values), ["component.enabledd"])

    def test_nested_typo_below_a_known_key_is_reported(self):
        schema = {
            "type": "object",
            "properties": {
                "orchestration": {
                    "type": "object",
                    "properties": {"contextPath": {"type": "string"}},
                }
            },
        }
        values = {"orchestration": {"contextPath": "/c8", "contexPath": "/typo"}}
        self.assertEqual(check(schema, values), ["orchestration.contexPath"])

    def test_typo_beside_a_free_form_map_is_still_reported(self):
        """Relaxing free-form maps must not relax their siblings."""
        schema = {
            "type": "object",
            "properties": {
                "identity": {
                    "type": "object",
                    "properties": {
                        "podAnnotations": {"type": "object"},
                        "enabled": {"type": "boolean"},
                    },
                }
            },
        }
        values = {
            "identity": {
                "podAnnotations": {"anything": "goes"},
                "enabledd": True,
            }
        }
        self.assertEqual(check(schema, values), ["identity.enabledd"])

    def test_array_items_are_validated(self):
        schema = {
            "type": "object",
            "properties": {
                "env": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "name": {"type": "string"},
                            "value": {"type": "string"},
                        },
                    },
                }
            },
        }
        values = {"env": [{"name": "A", "value": "1"}, {"name": "B", "valu": "2"}]}
        self.assertEqual(check(schema, values), ["env[1].valu"])

    def test_pattern_properties_match_is_not_reported(self):
        schema = {
            "type": "object",
            "properties": {
                "extra": {
                    "type": "object",
                    "patternProperties": {"^x-": {"type": "string"}},
                }
            },
        }
        values = {"extra": {"x-team": "infra"}}
        self.assertEqual(check(schema, values), [])

    def test_pattern_properties_miss_is_reported(self):
        schema = {
            "type": "object",
            "properties": {
                "extra": {
                    "type": "object",
                    "patternProperties": {"^x-": {"type": "string"}},
                }
            },
        }
        values = {"extra": {"team": "infra"}}
        self.assertEqual(check(schema, values), ["extra.team"])


class CommandLineTest(unittest.TestCase):
    def run_script(self, schema, values):
        with tempfile.TemporaryDirectory() as tmp:
            schema_path = Path(tmp) / "schema.json"
            values_path = Path(tmp) / "values.json"
            schema_path.write_text(json.dumps(schema))
            values_path.write_text(json.dumps(values))
            return subprocess.run(
                [sys.executable, str(MODULE_PATH), str(schema_path), str(values_path)],
                capture_output=True,
                text=True,
                check=False,
            )

    def test_exit_code_zero_when_clean(self):
        schema = {"type": "object", "properties": {"a": {"type": "object"}}}
        result = self.run_script(schema, {"a": {"free": "form"}})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_exit_code_one_on_unknown_key(self):
        schema = {"type": "object", "properties": {"a": {"type": "object"}}}
        result = self.run_script(schema, {"b": {}})
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("- b", result.stdout)

    def test_exit_code_two_on_bad_input(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = subprocess.run(
                [sys.executable, str(MODULE_PATH), f"{tmp}/missing.json", f"{tmp}/x.json"],
                capture_output=True,
                text=True,
                check=False,
            )
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
