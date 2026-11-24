"""Print the shape of a JSON document for REA inspection.

Usage:
  python json_shape.py <file> [path ...]

Without paths it prints top-level keys and value kinds. Each path is a
dot-separated lookup such as `home` or `data.items`; list indexes are allowed.
"""

import json
import sys


def kind(value):
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "bool"
    if isinstance(value, (int, float)):
        return f"number({value})"
    if isinstance(value, str):
        text = value.replace("\n", "\\n")
        return f"string({len(value)}): {text[:160]}"
    if isinstance(value, list):
        return f"list({len(value)})"
    if isinstance(value, dict):
        return f"map({len(value)})"
    return type(value).__name__


def lookup(root, path):
    value = root
    for part in path.split("."):
        if isinstance(value, list):
            value = value[int(part)]
        elif isinstance(value, dict):
            value = value[part]
        else:
            raise KeyError(path)
    return value


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    with open(sys.argv[1], "rb") as handle:
        data = json.load(handle)
    paths = sys.argv[2:]
    if not paths:
        if isinstance(data, dict):
            for key, value in data.items():
                print(f"{key}\t{kind(value)}")
        else:
            print(kind(data))
        return 0
    for path in paths:
        try:
            value = lookup(data, path)
        except Exception as error:
            print(f"{path}\tERROR {error!r}")
            continue
        print(f"===== {path} ({kind(value)}) =====")
        if isinstance(value, (dict, list)):
            text = json.dumps(value, ensure_ascii=False, indent=2)
            print(text[:12000])
            if len(text) > 12000:
                print(f"... truncated, total {len(text)} chars")
        else:
            print(value)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
