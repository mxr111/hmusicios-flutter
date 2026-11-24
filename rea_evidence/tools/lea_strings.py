"""Extract string constants referenced by LEA in a function range.

Usage: python lea_strings.py <exe> <start-va> <stop-va> [objdump-path]
Runs objdump, collects every `lea ... # 0xADDR`, and prints printable text at
that VA. Useful for Go string tables where constants are packed back-to-back.
"""

import re
import struct
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def load_sections(path):
    with open(path, "rb") as handle:
        data = handle.read()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    count = struct.unpack_from("<H", data, pe + 6)[0]
    opt_size = struct.unpack_from("<H", data, pe + 20)[0]
    opt = pe + 24
    image_base = struct.unpack_from("<Q", data, opt + 24)[0]
    table = opt + opt_size
    result = []
    for i in range(count):
        off = table + i * 40
        vsize, vaddr, raw_size, raw_ptr = struct.unpack_from("<IIII", data, off + 8)
        result.append((vaddr, max(vsize, raw_size), raw_ptr, raw_size))
    return data, image_base, result


def read_text(data, image_base, sections, va, limit=120):
    rva = va - image_base
    for vaddr, size, raw_ptr, raw_size in sections:
        if vaddr <= rva < vaddr + size:
            offset = raw_ptr + (rva - vaddr)
            raw = data[offset : offset + limit]
            text = raw.decode("utf-8", "replace")
            out = []
            for ch in text:
                code = ord(ch)
                if ch in "\n\t" or (0x20 <= code < 0x7F) or code >= 0xA0:
                    out.append(ch)
                else:
                    break
            return "".join(out)
    return ""


def read_exact(data, image_base, sections, va, length):
    rva = va - image_base
    for vaddr, size, raw_ptr, raw_size in sections:
        if vaddr <= rva < vaddr + size:
            offset = raw_ptr + (rva - vaddr)
            return data[offset : offset + length]
    return b""


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    exe = sys.argv[1]
    start = int(sys.argv[2], 0)
    stop = int(sys.argv[3], 0)
    objdump = sys.argv[4] if len(sys.argv) > 4 else r"C:\Dev\mingw64\bin\objdump.exe"
    data, image_base, sections = load_sections(exe)
    output = subprocess.run(
        [
            objdump,
            "-d",
            f"--start-address={hex(start)}",
            f"--stop-address={hex(stop)}",
            exe,
        ],
        capture_output=True,
        text=True,
        errors="replace",
        check=False,
    ).stdout
    pattern = re.compile(r"lea\s+[^#]*#\s+0x([0-9a-f]+)", re.IGNORECASE)
    length_pattern = re.compile(r"mov\s+\$0x([0-9a-f]+),", re.IGNORECASE)
    lines = output.splitlines()
    seen = set()
    for index, line in enumerate(lines):
        match = pattern.search(line)
        if not match:
            continue
        va = int(match.group(1), 16)
        if va in seen:
            continue
        seen.add(va)
        length = 0
        for probe in lines[index + 1 : index + 4]:
            length_match = length_pattern.search(probe)
            if length_match:
                length = int(length_match.group(1), 16)
                break
        if 0 < length <= 512:
            raw = read_exact(data, image_base, sections, va, length)
            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError:
                text = raw.decode("latin-1", "replace")
            print(f"{va:#x}\t{length}\t{text}")
        else:
            text = read_text(data, image_base, sections, va)
            if len(text) >= 2:
                print(f"{va:#x}\t?\t{text}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
