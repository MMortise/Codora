#!/usr/bin/env python3
"""Codora 品牌资产生成器 —— 单一矢量源，导出全部平台图标。

改 logo 只改这个文件，然后重跑：  python3 tool/brand.py
依赖：pip install cairosvg pillow
"""
import math
import os

import cairosvg
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRAND = os.path.join(ROOT, "assets", "brand")
APPICON = os.path.join(ROOT, "macos/Runner/Assets.xcassets/AppIcon.appiconset")
WINRES = os.path.join(ROOT, "windows/runner/resources")

# ── 调色：全部取自 lib/app_theme.dart ───────────────────────────────
DEEP, ACCENT, GLOW = "#5B21C7", "#6D34E8", "#9856DC"          # 白底三段，对比 8.4 / 6.3 / 4.5:1
D_DEEP, D_ACCENT, D_GLOW = "#CFC2FF", "#A97CF0", "#9856DC"    # 深底三段，对比 10.9 / 5.7 / 4.0:1
PLATE_LIGHT = ("#FFFFFF", "#EBE1FE")
PLATE_DARK = ("#241D33", "#171320")


def arc(cx, cy, r, a1, a2):
    """a1→a2 逆时针扫过的弧（数学角度，屏幕上也是逆时针）。"""
    x1, y1 = cx + r * math.cos(math.radians(a1)), cy - r * math.sin(math.radians(a1))
    x2, y2 = cx + r * math.cos(math.radians(a2)), cy - r * math.sin(math.radians(a2))
    large = 1 if (a2 - a1) % 360 > 180 else 0
    return f"M {x1:.2f} {y1:.2f} A {r} {r} 0 {large} 0 {x2:.2f} {y2:.2f}"


def mark(colors, r=225, w=122, mouth=110, gap=42):
    """三段弧拼成的 C：三个来源，一个阅读器。

    mouth 是 C 的主开口，gap 是段间缝隙 —— 两者必须拉开差距，否则三个豁口
    一样大，整个标就读成 loading spinner 而不是字母。圆头笔帽每端还会向外
    多吃掉 atan((w/2)/r) 的角度，缝隙要先扣掉它才是眼睛看到的宽度。
    """
    span = 360 - mouth
    seg = (span - 2 * gap) / 3
    cap = math.degrees(math.atan((w / 2) / r))
    visible_gap = gap - 2 * cap
    assert visible_gap > 4, f"缝隙被笔帽吃光了（只剩 {visible_gap:.1f}°）"
    assert mouth - 2 * cap > visible_gap * 3, "主开口不够大，会读成 spinner"
    out = []
    for i, c in enumerate(colors):
        a1 = mouth / 2 + i * (seg + gap)
        out.append(f'<path d="{arc(512, 512, r, a1, a1 + seg)}" fill="none" '
                   f'stroke="{c}" stroke-width="{w}" stroke-linecap="round"/>')
    return "".join(out)


def svg(body, plate=None):
    defs, bg = "", ""
    if plate:
        defs = (f'<linearGradient id="p" x1="0" y1="0" x2="1" y2="1">'
                f'<stop offset="0" stop-color="{plate[0]}"/>'
                f'<stop offset="1" stop-color="{plate[1]}"/></linearGradient>')
        bg = '<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#p)"/>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" '
            f'width="1024" height="1024"><defs>{defs}</defs>{bg}{body}</svg>')


# 小尺寸光学补偿：16/32px 下细节全丢，图形要更大、更粗、缝隙更张
SMALL = dict(r=232, w=150, mouth=118, gap=56)


def icon_svg(dark=False, small=False):
    cols = (D_DEEP, D_ACCENT, D_GLOW) if dark else (DEEP, ACCENT, GLOW)
    plate = PLATE_DARK if dark else PLATE_LIGHT
    return svg(mark(cols, **(SMALL if small else {})), plate)


def render(svg_text, path, size):
    cairosvg.svg2png(bytestring=svg_text.encode(), write_to=path,
                     output_width=size, output_height=size)


def wordmark():
    """横版：标 + Outfit 字体的 Codora，README 用。"""
    S, H, PAD = 232, 320, 56
    img = Image.new("RGBA", (1180, H), (0, 0, 0, 0))
    glyph = os.path.join(BRAND, "_wm.png")
    render(svg(mark((DEEP, ACCENT, GLOW))), glyph, S + 96)
    g = Image.open(glyph).convert("RGBA")
    img.alpha_composite(g, (PAD - 48, (H - g.height) // 2))
    os.remove(glyph)

    f = ImageFont.truetype(os.path.join(ROOT, "assets/fonts/Outfit.ttf"), 128)
    try:
        f.set_variation_by_name("SemiBold")
    except Exception:
        pass  # 静态字重的 Outfit 没有可变轴，用原样
    d = ImageDraw.Draw(img)
    x = PAD + S + 34
    d.text((x, H // 2), "Codora", font=f, fill="#1C1430", anchor="lm")
    right = d.textbbox((x, H // 2), "Codora", font=f, anchor="lm")[2]
    img.crop((0, 0, right + PAD, H)).save(os.path.join(BRAND, "codora_wordmark.png"))


def main():
    os.makedirs(BRAND, exist_ok=True)

    # 1) 矢量源
    assets = {
        "codora_icon.svg": icon_svg(),
        "codora_icon_dark.svg": icon_svg(dark=True),
        "codora_mark.svg": svg(mark((DEEP, ACCENT, GLOW))),            # 透明底
        "codora_mark_dark.svg": svg(mark((D_DEEP, D_ACCENT, D_GLOW))),
    }
    for name, text in assets.items():
        with open(os.path.join(BRAND, name), "w") as fh:
            fh.write(text)
    render(assets["codora_icon.svg"], os.path.join(BRAND, "codora_icon.png"), 512)

    # 2) macOS AppIcon —— 16/32 用光学补偿版
    for size in (16, 32, 64, 128, 256, 512, 1024):
        render(icon_svg(small=size <= 32),
               os.path.join(APPICON, f"app_icon_{size}.png"), size)

    # 3) Windows .ico —— 多尺寸打进一个文件
    tmp = os.path.join(BRAND, "_ico_src.png")
    render(icon_svg(), tmp, 256)
    Image.open(tmp).save(os.path.join(WINRES, "app_icon.ico"),
                         sizes=[(16, 16), (32, 32), (48, 48), (64, 64),
                                (128, 128), (256, 256)])
    os.remove(tmp)

    # 4) 横版 wordmark
    wordmark()
    print("品牌资产已生成")


if __name__ == "__main__":
    main()
