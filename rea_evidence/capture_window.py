"""REA runtime UI evidence: capture the running Muyu window.

Uses Win32 EnumWindows/GetWindowRect to locate the target PID's visible
windows, brings the largest one to front, and grabs it with Pillow.
"""
import ctypes
import ctypes.wintypes as w
import time
from pathlib import Path

from PIL import ImageGrab

PID = 2584
OUT_DIR = Path(__file__).resolve().parent

u = ctypes.WinDLL("user32", use_last_error=True)
EnumProc = ctypes.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)

u.EnumWindows.argtypes = [EnumProc, w.LPARAM]
u.EnumWindows.restype = w.BOOL
u.GetWindowThreadProcessId.argtypes = [w.HWND, ctypes.POINTER(w.DWORD)]
u.GetWindowThreadProcessId.restype = w.DWORD
u.IsWindowVisible.argtypes = [w.HWND]
u.IsWindowVisible.restype = w.BOOL
u.GetWindowTextLengthW.argtypes = [w.HWND]
u.GetWindowTextLengthW.restype = ctypes.c_int
u.GetWindowTextW.argtypes = [w.HWND, w.LPWSTR, ctypes.c_int]
u.GetWindowTextW.restype = ctypes.c_int
u.GetWindowRect.argtypes = [w.HWND, ctypes.POINTER(w.RECT)]
u.GetWindowRect.restype = w.BOOL
u.SetForegroundWindow.argtypes = [w.HWND]
u.SetForegroundWindow.restype = w.BOOL
u.ShowWindow.argtypes = [w.HWND, ctypes.c_int]
u.ShowWindow.restype = w.BOOL


def windows_of(pid):
    found = []

    def cb(hwnd, _):
        proc = w.DWORD()
        u.GetWindowThreadProcessId(hwnd, ctypes.byref(proc))
        if proc.value == pid and u.IsWindowVisible(hwnd):
            n = u.GetWindowTextLengthW(hwnd)
            buf = ctypes.create_unicode_buffer(n + 1)
            u.GetWindowTextW(hwnd, buf, n + 1)
            r = w.RECT()
            u.GetWindowRect(hwnd, ctypes.byref(r))
            found.append((hwnd, buf.value, (r.left, r.top, r.right, r.bottom)))
        return True

    u.EnumWindows(EnumProc(cb), 0)
    return found


wins = windows_of(PID)
print("windows:", len(wins))
for hwnd, title, rect in wins:
    print("  hwnd", hwnd, "title", repr(title), "rect", rect)

if not wins:
    raise SystemExit("no visible window for PID")

# 最大的可见窗口通常是主界面
hwnd, title, rect = max(wins, key=lambda x: (x[2][2] - x[2][0]) * (x[2][3] - x[2][1]))
u.ShowWindow(hwnd, 9)  # SW_RESTORE
u.SetForegroundWindow(hwnd)
time.sleep(0.8)

left, top, right, bottom = rect
left = max(0, left)
top = max(0, top)
img = ImageGrab.grab(bbox=(left, top, right, bottom), all_screens=True)
out = OUT_DIR / "muyu_window.png"
img.save(out)
print("saved", out, img.size)
