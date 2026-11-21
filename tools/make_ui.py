"""Generate crisp 2x-nearest pixel-art UI textures for Chubby Whale Run.

Every sprite is authored on an exact 1x logical pixel grid using pure Python + Pillow
and scaled 2x with Image.Resampling.NEAREST so StyleBoxTexture and TextureRect align
to the game's pixel density without blurring.
"""
from __future__ import annotations

import os
from PIL import Image

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "sprites", "ui")


def hx(s: str, a: int = 255) -> tuple[int, int, int, int]:
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), a)


def new_canvas(w: int, h: int) -> Image.Image:
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def save_2x(img: Image.Image, name: str) -> str:
    os.makedirs(OUT_DIR, exist_ok=True)
    up = img.resize((img.width * 2, img.height * 2), Image.Resampling.NEAREST)
    path = os.path.join(OUT_DIR, name)
    up.save(path)
    return path


def draw_bitmap(
    img: Image.Image,
    rows: list[str],
    palette: dict[str, tuple[int, int, int, int]],
    ox: int = 0,
    oy: int = 0,
) -> None:
    px = img.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in palette:
                ix, iy = ox + x, oy + y
                if 0 <= ix < img.width and 0 <= iy < img.height:
                    px[ix, iy] = palette[ch]


def make_panel_frame() -> Image.Image:
    """48x48 logical -> 96x96 output, 9-slice margin = 28px (14 logical)."""
    w, h = 48, 48
    img = new_canvas(w, h)
    px = img.load()

    outline = hx("#040811")
    rim_hi = hx("#4c74a1")
    rim_mid = hx("#274162")
    rim_lo = hx("#132238")
    rim_deep = hx("#0a1422")
    trench = hx("#060b14")
    inner_hi = hx("#29476b")
    bg_dark = hx("#08111f", 240)
    bg_step = hx("#0a1526", 240)

    brass_hi = hx("#f2c879")
    brass_mid = hx("#b87c3b")
    brass_lo = hx("#5c361a")

    moss_hi = hx("#69a888")
    moss_mid = hx("#3e705c")
    coral = hx("#cf78b2")

    for y in range(h):
        for x in range(w):
            # Chamfered corners (cut outer 2 pixels cleanly).
            d_tl = x + y
            d_tr = (w - 1 - x) + y
            d_bl = x + (h - 1 - y)
            d_br = (w - 1 - x) + (h - 1 - y)
            if min(d_tl, d_tr, d_bl, d_br) <= 1:
                continue

            edge = min(x, w - 1 - x, y, h - 1 - y)
            corner_cut = min(d_tl, d_tr, d_bl, d_br) == 2

            if edge == 0 or corner_cut:
                px[x, y] = outline
            elif edge == 1:
                # Top / left crisp rim highlight, bottom / right dark stone shadow.
                if y == 1 or x == 1:
                    px[x, y] = rim_hi
                else:
                    px[x, y] = rim_deep
            elif edge in (2, 3, 4):
                # Keep masonry joint accents strictly inside the unstretched 14px corners.
                in_corner_slice = (x < 14 or x >= w - 14) and (y < 14 or y >= h - 14)
                near_joint = (x in (11, w - 12) and y in (2, 3, h - 4, h - 3)) or (
                    y in (11, h - 12) and x in (2, 3, w - 4, w - 3)
                )
                if near_joint or (in_corner_slice and edge == 3 and (x + y) % 7 == 0):
                    px[x, y] = rim_lo
                elif y <= 4 or x <= 4:
                    px[x, y] = rim_mid if edge != 2 else hx("#33547b")
                else:
                    px[x, y] = rim_lo
            elif edge == 5:
                px[x, y] = trench
            elif edge == 6:
                px[x, y] = inner_hi if (y == 6 or x == 6) else hx("#172840")
            else:
                px[x, y] = bg_dark

    # Corner brass rivets inside the 14px corner margin.
    rivet = [
        ".OO.",
        "OHMO",
        "OMLO",
        ".OO.",
    ]
    pal_rivet = {"O": outline, "H": brass_hi, "M": brass_mid, "L": brass_lo}
    for rx, ry in [(3, 3), (w - 7, 3), (3, h - 7), (w - 7, h - 7)]:
        draw_bitmap(img, rivet, pal_rivet, rx, ry)

    # Small abyssal sea-moss & tiny coral dots nestled along rim edges (safe inside 14px corners).
    moss_tl = [
        "..HM..",
        ".HHMM.",
        "HMC.M.",
    ]
    pal_moss = {"H": moss_hi, "M": moss_mid, "C": coral}
    draw_bitmap(img, moss_tl, pal_moss, 8, 1)

    moss_br = [
        ".MH..",
        "CMHH.",
        ".MM..",
    ]
    draw_bitmap(img, moss_br, pal_moss, w - 13, h - 5)

    return img


