#!/usr/bin/env python3
"""生成「深海鲸堡小店」专属循环背景音乐 -> `audio/bgm/bgm_shop.wav`（16bit / 44.1kHz / 双声道）。

音乐气质：
  · 100 BPM · 16 小节（38.4 秒无缝相位对齐循环）
  · 温暖咖啡馆感：暖心电钢/马林巴和弦 + 弹性贝斯 + 轻脆沙锤扫弦 + 深海晴朗木琴主旋律
"""

import math
import os
import random
import struct
import wave

SR = 44100
BPM = 100.0
BEAT = 60.0 / BPM          # 0.6s
BAR = BEAT * 4.0           # 2.4s
BARS = 16
DUR = BAR * BARS           # 38.4s
N_SAMPLES = int(round(SR * DUR))

OUT_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "audio", "bgm", "bgm_shop.wav")


def midi_to_hz(m: float) -> float:
    return 440.0 * (2.0 ** ((m - 69.0) / 12.0))


def add_note_wrap(buf_l, buf_r, start_sec: float, note_len: float, fn, amp: float, pan: float = 0.0):
    """把音符安全写进循环缓冲，尾部越界自动回卷到开头实现零咔哒无缝循环。"""
    s0 = int(round(start_sec * SR))
    cnt = int(round(note_len * SR))
    gl = amp * math.sqrt(max(0.0, 0.5 * (1.0 - pan)))
    gr = amp * math.sqrt(max(0.0, 0.5 * (1.0 + pan)))
    for k in range(cnt):
        t = k / SR
        v = fn(t, note_len)
        idx = (s0 + k) % N_SAMPLES
        buf_l[idx] += v * gl
        buf_r[idx] += v * gr


def synth_epiano(hz: float):
    def fn(t: float, dur: float) -> float:
        atk = min(1.0, t / 0.014)
        rel = 1.0 if t < dur - 0.12 else max(0.0, (dur - t) / 0.12)
        env = atk * rel * math.exp(-t * 1.45)
        w1 = math.sin(2.0 * math.pi * hz * t)
        w2 = 0.34 * math.sin(2.0 * math.pi * hz * 2.0 * t) * math.exp(-t * 3.0)
        bell = 0.14 * math.sin(2.0 * math.pi * hz * 4.0 * t) * math.exp(-t * 11.0)
        return (w1 + w2 + bell) * env
    return fn


def synth_marimba(hz: float):
    def fn(t: float, dur: float) -> float:
        atk = min(1.0, t / 0.005)
        rel = 1.0 if t < dur - 0.04 else max(0.0, (dur - t) / 0.04)
        env = atk * rel * math.exp(-t * 4.8)
        w1 = math.sin(2.0 * math.pi * hz * t)
        w4 = 0.22 * math.sin(2.0 * math.pi * hz * 3.98 * t) * math.exp(-t * 14.0)
        return (w1 + w4) * env
    return fn


def synth_bass(hz: float):
    def fn(t: float, dur: float) -> float:
        atk = min(1.0, t / 0.010)
        rel = 1.0 if t < dur - 0.05 else max(0.0, (dur - t) / 0.05)
        env = atk * rel * math.exp(-t * 3.1)
        w1 = math.sin(2.0 * math.pi * hz * t)
        w2 = 0.28 * math.sin(2.0 * math.pi * hz * 2.0 * t) * math.exp(-t * 5.0)
        return (w1 + w2) * env
    return fn


def synth_shaker(rng: random.Random, accent: bool):
    seed_vals = [rng.uniform(-1.0, 1.0) for _ in range(int(SR * 0.065))]

    def fn(t: float, dur: float) -> float:
        idx = min(len(seed_vals) - 1, int(t * SR))
        prev = seed_vals[max(0, idx - 1)]
        hp = seed_vals[idx] - prev
        env = min(1.0, t / 0.004) * math.exp(-t * (42.0 if accent else 62.0))
        return hp * env * (0.95 if accent else 0.55)
    return fn


