"""Read bytes at a PE virtual address (image base + RVA).

Usage: python read_va.py <exe> <va> <length>
Prints hex and the UTF-8/ASCII printable interpretation.
"""

import struct
import sys


def sections(path):
    with open(path, "rb") as handle:
        data = handle.read()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    machine, count = struct.unpack_from("<HH", data, pe + 4)
    opt_size = struct.unpack_from("<H", data, pe + 20)[0]
    opt = pe + 24
    image_base = struct.unpack_from("<Q", data, opt + 24)[0]
    table = opt + opt_size
    result = []
    for i in range(count):
        off = table + i * 40
        name = data[off : off + 8].rstrip(b"\0").decode("ascii", "replace")
        vsize, vaddr, raw_size, raw_ptr = struct.unpack_from("<IIII", data, off + 8)
        result.append((name, vaddr, vsize, raw_ptr, raw_size))
    return data, image_base, result


def read_va(path, va, length):
    data, image_base, table = sections(path)
    rva = va - image_base
    for name, vaddr, vsize, raw_ptr, raw_size in table:
        if vaddr <= rva < vaddr + max(vsize, raw_size):
            offset = raw_ptr + (rva - vaddr)
            return data[offset : offset + length]
    raise SystemExit(f"VA {va:#x} not mapped")


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    va = int(sys.argv[2], 0)
    length = int(sys.argv[3], 0)
    raw = read_va(sys.argv[1], va, length)
    print(f"VA {va:#x} len {len(raw)}")
    print("hex:", raw.hex())
    text = raw.decode("utf-8", "replace")
    printable = "".join(c if c == "\n" or c == "\t" or 0x20 <= ord(c) < 0x7F else "." for c in text)
    print("text:", printable)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