def make_stat_slot() -> Image.Image:
    """24x24 logical -> 48x48 output, 9-slice margin = 12px (6 logical)."""
    w, h = 24, 24
    img = new_canvas(w, h)
    px = img.load()

    trench = hx("#040810")
    shadow_in = hx("#07101c")
    lip_lo = hx("#233c5d")
    lip_corner = hx("#162840")
    fill = hx("#0a1627", 232)

    for y in range(h):
        for x in range(w):
            d = min(x + y, (w - 1 - x) + y, x + (h - 1 - y), (w - 1 - x) + (h - 1 - y))
            if d == 0:
                continue
            edge = min(x, w - 1 - x, y, h - 1 - y)
            if edge == 0 or d == 1:
                px[x, y] = trench
            elif edge == 1:
                if y == 1 or x == 1:
                    px[x, y] = shadow_in
                elif y == h - 2 or x == w - 2:
                    px[x, y] = lip_lo
                else:
                    px[x, y] = lip_corner
            else:
                px[x, y] = fill
    return img


def make_keycap_frame(cyan_glow: bool = False) -> Image.Image:
    """18x18 logical -> 36x36 output, 9-slice margin = 10px (5 logical top/left/right, 12px bottom)."""
    w, h = 18, 18
    img = new_canvas(w, h)
    px = img.load()

    if cyan_glow:
        outline = hx("#061829")
        top_hi = hx("#9efaff")
        face = hx("#23688f")
        face_lo = hx("#194f70")
        lip_top = hx("#133a57")
        lip_bot = hx("#0c273d")
    else:
        outline = hx("#050912")
        top_hi = hx("#6391c2")
        face = hx("#233b59")
        face_lo = hx("#1a2d47")
        lip_top = hx("#122036")
        lip_bot = hx("#0b1526")

    for y in range(h):
        for x in range(w):
            d = min(x + y, (w - 1 - x) + y, x + (h - 1 - y), (w - 1 - x) + (h - 1 - y))
            if d == 0:
                continue
            if x == 0 or x == w - 1 or y == 0 or y == h - 1 or d == 1:
                px[x, y] = outline
            elif y == 1:
                px[x, y] = top_hi
            elif y <= h - 5:
                px[x, y] = face if x < w - 2 else face_lo
            elif y == h - 4:
                px[x, y] = lip_top
            else:
                px[x, y] = lip_bot
    return img


def make_warn_ribbon(tint: str) -> Image.Image:
    """160x22 logical -> 320x44 output: bright high-contrast horizontally feathered ribbon."""
    w, h = 160, 22
    img = new_canvas(w, h)
    px = img.load()

    if tint == "amber":
        core = (48, 29, 10)
        line_col = (255, 214, 92)
        inner_glow = (146, 94, 24)
    else:
        core = (74, 14, 22)
        line_col = (255, 92, 104)
        inner_glow = (182, 34, 52)

    fade_w = 40
    for y in range(h):
        for x in range(w):
            # Stepped pixel alpha fade at left & right edges (no crisp border!).
            if x < fade_w:
                t = x / float(fade_w)
            elif x >= w - fade_w:
                t = (w - 1 - x) / float(fade_w)
            else:
                t = 1.0
            # Quantize horizontal fade into clean 7 steps for pixel cohesion.
            qt = int(t * 7.0) / 7.0
            if qt <= 0.0:
                continue

            if y in (0, h - 1):
                continue
            elif y in (1, h - 2):
                a = int(225 * qt)
                px[x, y] = (line_col[0], line_col[1], line_col[2], a)
            elif y in (2, h - 3):
                a = int(195 * qt)
                px[x, y] = (inner_glow[0], inner_glow[1], inner_glow[2], a)
            else:
                a = int(238 * qt)
                px[x, y] = (core[0], core[1], core[2], a)
    return img