def main():
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    rng = random.Random(20261127)
    buf_l = [0.0] * N_SAMPLES
    buf_r = [0.0] * N_SAMPLES

    # 和弦进行（C 大调治愈系咖啡馆循环）：
    # Fmaj7 - G6 - Em7 - Am7 / Fmaj7 - G7 - Cmaj7 - C7 /
    # Fmaj7 - G6 - Em7 - A7  / Dm7 - G13 - Cmaj7 - G7sus4
    chords = [
        ([53, 60, 64, 69], 41),  # Fmaj7
        ([55, 62, 64, 67], 43),  # G6
        ([52, 59, 62, 67], 40),  # Em7
        ([57, 60, 64, 67], 45),  # Am7
        ([53, 60, 64, 69], 41),  # Fmaj7
        ([55, 59, 62, 65], 43),  # G7
        ([48, 59, 64, 67], 36),  # Cmaj7
        ([48, 58, 64, 67], 36),  # C7
        ([53, 60, 64, 69], 41),  # Fmaj7
        ([55, 62, 64, 67], 43),  # G6
        ([52, 59, 62, 67], 40),  # Em7
        ([57, 61, 64, 67], 45),  # A7
        ([50, 57, 60, 65], 38),  # Dm7
        ([55, 59, 64, 65], 43),  # G13
        ([48, 59, 64, 67], 36),  # Cmaj7
        ([55, 60, 62, 67], 43),  # G7sus4
    ]

    # 16 小节木琴小调主旋律 (beat_offset_in_bar, midi_note, length_in_beats)
    melody_bars = [
        [(0.0, 76, 0.75), (0.75, 79, 0.75), (1.5, 81, 1.0), (3.0, 79, 0.75)],
        [(0.0, 76, 1.0), (1.5, 74, 0.75), (2.5, 76, 1.25)],
        [(0.0, 79, 0.75), (0.75, 76, 0.75), (1.5, 74, 1.0), (2.75, 72, 0.75)],
        [(0.0, 74, 1.0), (1.25, 76, 0.75), (2.25, 72, 1.5)],
        [(0.0, 76, 0.75), (0.75, 79, 0.75), (1.5, 81, 0.75), (2.25, 84, 1.25)],
        [(0.0, 83, 0.75), (1.0, 81, 0.75), (2.0, 79, 1.0), (3.25, 76, 0.5)],
        [(0.0, 79, 1.5), (1.75, 76, 0.75), (2.75, 74, 1.0)],
        [(0.0, 72, 1.25), (1.5, 74, 0.75), (2.5, 76, 1.0)],
        [(0.0, 81, 0.75), (0.75, 84, 0.75), (1.5, 81, 0.75), (2.5, 79, 1.25)],
        [(0.0, 76, 0.75), (1.0, 79, 0.75), (2.0, 83, 1.0), (3.25, 79, 0.5)],
        [(0.0, 76, 1.0), (1.5, 79, 0.75), (2.5, 81, 1.25)],
        [(0.0, 79, 0.75), (1.0, 76, 0.75), (2.0, 73, 1.25)],
        [(0.0, 74, 0.75), (0.75, 77, 0.75), (1.5, 81, 1.0), (2.75, 79, 0.75)],
        [(0.0, 76, 0.75), (1.0, 74, 0.75), (2.0, 72, 1.0), (3.25, 74, 0.5)],
        [(0.0, 76, 1.5), (1.75, 79, 0.75), (2.75, 76, 1.0)],
        [(0.0, 74, 1.0), (1.5, 72, 0.75), (2.5, 74, 1.0)],
    ]

    for b_idx, (notes, bass_root) in enumerate(chords):
        bar_t = b_idx * BAR
        # 温暖电钢拍点节奏（1 拍 + 2.5 拍切分小晃感）
        for hit_beat, hit_len, amp in [(0.0, 1.75, 0.085), (2.0, 1.65, 0.070)]:
            for ni, mn in enumerate(notes):
                pan = -0.28 + 0.18 * ni
                add_note_wrap(buf_l, buf_r, bar_t + hit_beat * BEAT, hit_len * BEAT, synth_epiano(midi_to_hz(mn)), amp, pan)

        # 弹性深海贝斯（1 拍 + 2.5 拍 + 3.5 拍）
        for beat_off, m_note, b_len, b_amp in [
            (0.0, bass_root, 1.2, 0.17),
            (2.0, bass_root + 7, 0.9, 0.12),
            (3.0, bass_root + 12, 0.7, 0.10),
        ]:
            add_note_wrap(buf_l, buf_r, bar_t + beat_off * BEAT, b_len * BEAT, synth_bass(midi_to_hz(m_note)), b_amp, 0.0)

        # 轻快咖啡馆沙锤（八分音符微摆）
        for e in range(8):
            is_off = (e % 2 == 1)
            pan = 0.24 if is_off else -0.20
            add_note_wrap(buf_l, buf_r, bar_t + e * 0.5 * BEAT, 0.06, synth_shaker(rng, is_off), 0.042, pan)

        # 晴朗木琴主旋律
        for b_off, m_note, m_len in melody_bars[b_idx]:
            add_note_wrap(buf_l, buf_r, bar_t + b_off * BEAT, m_len * BEAT, synth_marimba(midi_to_hz(m_note)), 0.145, 0.10)

    # 软压缩归一 + 输出 16bit Stereo WAV
    peak = max(1e-6, max(max(abs(x) for x in buf_l), max(abs(x) for x in buf_r)))
    scale = 0.78 / peak if peak > 0.78 else 1.0
    pcm = bytearray(N_SAMPLES * 4)
    for i in range(N_SAMPLES):
        l = max(-0.98, min(0.98, math.tanh(buf_l[i] * scale * 1.1)))
        r = max(-0.98, min(0.98, math.tanh(buf_r[i] * scale * 1.1)))
        struct.pack_into("<hh", pcm, i * 4, int(l * 32767.0), int(r * 32767.0))

    with wave.open(OUT_PATH, "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(pcm)
    print(f"[make_bgm_shop] Generated {OUT_PATH} ({DUR:.1f}s stereo 44.1kHz)")


if __name__ == "__main__":
    main()
