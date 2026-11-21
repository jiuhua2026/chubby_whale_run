#!/usr/bin/env python3
"""生成深海沉船跑酷全套游戏音效 → `audio/*.wav`（16bit / 44.1kHz / 单声道）。

## 声音设计规范（深海沉船 + 鲸鱼娘主题）
避免简陋合成音的"生硬/尴尬感"，采用标准双二阶滤波器（Biquad Resonant Filter）、
多重谐波叠加、物理阻尼包络与软饱和压缩（Soft Saturation），打造浑厚有机的水下听感：
  1. sfx_jump.wav          - 水中跃起/蹬水水花声（低通滤波水声 + 柔和起跳推力）
  2. sfx_slide.wav         - 潜水滑行水流穿梭声（水流摩擦质感，平滑淡入淡出）
  3. sfx_near_miss.wav     - 擦身而过贴险奖励音（空灵清脆的高音水晶/水滴叮声，反馈感极强）
  4. sfx_dash_ready.wav    - 势能攒满 3 格就绪提示（短促上行晶体和弦，提醒按空格）
  5. sfx_dash.wav          - 冲刺爆发（水下高压水流喷射与鱼雷破水轰鸣）
  6. sfx_hit.wav           - 撞击障碍（沉闷水下钝击 + 木质/金属微碎裂声，不刺耳）
  7. sfx_fall.wav          - 坠入无底深渊（向下的低沉深海混响）
  8. chase_warning.wav     - 黑鲸娘追击开始警报（低频压迫声波）
  9. chase_heartbeat.wav   - 逼近贴身心跳（真实的低通肌肉收缩双拍心跳）
  10. chase_bite.wav       - 咬击瞬间（突发咬合闭合音 + 水下冲击定格）
  11. ui_move.wav          - 菜单光标移动（轻柔气泡音）
  12. ui_confirm.wav       - 菜单确认（清脆水泡破裂确认音）

用法：
  python tools/make_sfx.py
"""

import math
import os
import random
import struct
import sys
import wave

SR = 44100
OUT = "audio"


class Biquad:
    """标准 RBJ Audio EQ Cookbook 双二阶谐振滤波器。"""
    def set_params(self, filter_type: str, fc: float, q: float = 0.707, sr: int = 44100) -> None:
        fc = max(20.0, min(fc, float(sr) * 0.49))
        w0 = 2.0 * math.pi * fc / sr
        alpha = math.sin(w0) / (2.0 * max(0.01, q))
        cos_w = math.cos(w0)
        if filter_type == "lowpass":
            b0 = (1.0 - cos_w) * 0.5
            b1 = 1.0 - cos_w
            b2 = (1.0 - cos_w) * 0.5
            a0 = 1.0 + alpha
            a1 = -2.0 * cos_w
            a2 = 1.0 - alpha
        elif filter_type == "bandpass":
            b0 = alpha
            b1 = 0.0
            b2 = -alpha
            a0 = 1.0 + alpha
            a1 = -2.0 * cos_w
            a2 = 1.0 - alpha
        elif filter_type == "highpass":
            b0 = (1.0 + cos_w) * 0.5
            b1 = -(1.0 + cos_w)
            b2 = (1.0 + cos_w) * 0.5
            a0 = 1.0 + alpha
            a1 = -2.0 * cos_w
            a2 = 1.0 - alpha
        else:
            raise ValueError(f"Unknown filter type {filter_type}")
        self.b0 = b0 / a0
        self.b1 = b1 / a0
        self.b2 = b2 / a0
        self.a1 = a1 / a0
        self.a2 = a2 / a0

    def __init__(self, filter_type: str, fc: float, q: float = 0.707, sr: int = 44100):
        self.x1 = 0.0
        self.x2 = 0.0
        self.y1 = 0.0
        self.y2 = 0.0
        self.set_params(filter_type, fc, q, sr)

    def process(self, x: float) -> float:
        y = (self.b0 * x + self.b1 * self.x1 + self.b2 * self.x2
             - self.a1 * self.y1 - self.a2 * self.y2)
        self.x2 = self.x1
        self.x1 = x
        self.y2 = self.y1
        self.y1 = y
        return y


def soft_clip(x: float) -> float:
    """软饱和压缩，防止硬削波产生刺耳高频杂音。"""
    if x > 1.25:
        return 0.96
    if x < -1.25:
        return -0.96
    return math.tanh(x * 0.85) / math.tanh(0.85)


