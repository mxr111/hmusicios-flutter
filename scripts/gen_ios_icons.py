"""把沐语 App 图标（REA 配色：深色底 + 沐语红环 + 白色「沐」字）
按 ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json 生成所有尺寸。

源图默认取 ../MuyuIOS/.../AppIcon-1024.png；也接受命令行传入路径。
"""
import json
import shutil
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ASSET = ROOT / "assets" / "app_icon.png"
ICONSET = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"

source = Path(sys.argv[1]) if len(sys.argv) > 1 else (
    ROOT / "assets" / "app_icon.png"
)
if not source.exists():
    raise SystemExit(f"source icon not found: {source}")

ASSET.parent.mkdir(parents=True, exist_ok=True)
if source.resolve() != ASSET.resolve():
    shutil.copyfile(source, ASSET)
base = Image.open(ASSET).convert("RGB")
print("source", source, base.size)

contents = json.loads((ICONSET / "Contents.json").read_text(encoding="utf-8"))
for entry in contents["images"]:
    filename = entry.get("filename")
    if not filename:
        continue
    w, h = (float(v) for v in entry["size"].split("x"))
    scale = float(entry["scale"].replace("x", ""))
    px = int(round(w * scale))
    resized = base.resize((px, px), Image.LANCZOS)
    out = ICONSET / filename
    resized.save(out, "PNG", optimize=True)
    print("  %-38s %4d x %4d" % (filename, px, px))
print("done")
