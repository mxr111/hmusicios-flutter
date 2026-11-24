"""Summarize Muyu 2.0.4 pclntab symbols by internal package."""

import collections
import re
import sys


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else "rea_evidence/_syms_204.tsv"
    counts = collections.Counter()
    total = 0
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3:
                continue
            total += 1
            name = parts[2]
            match = re.match(r"muyu\.local/desktop/internal/([^./]+)", name)
            if match:
                key = match.group(1)
            elif name.startswith("muyu.local/desktop."):
                key = "root"
            elif name.startswith("main."):
                key = "main"
            else:
                key = "stdlib/other"
            counts[key] += 1
    print("TOTAL", total)
    for key, value in counts.most_common(40):
        print(key, value)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