def make_icon_compass() -> Image.Image:
    """16x16 logical -> 32x32 output."""
    rows = [
        "......OOOO......",
        ".....OHHHHO.....",
        "....OHDDDDHO....",
        "..OOHDWWWWHDHO..",
        ".OHHDWWWWWWDDHO.",
        ".OHDWDDWWDWDDHO.",
        "OHDWWDDWWDDWWDHO",
        "OHDWWWCWWCWWWDHO",
        "OHDWWCCWWCCWWDHO",
        "OHDWCCCBBCCWWDHO",
        ".OHDWCCBBCWWDHO.",
        ".OMHDCCBBCCHDMO.",
        "..OOMDDDDDDMOO..",
        "....OMMMMMMO....",
        ".....OOOOOO.....",
        "................",
    ]
    # Cleaner crisp compass art:
    rows = [
        ".....OOOOOO.....",
        "....OHHHHHHO....",
        "..OOHDDDDDDHOO..",
        ".OHDDWWDDWWDDHO.",
        ".OHDWDDDDDDWDHO.",
        "OHDWDDDWWDDDWDD.",
        "OHDDDDWWWWDDDDHO",
        "OHDDWWWWWWWWDDHO",
        "OHDDDDCCCCDDDDHO",
        "OHDWDDCCCCDDWDHO",
        ".OHDWDDCCDDWDHO.",
        ".OMDDDCCCCDDDMO.",
        "..OOMDDDDDDMOO..",
        "....OMMMMMMO....",
        ".....OOOOOO.....",
        "................",
    ]
    # Ensure exact 16-char rows with brass top loop!
    rows = [
        "......OOOO......",
        ".....OHMMHO.....",
        "....OOHHHHOO....",
        "..OOHDDDDDDHOO..",
        ".OHDDWDDDDWDDHO.",
        ".OHDDDDWWDDDDHO.",
        "OHDDDDWWWWDDDDHO",
        "OHDDWWWWWWWWDDHO",
        "OHDDDDCCCCDDDDHO",
        "OHDDDDCCCCDDDDHO",
        ".OHDWDDCCDDWDHO.",
        ".OMDDDDCCDDDDMO.",
        "..OOMDDDDDDMOO..",
        "....OMMMMMMO....",
        ".....OOOOOO.....",
        "................",
    ]
    pal = {
        "O": hx("#050912"),
        "H": hx("#ffe38a"),
        "M": hx("#c48634"),
        "D": hx("#0c192c"),
        "W": hx("#f4f9ff"),
        "C": hx("#47bfff"),
    }
    img = new_canvas(16, 16)
    draw_bitmap(img, rows, pal)
    return img


