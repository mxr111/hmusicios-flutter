"""把用户提供的渐变音符图标按 RGB 抠掉黑边，生成可用的 App 图标。

做法：
1. RGB 阈值找出近黑像素（max(R,G,B) < THRESHOLD）；
2. 从图像边界做泛洪填充，只标记「与外部相连」的黑边，
   避免把图标内部本来就偏深的蓝紫暗部误抠掉；
3. 生成 alpha 通道（透明版），并对边缘做羽化；
4. iOS App 图标不允许透明，所以把透明区域合成到同色系的
   顶青蓝→底粉紫渐变背景上，输出不透明 1024×1024 RGB PNG。

用法：
  python scripts/process_icon.py [源图路径]
"""
import sys
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE = Path(
    r"C:/Data/xwechat_files/wxid_6kxbbz4qbmya21_6f8e/temp/RWTemp/"
    r"2026-11/b8cb3096e7ed5d7a9bc411ccdd1cd658/e85434d41bd9396863f8995a7ac4778a.jpg"
)
OUT = ROOT / "assets" / "app_icon.png"
CUTOUT = ROOT / "assets" / "app_icon_cutout.png"

THRESHOLD = 34
TOP = (15, 58, 171)      # 顶边中点采样：青蓝
BOTTOM = (106, 10, 208)  # 底边中点采样：紫粉


def external_black_mask(src: Image.Image) -> bytes:
    w, h = src.size
    px = src.load()

    dark = bytearray(w * h)
    for y in range(h):
        row = y * w
        for x in range(w):
            r, g, b = px[x, y]
            if max(r, g, b) < THRESHOLD:
                dark[row + x] = 1

    marked = bytearray(w * h)
    queue = deque()

    def seed(x, y):
        i = y * w + x
        if dark[i] and not marked[i]:
            marked[i] = 1
            queue.append((x, y))

    for x in range(w):
        seed(x, 0)
        seed(x, h - 1)
    for y in range(h):
        seed(0, y)
        seed(w - 1, y)

    while queue:
        x, y = queue.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h:
                i = ny * w + nx
                if dark[i] and not marked[i]:
                    marked[i] = 1
                    queue.append((nx, ny))

    # alpha：255 = 保留原图（彩色区），0 = 外部黑边（替换为渐变背景）
    return bytes(0 if marked[i] else 255 for i in range(w * h))


def gradient_background(size):
    w, h = size
    strip = Image.new("RGB", (1, h))
    p = strip.load()
    for y in range(h):
        t = y / (h - 1)
        p[0, y] = tuple(
            int(TOP[c] * (1 - t) + BOTTOM[c] * t) for c in range(3)
        )
    return strip.resize((w, h), Image.BICUBIC)


def main():
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SOURCE
    if not source.exists():
        raise SystemExit(f"源图不存在：{source}")

    src = Image.open(source).convert("RGB")
    w, h = src.size
    keep = external_black_mask(src)

    alpha = Image.frombytes("L", (w, h), keep)
    alpha = alpha.filter(ImageFilter.GaussianBlur(1.4))  # 羽化，消除 JPEG 硬边

    # 透明版（供需要透明通道的场景使用）
    cutout = src.convert("RGBA")
    cutout.putalpha(alpha)
    cutout.save(CUTOUT, "PNG", optimize=True)

    # 不透明版：黑边区域用同色系渐变补齐
    bg = gradient_background((w, h))
    composed = Image.composite(src, bg, alpha)
    icon = composed.resize((1024, 1024), Image.LANCZOS).convert("RGB")
    icon.save(OUT, "PNG", optimize=True)

    print("source", source, src.size)
    print("removed black edge pixels:", keep.count(0))
    print("corner after:", icon.getpixel((2, 2)), icon.getpixel((1021, 1021)))
    print("center after:", icon.getpixel((512, 512)))
    print("wrote", OUT, OUT.stat().st_size, "bytes")
    print("wrote", CUTOUT, CUTOUT.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