def write_wav(filename: str, samples: list, normalize_peak: float = 0.92):
    """保存 16-bit PCM WAV，带软饱和与峰值标准化。"""
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, filename)
    processed = [soft_clip(s) for s in samples]
    peak = max(1e-9, max(abs(s) for s in processed))
    gain = normalize_peak / peak if peak > 0.001 else 1.0

    raw_bytes = bytearray()
    for s in processed:
        val = int(max(-32767, min(32767, s * gain * 32767.0)))
        raw_bytes += struct.pack("<h", val)

    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(raw_bytes))

    rms = math.sqrt(sum(t * t for t in processed) / max(1, len(processed))) * gain
    dur = len(samples) / float(SR)
    print(f"  [OK] {filename:<22} len: {dur:.2f}s | peak: {peak * gain:.2f} | RMS: {rms:.3f}")


# ---------------------------------------------------------------- 音效发生器
def gen_jump():
    """水下跃起水花声：浑厚的推水声 + 气泡涌动。"""
    dur = 0.24
    n = int(SR * dur)
    filt = Biquad("lowpass", 320, 1.2, SR)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        # 频率从 80Hz 平滑升到 150Hz 的起跳推力
        f = 85.0 + (140.0 - 85.0) * math.pow(t / dur, 0.7)
        ph += 2 * math.pi * f / SR
        sine = math.sin(ph) * math.exp(-t * 12.0)
        noise = random.uniform(-1.0, 1.0) * math.exp(-t * 16.0) * 0.9
        filtered_noise = filt.process(noise)
        out.append(sine * 0.75 + filtered_noise * 0.6)
    write_wav("sfx_jump.wav", out, 0.90)


def gen_slide():
    """滑行水流穿梭声：水下高速滑行动力水声。"""
    dur = 0.38
    n = int(SR * dur)
    bp = Biquad("bandpass", 420, 1.4, SR)
    lp = Biquad("lowpass", 650, 0.8, SR)
    out = []
    for i in range(n):
        t = i / SR
        # 包络：平缓起伏，头尾无爆音
        env = math.sin(math.pi * (t / dur))
        noise = random.uniform(-1.0, 1.0)
        water = lp.process(bp.process(noise))
        # 极低频水涌感
        bubble = math.sin(2 * math.pi * 55 * t) * 0.35 * env
        out.append((water * 1.6 + bubble) * env)
    write_wav("sfx_slide.wav", out, 0.85)


def gen_near_miss():
    """擦身而过（Near Miss）奖励音：空灵清脆的高音水滴/水晶叮声。"""
    dur = 0.42
    n = int(SR * dur)
    f0 = 1174.66  # D6
    f1 = 2349.32  # 泛音 D7
    f2 = 3520.00  # 高频谐波 A7
    out = []
    for i in range(n):
        t = i / SR
        # 快起指数衰减
        atk = min(1.0, t / 0.002)
        env0 = atk * math.exp(-t * 9.0)
        env1 = atk * math.exp(-t * 14.0)
        env2 = atk * math.exp(-t * 22.0)
        s0 = math.sin(2 * math.pi * f0 * t) * env0
        s1 = math.sin(2 * math.pi * f1 * t) * env1 * 0.45
        s2 = math.sin(2 * math.pi * f2 * t) * env2 * 0.20
        out.append(s0 + s1 + s2)
    write_wav("sfx_near_miss.wav", out, 0.90)


def gen_dash_ready():
    """势能满 3 格提示音：清脆上行晶体和弦（C6 -> E6 -> G6）。"""
    dur = 0.48
    n = int(SR * dur)
    out = [0.0] * n
    notes = [1046.50, 1318.51, 1567.98]  # C6, E6, G6
    stagger = int(SR * 0.055)
    for idx, f in enumerate(notes):
        st = idx * stagger
        for i in range(st, n):
            t = (i - st) / SR
            atk = min(1.0, t / 0.002)
            env = atk * math.exp(-t * 12.0)
            tone = (math.sin(2 * math.pi * f * t)
                    + 0.3 * math.sin(4 * math.pi * f * t)) * env
            out[i] += tone * 0.55
    write_wav("sfx_dash_ready.wav", out, 0.92)


def gen_dash():
    """冲刺爆发：强力水下鱼雷推进爆发轰鸣。"""
    dur = 0.65
    n = int(SR * dur)
    lp = Biquad("lowpass", 700, 1.5, SR)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        # 低频下潜冲击
        f = 90.0 * math.exp(-t * 5.0) + 38.0
        ph += 2 * math.pi * f / SR
        sub = math.sin(ph) * math.exp(-t * 3.5)
        # 水流喷射噪声
        noise = random.uniform(-1.0, 1.0) * math.exp(-t * 4.2)
        jet = lp.process(noise)
        out.append(sub * 0.8 + jet * 0.75)
    write_wav("sfx_dash.wav", out, 0.92)