def make_icon_pearl() -> Image.Image:
    """16x16 logical -> 32x32 output: scalloped shell cradling a golden pearl."""
    rows = [
        "................",
        "....OOOOOOOO....",
        "..OOBBSSSSBBOO..",
        ".OBSSWWWWWWSSBO.",
        ".OBSWWWWWWWWSBO.",
        "OBSWWWGGGGWWWSBO",
        "OBSWWGGGGGGWWSBO",
        "OBSWWGGHHGGWWSBO",
        "OBSWWGGGGGGWWSBO",
        ".OBDDDDGGGGDDBO.",
        ".OBBDDDDDDDDDBO.",
        "..OOBBDDDDDBBOO.",
        "...OBSDDDDSSBO..",
        "....OOBBBBBOO...",
        "......OOOOO.....",
        "................",
    ]
    # Better pearl + fanned scallop ridges:
    rows = [
        ".....OOOOOO.....",
        "...OOHHHHHHOO...",
        "..OHHDDDDDDHHO..",
        ".OHDDWWGGGGDDHO.",
        ".OHDWGGGGGGGGHO.",
        "OHDDWGHHGGGGGGHO",
        "OHDDWGGGGGGGGGHO",
        "OBSDDGGGGGGGGSBO",
        "OBSSDDGGGGGGSSBO",
        ".OBSSDDDDDDSSBO.",
        ".OBBSSDDDDSSBBO.",
        "..OOBBSSSSBBOO..",
        "...OOBSSSSBOO...",
        "....OOBBBBOO....",
        ".....OOOOOO.....",
        "................",
    ]
    # Even crisper open clam shell + golden glowing pearl center!
    rows = [
        ".....OOOOOO.....",
        "...OOSSSSSSOO...",
        "..OSSBSSSSBSSO..",
        ".OSSBDDSSDDSSSO.",
        ".OSBDWWWWWWDBSO.",
        "OSBDWWGGGGWWDBSO",
        "OSBDWGGHHGGWDBSO",
        "OSBDWGGGGGGWDBSO",
        "OBBSDDGGGGDDSBBO",
        ".OBSSDDDDDDSSBO.",
        ".OBBSSDSSDSSBBO.",
        "..OOBSSSSSSBBOO.",
        "...OOBBBBBBBBO..",
        "....OOOOOOOOO...",
        "................",
        "................",
    ]
    pal = {
        "O": hx("#050912"),
        "S": hx("#4a82a8"),
        "B": hx("#234766"),
        "D": hx("#0c1b2e"),
        "W": hx("#fff6c4"),
        "G": hx("#ffd044"),
        "H": hx("#ffffff"),
    }
    img = new_canvas(16, 16)
    draw_bitmap(img, rows, pal)
    return img


def make_dash_tube_base() -> Image.Image:
    """68x13 logical -> 136x26 output: unified deep-sea glass energy conduit housing."""
    w, h = 68, 13
    img = new_canvas(w, h)
    px = img.load()

    outline = hx("#040912")
    rim_hi = hx("#5888bf")
    cap_hi = hx("#82b8f0")
    cap_mid = hx("#2b486b")
    cap_lo = hx("#162840")
    trench = hx("#070f1c")
    glass_bg = hx("#091526", 218)
    glass_top = hx("#0d1e36", 224)
    inner_bot = hx("#2c4a70")
    bot_casing = hx("#132338")
    bolt_hi = hx("#9be8ff")
    bolt_lo = hx("#30608a")

    for y in range(h):
        for x in range(w):
            d = min(x + y, (w - 1 - x) + y, x + (h - 1 - y), (w - 1 - x) + (h - 1 - y))
            if d == 0:
                continue
            if x == 0 or x == w - 1 or y == 0 or y == h - 1 or d == 1:
                px[x, y] = outline
            elif x in (1, 2, 3, 4) or x in (w - 5, w - 4, w - 3, w - 2):
                # Steel beveled end-caps on left and right.
                if y == 1:
                    px[x, y] = cap_hi if x in (1, 2, w - 3, w - 2) else rim_hi
                elif y == h - 2:
                    px[x, y] = cap_lo
                elif x in (4, w - 5):
                    px[x, y] = trench
                elif x in (1, w - 2):
                    px[x, y] = cap_mid
                else:
                    px[x, y] = cap_hi if y <= 3 else (cap_mid if y <= 8 else cap_lo)
            elif y == 1:
                px[x, y] = rim_hi
            elif y == 2:
                px[x, y] = trench
            elif y == h - 3:
                px[x, y] = inner_bot
            elif y == h - 2:
                px[x, y] = bot_casing
            elif y == 3:
                px[x, y] = glass_top
            else:
                px[x, y] = glass_bg

    # Tiny aqua gauge rivets on left and right endcaps.
    for rx in (2, w - 4):
        px[rx, 5] = bolt_hi
        px[rx + 1, 5] = cap_mid
        px[rx, 6] = bolt_lo
        px[rx + 1, 6] = cap_lo
        px[rx, 7] = bolt_lo
    return img


def make_dash_tube_overlay() -> Image.Image:
    """68x13 logical -> 136x26 output: steel divider ribs & curved glass specular gleam."""
    w, h = 68, 13
    img = new_canvas(w, h)
    px = img.load()

    rib_hi = hx("#699bd1")
    rib_mid = hx("#335780")
    rib_lo = hx("#162840")
    rib_edge = hx("#050b14")
    gleam = (205, 245, 255, 62)

    dividers = (23, 24, 43, 44)
    for y in range(2, h - 2):
        for x in dividers:
            if y in (2, h - 3):
                px[x, y] = rib_mid if x in (23, 43) else rib_edge
            elif y in (3, 4):
                px[x, y] = rib_hi if x in (23, 43) else rib_lo
            else:
                px[x, y] = rib_mid if x in (23, 43) else rib_edge

    # Crisp glass reflection glint along upper window row across the 3 chambers.
    for x in range(6, 62):
        if x not in dividers:
            px[x, 3] = gleam
    return img


