"""从 Windows Go PE 的 pclntab 解析函数名 -> 虚拟地址（Go 1.20+，magic 0xFFFFFFF1）。

用法: python go_sym_addr.py <exe> [关键字...]
"""
import struct
import sys


def u32(d, o):
    return struct.unpack_from('<I', d, o)[0]


def u64(d, o):
    return struct.unpack_from('<Q', d, o)[0]


def i32(d, o):
    return struct.unpack_from('<i', d, o)[0]


def cstring(d, o):
    end = d.find(b'\0', o)
    return d[o:end].decode('utf-8', 'replace')


def sections(d):
    pe = u32(d, 0x3c)
    assert d[pe:pe + 4] == b'PE\0\0', 'not PE'
    coff = pe + 4
    nsec = struct.unpack_from('<H', d, coff + 2)[0]
    opt_size = struct.unpack_from('<H', d, coff + 16)[0]
    opt = coff + 20
    magic = struct.unpack_from('<H', d, opt)[0]
    image_base = u64(d, opt + 24) if magic == 0x20b else u32(d, opt + 28)
    return image_base, [d[opt + opt_size + i * 40:opt + opt_size + (i + 1) * 40]
                        for i in range(nsec)]


def find_pclntab(d):
    # Go 1.20+ header: magic, 00 00, minLC=01, ptrSize=08
    pat = b'\xf1\xff\xff\xff\x00\x00\x01\x08'
    pos = 0
    while True:
        pos = d.find(pat, pos)
        if pos < 0:
            raise SystemExit('pclntab header not found')
        nfunc = u64(d, pos + 8)
        if 1000 < nfunc < 2000000 and u64(d, pos + 24) < 0x100000:
            return pos
        pos += 1


def parse_symbols(d):
    image_base, _secs = sections(d)
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
            out.append((sym, image_base + text_start + entry))
    return out


def main():
    path = sys.argv[1]
    kws = sys.argv[2:]
    d = open(path, 'rb').read()
    syms = parse_symbols(d)
    print('symbols', len(syms), file=sys.stderr)
    for name, addr in syms:
        if not kws or any(k.lower() in name.lower() for k in kws):
            print(f'0x{addr:x}\t{name}')


if __name__ == '__main__':
    main()