def gen_hit():
    """撞击障碍：低沉钝击 + 水下闷响（无失真刺耳声）。"""
    dur = 0.32
    n = int(SR * dur)
    lp = Biquad("lowpass", 280, 1.0, SR)
    bp = Biquad("bandpass", 450, 2.0, SR)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = 140.0 * math.exp(-t * 16.0) + 40.0
        ph += 2 * math.pi * f / SR
        sub = math.sin(ph) * math.exp(-t * 11.0)
        # 木质断裂轻微冲击
        crack = bp.process(random.uniform(-1.0, 1.0) * math.exp(-t * 30.0))
        thud = lp.process(random.uniform(-1.0, 1.0) * math.exp(-t * 14.0))
        out.append(sub * 0.85 + thud * 0.45 + crack * 0.35)
    write_wav("sfx_hit.wav", out, 0.92)


def gen_fall():
    """坠入深渊：向下的低沉深海回荡。"""
    dur = 0.95
    n = int(SR * dur)
    lp = Biquad("lowpass", 220, 0.8, SR)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = max(24.0, 95.0 - 75.0 * (t / dur))
        ph += 2 * math.pi * f / SR
        sub = math.sin(ph) * (1.0 - t / dur)
        noise = lp.process(random.uniform(-1.0, 1.0) * (1.0 - t / dur) * 0.5)
        out.append((sub * 0.7 + noise * 0.4) * math.exp(-t * 1.8))
    write_wav("sfx_fall.wav", out, 0.88)


def gen_chase_warning():
    """追击开始声呐警报：低音悬疑回波。"""
    dur = 0.75
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        env = math.sin(math.pi * (t / dur)) * math.exp(-t * 1.5)
        # 拍频次中音（悬疑不安感）
        tone = (math.sin(2 * math.pi * 185.0 * t) * 0.6
                + math.sin(2 * math.pi * 192.0 * t) * 0.6)
        out.append(tone * env)
    write_wav("chase_warning.wav", out, 0.86)


def gen_chase_heartbeat():
    """贴身心跳声：深海压迫感真实心跳（咚-咚 双拍，极低频低通）。"""
    dur = 0.38
    n = int(SR * dur)
    lp = Biquad("lowpass", 110, 1.1, SR)
    out = [0.0] * n

    def beat(t_local, decay):
        f = 52.0 * math.exp(-t_local * 8.0)
        ph = 2 * math.pi * f * t_local
        atk = min(1.0, t_local / 0.008)
        return math.sin(ph) * math.exp(-t_local * decay) * atk

    # 第一拍 Lub (较大)
    for i in range(n):
        t = i / SR
        out[i] += beat(t, 20.0) * 0.95

    # 第二拍 Dub (稍小，延迟 0.145s)
    st2 = int(SR * 0.145)
    for i in range(st2, n):
        t2 = (i - st2) / SR
        out[i] += beat(t2, 24.0) * 0.65

    filtered = [lp.process(s) for s in out]
    write_wav("chase_heartbeat.wav", filtered, 0.94)


def gen_chase_bite():
    """咬击音效：黑鲸娘巨口咬合与冲击闭合顿挫。"""
    dur = 0.42
    n = int(SR * dur)
    lp = Biquad("lowpass", 350, 1.2, SR)
    bp = Biquad("bandpass", 800, 2.5, SR)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = 160.0 * math.exp(-t * 18.0) + 36.0
        ph += 2 * math.pi * f / SR
        sub = math.sin(ph) * math.exp(-t * 9.0)
        # 前 25ms 快速闭合脆响
        snap = bp.process(random.uniform(-1.0, 1.0) * math.exp(-t * 45.0)) * 1.5
        # 冲击水波
        wave_thud = lp.process(random.uniform(-1.0, 1.0) * math.exp(-t * 12.0))
        out.append(sub * 0.8 + snap * 0.7 + wave_thud * 0.5)
    write_wav("chase_bite.wav", out, 0.95)


def gen_ui_move():
    """菜单光标移动：柔和气泡泡裂声。"""
    dur = 0.08
    n = int(SR * dur)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = 420.0 + 380.0 * (t / dur)
        ph += 2 * math.pi * f / SR
        env = math.sin(math.pi * (t / dur))
        out.append(math.sin(ph) * env)
    write_wav("ui_move.wav", out, 0.70)


