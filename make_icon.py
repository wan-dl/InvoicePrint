#!/usr/bin/env python3
"""生成 发票合并打印 的 App 图标 (AppIcon.icns)。"""
import os
import subprocess
from PIL import Image, ImageDraw, ImageFilter

S = 1024
ROOT = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(ROOT, "Assets")
os.makedirs(ASSETS, exist_ok=True)

TOP = (70, 138, 255)
BOT = (32, 62, 196)


def gradient(size):
    img = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        c = tuple(int(TOP[i] + (BOT[i] - TOP[i]) * t) for i in range(3))
        d.line([(0, y), (size, y)], fill=c)
    return img


def squircle_mask(size, margin, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        [margin, margin, size - margin, size - margin], radius=radius, fill=255
    )
    return m


def build_icon():
    m = 100
    radius = 190
    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    icon.paste(gradient(S), (0, 0), squircle_mask(S, m, radius))

    d = ImageDraw.Draw(icon)

    # 纸张阴影
    page_w, page_h = 500, 620
    px = (S - page_w) // 2
    py = (S - page_h) // 2 - 6
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [px, py + 14, px + page_w, py + page_h + 14], radius=54, fill=(0, 0, 0, 90)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(26))
    icon.alpha_composite(shadow)

    # 纸张
    d.rounded_rectangle([px, py, px + page_w, py + page_h], radius=54, fill=(255, 255, 255, 255))

    # 顶部标题条
    d.rounded_rectangle(
        [px + 46, py + 50, px + page_w - 46, py + 92], radius=21, fill=(70, 138, 255, 255)
    )

    # 2x3 宫格（代表合并后的一张纸）
    cols, rows = 2, 3
    gx, gy = 46, 44
    grid_top = py + 132
    cell_w = (page_w - gx * 2 - gy * (cols - 1)) / cols
    cell_h = (page_h - (grid_top - py) - gx - gy * (rows - 1)) / rows
    palette = [
        (219, 232, 255, 255),
        (205, 224, 255, 255),
        (219, 232, 255, 255),
        (205, 224, 255, 255),
        (219, 232, 255, 255),
        (205, 224, 255, 255),
    ]
    k = 0
    for r in range(rows):
        for c in range(cols):
            x0 = px + gx + c * (cell_w + gy)
            y0 = grid_top + r * (cell_h + gy)
            d.rounded_rectangle(
                [x0, y0, x0 + cell_w, y0 + cell_h], radius=20, fill=palette[k % len(palette)]
            )
            # 卡片内的文字线条
            lx0 = x0 + 18
            for li in range(3):
                ly = y0 + 22 + li * 22
                lw = (cell_w - 36) * (0.85 if li == 0 else 0.6)
                d.rounded_rectangle([lx0, ly, lx0 + lw, ly + 8], radius=4, fill=(150, 178, 235, 255))
            k += 1

    # 右下角印章
    seal_r = 58
    sx = px + page_w - 92
    sy = py + page_h - 92
    d.ellipse([sx - seal_r, sy - seal_r, sx + seal_r, sy + seal_r], fill=(228, 66, 66, 255))
    d.ellipse([sx - seal_r + 12, sy - seal_r + 12, sx + seal_r - 12, sy + seal_r - 12],
              outline=(255, 255, 255, 255), width=6)

    return icon


def main():
    icon = build_icon()
    master = os.path.join(ASSETS, "icon_master.png")
    icon.save(master)

    iconset = os.path.join(ASSETS, "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)
    specs = [
        (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
    ]
    for size, name in specs:
        icon.resize((size, size), Image.LANCZOS).save(os.path.join(iconset, name))

    icns = os.path.join(ASSETS, "AppIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", icns], check=True)
    print("生成:", icns)


if __name__ == "__main__":
    main()