def _make_warn_triangle(pal: dict[str, tuple[int, int, int, int]]) -> Image.Image:
    rows = [
        ".......OO.......",
        "......OOOO......",
        ".....OOHHOO.....",
        "....OHMMMMHO....",
        "....OHMBBMHO....",
        "...OHMMBBMMHO...",
        "...OHMMBBMMHO...",
        "..OHMMMBBMMMHO..",
        "..OHMMMBBMMMHO..",
        ".OHMMMMBBMMMMHO.",
        ".OHMMMMMMMMMMHO.",
        "OHMMMMMBBMMMMMHO",
        "OHMMMMMBBMMMMMHO",
        "OMMMMMMMMMMMMMMO",
        ".OOOOOOOOOOOOOO.",
        "................",
    ]
    img = new_canvas(16, 16)
    draw_bitmap(img, rows, pal)
    return img


def make_icon_warn_amber() -> Image.Image:
    """16x16 logical -> 32x32 output: bright high-contrast amber warning triangle."""
    return _make_warn_triangle({
        "O": hx("#180a04"),
        "H": hx("#fff4a8"),
        "M": hx("#ffbe30"),
        "B": hx("#1e0902"),
    })


def make_icon_warn_chase() -> Image.Image:
    """16x16 logical -> 32x32 output: bright high-contrast crimson warning triangle."""
    return _make_warn_triangle({
        "O": hx("#1a0308"),
        "H": hx("#ffd4da"),
        "M": hx("#ff3e52"),
        "B": hx("#1f0206"),
    })


def make_badge_bite() -> Image.Image:
    """26x22 logical -> 52x44 output: abyssal whale snapping jaws + crimson eyes."""
    rows = [
        "........OOOOOOOOOO........",
        "......OOHHHHHHHHHHOO......",
        "....OOHMMMMMMMMMMMMHOO....",
        "...OHMMMRRMMMMMMRRMHHMO...",
        "..OHMMMRWWRMMMMRWWRMMHMO..",
        "..OHMMMMRRMMMMMMRRMMMMHO..",
        ".OHMMMMMMMMMMMMMMMMMMMMHO.",
        ".OOMMMMMMMDDDDDDMMMMMMMOO.",
        "OOMWWMDWWWMDDDDMWWWMDWWMOO",
        "OODWWDDWWWDDDDDDWWWDDWWDDO",
        "OODDDDDDDDDDDDDDDDDDDDDDDO",
        "OODWWDDWWWDDDDDDWWWDDWWDDO",
        "OOMWWMMWWWMMMMMMWWWMMWWMOO",
        ".OOMMMMMMMMMMMMMMMMMMMMOO.",
        ".OHMMDDDDDDDDDDDDDDDDMMHO.",
        "..OHMMMMMMMMMMMMMMMMMMHO..",
        "...OOMMMMMMMMMMMMMMMMOO...",
        "....OOOMMMMMMMMMMMMOOO....",
        "......OOOOOOOOOOOOOO......",
        "..........................",
        "..........................",
        "..........................",
    ]
    pal = {
        "O": hx("#04060d"),
        "H": hx("#545b8f"),
        "M": hx("#1c1e38"),
        "D": hx("#0b0a17"),
        "R": hx("#ff364f"),
        "W": hx("#f2f7ff"),
    }
    img = new_canvas(26, 22)
    draw_bitmap(img, rows, pal)
    return img


