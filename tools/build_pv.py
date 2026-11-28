#!/usr/bin/env python3
"""《大肥鱼快跑》v2.0 宣传 PV 混剪脚本（用户高清实机素材 + 引擎开场/扑咬补戏 + 原生 BGM/SFX 混音 · 1080p60）。

5 幕结构与转场纪律：
  1. 幕一 Opening   ：游戏 4 幕开场动画 → 第 4 幕黑鲸扑水海浪直接擦出《原皮跑酷.mp4》（不切亮海标题页）
  2. 幕二 Intro     ：《原皮跑酷.mp4》→ 左→右青蓝速度水幕扫屏（零白闪）→ 同位变装《皮肤跑酷.mp4》（暖冬针织）
  3. 幕三 Escalation：主角胸口水泡圆环展开进《鲸堡小店.mp4》→ 收缩回胸口化身大水泡护盾接《护盾.mp4》撞箱碎盾
  4. 幕四 Climax    ：《黑鲸娘狂暴.mp4》红转黑弹幕战 → 赤蓝斩光顺切《暖冬针织》正面破弹+红眼黑鲸贴背扑咬
                     → 全片唯一 1 次 0.05s 白闪硬切断音 + 0.70s 深渊死寂 → 破浪高清 Title Card
  5. 幕五 Button    ：“叮铃！”回《鲸堡小店.mp4》后半段：1.0x 全景 → 右移放大至 1.70x 墨镜黑鲸娘嘴硬反转收尾
"""

import math
import os
import subprocess
import imageio_ffmpeg
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
USER_SRC = os.path.join(ROOT, "PV", "素材")
TMP = os.path.join(ROOT, "tools", "pv_tmp")
OVL_DIR = os.path.join(TMP, "overlays")
WAVE_DIR = os.path.join(TMP, "wave_seq")
SWIPE_CYAN_DIR = os.path.join(TMP, "swipe_cyan_seq")
SWIPE_RED_DIR = os.path.join(TMP, "swipe_red_seq")
IRIS_IN_DIR = os.path.join(TMP, "iris_in_seq")
IRIS_OUT_DIR = os.path.join(TMP, "iris_out_seq")

PV_OUT = os.path.join(ROOT, "PV", "大肥鱼快跑_v2.0宣传PV.mp4")
PV_OLD_LIST = [
    os.path.join(ROOT, "PV", "大肥鱼快跑_v2.0宣传PV_60s.mp4"),
    os.path.join(ROOT, "PV", "大肥鱼快跑_v2.0宣传PV_45s.mp4"),
]
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()

FONT_SERIF_HEAVY = r"C:\Windows\Fonts\Source Han Serif SC Heavy (TrueType).ttf"
FONT_SANS_BOLD = r"C:\Windows\Fonts\Noto Sans SC Bold (TrueType).otf"
FONT_FALLBACK = r"C:\Windows\Fonts\msyhbd.ttc"

W, H = 1920, 1080

# 精确裁切为标准 16:9（保留完整 HUD 与 Boss 预警条，对齐各片段地平线）
CROP_ORIG = "1280:720:0:16"   # 1280x800
CROP_784 = "1280:720:0:12"    # 1280x784 (皮肤/护盾/狂暴)
CROP_SHOP = "1280:720:0:28"   # 1280x784 (鲸堡小店 UI)
CROP_NONE = None              # 1280x720 (Godot 电影直录)


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


