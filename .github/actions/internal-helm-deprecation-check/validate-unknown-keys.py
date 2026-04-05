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

    # Detect object schemas: explicit type, properties, or patternProperties
    is_object = (
        schema.get("type") == "object"
        or "properties" in schema
        or "patternProperties" in schema
    )

    if is_object:
        schema["additionalProperties"] = False

    # Recursively process known subschema locations
    if "properties" in schema and isinstance(schema["properties"], dict):
        for key, value in list(schema["properties"].items()):
            if isinstance(value, dict):
                schema["properties"][key] = make_schema_strict(value)

    if "patternProperties" in schema and isinstance(schema["patternProperties"], dict):
        for pattern, value in list(schema["patternProperties"].items()):
            if isinstance(value, dict):
                schema["patternProperties"][pattern] = make_schema_strict(value)

    # items (arrays)
    if "items" in schema:
        items = schema["items"]
        if isinstance(items, dict):
            schema["items"] = make_schema_strict(items)
        elif isinstance(items, list):
            schema["items"] = [
                make_schema_strict(item) if isinstance(item, dict) else item
                for item in items
            ]

    # Composition keywords
    for combiner in ("allOf", "anyOf", "oneOf"):
        if combiner in schema and isinstance(schema[combiner], list):
            schema[combiner] = [
                make_schema_strict(sub) if isinstance(sub, dict) else sub
                for sub in schema[combiner]
            ]

    if "not" in schema and isinstance(schema["not"], dict):
        schema["not"] = make_schema_strict(schema["not"])

    # Generic fallback for remaining nested dicts/lists (e.g. definitions)
    handled_keys = {
        "properties", "patternProperties", "items",
        "allOf", "anyOf", "oneOf", "not",
    }
    for key, value in list(schema.items()):
        if key in handled_keys:
            continue
        if isinstance(value, dict):
            schema[key] = make_schema_strict(value)
        elif isinstance(value, list):
            schema[key] = [
                make_schema_strict(item) if isinstance(item, dict) else item
                for item in value
            ]

    return schema


def _recurse_into_value(schema, value, path):
    """Recurse into a value (dict or list) using the corresponding schema."""
    unknown = []
    if isinstance(value, dict):
        unknown.extend(find_unknown_keys(schema, value, path))
    elif isinstance(value, list):
        items_schema = schema.get("items", {})
        if isinstance(items_schema, dict):
            for idx, item in enumerate(value):
                if isinstance(item, dict):
                    unknown.extend(
                        find_unknown_keys(items_schema, item, f"{path}[{idx}]")
                    )
    return unknown


def find_unknown_keys(schema, values, path=""):
    """
    Recursively find keys in values that are not defined in the schema.

    Returns a list of dotted key paths (strings) for each unknown key found.
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
            unknown.extend(_recurse_into_value(sub_schema, values[key], full_path))
        elif pattern_properties:
            # Check if the key matches any pattern property
            matched = False
            for pattern, sub_schema in pattern_properties.items():
                if re.search(pattern, key):
                    matched = True
                    unknown.extend(
                        _recurse_into_value(sub_schema, values[key], full_path)
                    )
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
