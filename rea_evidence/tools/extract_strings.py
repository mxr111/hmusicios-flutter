"""Extract printable ASCII/UTF-8 runs from a PE (or any) binary.

Usage:
  python extract_strings.py <binary> <out.tsv> [minlen]

Output TSV: offset<TAB>length<TAB>text   (text has tabs/newlines escaped)
Only runs that decode as UTF-8 without replacement chars are kept, so Chinese
literals survive intact when they are stored contiguously.
"""
import sys

def main() -> None:
    path = sys.argv[1]
    out = sys.argv[2]
    minlen = int(sys.argv[3]) if len(sys.argv) > 3 else 4
    data = open(path, "rb").read()
    n = len(data)
    rows = []
    i = 0
    while i < n:
        b = data[i]
        # start candidates: printable ASCII or UTF-8 multi-byte lead
        if 0x20 <= b < 0x7F or b >= 0xC0:
            j = i
            while j < n:
                c = data[j]
                if 0x20 <= c < 0x7F or c >= 0x80:
                    j += 1
                else:
                    break
            if j - i >= minlen:
                chunk = data[i:j]
                try:
                    text = chunk.decode("utf-8")
                except UnicodeDecodeError:
                    text = None
                if text is not None and any(0x20 <= x < 0x7F for x in chunk):
                    rows.append((i, j - i, text))
            i = j
        else:
            i += 1
    with open(out, "w", encoding="utf-8") as f:
        for off, ln, text in rows:
            esc = text.replace("\t", "\\t").replace("\n", "\\n").replace("\r", "\\r")
            f.write(f"{off}\t{ln}\t{esc}\n")
    print(f"strings={len(rows)} -> {out}")


if __name__ == "__main__":
    main()
