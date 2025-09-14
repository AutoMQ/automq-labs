#!/usr/bin/env python3
import argparse
import json
import random
import string
import sys
from typing import Any, Dict, List, Union


Json = Union[Dict[str, Any], List[Any], str, int, float, bool, None]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Generate JSON records conforming to an Avro .avsc schema")
    p.add_argument("--schema", required=True, help="Path to .avsc file (record schema)")
    p.add_argument("--count", type=int, default=10, help="Number of records to generate")
    p.add_argument("--seed", type=int, default=42, help="Random seed for reproducibility")
    p.add_argument(
        "--template",
        action="append",
        default=[],
        help="Field template overrides: field=pattern (supports {i}), may repeat",
    )
    return p.parse_args()


def load_schema(path: str) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def choose_union_type(t: List[Any]) -> Any:
    # Prefer first non-null type
    for item in t:
        if item != "null":
            return item
    return t[0]


def rand_str(n: int = 8) -> str:
    return "".join(random.choices(string.ascii_lowercase + string.digits, k=n))


def gen_primitive(t: str, i: int) -> Json:
    if t == "string":
        return f"str_{i}_{rand_str(6)}"
    if t == "int":
        return i
    if t == "long":
        return i
    if t == "float":
        return round(100.0 + i * 0.1, 3)
    if t == "double":
        return 1000.0 + i * 0.01
    if t == "boolean":
        return (i % 2) == 0
    if t == "bytes":
        # Avro JSON encoding for bytes is base64; use simple ascii then base64-ish marker
        return ""  # keep empty for simplicity
    if t == "null":
        return None
    return f"unsupported_{t}"


def gen_from_type(t: Any, i: int, named: Dict[str, Any]) -> Json:
    # Union type - handle specially for JSON encoding
    if isinstance(t, list):
        # For unions, we need to choose a type and format appropriately for Avro JSON
        chosen_type = choose_union_type(t)
        value = gen_from_type(chosen_type, i, named)

        # If union contains null and we're generating a non-null value,
        # we need to wrap it in the Avro JSON union format
        if "null" in t and chosen_type != "null":
            # For simple types, Avro JSON union format is: {"type_name": value}
            if chosen_type in ("boolean", "int", "long", "float", "double", "bytes", "string"):
                return {chosen_type: value}
            else:
                return {chosen_type: value}
        else:
            return value

    # Named reference
    if isinstance(t, str):
        # primitive or named
        if t in ("null", "boolean", "int", "long", "float", "double", "bytes", "string"):
            return gen_primitive(t, i)
        # referenced named type
        if t in named:
            return gen_record(named[t], i, named)
        return f"ref_{t}_{i}"

    # Complex type (dict)
    if isinstance(t, dict):
        ttype = t.get("type")
        if ttype == "array":
            items = t.get("items", "string")
            # small list
            return [gen_from_type(items, i + k, named) for k in range(1, 2)]
        if ttype == "map":
            values = t.get("values", "string")
            return {f"k{i}": gen_from_type(values, i, named)}
        if ttype == "record":
            return gen_record(t, i, named)
        if ttype == "enum":
            symbols = t.get("symbols", [])
            return symbols[i % len(symbols)] if symbols else "UNKNOWN"
        if ttype == "fixed":
            size = int(t.get("size", 4))
            return ""  # keep empty; console producer accepts as string
        # logical types on primitives
        logical = t.get("logicalType")
        base = t.get("type")
        if logical == "timestamp-millis":
            return 1_700_000_000_000 + i * 1000
        if base in ("int", "long", "float", "double", "boolean", "bytes", "string"):
            return gen_primitive(base, i)
        return f"complex_{ttype}_{i}"

    return f"unknown_{t}_{i}"


def collect_named_types(schema: Dict[str, Any]) -> Dict[str, Any]:
    named: Dict[str, Any] = {}

    def walk(obj: Any):
        if isinstance(obj, dict):
            if obj.get("type") == "record" and "name" in obj:
                named[obj["name"]] = obj
                for f in obj.get("fields", []):
                    walk(f.get("type"))
            else:
                for v in obj.values():
                    walk(v)
        elif isinstance(obj, list):
            for v in obj:
                walk(v)

    walk(schema)
    return named


def is_string_type(t: Any) -> bool:
    if isinstance(t, str):
        return t == "string"
    if isinstance(t, list):
        return any(is_string_type(x) for x in t)
    if isinstance(t, dict):
        ttype = t.get("type")
        if ttype == "string":
            return True
        # unions can appear as dict? Typically list, but be permissive
    return False


def gen_record(schema: Dict[str, Any], i: int, named: Dict[str, Any], templates: Dict[str, str] = None) -> Dict[str, Json]:
    out: Dict[str, Json] = {}
    templates = templates or {}
    for f in schema.get("fields", []):
        fname = f["name"]
        ftype = f["type"]
        if fname in templates and is_string_type(ftype):
            try:
                out[fname] = templates[fname].format(i=i)
            except Exception:
                out[fname] = templates[fname]
        else:
            out[fname] = gen_from_type(ftype, i, named)
    return out


def main():
    args = parse_args()
    random.seed(args.seed)
    schema = load_schema(args.schema)
    named = collect_named_types(schema)

    # parse templates
    template_map: Dict[str, str] = {}
    for t in args.template:
        if "=" in t:
            k, v = t.split("=", 1)
            template_map[k.strip()] = v

    # top-level must be a record
    if schema.get("type") != "record":
        print("Top-level schema must be a record", file=sys.stderr)
        sys.exit(2)

    for i in range(1, args.count + 1):
        rec = gen_record(schema, i, named, templates=template_map)
        print(json.dumps(rec, ensure_ascii=False))


if __name__ == "__main__":
    main()
