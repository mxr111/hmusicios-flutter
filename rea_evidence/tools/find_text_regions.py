"""Find long contiguous text regions inside a binary and dump them.

Go apps that embed a JS/TS frontend (goja, mygo) keep the bundle as plain UTF-8
text in .rodata. This scans for long runs of printable text and writes each
region to <outdir>/region_<start>.txt for reading.

Usage: python find_text_regions.py <binary> <outdir> [min_region_bytes] [max_regions]
"""
import os
import sys


def is_text_byte(b: int) -> bool:
    return b in (9, 10, 13) or 0x20 <= b < 0x7F or b >= 0x80


def main() -> None:
    path, outdir = sys.argv[1], sys.argv[2]
    min_region = int(sys.argv[3]) if len(sys.argv) > 3 else 20000
    max_regions = int(sys.argv[4]) if len(sys.argv) > 4 else 40
    data = open(path, "rb").read()
    os.makedirs(outdir, exist_ok=True)

    regions = []
    n = len(data)
    i = 0
    step = 512
    while i < n:
        # sample a window; if heavily textual, expand
        if is_text_byte(data[i]):
            j = i
            bad = 0
            while j < n:
                c = data[j]
                if is_text_byte(c):
                    j += 1
                else:
                    bad += 1
                    j += 1
                    if bad > 32:
                        break
                if j - i > 64 * 1024 * 1024:
                    break
            if j - i >= min_region:
                regions.append((i, j))
            i = max(j, i + step)
        else:
            i += step

    regions.sort(key=lambda r: r[0] - r[1])  # largest first by negative length
    for start, end in regions[:max_regions]:
        chunk = data[start:end]
        try:
            text = chunk.decode("utf-8")
        except UnicodeDecodeError:
            text = chunk.decode("utf-8", "replace")
        out = os.path.join(outdir, f"region_{start:09d}_{end - start}.txt")
        with open(out, "w", encoding="utf-8") as f:
            f.write(text)
        print(f"{start}\t{end - start}\t{out}")
    print(f"regions={len(regions)}")


if __name__ == "__main__":
    main()
