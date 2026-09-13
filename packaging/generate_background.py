#!/usr/bin/env python3
"""DMG用のRetina対応背景画像を生成するスクリプト"""

import os
from PIL import Image, ImageDraw, ImageFont

def generate_background(output_path="packaging/dmg_background.png", width=600, height=400, scale=2):
    w = width * scale
    h = height * scale
    
    # ベースイメージ（RGBA）
    img = Image.new("RGBA", (w, h))
    draw = ImageDraw.Draw(img)
    
    # 垂直グラデーション背景 (#181a20 -> #222630)
    top_color = (24, 26, 32)
    bot_color = (34, 38, 48)
    for y in range(h):
        t = y / h
        r = int(top_color[0] + (bot_color[0] - top_color[0]) * t)
        g = int(top_color[1] + (bot_color[1] - top_color[1]) * t)
        b = int(top_color[2] + (bot_color[2] - top_color[2]) * t)
        draw.line([(0, y), (w, y)], fill=(r, g, b, 255))
        
    # 微細な外枠（ウィンドウ境界のアクセント）
    draw.rectangle([(1, 1), (w - 2, h - 2)], outline=(255, 255, 255, 20), width=scale)
    
    # フォント設定
    font_paths = [
        "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc",
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf"
    ]
    
    font_title = None
    for fp in font_paths:
        if os.path.exists(fp):
            try:
                font_title = ImageFont.truetype(fp, 16 * scale, index=0)
                break
            except Exception:
                continue
    if not font_title:
        font_title = ImageFont.load_default()

    font_sub = None
    sub_font_paths = [
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/SFNS.ttf"
    ]
    for fp in sub_font_paths:
        if os.path.exists(fp):
            try:
                font_sub = ImageFont.truetype(fp, 13 * scale)
                break
            except Exception:
                continue
    if not font_sub:
        font_sub = ImageFont.load_default()
        
    # ガイドテキスト
    title_text = "MousePollingRateTool を Applications にドラッグ＆ドロップ"
    sub_text = "Drag and drop to Applications folder to install"
    
    # タイトル描画
    bbox_title = draw.textbbox((0, 0), title_text, font=font_title)
    title_w = bbox_title[2] - bbox_title[0]
    draw.text(((w - title_w) // 2, 44 * scale), title_text, fill=(242, 244, 248, 245), font=font_title)
    
    # サブタイトル描画
    bbox_sub = draw.textbbox((0, 0), sub_text, font=font_sub)
    sub_w = bbox_sub[2] - bbox_sub[0]
    draw.text(((w - sub_w) // 2, 70 * scale), sub_text, fill=(145, 154, 168, 220), font=font_sub)
    
    # 中央の矢印 (アイコン中心 y=190pt 付近)
    center_x = 300 * scale
    center_y = 190 * scale
    arrow_len = 64 * scale
    ax0 = center_x - arrow_len // 2
    ax1 = center_x + arrow_len // 2
    
    arrow_color = (74, 160, 255, 235)  # アクセントブルー (#4aa0ff)
    draw.line([(ax0, center_y), (ax1, center_y)], fill=arrow_color, width=4 * scale)
    
    # 矢印の先端
    head_size = 14 * scale
    head_pts = [
        (ax1 - head_size, center_y - head_size),
        (ax1 + 4 * scale, center_y),
        (ax1 - head_size, center_y + head_size)
    ]
    draw.line([head_pts[0], head_pts[1]], fill=arrow_color, width=4 * scale)
    draw.line([head_pts[1], head_pts[2]], fill=arrow_color, width=4 * scale)
    
    # 保存 (72 * scale dpi)
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path, "PNG", dpi=(72 * scale, 72 * scale))
    print(f"DMG background generated: {output_path} ({w}x{h})")

if __name__ == "__main__":
    generate_background()