def make_badge_overlay(filename: str, tag: str, title: str, accent=(92, 236, 255), border=(110, 224, 255), bottom_y: int = 44):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    f_tag = load_font(FONT_SANS_BOLD, 22)
    f_ttl = load_font(FONT_SANS_BOLD, 38)

    bbox_t = draw.textbbox((0, 0), title, font=f_ttl)
    bbox_g = draw.textbbox((0, 0), tag, font=f_tag)
    bw = max(bbox_t[2] - bbox_t[0], bbox_g[2] - bbox_g[0]) + 72
    bh = 94
    x0, y0 = 52, H - bh - bottom_y
    x1, y1 = x0 + bw, y0 + bh

    draw.rounded_rectangle([x0 - 4, y0 - 4, x1 + 4, y1 + 4], radius=16, fill=(2, 8, 18, 125))
    draw.rounded_rectangle([x0, y0, x1, y1], radius=14, fill=(8, 18, 34, 212), outline=(*border, 232), width=3)
    draw.rounded_rectangle([x0 + 14, y0 + 15, x0 + 22, y1 - 15], radius=4, fill=(*accent, 255))

    draw.text((x0 + 36, y0 + 10), tag, font=f_tag, fill=(*accent, 255))
    draw_text_outline(draw, (x0 + 36, y0 + 40), title, f_ttl, fill=(246, 250, 255, 255), outline=(4, 10, 22, 235), width=3)

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

    draw.rounded_rectangle([x0 - 5, y0 - 5, x1 + 5, y1 + 5], radius=22, fill=(10, 4, 16, 145))
    draw.rounded_rectangle([x0, y0, x1, y1], radius=18, fill=(14, 12, 24, 226), outline=(255, 198, 92, 240), width=3)
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
        a = int(214 * (t ** 1.30))
        gdraw.line([(0, y), (W, y)], fill=(3, 10, 22, a))
    img = Image.alpha_composite(img, grad)
    draw = ImageDraw.Draw(img)

    f_title = load_font(FONT_SERIF_HEAVY, 108)
    f_slogan = load_font(FONT_SANS_BOLD, 44)
    f_keys = load_font(FONT_SANS_BOLD, 28)

    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gl_d = ImageDraw.Draw(glow)
    gl_d.text((W // 2, int(H * 0.67)), "大肥鱼快跑", font=f_title, fill=(64, 210, 255, 195), anchor="mm")
    glow = glow.filter(ImageFilter.GaussianBlur(14))
    img = Image.alpha_composite(img, glow)
    draw = ImageDraw.Draw(img)

    draw_text_outline(
        draw, (W // 2, int(H * 0.67)), "大肥鱼快跑", f_title,
        fill=(255, 236, 152, 255), outline=(8, 22, 46, 255), width=7, anchor="mm",
    )
    draw_text_outline(
        draw, (W // 2, int(H * 0.79)), "冲破深渊围猎，海味狂飙不止！", f_slogan,
        fill=(182, 244, 255, 255), outline=(6, 14, 30, 245), width=4, anchor="mm",
    )

    keys_txt = "↑ 跳跃   ·   ↓ 滑铲   ·   Space 深海冲刺 / 弹反"
    kb = draw.textbbox((0, 0), keys_txt, font=f_keys)
    kw = (kb[2] - kb[0]) + 56
    kx0, ky0 = W // 2 - kw // 2, int(H * 0.88) - 24
    draw.rounded_rectangle([kx0, ky0, kx0 + kw, ky0 + 48], radius=24, fill=(8, 22, 42, 200), outline=(100, 215, 255, 190), width=2)
    draw.text((W // 2, ky0 + 24), keys_txt, font=f_keys, fill=(224, 246, 255, 245), anchor="mm")

    out = os.path.join(OVL_DIR, filename)
    img.save(out)
    return out


def build_wave_wipe_assets(frames: int = 36):
    """转场 1：OpeningIntro 第 4 幕海浪＋黑鲸扑跃，直接擦开暗海实机跑酷。"""
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


def build_speed_swipe_assets(out_dir: str, c_glow, c_mid, c_core, frames: int = 16):
    """速度光幕左→右扫屏转场（零白闪）：青蓝用于换装，暗红用于 Boss 狂暴推进切换。"""
    os.makedirs(out_dir, exist_ok=True)
    for fi in range(frames):
        p = fi / max(1, frames - 1)
        ease_p = p * p * (3.0 - 2.0 * p)
        cx = int(-260 + (W + 520) * ease_p)

        mask = Image.new("L", (W, H), 0)
        if cx > 0:
            ImageDraw.Draw(mask).rectangle([0, 0, min(W, cx), H], fill=255)
        mask.save(os.path.join(out_dir, f"mask_{fi:03d}.png"))

        fg = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(fg)
        bell = math.sin(p * math.pi)
        w_glow = int(190 * (0.35 + 0.65 * bell))
        d.rectangle([cx - w_glow, 0, cx + 40, H], fill=(*c_glow, int(125 * bell)))
        d.rectangle([cx - 32, 0, cx + 18, H], fill=(*c_mid, int(195 * bell)))
        d.rectangle([cx - 8, 0, cx + 8, H], fill=(*c_core, int(235 * bell)))
        fg = fg.filter(ImageFilter.GaussianBlur(10))
        fg.save(os.path.join(out_dir, f"fg_{fi:03d}.png"))


def build_bubble_iris_assets(out_dir: str, expand: bool, cx: int, cy: int, min_r: float, frames: int = 26):
    """水泡圆环膨胀进小店 / 收缩回胸口直接化身水泡护盾！"""
    os.makedirs(out_dir, exist_ok=True)
    max_r = math.hypot(W - cx, max(cy, H - cy)) + 40.0

    for fi in range(frames):
        p = fi / max(1, frames - 1)
        ease_p = p * p * (3.0 - 2.0 * p)
        r = (min_r + (max_r - min_r) * ease_p) if expand else (max_r - (max_r - min_r) * ease_p)

        mask = Image.new("L", (W, H), 0 if expand else 255)
        ImageDraw.Draw(mask).ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255 if expand else 0))
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
    src_path: str,
    ss: float,
    dur: float,
    out_mp4: str,
    crop: str | None = None,
    overlay_png: str | None = None,
    ovl_fade_in: float = 0.25,
    scale_flags: str = "lanczos",
    audio_gain: float = 0.0,
):
    vf_parts = []
    if crop:
        vf_parts.append(f"crop={crop}")
    vf_parts.extend([f"scale={W}:{H}:flags={scale_flags}", "setsar=1", "fps=60"])

    if overlay_png is None:
        cmd = [
            FFMPEG, "-y", "-ss", f"{ss:.3f}", "-t", f"{dur:.3f}", "-i", src_path,
            "-vf", ",".join(vf_parts),
            "-af", f"volume={audio_gain:.2f}",
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
            FFMPEG, "-y", "-ss", f"{ss:.3f}", "-t", f"{dur:.3f}", "-i", src_path,
            "-loop", "1", "-t", f"{dur:.3f}", "-i", overlay_png,
            "-filter_complex", fc,
            "-map", "[vout]", "-map", "0:a",
            "-af", f"volume={audio_gain:.2f}",
            "-c:v", "libx264", "-preset", "medium", "-crf", "15", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-ac", "2",
            out_mp4,
        ]
    run(cmd)


def render_masked_bridge(
    clip_a: str, a_ss: float, crop_a: str | None, flags_a: str,
    clip_b: str, b_ss: float, crop_b: str | None, flags_b: str,
    seq_dir: str, frames: int, out_mp4: str,
    gain_a: float = 0.0,
):
    dur = frames / 60.0
    mask_pat = os.path.join(seq_dir, "mask_%03d.png")
    fg_pat = os.path.join(seq_dir, "fg_%03d.png")

    va_chain = (f"crop={crop_a}," if crop_a else "") + f"scale={W}:{H}:flags={flags_a},setsar=1,fps=60"
    vb_chain = (f"crop={crop_b}," if crop_b else "") + f"scale={W}:{H}:flags={flags_b},setsar=1,fps=60"

    fc = (
        f"[0:v]{va_chain}[va];[1:v]{vb_chain}[vb];"
        f"[2:v]format=gray[mk];[vb][mk]alphamerge[vbm];"
        f"[va][vbm]overlay=0:0:shortest=1[bgm];"
        f"[3:v]format=rgba[fg];[bgm][fg]overlay=0:0:shortest=1[vout]"
    )
    run([
        FFMPEG, "-y",
        "-ss", f"{a_ss:.3f}", "-t", f"{dur:.3f}", "-i", clip_a,
        "-ss", f"{b_ss:.3f}", "-t", f"{dur:.3f}", "-i", clip_b,
        "-framerate", "60", "-i", mask_pat,
        "-framerate", "60", "-i", fg_pat,
        "-filter_complex", fc,
        "-map", "[vout]", "-map", "0:a",
        "-af", f"volume={gain_a:.2f}",
        "-c:v", "libx264", "-preset", "medium", "-crf", "15", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-ac", "2",
        out_mp4,
    ])


def render_bite_push(clip_kb: str, ss: float, dur: float, ovl_boss: str, out_mp4: str):
    """暖冬针织正面破弹 + 红眼狂暴黑鲸紧逼贴背凌空扑咬（后期微推景深增加绝境压迫感）。"""
    kb_dir = os.path.join(TMP, "kb_push_frames")
    os.makedirs(kb_dir, exist_ok=True)
    for fn in os.listdir(kb_dir):
        os.remove(os.path.join(kb_dir, fn))

    aud_wav = os.path.join(TMP, "kb_push_aud.wav")
    run([
        FFMPEG, "-y", "-ss", f"{ss:.3f}", "-t", f"{dur:.3f}", "-i", clip_kb,
        "-vf", "fps=60", os.path.join(kb_dir, "f_%04d.png"),
        "-vn", "-acodec", "pcm_s16le", "-ar", "44100", "-ac", "2", aud_wav,
    ])
    ovl_rgba = Image.open(ovl_boss).convert("RGBA")
    files = sorted([f for f in os.listdir(kb_dir) if f.startswith("f_") and f.endswith(".png")])

    vid_silent = os.path.join(TMP, "kb_push_silent.mp4")
    proc = subprocess.Popen([
        FFMPEG, "-y",
        "-f", "rawvideo", "-vcodec", "rawvideo", "-pix_fmt", "rgb24",
        "-s", f"{W}x{H}", "-r", "60", "-i", "-",
        "-c:v", "libx264", "-preset", "medium", "-crf", "15", "-pix_fmt", "yuv420p",
        vid_silent,
    ], stdin=subprocess.PIPE)

    n = max(1, len(files) - 1)
    for idx, fn in enumerate(files):
        t = idx / 60.0
        # 0.4s 后伴随黑鲸娘贴近逐步平滑推进至 1.18x（焦点锁定左下中景黑鲸娘与主角扑咬处）
        p = max(0.0, min(1.0, (t - 0.35) / max(0.2, dur - 0.35)))
        ease = p * p * (3.0 - 2.0 * p)
        zoom = 1.0 + 0.18 * ease
        cw = 1280.0 / zoom
        ch = 720.0 / zoom
        # 角色与扑咬位置大概在 1280x720 的 (360, 460) 偏左中下区域
        cx = 160.0 * ease
        cy = 180.0 * ease

        with Image.open(os.path.join(kb_dir, fn)) as src:
            cropped = src.crop((cx, cy, cx + cw, cy + ch))
            scaled = cropped.resize((W, H), Image.Resampling.NEAREST).convert("RGBA")

        scaled = Image.alpha_composite(scaled, ovl_rgba)
        proc.stdin.write(scaled.convert("RGB").tobytes())

    proc.stdin.close()
    proc.wait()
    if proc.returncode != 0:
        raise RuntimeError("Bite push render failed")

    run([
        FFMPEG, "-y", "-i", vid_silent, "-i", aud_wav,
        "-af", "volume=1.10",
        "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", out_mp4,
    ])


def render_cutoff_and_title(clip_intro: str, ovl_end: str, out_mp4: str):
    """全片唯一 1 次白闪（0.05s）+ 0.70s 纯黑死寂 + 5.60s 破浪高清定格标题页。"""
    p_silence = os.path.join(TMP, "seg_u_silence.mp4")
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

    dur_title = 5.60
    p_title = os.path.join(TMP, "seg_u_title.mp4")
    # 5.65s..7.00s 是 OpeningIntro 纯净破浪主视觉（菜单文字 7.30s 才开始淡入，干净无字！）
    fc = (
        f"[0:v]scale={W}:{H}:flags=neighbor,setsar=1,fps=60,"
        f"tpad=stop_mode=clone:stop_duration={dur_title - 1.35:.2f}[base];"
        f"[1:v]format=rgba,fade=t=in:st=1.00:d=0.45:alpha=1[ov];"
        f"[base][ov]overlay=0:0:shortest=1,fade=t=out:st={dur_title - 0.35:.2f}:d=0.35[vout]"
    )
    run([
        FFMPEG, "-y",
        "-ss", "5.650", "-t", "1.350", "-i", clip_intro,
        "-loop", "1", "-t", f"{dur_title:.3f}", "-i", ovl_end,
        "-filter_complex", fc,
        "-map", "[vout]", "-map", "0:a",
        "-af", f"apad=whole_dur={dur_title:.2f},volume=0.80",
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


def render_button_pan_zoom(shop_mp4: str, ovl_btn: str, out_mp4: str, total_dur: float = 6.20):
    """Button 尾音：用《鲸堡小店.mp4》后半段，1.0x 全景 → 平滑右移放大至 1.70x 墨镜黑鲸娘嘴硬特写。"""
    btn_dir = os.path.join(TMP, "btn_u_frames")
    os.makedirs(btn_dir, exist_ok=True)
    for fn in os.listdir(btn_dir):
        os.remove(os.path.join(btn_dir, fn))

    # 提取 5.40s ~ 8.65s (3.25s @60fps = ~195 帧)，定格在 8.65s 乔装黑鲸娘脸红偷吃冒泡峰值瞬间，避免 8.9s 后离座变空座
    run([
        FFMPEG, "-y", "-ss", "5.400", "-t", "3.250", "-i", shop_mp4,
        "-vf", f"crop={CROP_SHOP},fps=60", os.path.join(btn_dir, "f_%04d.png"),
    ])

    ovl_rgba = Image.open(ovl_btn).convert("RGBA")
    files = sorted([f for f in os.listdir(btn_dir) if f.startswith("f_") and f.endswith(".png")])
    n_total = int(round(total_dur * 60))

    vid_silent = os.path.join(TMP, "btn_u_silent.mp4")
    proc = subprocess.Popen([
        FFMPEG, "-y",
        "-f", "rawvideo", "-vcodec", "rawvideo", "-pix_fmt", "rgb24",
        "-s", f"{W}x{H}", "-r", "60", "-i", "-",
        "-c:v", "libx264", "-preset", "medium", "-crf", "15", "-pix_fmt", "yuv420p",
        vid_silent,
    ], stdin=subprocess.PIPE)

    t_hold_wide = 1.25
    t_pan_dur = 1.75
    t_quote_in = 2.85
    t_fade_out = total_dur - 0.50

    for idx in range(n_total):
        t = idx / 60.0
        fn = files[min(idx, len(files) - 1)]

        if t <= t_hold_wide:
            k = 0.0
        elif t <= t_hold_wide + t_pan_dur:
            u = (t - t_hold_wide) / t_pan_dur
            k = u * u * (3.0 - 2.0 * u)
        else:
            k = 1.0

        # 从全屏 (0,0,1280,720) 平滑右推放大到 (528, 76, 752, 423) 完整罩住墨镜黑鲸娘与气泡且裁去底栏
        cx = 528.0 * k
        cy = 76.0 * k
        cw = 1280.0 + (752.0 - 1280.0) * k
        ch = 720.0 + (423.0 - 720.0) * k

        with Image.open(os.path.join(btn_dir, fn)) as src:
            cropped = src.crop((cx, cy, cx + cw, cy + ch))
            scaled = cropped.resize((W, H), Image.Resampling.LANCZOS).convert("RGBA")

        if t >= t_quote_in:
            qa = min(1.0, (t - t_quote_in) / 0.30)
            ov = ovl_rgba.copy()
            if qa < 0.999:
                a_ch = ov.getchannel("A").point(lambda v: int(v * qa))
                ov.putalpha(a_ch)
            scaled = Image.alpha_composite(scaled, ov)

        if t < 0.15:
            br = t / 0.15
            scaled = Image.alpha_composite(scaled, Image.new("RGBA", (W, H), (0, 0, 0, int(255 * (1.0 - br)))))
        elif t >= t_fade_out:
            fo = min(1.0, (t - t_fade_out) / 0.50)
            scaled = Image.alpha_composite(scaled, Image.new("RGBA", (W, H), (0, 0, 0, int(255 * fo))))

        proc.stdin.write(scaled.convert("RGB").tobytes())

    proc.stdin.close()
    proc.wait()
    if proc.returncode != 0:
        raise RuntimeError("Button render failed")

    run([
        FFMPEG, "-y", "-i", vid_silent, "-f", "lavfi", "-t", f"{total_dur:.3f}", "-i", "anullsrc=r=44100:cl=stereo",
        "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", out_mp4,
    ])


def main():
    os.makedirs(OVL_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(PV_OUT), exist_ok=True)

    build_wave_wipe_assets(frames=36)
    build_speed_swipe_assets(SWIPE_CYAN_DIR, (42, 188, 245), (120, 236, 255), (224, 252, 255), frames=16)
    build_speed_swipe_assets(SWIPE_RED_DIR, (210, 38, 92), (255, 86, 130), (255, 224, 236), frames=14)
    build_bubble_iris_assets(IRIS_IN_DIR, expand=True, cx=565, cy=765, min_r=68.0, frames=26)
    build_bubble_iris_assets(IRIS_OUT_DIR, expand=False, cx=565, cy=785, min_r=104.0, frames=26)

    ovl_intro = make_badge_overlay("ovl_u_intro.png", "CHUBBY WHALE RUN", "《大肥鱼快跑》 · 极简三键深海跑酷", accent=(110, 236, 255), border=(90, 200, 255))
    ovl_skin = make_badge_overlay("ovl_u_skin.png", "STYLE & TERRAIN", "暖冬针织换装 · 百变深海险境", accent=(255, 224, 118), border=(245, 190, 88))
    ovl_shop = make_badge_overlay("ovl_u_shop.png", "WHALE BURGER", "鲸堡小店营业 · 拍★金脆赚贝壳币 · 吃堡加Buff", accent=(255, 214, 102), border=(245, 178, 76), bottom_y=20)
    ovl_shield = make_badge_overlay("ovl_u_shield.png", "BUBBLE SHIELD", "大水泡护盾觉醒 · 撞障碎盾不减速", accent=(112, 234, 255), border=(84, 204, 255))
    ovl_boss = make_badge_overlay("ovl_u_boss.png", "HARD MODE BOSS", "红转黑狂暴决战 · 三高度弹幕 · 绝境扑杀", accent=(255, 102, 134), border=(255, 76, 118))
    ovl_end = make_endcard_overlay("ovl_u_endcard.png")
    ovl_btn = make_button_quote_overlay("ovl_u_button.png")

    clip_intro = os.path.join(TMP, "clip_intro.avi")
    clip_bite = os.path.join(TMP, "clip_boss_knit_bite.avi")
    u_orig = os.path.join(USER_SRC, "原皮跑酷.mp4")
    u_skin = os.path.join(USER_SRC, "皮肤跑酷.mp4")
    u_shop = os.path.join(USER_SRC, "鲸堡小店.mp4")
    u_shield = os.path.join(USER_SRC, "护盾.mp4")
    u_boss = os.path.join(USER_SRC, "黑鲸娘狂暴.mp4")

    # ── 幕一 · Opening (0.00 ~ 5.15s)：完整 4 幕开场动画 → 第 4 幕黑鲸海浪直接擦出《原皮跑酷.mp4》
    s1_intro = os.path.join(TMP, "u1_intro.mp4")
    render_clip(clip_intro, 0.00, 4.55, s1_intro, crop=CROP_NONE, scale_flags="neighbor", audio_gain=1.00)

    s1_wipe = os.path.join(TMP, "u1_wipe.mp4")
    render_masked_bridge(
        clip_intro, 4.55, CROP_NONE, "neighbor",
        u_orig, 0.00, CROP_ORIG, "lanczos",
        WAVE_DIR, 36, s1_wipe, gain_a=0.90,
    )

    # ── 幕二 · Intro + 换装 (5.55 ~ 21.15s)：原皮跑酷 10.1s → 青蓝水幕扫屏 → 暖冬针织 5.03s
    s2_orig = os.path.join(TMP, "u2_orig.mp4")
    render_clip(u_orig, 0.60, 10.10, s2_orig, crop=CROP_ORIG, overlay_png=ovl_intro, scale_flags="lanczos", audio_gain=0.0)

    s2_swipe = os.path.join(TMP, "u2_swipe.mp4")
    render_masked_bridge(
        u_orig, 10.70, CROP_ORIG, "lanczos",
        u_skin, 0.15, CROP_784, "lanczos",
        SWIPE_CYAN_DIR, 16, s2_swipe, gain_a=0.0,
    )

    s2_knit = os.path.join(TMP, "u2_knit.mp4")
    render_clip(u_skin, 0.42, 5.03, s2_knit, crop=CROP_784, overlay_png=ovl_skin, scale_flags="lanczos", audio_gain=0.0)

    # ── 幕三 · Escalation (21.15 ~ 30.80s)：水泡展开进小店 5.22s → 水泡收缩变大护盾碎箱 3.37s
    s3_iris_in = os.path.join(TMP, "u3_iris_in.mp4")
    render_masked_bridge(
        u_skin, 5.45, CROP_784, "lanczos",
        u_shop, 0.15, CROP_SHOP, "lanczos",
        IRIS_IN_DIR, 26, s3_iris_in, gain_a=0.0,
    )

    s3_shop = os.path.join(TMP, "u3_shop.mp4")
    render_clip(u_shop, 0.58, 5.22, s3_shop, crop=CROP_SHOP, overlay_png=ovl_shop, scale_flags="lanczos", audio_gain=0.0)

    s3_iris_out = os.path.join(TMP, "u3_iris_out.mp4")
    render_masked_bridge(
        u_shop, 5.80, CROP_SHOP, "lanczos",
        u_shield, 0.10, CROP_784, "lanczos",
        IRIS_OUT_DIR, 26, s3_iris_out, gain_a=0.0,
    )

    s3_shield = os.path.join(TMP, "u3_shield.mp4")
    render_clip(u_shield, 0.53, 3.37, s3_shield, crop=CROP_784, overlay_png=ovl_shield, scale_flags="lanczos", audio_gain=0.0)

    # ── 幕四 · Climax (30.80 ~ 51.40s)：狂暴弹幕 12.15s → 顺切暖冬针织破弹+红眼扑咬 1.68s → 唯一白闪断音 → 标题页
    s4_boss = os.path.join(TMP, "u4_boss_user.mp4")
    render_clip(u_boss, 0.25, 12.15, s4_boss, crop=CROP_784, overlay_png=ovl_boss, scale_flags="lanczos", audio_gain=0.0)

    s4_cswipe = os.path.join(TMP, "u4_crimson_swipe.mp4")
    render_masked_bridge(
        u_boss, 12.40, CROP_784, "lanczos",
        clip_bite, 1.48, CROP_NONE, "neighbor",
        SWIPE_RED_DIR, 14, s4_cswipe, gain_a=0.0,
    )

    s4_bite = os.path.join(TMP, "u4_boss_bite.mp4")
    render_bite_push(clip_bite, 1.72, 1.68, ovl_boss, s4_bite)

    s4_title = os.path.join(TMP, "u4_title.mp4")
    render_cutoff_and_title(clip_intro, ovl_end, s4_title)

    # ── 幕五 · Button (51.40 ~ 57.60s)：叮铃回小店 1.0x → 1.70x 墨镜黑鲸娘嘴硬反转
    s5_btn = os.path.join(TMP, "u5_button.mp4")
    render_button_pan_zoom(u_shop, ovl_btn, s5_btn, total_dur=6.20)

    segs = [
        s1_intro, s1_wipe,
        s2_orig, s2_swipe, s2_knit,
        s3_iris_in, s3_shop, s3_iris_out, s3_shield,
        s4_boss, s4_cswipe, s4_bite, s4_title,
        s5_btn,
    ]

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

    t_wipe = starts[1]
    t_orig = starts[2]
    t_swipe_skin = starts[3]
    t_knit = starts[4]
    t_shop_in = starts[5] + 0.15
    t_shop = starts[6]
    t_shield_in = starts[7] + 0.15
    t_shield = starts[8]
    t_boss = starts[9]
    t_cswipe = starts[10]
    t_bite = starts[11]
    t_cutoff = starts[12]
    t_title = starts[12] + 0.77
    t_btn = starts[13]
    total_dur = acc
    print(f"[build_pv user] orig={t_orig:.2f}s knit={t_knit:.2f}s shop={t_shop_in:.2f}s shield={t_shield_in:.2f}s boss={t_boss:.2f}s bite={t_bite:.2f}s cutoff={t_cutoff:.2f}s btn={t_btn:.2f}s total={total_dur:.2f}s")

    concat_txt = os.path.join(TMP, "concat_user.txt")
    with open(concat_txt, "w", encoding="utf-8") as f:
        for p in segs:
            f.write(f"file '{p.replace(chr(92), '/')}'\n")

    raw_concat = os.path.join(TMP, "pv_raw_user.mp4")
    run([
        FFMPEG, "-y", "-f", "concat", "-safe", "0", "-i", concat_txt,
        "-c:v", "libx264", "-preset", "medium", "-crf", "15", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k",
        raw_concat,
    ])

    # ── 原生游戏 BGM + 交互 SFX 精准对位混音 ──
    bgm_run = os.path.join(ROOT, "audio", "bgm", "bgm_run.mp3")
    bgm_chase = os.path.join(ROOT, "audio", "bgm", "bgm_chase.ogg")
    bgm_shop = os.path.join(ROOT, "audio", "bgm", "bgm_shop.wav")
    bgm_menu = os.path.join(ROOT, "audio", "bgm", "bgm_menu.mp3")

    sfx_whoosh = os.path.join(ROOT, "audio", "intro_whoosh.wav")
    sfx_jump = os.path.join(ROOT, "audio", "sfx", "sfx_jump.wav")
    sfx_dash = os.path.join(ROOT, "audio", "sfx_dash.wav")
    sfx_near = os.path.join(ROOT, "audio", "sfx_near_miss.wav")
    sfx_hit = os.path.join(ROOT, "audio", "sfx", "sfx_hit.ogg")
    sfx_crisp = os.path.join(ROOT, "audio", "sfx", "shop_crisp.wav")
    sfx_coin = os.path.join(ROOT, "audio", "sfx", "shop_coin.wav")
    sfx_serve = os.path.join(ROOT, "audio", "sfx", "shop_serve.wav")
    sfx_warn = os.path.join(ROOT, "audio", "chase_warning.wav")
    sfx_heart = os.path.join(ROOT, "audio", "chase_heartbeat.wav")
    sfx_bite = os.path.join(ROOT, "audio", "sfx", "chase_bite.ogg")
    sfx_confirm = os.path.join(ROOT, "audio", "sfx", "ui_confirm.wav")

    m_run1_dur = max(1.0, t_shop_in - t_wipe + 0.10)
    m_shop1_dur = max(1.0, t_shield_in - t_shop_in + 0.15)
    m_run2_dur = max(1.0, t_boss - t_shield_in + 0.15)
    m_boss_dur = max(1.0, t_cutoff - t_boss)
    m_title_dur = max(1.0, t_btn - t_title)
    m_btn_dur = max(1.0, total_dur - t_btn)

    inputs = [
        "-i", raw_concat,     # 0: 视频实录与直录原始 SFX（开场水雷/海浪 + 补拍碎弹扑咬音）
        "-i", bgm_run,        # 1
        "-i", bgm_shop,       # 2
        "-i", bgm_chase,      # 3
        "-i", bgm_menu,       # 4
        "-i", sfx_whoosh,     # 5
        "-i", sfx_jump,       # 6
        "-i", sfx_dash,       # 7
        "-i", sfx_near,       # 8
        "-i", sfx_hit,        # 9
        "-i", sfx_crisp,      # 10
        "-i", sfx_coin,       # 11
        "-i", sfx_serve,      # 12
        "-i", sfx_warn,       # 13
        "-i", sfx_heart,      # 14
        "-i", sfx_bite,       # 15
        "-i", sfx_confirm,    # 16
    ]

    # 精准 SFX 时间点（单位：秒）
    sfx_events = [
        (5, t_wipe + 0.05, 0.72),          # 开场黑鲸海浪擦屏
        (6, t_orig + 2.50, 0.50),          # 原皮跳木箱
        (8, t_orig + 5.10, 0.45),          # 原皮擦身/滑过吊架
        (6, t_orig + 6.70, 0.50),          # 原皮跨断桥
        (7, t_orig + 7.95, 0.65),          # 原皮 Space 蓝色冲刺爆发！
        (13, t_orig + 9.45, 0.58),         # 黑鲸娘预警登场
        (7, t_swipe_skin + 0.02, 0.58),    # 速度水幕扫屏换装！
        (6, t_knit + 0.80, 0.48),          # 暖冬针织跳台阶
        (6, t_knit + 4.55, 0.48),          # 暖冬针织跃断桥
        (12, t_shop_in + 0.05, 0.62),      # 水泡进小店叮铃
        (10, t_shop + 1.95, 0.75),         # 小店拍中 ★金脆！
        (11, t_shop + 2.25, 0.65),         # 金脆贝壳币爆散！
        (9, t_shield + 0.90, 0.78),        # 护盾撞碎木箱碎盾音效！
        (6, t_shield + 1.68, 0.48),        # 碎盾后跳深沟
        (13, t_boss + 0.80, 0.72),         # 黑鲸娘红转黑锁血狂暴警报！
        (8, t_boss + 6.75, 0.52),          # 躲过第一波月牙飞刃擦身
        (8, t_boss + 11.40, 0.52),         # 躲过第二波月牙飞刃擦身
        (7, t_cswipe + 0.00, 0.58),        # 红黑斩光接高潮破弹！
        (14, t_bite + 0.60, 0.75),         # 贴背扑近心跳加速
        (15, t_bite + 1.32, 0.85),         # 凌空张嘴扑咬震撼音（至白闪戛然而止）
        (16, t_title + 0.04, 0.78),        # 寂静后主标题浮现确认音
        (12, t_btn + 0.02, 0.88),          # Button 尾音叮铃进小店
        (11, t_btn + 2.80, 0.55),          # 墨镜黑鲸娘吐双倍贝壳币彩蛋！
    ]

    fc_parts = ["[0:a]volume=1.00[sfx_raw]"]
    mix_labels = ["[sfx_raw]"]

    # 5 段原生配乐：
    # 1) 海浪擦屏起 bgm_run 至进小店
    fc_parts.append(
        f"[1:a]atrim=0:{m_run1_dur:.3f},asetpts=PTS-STARTPTS,"
        f"afade=t=in:st=0:d=0.25,afade=t=out:st={max(0.0, m_run1_dur - 0.25):.3f}:d=0.25,"
        f"volume=0.45,adelay={int(t_wipe * 1000)}|{int(t_wipe * 1000)}[m_r1]"
    )
    mix_labels.append("[m_r1]")

    # 2) 小店营业 5.5s: bgm_shop
    fc_parts.append(
        f"[2:a]atrim=0:{m_shop1_dur:.3f},asetpts=PTS-STARTPTS,"
        f"afade=t=in:st=0:d=0.18,afade=t=out:st={max(0.0, m_shop1_dur - 0.25):.3f}:d=0.25,"
        f"volume=0.50,adelay={int(t_shop_in * 1000)}|{int(t_shop_in * 1000)}[m_s1]"
    )
    mix_labels.append("[m_s1]")

    # 3) 水泡护盾破障回赛道: bgm_run 副歌推进段
    fc_parts.append(
        f"[1:a]atrim=16.0:{16.0 + m_run2_dur:.3f},asetpts=PTS-STARTPTS,"
        f"afade=t=in:st=0:d=0.16,afade=t=out:st={max(0.0, m_run2_dur - 0.18):.3f}:d=0.18,"
        f"volume=0.48,adelay={int(t_shield_in * 1000)}|{int(t_shield_in * 1000)}[m_r2]"
    )
    mix_labels.append("[m_r2]")

    # 4) Climax Boss 战: bgm_chase 推向顶峰，并在 t_cutoff 前 0.02s 彻底硬切断！
    fc_parts.append(
        f"[3:a]atrim=0:{m_boss_dur:.3f},asetpts=PTS-STARTPTS,"
        f"afade=t=in:st=0:d=0.18,afade=t=out:st={max(0.0, m_boss_dur - 0.02):.3f}:d=0.02,"
        f"volume=0.58,adelay={int(t_boss * 1000)}|{int(t_boss * 1000)}[m_cb]"
    )
    mix_labels.append("[m_cb]")

    # 5) 寂静后 Title Card: bgm_menu 温和亮海余韵
    fc_parts.append(
        f"[4:a]atrim=0:{m_title_dur:.3f},asetpts=PTS-STARTPTS,"
        f"afade=t=in:st=0:d=0.35,afade=t=out:st={max(0.0, m_title_dur - 0.40):.3f}:d=0.40,"
        f"volume=0.42,adelay={int(t_title * 1000)}|{int(t_title * 1000)}[m_ttl]"
    )
    mix_labels.append("[m_ttl]")

    # 6) Button 尾音彩蛋: bgm_shop 俏皮落幕
    fc_parts.append(
        f"[2:a]atrim=6.0:{6.0 + m_btn_dur:.3f},asetpts=PTS-STARTPTS,"
        f"afade=t=in:st=0:d=0.12,afade=t=out:st={max(0.0, m_btn_dur - 0.50):.3f}:d=0.50,"
        f"volume=0.52,adelay={int(t_btn * 1000)}|{int(t_btn * 1000)}[m_s2]"
    )
    mix_labels.append("[m_s2]")

    # 叠入精准时间点的原生 SFX
    for si, (inp_idx, ts_sec, vol) in enumerate(sfx_events):
        lbl = f"[sx{si}]"
        ms = max(0, int(round(ts_sec * 1000)))
        fc_parts.append(f"[{inp_idx}:a]volume={vol:.2f},adelay={ms}|{ms}{lbl}")
        mix_labels.append(lbl)

    fc_parts.append(
        f"{''.join(mix_labels)}amix=inputs={len(mix_labels)}:duration=first:dropout_transition=0:normalize=0,"
        f"alimiter=limit=0.95[aout]"
    )

    run([
        FFMPEG, "-y", *inputs,
        "-filter_complex", ";".join(fc_parts),
        "-map", "0:v", "-map", "[aout]",
        "-c:v", "copy",
        "-c:a", "aac", "-b:a", "224k", "-ar", "44100", "-ac", "2",
        "-movflags", "+faststart",
        PV_OUT,
    ])
    for old_p in PV_OLD_LIST:
        if os.path.exists(old_p):
            os.remove(old_p)
    print(f"[build_pv user] Done -> {PV_OUT}")


if __name__ == "__main__":
    main()
