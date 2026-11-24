"""Find likely Go function prologues near pclntab symbol addresses.

Usage: python find_entries.py <exe> <syms.tsv> [max_symbols]
Scans +/- 64 bytes around each symbol for common amd64 Go stack-check
prologues and prints candidate offsets.
"""

import struct
import sys


PATTERNS = {
    "cmp-sp-r14": bytes.fromhex("493b6610"),
    "mov-r14-stack": bytes.fromhex("4c8b742410"),
    "push-rbp": bytes.fromhex("55"),
    "sub-rsp-imm8": bytes.fromhex("4883ec"),
    "sub-rsp-imm32": bytes.fromhex("4881ec"),
    "lea-rsp": bytes.fromhex("488d6424"),
}


def load_sections(path):
    with open(path, "rb") as handle:
        data = handle.read()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    count = struct.unpack_from("<H", data, pe + 6)[0]
    opt_size = struct.unpack_from("<H", data, pe + 20)[0]
    opt = pe + 24
    image_base = struct.unpack_from("<Q", data, opt + 24)[0]
    table = opt + opt_size
    sections = []
    for i in range(count):
        off = table + i * 40
        vsize, vaddr, raw_size, raw_ptr = struct.unpack_from("<IIII", data, off + 8)
        sections.append((vaddr, max(vsize, raw_size), raw_ptr, raw_size))
    return data, image_base, sections


def read_bytes(data, image_base, sections, va, length):
    rva = va - image_base
    for vaddr, size, raw_ptr, raw_size in sections:
        if vaddr <= rva < vaddr + size:
            offset = raw_ptr + (rva - vaddr)
            return data[offset : offset + length]
    return b""


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    exe, syms = sys.argv[1], sys.argv[2]
    limit = int(sys.argv[3]) if len(sys.argv) > 3 else 30
    data, image_base, sections = load_sections(exe)
    printed = 0
    with open(syms, encoding="utf-8") as handle:
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3:
                continue
            name = parts[2]
            if not name.startswith("muyu.local/desktop/internal/gateway"):
                continue
            va = int(parts[0], 0)
            window = read_bytes(data, image_base, sections, va - 64, 128)
            hits = []
            for label, pattern in PATTERNS.items():
                start = 0
                while True:
                    index = window.find(pattern, start)
                    if index < 0:
                        break
                    hits.append((index - 64, label))
                    start = index + 1
            hits.sort()
            print(f"{name}\t{va:#x}\t{hits[:6]}")
            printed += 1
            if printed >= limit:
                break
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
