"""Find the pclntab symbol containing a virtual address."""

import bisect
import sys


def load(path):
    rows = []
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3:
                continue
            try:
                address = int(parts[0], 0)
                size = int(parts[1], 0)
            except ValueError:
                continue
            rows.append((address, size, parts[2]))
    rows.sort()
    return rows


def main():
    if len(sys.argv) < 3:
        print("usage: symbol_at.py <syms.tsv> <va> [va ...]")
        return 2
    rows = load(sys.argv[1])
    starts = [row[0] for row in rows]
    for raw in sys.argv[2:]:
        va = int(raw, 0)
        index = bisect.bisect_right(starts, va) - 1
        if index < 0:
            print(f"{va:#x}\tnot found")
            continue
        address, size, name = rows[index]
        offset = va - address
        inside = offset < size if size else True
        print(
            f"{va:#x}\t{name}\tentry={address:#x}\tsize={size:#x}\t"
            f"offset={offset:#x}\t{'inside' if inside else 'after'}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
