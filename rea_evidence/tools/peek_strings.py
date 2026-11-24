"""Print printable ASCII runs in a byte range of a PE, with file offsets.

Usage: python peek_strings.py <exe> <start> <length> [min_length]
Useful for inspecting packed Go string tables without guessing boundaries.
"""

import sys


def main() -> int:
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    path = sys.argv[1]
    start = int(sys.argv[2], 0)
    length = int(sys.argv[3], 0)
    minimum = int(sys.argv[4], 0) if len(sys.argv) > 4 else 3
    with open(path, "rb") as handle:
        data = handle.read()
    end = min(len(data), start + length)
    i = start
    while i < end:
        if 32 <= data[i] < 127:
            j = i
            while j < end and 32 <= data[j] < 127:
                j += 1
            if j - i >= minimum:
                print(f"{i}\t{j - i}\t{data[i:j].decode('ascii')}")
            i = j
        else:
            i += 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
