"""Reconstruct Go string literals from a PE by scanning rodata for {ptr,len} headers.

Go stores string literals inline in a blob and references each as a 16-byte
{dataPtr, len} pair. Scanning 8-byte boundaries for a pointer into a readable
section followed by a plausible length recovers the exact literals instead of
merged runs.

Usage: python extract_go_strings.py <exe> <out.tsv>
Output: dataoffset<TAB>len<TAB>text
"""
import struct
import sys


def sections(d):
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    assert d[pe:pe + 4] == b"PE\0\0", "not PE"
    coff = pe + 4
    nsec = struct.unpack_from("<H", d, coff + 2)[0]
    opt_size = struct.unpack_from("<H", d, coff + 16)[0]
    opt = coff + 20
    magic = struct.unpack_from("<H", d, opt)[0]
    image_base = struct.unpack_from("<Q", d, opt + 24)[0] if magic == 0x20B else struct.unpack_from("<I", d, opt + 28)[0]
    raw = d[opt + opt_size: opt + opt_size + nsec * 40]
    out = []
    for i in range(nsec):
        name = raw[i * 40:i * 40 + 8].rstrip(b"\0").decode("ascii", "replace")
        vsize, vaddr, rawsize, rawptr = struct.unpack_from("<IIII", raw, i * 40 + 8)
        out.append({"name": name, "va": vaddr, "vsize": vsize, "raw": rawptr, "rawsize": rawsize})
    return image_base, out


def main() -> None:
    path, out_path = sys.argv[1], sys.argv[2]
    d = open(path, "rb").read()
    image_base, secs = sections(d)

    # VA -> file offset mapping (only sections whose raw data exists)
    def va_to_off(va):
        for s in secs:
            if s["rawsize"] and s["va"] <= va < s["va"] + s["rawsize"]:
                return s["raw"] + (va - s["va"])
        return None

    def off_to_va(off):
        for s in secs:
            if s["rawsize"] and s["raw"] <= off < s["raw"] + s["rawsize"]:
                return s["va"] + (off - s["raw"])
        return None

    # Candidate data sections: those that hold the literal blob
    data_secs = [s for s in secs if s["rawsize"] and s["name"] in ("rdata", ".rdata", "data", ".data", "rodata")]
    # scan window: sections likely holding (ptr,len) headers
    hdr_secs = [s for s in secs if s["rawsize"] and s["name"] in ("rdata", ".rdata", "data", ".data")]

    found = {}
    for hs in hdr_secs:
        start = hs["raw"]
        end = start + hs["rawsize"] - 16
        off = start
        while off < end:
            ptr = struct.unpack_from("<Q", d, off)[0]
            ln = struct.unpack_from("<Q", d, off + 8)[0]
            if 1 <= ln <= 4000:
                target = va_to_off(ptr - image_base) if ptr >= image_base else None
                if target is not None and target + ln <= len(d):
                    chunk = d[target:target + ln]
                    if b"\0" not in chunk:
                        try:
                            text = chunk.decode("utf-8")
                        except UnicodeDecodeError:
                            off += 8
                            continue
                        if text.isprintable() or any("\u4e00" <= ch <= "\u9fff" for ch in text):
                            found[(target, ln)] = text
            off += 8

    with open(out_path, "w", encoding="utf-8") as f:
        for (target, ln), text in sorted(found.items()):
            esc = text.replace("\t", "\\t").replace("\n", "\\n").replace("\r", "\\r")
            f.write(f"{target}\t{ln}\t{esc}\n")
    print(f"literals={len(found)} -> {out_path}")


if __name__ == "__main__":
    main()
