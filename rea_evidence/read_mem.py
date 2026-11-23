"""REA runtime observation: read printable strings from the running Muyu process.

Uses ctypes + Win32 ReadProcessMemory (no Add-Type / no admin required).
Goal: recover real request URLs, headers and session fields from Go heap.
"""
import ctypes
import ctypes.wintypes as w
import re
import sys

PID = int(sys.argv[1]) if len(sys.argv) > 1 else 2584

k32 = ctypes.WinDLL("kernel32", use_last_error=True)


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


OpenProcess = k32.OpenProcess
OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]
OpenProcess.restype = w.HANDLE
ReadProcessMemory = k32.ReadProcessMemory
ReadProcessMemory.argtypes = [w.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                              ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
ReadProcessMemory.restype = w.BOOL
VirtualQueryEx = k32.VirtualQueryEx
VirtualQueryEx.argtypes = [w.HANDLE, ctypes.c_void_p, ctypes.POINTER(MBI), ctypes.c_size_t]
VirtualQueryEx.restype = ctypes.c_size_t

h = OpenProcess(0x0010 | 0x0400, False, PID)
if not h:
    print("OpenProcess FAILED", ctypes.get_last_error())
    sys.exit(1)
print("OpenProcess OK handle", h)

keywords = [b"api-drcn", b"music-operation-service", b"pageType=7",
            b"x-hw-", b"HBN-AL00", b"dbankcloud", b"Authorization",
            b"signature", b"Bearer", b"contentCode", b"bycontentcode"]
hits = []
addr = 0
MAX_ADDR = 0x7FFFFFFFFFFF
mbi = MBI()
total = 0
regions = 0
while addr < MAX_ADDR:
    r = VirtualQueryEx(h, ctypes.c_void_p(addr), ctypes.byref(mbi), ctypes.sizeof(mbi))
    if r == 0:
        break
    size = mbi.RegionSize or 0
    if size == 0:
        break
    protect = mbi.Protect
    readable = bool(protect & 0x06) and not bool(protect & 0x100)
    if mbi.State == 0x1000 and readable and size <= 64 * 1024 * 1024:
        regions += 1
        off = 0
        chunk = 1024 * 1024
        while off < size:
            n = min(chunk, size - off)
            buf = ctypes.create_string_buffer(n)
            read = ctypes.c_size_t(0)
            ok = ReadProcessMemory(h, ctypes.c_void_p(addr + off), buf, n,
                                   ctypes.byref(read))
            if ok and read.value:
                data = buf.raw[:read.value]
                total += read.value
                low = data.lower()
                for k in keywords:
                    i = low.find(k.lower())
                    if i >= 0:
                        ctx = data[max(0, i - 110):i + 230]
                        ctx = re.sub(rb"[^\x20-\x7e]", b".", ctx).decode("ascii", "replace")
                        hits.append((k.decode(), addr + off + i, ctx))
            off += n
    addr += size

print("regions", regions, "scanned_bytes", total, "hits", len(hits))
seen = set()
shown = 0
for key, loc, ctx in hits:
    sig = ctx[:90]
    if sig in seen:
        continue
    seen.add(sig)
    print("%s @0x%X :: %s" % (key, loc, ctx))
    shown += 1
    if shown >= 70:
        break