def gen_ui_confirm():
    """菜单确认音：清脆水滴确认音。"""
    dur = 0.18
    n = int(SR * dur)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = 680.0 + 520.0 * math.pow(t / dur, 0.5)
        ph += 2 * math.pi * f / SR
        atk = min(1.0, t / 0.003)
        env = atk * math.exp(-t * 18.0)
        out.append(math.sin(ph) * env)
    write_wav("ui_confirm.wav", out, 0.80)


# ---------------------------------------------------------------- 开场大片定制音效
def gen_intro_buildup():
    """片头前段（Stage 1~2）蓄力音床：深海暗流底噪 + 逐步加速的水下战鼓心跳 + 声呐微鸣。"""
    dur = 5.00
    n = int(SR * dur)
    out = [0.0] * n
    flow_lp = Biquad("lowpass", 150.0, 0.85, SR)
    shimmer_lp = Biquad("lowpass", 920.0, 0.70, SR)

    # 1. 深海暗流 + 低频和声铺底（前 0.35s 柔入，4.55s 后柔出交给 whoosh）
    for i in range(n):
        t = i / SR
        fade_in = min(1.0, t / 0.35)
        fade_out = 1.0 if t < 4.50 else max(0.0, 1.0 - (t - 4.50) / 0.50)
        swell = 0.32 + 0.68 * math.pow(min(1.0, t / 4.45), 1.35)
        env = fade_in * fade_out * swell

        if (i & 31) == 0:
            flow_lp.set_params("lowpass", 140.0 + 260.0 * min(1.0, t / 4.45), 0.9, SR)
        current = flow_lp.process(random.uniform(-1.0, 1.0)) * 0.55

        # A1 (55Hz) + E2 (82.4Hz) 沉稳低频海渊底噪
        drone = (math.sin(2 * math.pi * 55.0 * t) * 0.42
                 + math.sin(2 * math.pi * 82.41 * t) * 0.24
                 + math.sin(2 * math.pi * 110.0 * t) * 0.10) * 0.42
        out[i] += (current + drone) * env

    # 2. 渐进加速的水下重鼓/心跳脉动（越近越急、越重）
    hits = [
        (0.45, 0.32), (1.20, 0.38), (1.85, 0.44), (2.42, 0.52),
        (2.90, 0.60), (3.30, 0.68), (3.64, 0.76), (3.92, 0.84),
        (4.16, 0.92), (4.36, 1.00),
    ]
    drum_lp = Biquad("lowpass", 145.0, 1.05, SR)
    drum_buf = [0.0] * n
    for hit_t, weight in hits:
        st = int(hit_t * SR)
        beat_len = int(0.48 * SR)
        ph = 0.0
        for k in range(beat_len):
            idx = st + k
            if idx >= n:
                break
            tl = k / SR
            f = 42.0 + 48.0 * math.exp(-tl * 16.0)
            ph += 2 * math.pi * f / SR
            atk = min(1.0, tl / 0.008)
            env = atk * math.exp(-tl * 8.5)
            thud = (math.sin(ph) * 0.85 + math.sin(ph * 2.0) * 0.18) * env
            drum_buf[idx] += thud * weight * 0.85
    for i in range(n):
        out[i] += drum_lp.process(drum_buf[i])

    # 3. 两声极克制的深海空灵泛音（定调神秘感）
    for ping_t, base_f, amp in [(0.35, 587.33, 0.18), (2.42, 659.25, 0.22)]:
        st = int(ping_t * SR)
        plen = int(1.6 * SR)
        for k in range(plen):
            idx = st + k
            if idx >= n:
                break
            tl = k / SR
            atk = min(1.0, tl / 0.015)
            p_env = atk * math.exp(-tl * 2.4)
            tone = (math.sin(2 * math.pi * base_f * tl)
                    + 0.35 * math.sin(2 * math.pi * base_f * 1.5 * tl)) * p_env
            out[idx] += shimmer_lp.process(tone * amp)

    write_wav("intro_buildup.wav", out, 0.88)