def make_badge_wall() -> Image.Image:
    """26x22 logical -> 52x44 output: curling abyssal tsunami wave crest."""
    rows = [
        "........OOOOOOOOOO........",
        "......OOWWWWWWWWWWO.......",
        "....OOWWWCCCCHHHHHWOO.....",
        "...OOWWCCCCCCCCHHHWWWO....",
        "..OOWCCCCBBBBBBCCCHWWWO...",
        ".OOWCCCBBBBBBBBBBCCCHWWO..",
        ".OOWCCBBBBBBBBBBBBCCCHWO..",
        "OOWCCBBBBBBDDDDDBBBCCWWO..",
        "OOWCBBBBDDDD..OOOOBCCWO...",
        "OOWCBBBDDD...OO..OOO......",
        "OOWCBBBDDD.......OOWO.....",
        "OOWCCBBBDDD...............",
        "OOWCCBBBBDDDD.......OO....",
        "OOWCCCBBBBBBDDDDDDDOO.....",
        ".OOWCCCCBBBBBBBBBBCOO.....",
        ".OOWWCCCCCBBBBBBBBCCOO....",
        "..OOBBCCCCCCCCCCCCCCOO....",
        "...OOBBBBBBBBBBBBBBBOO....",
        "....OOOOOOOOOOOOOOOOO.....",
        "..........................",
        "..........................",
        "..........................",
    ]
    pal = {
        "O": hx("#040914"),
        "W": hx("#e6fbff"),
        "H": hx("#9ef0ff"),
        "C": hx("#3db8f5"),
        "B": hx("#1968a6"),
        "D": hx("#0b2747"),
    }
    img = new_canvas(26, 22)
    draw_bitmap(img, rows, pal)
    return img


def make_badge_chasm() -> Image.Image:
    """26x22 logical -> 52x44 output: split abyssal cliff + plunging vortex."""
    rows = [
        "..OOOOOO..........OOOOOO..",
        ".OGGGGGGO........OGGGGGGO.",
        "OHHHHHHHHO......OHHHHHHHHO",
        "OMMMMMMMMO......OMMMMMMMMO",
        "OMMDDDDMMO..OO..OMMDDDDMMO",
        "OMDDDDDDMO.OCCO.OMDDDDDDMO",
        "OMDDDDDMMO..OO..OMMDDDDDMO",
        "OMDDDDDDMO......OMDDDDDDMO",
        ".OMDDDDDMO..OO..OMDDDDDMO.",
        ".OMMDDDDMO.OCCO.OMDDDDMMO.",
        "..OMDDDDMO..OO..OMDDDDMO..",
        "..OMMDDDMO......OMDDDMMO..",
        "...OMDDDMO..OO..OMDDDMO...",
        "...OMMDDMO.OVVO.OMDDMMO...",
        "....OMDDMO..OO..OMDDMO....",
        "....OMDDMOOOOOOOOOMDMO....",
        ".....OMDDMMMMMMMMDDMO.....",
        "......OOMMMMMMMMMMOO......",
        ".......OOOOOOOOOOOO.......",
        "..........................",
        "..........................",
        "..........................",
    ]
    pal = {
        "O": hx("#040811"),
        "G": hx("#599c7f"),
        "H": hx("#3f6491"),
        "M": hx("#1f3552"),
        "D": hx("#0c1729"),
        "C": hx("#91d9ff"),
        "V": hx("#ff7866"),
    }
    img = new_canvas(26, 22)
    draw_bitmap(img, rows, pal)
    return img


def main() -> None:
    outputs = [
        ("panel_frame.png", make_panel_frame()),
        ("stat_slot.png", make_stat_slot()),
        ("keycap_frame.png", make_keycap_frame(False)),
        ("keycap_cyan_frame.png", make_keycap_frame(True)),
        ("warn_ribbon_amber.png", make_warn_ribbon("amber")),
        ("warn_ribbon_crimson.png", make_warn_ribbon("crimson")),
        ("dash_tube_base.png", make_dash_tube_base()),
        ("dash_tube_overlay.png", make_dash_tube_overlay()),
        ("icon_warn_amber.png", make_icon_warn_amber()),
        ("icon_warn_chase.png", make_icon_warn_chase()),
        ("badge_bite.png", make_badge_bite()),
        ("badge_wall.png", make_badge_wall()),
        ("badge_chasm.png", make_badge_chasm()),
    ]
    for name, img in outputs:
        p = save_2x(img, name)
        print(f"wrote {p} ({img.width*2}x{img.height*2})")


if __name__ == "__main__":
    main()
