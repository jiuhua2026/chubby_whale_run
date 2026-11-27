#!/usr/bin/env python3
"""《大肥鱼快跑》v2.0 60 秒 5 段式终版宣传 PV 合成脚本（16:9 · 1080p60）。

转场纪律（克制、统一、全有物理动机，零无效白闪/乱缩放）：
  1. 浪墙擦屏     ：Cold Open 黑鲸飞扑泡泡浪墙直接揭开暗海实机跑酷（一步到位不绕弯）
  2. 速度水幕扫屏 ：Introduction 原皮稳跑 11.3s → 右冲水幕扫屏无缝变装「暖冬针织」跑 6.0s
  3. 水泡圆环转场 ：Bubble Iris 扩张进 8.5s 完整小店营业 → 吃堡后圆环收缩回主角变成 r=70 大水泡护盾碎桶
  4. 终局唯一白闪 ：11.2s 紧张连贯 Boss 决战（一镜不剪碎）→ 扑咬爪击瞬白 + 0.7s 纯黑死寂 → 破浪封面 Title Card
  5. 尾音摇移特写 ：1.0x 完整小店全景 → 平滑右移放大至 1.70x 卡座黑鲸娘嘴硬反转
"""

import math
import os
import subprocess
import imageio_ffmpeg
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TMP = os.path.join(ROOT, "tools", "pv_tmp")
OVL_DIR = os.path.join(TMP, "overlays")
WAVE_DIR = os.path.join(TMP, "wave_seq")
SWIPE_DIR = os.path.join(TMP, "swipe_seq")
IRIS_IN_DIR = os.path.join(TMP, "iris_in_seq")
IRIS_OUT_DIR = os.path.join(TMP, "iris_out_seq")
PV_OUT = os.path.join(ROOT, "PV", "大肥鱼快跑_v2.0宣传PV_60s.mp4")
PV_OLD = os.path.join(ROOT, "PV", "大肥鱼快跑_v2.0宣传PV_45s.mp4")
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()

FONT_SERIF_HEAVY = r"C:\Windows\Fonts\Source Han Serif SC Heavy (TrueType).ttf"
FONT_SANS_BOLD = r"C:\Windows\Fonts\Noto Sans SC Bold (TrueType).otf"
FONT_FALLBACK = r"C:\Windows\Fonts\msyhbd.ttc"

W, H = 1920, 1080
GAMEPLAY_CROP = "1084:610:24:110"  # 全片跑酷统一 1.18x 视口（角色位置与体型从头到尾完全一致）


def load_font(path: str, size: int) -> ImageFont.FreeTypeFont:
    p = path if os.path.exists(path) else FONT_FALLBACK
    return ImageFont.truetype(p, size)


def draw_text_outline(draw: ImageDraw.ImageDraw, xy, text: str, font, fill, outline=(4, 10, 20, 245), width: int = 4, anchor="lt"):
    x, y = xy
    for ox in range(-width, width + 1):
        for oy in range(-width, width + 1):
            if ox * ox + oy * oy <= width * width:
                draw.text((x + ox, y + oy), text, font=font, fill=outline, anchor=anchor)
    draw.text((x, y), text, font=font, fill=fill, anchor=anchor)


def make_badge_overlay(filename: str, tag: str, title: str, accent=(92, 236, 255), border=(110, 224, 255), bottom_y: int = 46):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    f_tag = load_font(FONT_SANS_BOLD, 24)
    f_ttl = load_font(FONT_SANS_BOLD, 42)

    bbox_t = draw.textbbox((0, 0), title, font=f_ttl)
    bbox_g = draw.textbbox((0, 0), tag, font=f_tag)
    bw = max(bbox_t[2] - bbox_t[0], bbox_g[2] - bbox_g[0]) + 76
    bh = 104
    x0, y0 = 58, H - bh - bottom_y
    x1, y1 = x0 + bw, y0 + bh

    draw.rounded_rectangle([x0 - 4, y0 - 4, x1 + 4, y1 + 4], radius=16, fill=(2, 8, 18, 125))
    draw.rounded_rectangle([x0, y0, x1, y1], radius=14, fill=(8, 18, 34, 212), outline=(*border, 232), width=3)
    draw.rounded_rectangle([x0 + 14, y0 + 16, x0 + 22, y1 - 16], radius=4, fill=(*accent, 255))

    draw.text((x0 + 38, y0 + 12), tag, font=f_tag, fill=(*accent, 255))
    draw_text_outline(draw, (x0 + 38, y0 + 44), title, f_ttl, fill=(246, 250, 255, 255), outline=(4, 10, 22, 235), width=3)

    out = os.path.join(OVL_DIR, filename)
    img.save(out)
    return out


