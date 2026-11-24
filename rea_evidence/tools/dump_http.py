"""Dump HTTP request text blocks from a running process (read-only).

Usage: python dump_http.py <pid> [keyword ...]
Scans readable committed regions with ReadProcessMemory and prints printable
context around each keyword. Default keywords focus on Muyu's Huawei gateway.
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
        print(__doc__)
        return 2
    keywords = sys.argv[2:] or [
        "HTTP/1.1",
        "Digest username=",
        "favorite/simple/all",
        "page/detail/all",
        "loginex",
    ]
    encoded = [k.encode() for k in keywords]
    handle = k32.OpenProcess(0x0010 | 0x0400, False, pid)
    if not handle:
        print("OpenProcess failed", ctypes.get_last_error())
        return 1
    mbi = MBI()
    address = 0
    seen = set()
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
                    data = buffer.raw[: read.value]
                    low = data.lower()
                    for key, needle in zip(keywords, encoded):
                        start = 0
                        while True:
                            index = low.find(needle.lower(), start)
                            if index < 0:
                                break
                            start = index + 1
                            ctx = data[max(0, index - 40) : index + 900]
                            text = re.sub(rb"[^\x20-\x7e\r\n\t]", b".", ctx).decode(
                                "ascii", "replace"
                            )
                            signature = text[:160]
                            if signature in seen:
                                continue
                            seen.add(signature)
                            print(f"===== {key} @0x{address + offset + index:X} =====")
                            print(text)
                            print()
                offset += amount
        address += size
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
