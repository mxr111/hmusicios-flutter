"""Dump Go pclntab symbol table (name -> VA, size) for a Windows PE.

Adapted from go_sym_addr.py; adds function sizes derived from sorted entries.

Usage: python dump_symbols.py <exe> <out.tsv>
Output TSV: 0xVA<TAB>size<TAB>name  (include-private variants kept)
"""
import struct
import sys


def u32(d, o):
    return struct.unpack_from("<I", d, o)[0]


def u64(d, o):
    return struct.unpack_from("<Q", d, o)[0]


def i32(d, o):
    return struct.unpack_from("<i", d, o)[0]


def cstring(d, o):
    end = d.find(b"\0", o)
    return d[o:end].decode("utf-8", "replace")


def sections(d):
    pe = u32(d, 0x3C)
    assert d[pe:pe + 4] == b"PE\0\0", "not PE"
    coff = pe + 4
    nsec = struct.unpack_from("<H", d, coff + 2)[0]
    opt_size = struct.unpack_from("<H", d, coff + 16)[0]
    opt = coff + 20
    magic = struct.unpack_from("<H", d, opt)[0]
    image_base = u64(d, opt + 24) if magic == 0x20B else u32(d, opt + 28)
    raw = d[opt + opt_size: opt + opt_size + nsec * 40]
    return image_base, raw


def find_pclntab(d):
    pat = b"\xf1\xff\xff\xff\x00\x00\x01\x08"
    pos = 0
    while True:
        pos = d.find(pat, pos)
        if pos < 0:
            raise SystemExit("pclntab header not found")
        nfunc = u64(d, pos + 8)
        if 1000 < nfunc < 2000000 and u64(d, pos + 24) < 0x100000:
            return pos
        pos += 1


def parse(d):
    image_base, _raw = sections(d)
    tab = find_pclntab(d)
    nfunc = u64(d, tab + 8)
    text_start = u64(d, tab + 24)
    funcname_off = u64(d, tab + 32)
    pcln_off = u64(d, tab + 64)
    out = []
    for i in range(nfunc):
        entry = u32(d, tab + pcln_off + i * 8)
        func_off = u32(d, tab + pcln_off + i * 8 + 4)
        if func_off == 0 or func_off + 8 > len(d) - tab:
            continue
        name_off = i32(d, tab + pcln_off + func_off + 4)
        if name_off < 0 or tab + funcname_off + name_off >= len(d):
            continue
        sym = cstring(d, tab + funcname_off + name_off)
        if sym:
            out.append((image_base + text_start + entry, sym))
    out.sort()
    return out


def main() -> None:
    path, out_path = sys.argv[1], sys.argv[2]
    d = open(path, "rb").read()
    syms = parse(d)
    with open(out_path, "w", encoding="utf-8") as f:
        for idx, (addr, name) in enumerate(syms):
            size = (syms[idx + 1][0] - addr) if idx + 1 < len(syms) else 0
            f.write(f"0x{addr:x}\t{size}\t{name}\n")
    print(f"symbols={len(syms)} -> {out_path}")


if __name__ == "__main__":
    main()