def make_button_quote_overlay(filename: str):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    f_speaker = load_font(FONT_SANS_BOLD, 28)
    f_quote = load_font(FONT_SANS_BOLD, 42)
    quote = "“别盯着我尾巴——只是顺路视察对手的伙食水准！”"
    qb = draw.textbbox((0, 0), quote, font=f_quote)
    bw = (qb[2] - qb[0]) + 96
    bh = 122
    x0 = (W - bw) // 2
    y0 = H - bh - 44
    x1, y1 = x0 + bw, y0 + bh

    draw.rounded_rectangle([x0 - 5, y0 - 5, x1 + 5, y1 + 5], radius=22, fill=(10, 4, 16, 140))
    draw.rounded_rectangle([x0, y0, x1, y1], radius=18, fill=(14, 12, 24, 224), outline=(255, 198, 92, 240), width=3)
    draw.text((x0 + 32, y0 + 14), "乔装黑鲸娘（偷偷光顾中）", font=f_speaker, fill=(255, 212, 112, 255))
    draw_text_outline(draw, (x0 + 32, y0 + 52), quote, f_quote, fill=(255, 248, 236, 255), outline=(10, 6, 18, 245), width=3)

    out = os.path.join(OVL_DIR, filename)
    img.save(out)
    return out


def make_endcard_overlay(filename: str):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    grad = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(grad)
    for y in range(int(H * 0.40), H):
        t = max(0.0, (y - H * 0.40) / (H * 0.60))
        a = int(212 * (t ** 1.30))
        gdraw.line([(0, y), (W, y)], fill=(3, 10, 22, a))
    img = Image.alpha_composite(img, grad)
    draw = ImageDraw.Draw(img)

    f_title = load_font(FONT_SERIF_HEAVY, 108)
    f_slogan = load_font(FONT_SANS_BOLD, 44)
    f_keys = load_font(FONT_SANS_BOLD, 28)

    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gl_d = ImageDraw.Draw(glow)
    gl_d.text((W // 2, int(H * 0.68)), "大肥鱼快跑", font=f_title, fill=(64, 210, 255, 195), anchor="mm")
    glow = glow.filter(ImageFilter.GaussianBlur(14))
    img = Image.alpha_composite(img, glow)
    draw = ImageDraw.Draw(img)

    draw_text_outline(
        draw,
        (W // 2, int(H * 0.68)),
        "大肥鱼快跑",
        f_title,
        fill=(255, 236, 152, 255),
        outline=(8, 22, 46, 255),
        width=7,
        anchor="mm",
    )
    draw_text_outline(
        draw,
        (W // 2, int(H * 0.80)),
        "冲破深渊围猎，海味狂飙不止！",
        f_slogan,
        fill=(182, 244, 255, 255),
        outline=(6, 14, 30, 245),
        width=4,
        anchor="mm",
    )

    keys_txt = "↑ 跳跃   ·   ↓ 滑铲   ·   Space 深海冲刺"
    kb = draw.textbbox((0, 0), keys_txt, font=f_keys)
    kw = (kb[2] - kb[0]) + 56
    kx0, ky0 = W // 2 - kw // 2, int(H * 0.88) - 24
    draw.rounded_rectangle([kx0, ky0, kx0 + kw, ky0 + 48], radius=24, fill=(8, 22, 42, 200), outline=(100, 215, 255, 190), width=2)
    draw.text((W // 2, ky0 + 24), keys_txt, font=f_keys, fill=(224, 246, 255, 245), anchor="mm")

    out = os.path.join(OVL_DIR, filename)
    img.save(out)
    return out


def build_wave_wipe_assets(frames: int = 36):
    """转场 1：OpeningIntro 原版海浪与黑鲸扑跃，直接擦开暗海实机跑酷。"""
    os.makedirs(WAVE_DIR, exist_ok=True)
    wave_src = Image.open(os.path.join(ROOT, "sprites", "intro", "chaser_wipe_wave.png")).convert("RGBA")
    rush_src = Image.open(os.path.join(ROOT, "sprites", "intro", "chaser_wipe_rush.png")).convert("RGBA")

    wave_big = wave_src.resize((2400, 1080), Image.Resampling.NEAREST)
    rush_big = rush_src.resize((int(897 * 1.42), int(867 * 1.42)), Image.Resampling.BILINEAR)

    for fi in range(frames):
        wp = fi / max(1, frames - 1)
        ease_wp = wp * wp * (3.0 - 2.0 * wp)
        wave_x = int((-1620.0 + (1420.0 - (-1620.0)) * ease_wp) * 1.5)
        reveal_x = max(0, min(W, int((wave_x / 1.5 + 720.0) * 1.5)))

        mask = Image.new("L", (W, H), 0)
        if reveal_x > 0:
            ImageDraw.Draw(mask).rectangle([0, 0, reveal_x, H], fill=255)
        mask.save(os.path.join(WAVE_DIR, f"mask_{fi:03d}.png"))

        fg = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        arc_y = int((-55.0 - 26.0 * (4.0 * wp * (1.0 - wp))) * 1.5)
        fg.paste(wave_big, (wave_x, 0), wave_big)
        fg.paste(rush_big, (wave_x + int(830.0 * 1.5), arc_y), rush_big)
        fg.save(os.path.join(WAVE_DIR, f"fg_{fi:03d}.png"))


def build_speed_swipe_assets(frames: int = 16):
    """转场 2：左→右深海青蓝速度水幕掠过屏幕，顺滑切换女仆→暖冬针织（零白闪）。"""
    os.makedirs(SWIPE_DIR, exist_ok=True)
    for fi in range(frames):
        p = fi / max(1, frames - 1)
        ease_p = p * p * (3.0 - 2.0 * p)
        cx = int(-260 + (W + 520) * ease_p)

        mask = Image.new("L", (W, H), 0)
        if cx > 0:
            ImageDraw.Draw(mask).rectangle([0, 0, min(W, cx), H], fill=255)
        mask.save(os.path.join(SWIPE_DIR, f"mask_{fi:03d}.png"))

        # 一道带有深海光流拖尾的青蓝斜切水幕（宽度随推进柔和收束）
        fg = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(fg)
        bell = math.sin(p * math.pi)
        w_glow = int(190 * (0.35 + 0.65 * bell))
        d.rectangle([cx - w_glow, 0, cx + 40, H], fill=(42, 188, 245, int(115 * bell)))
        d.rectangle([cx - 32, 0, cx + 18, H], fill=(120, 236, 255, int(190 * bell)))
        d.rectangle([cx - 8, 0, cx + 8, H], fill=(224, 252, 255, int(235 * bell)))
        fg = fg.filter(ImageFilter.GaussianBlur(10))
        fg.save(os.path.join(SWIPE_DIR, f"fg_{fi:03d}.png"))


def build_bubble_iris_assets(out_dir: str, expand: bool, frames: int = 26):
    """转场 3：深海水泡圆环膨胀（进小店）/ 收缩（回赛道直接变成主角身上的 r=70 大水泡护盾！）。"""
    os.makedirs(out_dir, exist_ok=True)
    # 主角在 1084x610:24:110 裁切放大到 1920x1080 下的胸口圆心位置 ≈ (518, 690)
    cx, cy = 518, 690
    max_r = math.hypot(W - cx, max(cy, H - cy)) + 40.0
    min_r = 96.0  # 恰好对应主角大号水泡护盾半径！

    for fi in range(frames):
        p = fi / max(1, frames - 1)
        ease_p = p * p * (3.0 - 2.0 * p)
        if expand:
            r = min_r + (max_r - min_r) * ease_p
        else:
            r = max_r - (max_r - min_r) * ease_p

        # Mask：圆内 = Clip B，圆外 = Clip A（expand 时 Clip B 从圆心胀满；contract 时 Clip A 在圆外合拢把 Clip B 留给中心护盾？
        # Wait：进小店 (expand=True)：圆内显示新场景 Clip B（小店），由小变大铺满全屏！
        # 出小店回赛道 (expand=False)：圆**外**显示新场景 Clip B（赛道），圆内保留旧场景 Clip A（小店）不断缩小聚焦到主角胸口 r=96，啪地露出一整只顶着 r=70 护盾在赛道奔跑的主角！
        mask = Image.new("L", (W, H), 0 if expand else 255)
        md = ImageDraw.Draw(mask)
        md.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255 if expand else 0))
        mask = mask.filter(ImageFilter.GaussianBlur(3))
        mask.save(os.path.join(out_dir, f"mask_{fi:03d}.png"))

        fg = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        fd = ImageDraw.Draw(fg)
        fd.ellipse([cx - r - 8, cy - r - 8, cx + r + 8, cy + r + 8], outline=(82, 224, 255, 110), width=16)
        fd.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(186, 248, 255, 225), width=6)
        fg = fg.filter(ImageFilter.GaussianBlur(2))
        fg.save(os.path.join(out_dir, f"fg_{fi:03d}.png"))


def run(cmd):
    subprocess.run(cmd, check=True)


def render_clip(
    src_avi: str,
    ss: float,
    dur: float,
    out_mp4: str,
    crop: str | None = None,
    overlay_png: str | None = None,
    ovl_fade_in: float = 0.25,
    fade_in_sec: float = 0.0,
    fade_out_sec: float = 0.0,
    sfx_gain: float = 0.90,
):
    vf_parts = []
    if crop:
        vf_parts.append(f"crop={crop}")
    vf_parts.extend([f"scale={W}:{H}:flags=neighbor", "setsar=1", "fps=60"])
    if fade_in_sec > 0.0:
        vf_parts.append(f"fade=t=in:st=0:d={fade_in_sec:.2f}")
    if fade_out_sec > 0.0:
        vf_parts.append(f"fade=t=out:st={max(0.0, dur - fade_out_sec):.2f}:d={fade_out_sec:.2f}")

    if overlay_png is None:
        cmd = [
            FFMPEG, "-y", "-ss", f"{ss:.3f}", "-t", f"{dur:.3f}", "-i", src_avi,
            "-vf", ",".join(vf_parts),
            "-af", f"volume={sfx_gain:.2f}",
            "-c:v", "libx264", "-preset", "medium", "-crf", "15", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-ac", "2",
            out_mp4,
        ]
    else:
        fo = max(0.30, dur - 0.30)
        fc = (
            f"[1:v]format=rgba,fade=t=in:st=0.18:d={ovl_fade_in:.2f}:alpha=1,"
            f"fade=t=out:st={fo:.2f}:d=0.25:alpha=1[ov];"
            f"[0:v]{','.join(vf_parts)}[base];"
            f"[base][ov]overlay=0:0:shortest=1[vout]"
        )
        cmd = [
            FFMPEG, "-y", "-ss", f"{ss:.3f}", "-t", f"{dur:.3f}", "-i", src_avi,
            "-loop", "1", "-t", f"{dur:.3f}", "-i", overlay_png,
            "-filter_complex", fc,
            "-map", "[vout]", "-map", "0:a",
            "-af", f"volume={sfx_gain:.2f}",
            "-c:v", "libx264", "-preset", "medium", "-crf", "15", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-ac", "2",
            out_mp4,
        ]
    run(cmd)


def render_masked_bridge(
    clip_a: str, a_ss: float, crop_a: str | None,
    clip_b: str, b_ss: float, crop_b: str | None,
    seq_dir: str, frames: int, out_mp4: str,
    extra_sfx: str | None = None,
):
    dur = frames / 60.0
    mask_pat = os.path.join(seq_dir, "mask_%03d.png")
    fg_pat = os.path.join(seq_dir, "fg_%03d.png")

    va_chain = (f"crop={crop_a}," if crop_a else "") + f"scale={W}:{H}:flags=neighbor,setsar=1,fps=60"
    vb_chain = (f"crop={crop_b}," if crop_b else "") + f"scale={W}:{H}:flags=neighbor,setsar=1,fps=60"

    if extra_sfx:
        fc = (
            f"[0:v]{va_chain}[va];[1:v]{vb_chain}[vb];"
            f"[2:v]format=gray[mk];[vb][mk]alphamerge[vbm];"
            f"[va][vbm]overlay=0:0:shortest=1[bgm];"
            f"[3:v]format=rgba[fg];[bgm][fg]overlay=0:0:shortest=1[vout];"
            f"[0:a]volume=0.80[aa];[4:a]volume=0.85[ax];"
            f"[aa][ax]amix=inputs=2:duration=first:normalize=0[aout]"
        )
        inputs = [
            "-ss", f"{a_ss:.3f}", "-t", f"{dur:.3f}", "-i", clip_a,
            "-ss", f"{b_ss:.3f}", "-t", f"{dur:.3f}", "-i", clip_b,
            "-framerate", "60", "-i", mask_pat,
            "-framerate", "60", "-i", fg_pat,
            "-i", extra_sfx,
        ]
    else:
        fc = (
            f"[0:v]{va_chain}[va];[1:v]{vb_chain}[vb];"
            f"[2:v]format=gray[mk];[vb][mk]alphamerge[vbm];"
            f"[va][vbm]overlay=0:0:shortest=1[bgm];"
            f"[3:v]format=rgba[fg];[bgm][fg]overlay=0:0:shortest=1[vout];"
            f"[0:a]volume=0.90[aout]"
        )
        inputs = [
            "-ss", f"{a_ss:.3f}", "-t", f"{dur:.3f}", "-i", clip_a,
            "-ss", f"{b_ss:.3f}", "-t", f"{dur:.3f}", "-i", clip_b,
            "-framerate", "60", "-i", mask_pat,
            "-framerate", "60", "-i", fg_pat,
        ]

    run([
        FFMPEG, "-y", *inputs,
        "-filter_complex", fc,
        "-map", "[vout]", "-map", "[aout]",
        "-c:v", "libx264", "-preset", "medium", "-crf", "15", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-ac", "2",
        out_mp4,
    ])


def render_cutoff_and_title(clip_intro: str, ovl_end: str, out_mp4: str):
    """全片唯一 1 次白闪（2 帧）+ 0.70s 纯黑死寂 + 5.50s 破浪高清定格标题页。"""
    p_silence = os.path.join(TMP, "seg60_silence.mp4")
    run([
        FFMPEG, "-y",
        "-f", "lavfi", "-i", f"color=c=white:s={W}x{H}:r=60:d=0.05",
        "-f", "lavfi", "-i", f"color=c=#02060d:s={W}x{H}:r=60:d=0.70",
        "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
        "-filter_complex", "[0:v][1:v]concat=n=2:v=1:a=0[vout]",
        "-map", "[vout]", "-map", "2:a",
        "-t", "0.75",
        "-c:v", "libx264", "-preset", "medium", "-crf", "15", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k",
        p_silence,
    ])

    dur_title = 6.20
    p_title = os.path.join(TMP, "seg60_title.mp4")
    fc = (
        f"[0:v]scale={W}:{H}:flags=neighbor,setsar=1,fps=60,"
        f"tpad=stop_mode=clone:stop_duration={dur_title - 1.65:.2f}[base];"
        f"[1:v]format=rgba,fade=t=in:st=1.45:d=0.45:alpha=1[ov];"
        f"[base][ov]overlay=0:0:shortest=1,fade=t=out:st={dur_title - 0.30:.2f}:d=0.30[vout]"
    )
    run([
        FFMPEG, "-y",
        "-ss", "5.200", "-t", "1.650", "-i", clip_intro,
        "-loop", "1", "-t", f"{dur_title:.3f}", "-i", ovl_end,
        "-filter_complex", fc,
        "-map", "[vout]", "-map", "0:a",
        "-af", f"apad=whole_dur={dur_title:.2f},volume=0.95",
        "-c:v", "libx264", "-preset", "medium", "-crf", "15", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-ac", "2",
        p_title,
    ])

    run([
        FFMPEG, "-y", "-i", p_silence, "-i", p_title,
        "-filter_complex", "[0:v][0:a][1:v][1:a]concat=n=2:v=1:a=1[v][a]",
        "-map", "[v]", "-map", "[a]",
        "-c:v", "libx264", "-preset", "medium", "-crf", "15", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k",
        out_mp4,
    ])


def render_button_pan_zoom(clip_btn_avi: str, ovl_btn: str, out_mp4: str, total_dur: float = 6.20):
    """Button 尾音：1.35s 完整小店全景 → 1.80s 平滑向右推进放大至 1.70x 角落卡座黑鲸娘偷吃特写 → 3.05s 定格金句 + 落幕。"""
    btn_frames_dir = os.path.join(TMP, "btn_frames")
    os.makedirs(btn_frames_dir, exist_ok=True)
    raw_pat = os.path.join(btn_frames_dir, "f_%04d.png")
    # 导出 clip_shop_btn.avi 从 0.50s 起的 372 帧 (6.20s @60fps) + 对应音频
    btn_aud = os.path.join(TMP, "btn_aud.wav")
    run([
        FFMPEG, "-y", "-ss", "0.500", "-t", f"{total_dur:.3f}", "-i", clip_btn_avi,
        "-vf", "fps=60", raw_pat,
        "-vn", "-acodec", "pcm_s16le", "-ar", "44100", "-ac", "2", btn_aud,
    ])

    ovl_rgba = Image.open(ovl_btn).convert("RGBA")
    frames_files = sorted([f for f in os.listdir(btn_frames_dir) if f.startswith("f_") and f.endswith(".png")])

    out_vid = os.path.join(TMP, "btn_vid_silent.mp4")
    proc = subprocess.Popen([
        FFMPEG, "-y",
        "-f", "rawvideo", "-vcodec", "rawvideo", "-pix_fmt", "rgb24",
        "-s", f"{W}x{H}", "-r", "60", "-i", "-",
        "-c:v", "libx264", "-preset", "medium", "-crf", "15", "-pix_fmt", "yuv420p",
        out_vid,
    ], stdin=subprocess.PIPE)

    t_hold_wide = 1.50
    t_pan_dur = 1.85
    t_quote_in = 3.20
    t_fade_out = total_dur - 0.50

    # 起点全屏 (0, 0, 1280, 720) -> 终点卡座黑鲸娘特写 (518, 74, 752, 423)，完整裁掉底部操作栏
    for idx, fn in enumerate(frames_files):
        t = idx / 60.0
        if t <= t_hold_wide:
            k = 0.0
        elif t <= t_hold_wide + t_pan_dur:
            u = (t - t_hold_wide) / t_pan_dur
            k = u * u * (3.0 - 2.0 * u)
        else:
            k = 1.0

        cx = 518.0 * k
        cy = 74.0 * k
        cw = 1280.0 + (752.0 - 1280.0) * k
        ch = 720.0 + (423.0 - 720.0) * k

        with Image.open(os.path.join(btn_frames_dir, fn)) as src:
            cropped = src.crop((cx, cy, cx + cw, cy + ch))
            scaled = cropped.resize((W, H), Image.Resampling.BILINEAR).convert("RGBA")

        if t >= t_quote_in:
            qa = min(1.0, (t - t_quote_in) / 0.30)
            ov = ovl_rgba.copy()
            if qa < 0.999:
                a_ch = ov.getchannel("A").point(lambda v: int(v * qa))
                ov.putalpha(a_ch)
            scaled = Image.alpha_composite(scaled, ov)

        # 淡入与尾声落幕黑屏
        if t < 0.15:
            br = t / 0.15
            black = Image.new("RGBA", (W, H), (0, 0, 0, int(255 * (1.0 - br))))
            scaled = Image.alpha_composite(scaled, black)
        elif t >= t_fade_out:
            fo = min(1.0, (t - t_fade_out) / 0.50)
            black = Image.new("RGBA", (W, H), (0, 0, 0, int(255 * fo)))
            scaled = Image.alpha_composite(scaled, black)

        proc.stdin.write(scaled.convert("RGB").tobytes())

    proc.stdin.close()
    proc.wait()
    if proc.returncode != 0:
        raise RuntimeError("Button pan/zoom encode failed")

    run([
        FFMPEG, "-y", "-i", out_vid, "-i", btn_aud,
        "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", out_mp4,
    ])


def main():
    os.makedirs(OVL_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(PV_OUT), exist_ok=True)

    build_wave_wipe_assets(frames=36)
    build_speed_swipe_assets(frames=16)
    build_bubble_iris_assets(IRIS_IN_DIR, expand=True, frames=26)
    build_bubble_iris_assets(IRIS_OUT_DIR, expand=False, frames=26)

    ovl_intro = make_badge_overlay("ovl_intro.png", "CHUBBY WHALE RUN", "《大肥鱼快跑》 · 极简三键深海跑酷", accent=(110, 236, 255), border=(90, 200, 255))
    ovl_skin = make_badge_overlay("ovl_skin.png", "STYLE & TERRAIN", "多套主题穿搭 · 百变深海险境", accent=(255, 224, 118), border=(245, 190, 88))
    ovl_shop = make_badge_overlay("ovl_shop.png", "WHALE BURGER", "鲸堡小店营业 · 拍★金脆赚贝壳币 · 吃堡加Buff", accent=(255, 214, 102), border=(245, 178, 76), bottom_y=26)
    ovl_shield = make_badge_overlay("ovl_shield.png", "BUBBLE SHIELD", "大水泡护盾觉醒 · 撞障碎盾不减速", accent=(112, 234, 255), border=(84, 204, 255))
    ovl_boss = make_badge_overlay("ovl_boss.png", "HARD MODE BOSS", "红转黑狂暴决战 · 正面破弹 · 绝境扑杀", accent=(255, 102, 134), border=(255, 76, 118))
    ovl_end = make_endcard_overlay("ovl_endcard.png")
    ovl_btn = make_button_quote_overlay("ovl_button.png")

    clip_intro = os.path.join(TMP, "clip_intro.avi")
    clip_cold = os.path.join(TMP, "clip_cold_open.avi")
    clip_parkour = os.path.join(TMP, "clip_parkour.avi")
    clip_boss = os.path.join(TMP, "clip_boss.avi")
    clip_shop = os.path.join(TMP, "clip_shop.avi")
    clip_shop_btn = os.path.join(TMP, "clip_shop_btn.avi")
    clip_shield = os.path.join(TMP, "clip_shield.avi")

    # ── 1. Cold Open (0.00 ~ 4.00s): 破障震退黑鲸 + 海浪直接擦进暗海跑酷（不切亮海远景！）
    s1 = os.path.join(TMP, "s60_1_cold.mp4")
    render_clip(clip_cold, 0.50, 3.40, s1, crop=GAMEPLAY_CROP, sfx_gain=0.95)

    s1_wipe = os.path.join(TMP, "s60_1_wipe.mp4")
    render_masked_bridge(
        clip_cold, 3.90, GAMEPLAY_CROP,
        clip_parkour, 0.40, GAMEPLAY_CROP,
        WAVE_DIR, 36, s1_wipe,
        extra_sfx=os.path.join(ROOT, "audio", "intro_whoosh.wav"),
    )

    # ── 2. Introduction (4.00 ~ 15.32s): 原皮深海女仆稳跑 11.3 秒展示跳/滑/采植
    s2 = os.path.join(TMP, "s60_2_intro.mp4")
    render_clip(clip_parkour, 1.00, 11.32, s2, crop=GAMEPLAY_CROP, overlay_png=ovl_intro, sfx_gain=0.90)

    # ── 3. Escalation (15.32 ~ 34.05s):
    #    3A: 速度水幕从左向右扫屏换装「暖冬针织」（停留在 12.45s exact swap!）
    s3_swipe = os.path.join(TMP, "s60_3_swipe.mp4")
    render_masked_bridge(
        clip_parkour, 12.32, GAMEPLAY_CROP,
        clip_parkour, 12.45, GAMEPLAY_CROP,
        SWIPE_DIR, 16, s3_swipe,
        extra_sfx=os.path.join(ROOT, "audio", "sfx_dash.wav"),
    )

    s3_knit = os.path.join(TMP, "s60_3_knit.mp4")
    render_clip(clip_parkour, 12.72, 5.83, s3_knit, crop=GAMEPLAY_CROP, overlay_png=ovl_skin, sfx_gain=0.90)

    #    3B: 水泡圆环膨胀进 8.6s 完整小店实景（金脆彩带 + 上菜金币爱心 + 吃脆藻堡）
    s3_iris_in = os.path.join(TMP, "s60_3_iris_in.mp4")
    render_masked_bridge(
        clip_parkour, 18.55, GAMEPLAY_CROP,
        clip_shop, 0.50, None,
        IRIS_IN_DIR, 26, s3_iris_in,
        extra_sfx=os.path.join(ROOT, "audio", "sfx", "shop_serve.wav"),
    )

    s3_shop = os.path.join(TMP, "s60_3_shop.mp4")
    render_clip(clip_shop, 0.93, 8.62, s3_shop, crop=None, overlay_png=ovl_shop, sfx_gain=1.00)

    #    3C: 水泡圆环收缩回赛道 → 主角顶着 r=70 大水泡护盾迎撞木桶碎盾不减速！
    s3_iris_out = os.path.join(TMP, "s60_3_iris_out.mp4")
    render_masked_bridge(
        clip_shop, 9.55, None,
        clip_shield, 1.90, GAMEPLAY_CROP,
        IRIS_OUT_DIR, 26, s3_iris_out,
    )

    s3_shield = os.path.join(TMP, "s60_3_shield.mp4")
    render_clip(clip_shield, 2.33, 3.15, s3_shield, crop=GAMEPLAY_CROP, overlay_png=ovl_shield, sfx_gain=1.00)

    # ── 4. Climax (34.05 ~ 49.55s): 一镜到底 Boss 战（定格狂暴张嘴红爪瞬间！）+ 唯一白闪断音 + Title Card
    s4_boss = os.path.join(TMP, "s60_4_boss.mp4")
    render_clip(clip_boss, 0.50, 8.55, s4_boss, crop=GAMEPLAY_CROP, overlay_png=ovl_boss, sfx_gain=1.05)

    s4_title = os.path.join(TMP, "s60_4_title.mp4")
    render_cutoff_and_title(clip_intro, ovl_end, s4_title)

    # ── 5. Button (49.55 ~ 56.05s): 1.0x 全景小店 → 右移放大至 1.70x 墨镜黑鲸娘嘴硬反转
    s5_button = os.path.join(TMP, "s60_5_button.mp4")
    render_button_pan_zoom(clip_shop_btn, ovl_btn, s5_button, total_dur=6.50)

    segs = [s1, s1_wipe, s2, s3_swipe, s3_knit, s3_iris_in, s3_shop, s3_iris_out, s3_shield, s4_boss, s4_title, s5_button]

    def probe_dur(path: str) -> float:
        r = subprocess.run([FFMPEG, "-i", path], capture_output=True, text=True, encoding="utf-8", errors="replace")
        for ln in r.stderr.splitlines():
            if "Duration:" in ln:
                t_str = ln.split("Duration:")[1].split(",")[0].strip()
                h, m, s = t_str.split(":")
                return int(h) * 3600 + int(m) * 60 + float(s)
        return 0.0

    durs = [probe_dur(p) for p in segs]
    starts = []
    acc = 0.0
    for d in durs:
        starts.append(acc)
        acc += d

    # 精确音乐时间节点
    t_shop_in = starts[5] + 0.15       # 水泡展开进小店
    t_shield_in = starts[7] + 0.15     # 水泡收缩回护盾赛道
    t_climax_in = starts[9]            # Boss 决战开打
    t_cutoff = starts[10]              # ★ 唯一一次白闪与全部音乐断音
    t_title_in = starts[10] + 0.77     # 死寂后 Title 登场
    t_button_in = starts[11]           # Button 全景进小店
    total_dur = acc
    print(f"[build_pv 60s] shop={t_shop_in:.2f}s shield={t_shield_in:.2f}s climax={t_climax_in:.2f}s cutoff={t_cutoff:.2f}s title={t_title_in:.2f}s button={t_button_in:.2f}s total={total_dur:.2f}s")

    concat_txt = os.path.join(TMP, "concat_60s.txt")
    with open(concat_txt, "w", encoding="utf-8") as f:
        for p in segs:
            f.write(f"file '{p.replace(chr(92), '/')}'\n")

    raw_concat = os.path.join(TMP, "pv_raw_60s.mp4")
    run([
        FFMPEG, "-y", "-f", "concat", "-safe", "0", "-i", concat_txt,
        "-c:v", "libx264", "-preset", "medium", "-crf", "15", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k",
        raw_concat,
    ])

    bgm_run = os.path.join(ROOT, "audio", "bgm", "bgm_run.mp3")
    bgm_chase = os.path.join(ROOT, "audio", "bgm", "bgm_chase.ogg")
    bgm_shop = os.path.join(ROOT, "audio", "bgm", "bgm_shop.wav")
    sfx_confirm = os.path.join(ROOT, "audio", "sfx", "ui_confirm.wav")
    sfx_serve = os.path.join(ROOT, "audio", "sfx", "shop_serve.wav")

    m1_dur = max(1.0, t_shop_in + 0.10)
    m_shop1_dur = max(1.0, t_shield_in - t_shop_in + 0.15)
    m2_dur = max(1.0, t_climax_in - t_shield_in + 0.15)
    m_boss_dur = max(1.0, t_cutoff - t_climax_in)
    m_btn_dur = max(1.0, total_dur - t_button_in)

    audio_fc = (
        f"[0:a]volume=1.05[sfx_raw];"
        # 1) Cold Open + Intro + 针织穿搭：bgm_run
        f"[1:a]atrim=0:{m1_dur:.3f},asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.15,afade=t=out:st={max(0.0, m1_dur - 0.30):.3f}:d=0.30,volume=0.44[m1];"
        # 2) 小店营业 8.5s：bgm_shop
        f"[3:a]atrim=0:{m_shop1_dur:.3f},asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.20,afade=t=out:st={max(0.0, m_shop1_dur - 0.25):.3f}:d=0.25,volume=0.48,adelay={int(t_shop_in * 1000)}|{int(t_shop_in * 1000)}[ms1];"
        # 3) 护盾破障重返深渊 3.5s：bgm_run 高潮段衔接升温
        f"[1:a]atrim=16.0:{16.0 + m2_dur:.3f},asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.18,afade=t=out:st={max(0.0, m2_dur - 0.20):.3f}:d=0.20,volume=0.46,adelay={int(t_shield_in * 1000)}|{int(t_shield_in * 1000)}[m2];"
        # 4) Climax Boss 战：bgm_chase 推至顶峰并在 t_cutoff 0.02s 彻底切断！
        f"[2:a]atrim=0:{m_boss_dur:.3f},asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.18,afade=t=out:st={max(0.0, m_boss_dur - 0.02):.3f}:d=0.02,volume=0.58,adelay={int(t_climax_in * 1000)}|{int(t_climax_in * 1000)}[mb];"
        # 5) 寂静后 Title Card 确认音
        f"[4:a]volume=0.78,adelay={int(t_title_in * 1000)}|{int(t_title_in * 1000)}[td];"
        # 6) Button 尾音“叮铃！” + bgm_shop 俏皮落幕
        f"[5:a]volume=0.88,adelay={int(t_button_in * 1000)}|{int(t_button_in * 1000)}[bd];"
        f"[3:a]atrim=6.0:{6.0 + m_btn_dur:.3f},asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.12,afade=t=out:st={max(0.0, m_btn_dur - 0.45):.3f}:d=0.45,volume=0.52,adelay={int(t_button_in * 1000)}|{int(t_button_in * 1000)}[ms2];"
        f"[sfx_raw][m1][ms1][m2][mb][td][bd][ms2]amix=inputs=8:duration=first:dropout_transition=0:normalize=0,alimiter=limit=0.95[aout]"
    )

    run([
        FFMPEG, "-y",
        "-i", raw_concat,
        "-i", bgm_run,
        "-i", bgm_chase,
        "-i", bgm_shop,
        "-i", sfx_confirm,
        "-i", sfx_serve,
        "-filter_complex", audio_fc,
        "-map", "0:v", "-map", "[aout]",
        "-c:v", "copy",
        "-c:a", "aac", "-b:a", "224k", "-ar", "44100", "-ac", "2",
        "-movflags", "+faststart",
        PV_OUT,
    ])
    if os.path.exists(PV_OLD):
        os.remove(PV_OLD)
    print(f"[build_pv 60s] Done -> {PV_OUT}")


if __name__ == "__main__":
    main()
