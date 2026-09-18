#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成「fafu课程表」应用图标（蓝白纯色风格）

产出：
  assets/icon/app_icon.png     1024x1024 完整图标（蓝底）
  assets/icon/app_icon_fg.png  1024x1024 自适应图标前景（透明底，图形居中留安全区）
"""
import os
from PIL import Image, ImageDraw

BLUE = (21, 101, 192, 255)       # #1565C0 主蓝
BLUE_DARK = (13, 71, 161, 255)   # #0D47A1
WHITE = (255, 255, 255, 255)
LIGHT = (200, 223, 248, 255)     # 浅蓝
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "icon")
os.makedirs(OUT, exist_ok=True)

S = 1024


def rounded(draw, box, r, fill):
    draw.rounded_rectangle(box, radius=r, fill=fill)


def draw_calendar(img, scale=1.0, center=True):
    """在 img 上绘制白色日历 + 学士帽"""
    d = ImageDraw.Draw(img)
    w, h = img.size
    cx, cy = w // 2, h // 2

    # 日历主体尺寸
    bw, bh = int(430 * scale), int(400 * scale)
    x0, y0 = cx - bw // 2, cy - bh // 2 + int(28 * scale)
    x1, y1 = x0 + bw, y0 + bh
    rad = int(46 * scale)

    # 阴影（浅蓝）
    rounded(d, (x0 + 10, y0 + 14, x1 + 10, y1 + 14), rad, (10, 60, 130, 90))
    # 主体
    rounded(d, (x0, y0, x1, y1), rad, WHITE)
    # 顶部蓝色标题条
    hh = int(96 * scale)
    rounded(d, (x0, y0, x1, y0 + hh), rad, BLUE)
    d.rectangle((x0, y0 + hh - rad, x1, y0 + hh), fill=BLUE)

    # 两个挂环（贴在标题条上沿）
    for dx in (-1, 1):
        rx = cx + dx * int(120 * scale)
        d.rounded_rectangle(
            (rx - int(13 * scale), y0 - int(26 * scale),
             rx + int(13 * scale), y0 + int(26 * scale)),
            radius=int(13 * scale), fill=WHITE)

    # 标题条里的三个小白点
    for i in (-1, 0, 1):
        px = cx + i * int(58 * scale)
        d.ellipse((px - int(11 * scale), y0 + hh // 2 - int(11 * scale),
                   px + int(11 * scale), y0 + hh // 2 + int(11 * scale)), fill=WHITE)

    # 课程格子（浅蓝小方块，其中一块用主蓝高亮）
    pad = int(34 * scale)
    gx0, gy0 = x0 + pad, y0 + hh + pad
    gx1, gy1 = x1 - pad, y1 - pad
    cols, rows = 4, 3
    gap = int(14 * scale)
    cw = (gx1 - gx0 - gap * (cols - 1)) // cols
    ch = (gy1 - gy0 - gap * (rows - 1)) // rows
    highlight = (1, 1)
    for r in range(rows):
        for c in range(cols):
            bx0 = gx0 + c * (cw + gap)
            by0 = gy0 + r * (ch + gap)
            color = BLUE if (c, r) == highlight else LIGHT
            rounded(d, (bx0, by0, bx0 + cw, by0 + ch), int(9 * scale), color)

    # 学士帽（主体上方，居中）
    cap_cy = y0 - int(126 * scale)
    hw = int(150 * scale)
    hh2 = int(46 * scale)
    d.polygon([(cx, cap_cy - hh2), (cx + hw, cap_cy),
               (cx, cap_cy + hh2), (cx - hw, cap_cy)], fill=WHITE)
    # 帽穗
    d.line((cx + hw - int(14 * scale), cap_cy, cx + hw + int(18 * scale),
            cap_cy + int(96 * scale)), fill=WHITE, width=int(11 * scale))
    d.ellipse((cx + hw + int(6 * scale), cap_cy + int(86 * scale),
               cx + hw + int(32 * scale), cap_cy + int(112 * scale)), fill=WHITE)


# 1) 完整图标：蓝底
base = Image.new("RGBA", (S, S), BLUE)
draw_calendar(base, scale=1.0)
base.save(os.path.join(OUT, "app_icon.png"))

# 2) 自适应前景：透明底，图形缩放至安全区（约 66%）
fg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
draw_calendar(layer, scale=1.0)
small = layer.resize((int(S * 0.60), int(S * 0.60)), Image.LANCZOS)
fg.paste(small, ((S - small.width) // 2, (S - small.height) // 2), small)
fg.save(os.path.join(OUT, "app_icon_fg.png"))

# 3) 启动图用的中心 logo
base.resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, "app_icon_512.png"))

print("icon written to", OUT)
for f in sorted(os.listdir(OUT)):
    p = os.path.join(OUT, f)
    print("  ", f, os.path.getsize(p), "bytes")
