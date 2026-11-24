"""Extract the newest Huawei music token from a running Muyu process (read-only).

Usage: python extract_token.py <pid>
Prints only the token on stdout; diagnostics go to stderr.
"""

import ctypes
import ctypes.wintypes as w
import re
import sys


class MBI(ctypes.Structure):
    _fields_ = [
        ("BaseAddress", ctypes.c_void_p),
        ("AllocationBase", ctypes.c_void_p),
        ("AllocationProtect", w.DWORD),
        ("RegionSize", ctypes.c_size_t),
        ("State", w.DWORD),
        ("Protect", w.DWORD),
        ("Type", w.DWORD),
    ]


k32 = ctypes.WinDLL("kernel32", use_last_error=True)
k32.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]
k32.OpenProcess.restype = w.HANDLE
k32.ReadProcessMemory.argtypes = [
    w.HANDLE,
    ctypes.c_void_p,
    ctypes.c_void_p,
    ctypes.c_size_t,
    ctypes.POINTER(ctypes.c_size_t),
]
k32.ReadProcessMemory.restype = w.BOOL
k32.VirtualQueryEx.argtypes = [w.HANDLE, ctypes.c_void_p, ctypes.POINTER(MBI), ctypes.c_size_t]
k32.VirtualQueryEx.restype = ctypes.c_size_t


def main():
    pid = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    if pid <= 0:
        print(__doc__, file=sys.stderr)
        return 2
    handle = k32.OpenProcess(0x0010 | 0x0400, False, pid)
    if not handle:
        print("OpenProcess failed", ctypes.get_last_error(), file=sys.stderr)
        return 1
    mbi = MBI()
    address = 0
    found = []
    pattern = re.compile(rb"Authorization: Digest[^\r\n]*?token=([^\r\n,]+)")
    while address < 0x7FFFFFFFFFFF:
        if k32.VirtualQueryEx(handle, ctypes.c_void_p(address), ctypes.byref(mbi), ctypes.sizeof(mbi)) == 0:
            break
        size = mbi.RegionSize or 0
        if size == 0:
            break
        readable = bool(mbi.Protect & 0x06) and not bool(mbi.Protect & 0x100)
        if mbi.State == 0x1000 and readable and size <= 64 * 1024 * 1024:
            chunk = 1024 * 1024
            offset = 0
            while offset < size:
                amount = min(chunk, size - offset)
                buffer = ctypes.create_string_buffer(amount)
                read = ctypes.c_size_t(0)
                if k32.ReadProcessMemory(
                    handle,
                    ctypes.c_void_p(address + offset),
                    buffer,
                    amount,
                    ctypes.byref(read),
                ) and read.value:
                    for match in pattern.finditer(buffer.raw[: read.value]):
                        token = match.group(1).decode("ascii", "ignore").strip()
                        if token.startswith("security:"):
                            found.append(token)
                offset += amount
        address += size
    if not found:
        print("token not found", file=sys.stderr)
        return 1
    if "--all" in sys.argv:
        seen = set()
        for token in reversed(found):
            if token in seen:
                continue
            seen.add(token)
            print(token)
        return 0
    print(found[-1])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