def gen_intro_whoosh():
    """巨鲸贴脸横扫遮罩音效（Stage 3）：多普勒水浪啸声 + 重磅近身空化压迫。"""
    dur = 1.45
    n = int(SR * dur)
    bp = Biquad("bandpass", 200.0, 1.35, SR)
    lp = Biquad("lowpass", 360.0, 0.90, SR)
    out = [0.0] * n
    sub_ph = 0.0
    for i in range(n):
        t = i / SR
        u = t / dur
        # 对称略前倾的能量包络：0.44s 到达最强贴脸峰值
        peak_shape = math.sin(math.pi * math.pow(u, 0.78))
        # 多普勒中心频扫：160Hz -> 780Hz (接近) -> 125Hz (远去掀开画面)
        doppler_curve = math.exp(-((u - 0.42) / 0.22) ** 2)
        fc = 140.0 + 640.0 * doppler_curve
        if (i & 15) == 0:
            bp.set_params("bandpass", fc, 1.30, SR)
            lp.set_params("lowpass", 200.0 + 700.0 * doppler_curve, 0.85, SR)

        noise = random.uniform(-1.0, 1.0)
        sweep = bp.process(noise) * 1.45 + lp.process(noise) * 0.55

        # 巨物掠过时的低频水压震腹感
        sub_f = 34.0 + 48.0 * doppler_curve
        sub_ph += 2 * math.pi * sub_f / SR
        belly = math.sin(sub_ph) * (0.45 + 0.55 * doppler_curve)

        out[i] = (sweep * 0.85 + belly * 0.65) * peak_shape
    write_wav("intro_whoosh.wav", out, 0.94)


def gen_intro_impact():
    """遮罩拉开定格瞬间爆音（Stage 4）：深海炸浪重低音冲击 + 清澈深海水晶水花共鸣尾韵。"""
    dur = 1.65
    n = int(SR * dur)
    sub_lp = Biquad("lowpass", 280.0, 0.95, SR)
    chime_lp = Biquad("lowpass", 2400.0, 0.72, SR)
    splash_bp = Biquad("bandpass", 780.0, 1.35, SR)
    out = [0.0] * n

    sub_ph = 0.0
    for i in range(n):
        t = i / SR
        atk = min(1.0, t / 0.002)

        # 1. 瞬态低音炮冲击（175Hz 极速下潜至 42Hz，给切镜定格带来强劲拳感）
        f_sub = 42.0 + 135.0 * math.exp(-t * 30.0)
        sub_ph += 2 * math.pi * f_sub / SR
        sub = (math.sin(sub_ph) * 0.90 + math.sin(sub_ph * 2.0) * 0.22) * atk * math.exp(-t * 2.9)

        # 2. 海浪炸开的清脆水沫爆破感（前 140ms 贴合泡沫遮罩散开）
        splash = splash_bp.process(random.uniform(-1.0, 1.0)) * atk * math.exp(-t * 14.0) * 0.95

        # 3. 灵动明亮的深海水晶泛音和弦（C5 + G5 + D6，取代厚重古钟，契合萌系深海主题）
        c_atk = min(1.0, t / 0.008)
        chime_raw = (
            math.sin(2 * math.pi * 523.25 * t) * 0.45 * math.exp(-t * 1.9)
            + math.sin(2 * math.pi * 783.99 * t) * 0.36 * math.exp(-t * 2.3)
            + math.sin(2 * math.pi * 1046.50 * t) * 0.26 * math.exp(-t * 2.8)
            + math.sin(2 * math.pi * 1174.66 * t) * 0.16 * math.exp(-t * 3.4)
        ) * c_atk
        chime = chime_lp.process(chime_raw)

        tail_fade = 1.0 if t < dur - 0.22 else max(0.0, (dur - t) / 0.22)
        out[i] = (sub_lp.process(sub * 1.05) + splash * 0.58 + chime * 0.56) * tail_fade

    write_wav("intro_impact.wav", out, 0.94)


def main():
    intro_only = "--intro-only" in sys.argv
    print("=" * 60)
    if intro_only:
        print("正在生成片头开场定制音效...")
    else:
        print("正在生成深海鲸鱼娘跑酷全套拟真游戏音效...")
    print("=" * 60)
    random.seed(20261018)

    if not intro_only:
        gen_jump()
        gen_slide()
        gen_near_miss()
        gen_dash_ready()
        gen_dash()
        gen_hit()
        gen_fall()
        gen_chase_warning()
        gen_chase_heartbeat()
        gen_chase_bite()
        gen_ui_move()
        gen_ui_confirm()

    # 固定独立随机种子，确保 --intro-only 与全量生成的片头音效完全一致
    random.seed(20261116)
    gen_intro_buildup()
    gen_intro_whoosh()
    gen_intro_impact()

    print("=" * 60)
    count = 3 if intro_only else 15
    print(f"全部 {count} 款音效已成功生成至 {OUT}/ 目录！")
    print("=" * 60)


if __name__ == "__main__":
    main()
