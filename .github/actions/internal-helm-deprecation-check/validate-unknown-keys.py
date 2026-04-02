#!/usr/bin/env python3
"""
Validate deployed Helm values against a strict version of the chart schema.

Detects unknown keys (typos, removed properties) by checking that every key
in the values exists in the chart's JSON Schema definition.

Only uses Python standard library modules (json, sys, re).

Usage:
    python3 validate-unknown-keys.py <schema.json> <values.json>

Exit codes:
    0 - No unknown keys found
    1 - Unknown keys detected
    2 - Script error (missing file, invalid JSON, etc.)
"""

import json
import re
import sys


def make_schema_strict(schema):
    """Recursively add additionalProperties: false to all object schemas."""
    if not isinstance(schema, dict):
        return schema

    if schema.get("type") == "object" and "properties" in schema:
        schema["additionalProperties"] = False
        for key, value in schema["properties"].items():
            schema["properties"][key] = make_schema_strict(value)
    elif "properties" in schema and "type" not in schema:
        # Objects without explicit type but with properties
        schema["additionalProperties"] = False
        for key, value in schema["properties"].items():
            schema["properties"][key] = make_schema_strict(value)
    else:
        for key, value in schema.items():
            if isinstance(value, dict):
                schema[key] = make_schema_strict(value)
            elif isinstance(value, list):
                schema[key] = [make_schema_strict(item) if isinstance(item, dict) else item for item in value]

    return schema


def find_unknown_keys(schema, values, path=""):
    """
    Recursively find keys in values that are not defined in the schema.

    Returns a list of (path, key) tuples for each unknown key found.
    """
    unknown = []

    if not isinstance(values, dict):
        return unknown

    if not isinstance(schema, dict):
        return unknown

    # Get known properties from the schema
    known_properties = set(schema.get("properties", {}).keys())
    has_additional = schema.get("additionalProperties", True)
    pattern_properties = schema.get("patternProperties", {})

    if not known_properties and has_additional is not False:
        # Schema doesn't define properties and allows additional ones — skip
        return unknown

    for key in values:
        full_path = f"{path}.{key}" if path else key

        if key in known_properties:
            # Key is known — recurse into its sub-schema
            sub_schema = schema["properties"][key]
            if isinstance(values[key], dict):
                unknown.extend(find_unknown_keys(sub_schema, values[key], full_path))
        elif pattern_properties:
            # Check if the key matches any pattern property
            matched = False
            for pattern, sub_schema in pattern_properties.items():
                if re.search(pattern, key):
                    matched = True
                    if isinstance(values[key], dict):
                        unknown.extend(find_unknown_keys(sub_schema, values[key], full_path))
                    break
            if not matched and has_additional is False:
                unknown.append(full_path)
        elif has_additional is False:
            unknown.append(full_path)

    return unknown


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <schema.json> <values.json>", file=sys.stderr)
        sys.exit(2)

    schema_path = sys.argv[1]
    values_path = sys.argv[2]

    try:
        with open(schema_path) as f:
            schema = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f"Error reading schema: {e}", file=sys.stderr)
        sys.exit(2)

    try:
        with open(values_path) as f:
            values = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f"Error reading values: {e}", file=sys.stderr)
        sys.exit(2)

    strict_schema = make_schema_strict(schema)
    unknown_keys = find_unknown_keys(strict_schema, values)

    if unknown_keys:
        print(f"Found {len(unknown_keys)} unknown key(s) in deployed values:\n")
        for key_path in sorted(unknown_keys):
            print(f"  - {key_path}")
        print(
            "\nThese keys are not defined in the chart schema and will be silently ignored."
        )
        print(
            "See: https://github.com/camunda/camunda-platform-helm/issues/4564"
        )
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == "__main__":
    main()
