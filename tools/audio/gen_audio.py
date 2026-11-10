"""Genera los efectos de sonido y la música del juego por síntesis (sin grabaciones ni librerías externas).
Uso:  python3 tools/audio/gen_audio.py   →  godot/assets/audio/*.wav
"""
import math
import os
import random
import struct
import wave

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "godot", "assets", "audio")
os.makedirs(OUT, exist_ok=True)
rnd = random.Random(7)
TAU = math.tau


def buf(seconds):
    return [0.0] * int(SR * seconds)


def save(name, data, gain=0.9):
    peak = max(1e-9, max(abs(x) for x in data))
    k = gain / peak
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, math.tanh(x * k * 1.2) / math.tanh(1.2))) * 32767)) for x in data))
    print(name, round(len(data) / SR, 2), "s")


def osc(kind, ph):
    x = ph % 1.0
    if kind == "sine":
        return math.sin(TAU * x)
    if kind == "tri":
        return 4 * abs(x - 0.5) - 1
    if kind == "saw":
        return 2 * x - 1
    if kind == "square":
        return 1.0 if x < 0.5 else -1.0
    return 0.0


def tone(data, start, dur, f0, f1=None, kind="sine", vol=1.0, attack=0.005, curve=3.0, wrap=False, vib=0.0):
    """Añade una nota con barrido de frecuencia y caída exponencial."""
    n = int(dur * SR); s0 = int(start * SR); ph = 0.0; N = len(data)
    f1 = f0 if f1 is None else f1
    for i in range(n):
        t = i / n
        f = f0 * (f1 / f0) ** t
        if vib:
            f *= 1 + vib * math.sin(TAU * 6 * i / SR)
        ph += f / SR
        e = min(1.0, i / max(1, attack * SR)) * math.exp(-curve * t) * (1 - t) ** 0.5
        j = s0 + i
        if wrap:
            j %= N
        elif j >= N:
            break
        data[j] += osc(kind, ph) * e * vol


def noise(data, start, dur, vol=1.0, lp0=0.5, lp1=None, hp=False, attack=0.004, curve=3.0):
    """Ruido filtrado (paso bajo de un polo, con barrido); hp=True deja solo los agudos."""
    n = int(dur * SR); s0 = int(start * SR); y = 0.0
    lp1 = lp0 if lp1 is None else lp1
    for i in range(n):
        t = i / n
        a = lp0 + (lp1 - lp0) * t
        x = rnd.uniform(-1, 1)
        y += a * (x - y)
        v = (x - y) if hp else y
        e = min(1.0, i / max(1, attack * SR)) * math.exp(-curve * t) * (1 - t) ** 0.5
        if s0 + i < len(data):
            data[s0 + i] += v * e * vol


# ---------------------------------------------------------------- efectos
d = buf(0.06); tone(d, 0, 0.05, 950, 700, "sine", 1, curve=6); save("tap", d, 0.5)

d = buf(0.2); noise(d, 0, 0.16, 1, 0.7, 0.15, hp=True, curve=4); tone(d, 0.0, 0.03, 1800, 900, "tri", 0.25, curve=8); save("card", d, 0.7)
d = buf(0.24); noise(d, 0, 0.2, 1, 0.25, 0.6, hp=False, curve=3.5); noise(d, 0.02, 0.12, 0.5, 0.8, 0.3, hp=True); save("draw", d, 0.6)
d = buf(0.7)
for k in range(7):
    noise(d, k * 0.075 + rnd.uniform(0, 0.015), 0.09, 0.8, 0.75, 0.2, hp=True, curve=5)
save("shuffle", d, 0.65)

d = buf(0.6); tone(d, 0, 0.45, 660, kind="sine", curve=4); tone(d, 0, 0.45, 1320, kind="sine", vol=0.25, curve=5)
tone(d, 0.13, 0.45, 990, kind="sine", curve=4); tone(d, 0.13, 0.45, 1980, kind="sine", vol=0.2, curve=5); save("turn", d, 0.6)

d = buf(0.5); tone(d, 0, 0.2, 230, 170, "square", 0.6, curve=1.5); tone(d, 0.17, 0.3, 160, 105, "square", 0.7, curve=1.8)
tone(d, 0, 0.2, 115, 85, "saw", 0.5, curve=1.5); tone(d, 0.17, 0.3, 80, 52, "saw", 0.6, curve=1.8); save("nope", d, 0.7)
d = buf(0.5); tone(d, 0, 0.18, 520, 700, "tri", 0.7, curve=2.5); tone(d, 0.14, 0.32, 780, 1050, "tri", 0.8, curve=2.5); save("yup", d, 0.6)

# mecha: siseo creciente + pitido que sube (tensión antes de explotar)
d = buf(1.0)
n = len(d); y = 0.0
for i in range(n):
    t = i / n; x = rnd.uniform(-1, 1); y += 0.8 * (x - y)
    d[i] += (x - y) * (0.15 + 0.85 * t * t) * 0.8
for k in range(9):
    tone(d, 0.05 + k * (0.105 - k * 0.004), 0.05, 900 + k * 90, kind="square", vol=0.22, curve=3)
save("fuse", d, 0.6)

d = buf(1.7)
tone(d, 0, 1.5, 120, 32, "sine", 1.4, attack=0.002, curve=2.4)
tone(d, 0, 0.9, 75, 28, "tri", 0.8, attack=0.002, curve=3)
noise(d, 0, 1.5, 1.2, 0.5, 0.03, hp=False, attack=0.001, curve=3.2)
noise(d, 0, 0.25, 0.9, 0.9, 0.4, hp=True, attack=0.001, curve=6)
for k in range(10):
    noise(d, 0.15 + rnd.uniform(0, 0.9), 0.08, 0.25, 0.3, 0.1, curve=5)
save("explosion", d, 0.95)

d = buf(1.2)
tone(d, 0, 1.05, 62, 98, "saw", 0.9, attack=0.08, curve=1.2, vib=0.06)
tone(d, 0.02, 1.0, 93, 147, "saw", 0.45, attack=0.1, curve=1.4, vib=0.08)
tone(d, 0.25, 0.8, 392, 587, "sine", 0.3, attack=0.1, curve=1.5, vib=0.02)
noise(d, 0, 1.0, 0.35, 0.05, 0.25, curve=1.5, attack=0.1)
# suavizado (voz grave)
y = 0.0
for i in range(len(d)):
    y += 0.25 * (d[i] - y); d[i] = y
save("zombie", d, 0.85)

d = buf(0.4)
for k in range(2):
    noise(d, k * 0.13, 0.11, 1, 0.9, 0.2, hp=True, curve=4); tone(d, k * 0.13, 0.09, 1400, 500, "saw", 0.3, curve=5)
save("attack", d, 0.7)
d = buf(0.5); tone(d, 0, 0.16, 110, 70, "saw", 1, curve=2.5); tone(d, 0.2, 0.22, 110, 62, "saw", 1, curve=2.5); noise(d, 0, 0.4, 0.3, 0.1, curve=3); save("alarm", d, 0.75)
d = buf(0.22); tone(d, 0, 0.16, 320, 760, "tri", 1, curve=3); save("steal", d, 0.55)
d = buf(0.9)
for k, f in enumerate([392, 523, 659, 784, 1047]):
    tone(d, k * 0.09, 0.5, f, kind="sine", vol=0.6, curve=3); tone(d, k * 0.09, 0.5, f * 2, kind="sine", vol=0.15, curve=4)
save("revive", d, 0.6)
d = buf(1.9)
for k, f in enumerate([523, 659, 784, 1047, 784, 1047, 1319]):
    tone(d, k * 0.13, 0.9, f, kind="tri", vol=0.7, curve=2.2); tone(d, k * 0.13, 0.9, f / 2, kind="sine", vol=0.4, curve=2.2)
save("win", d, 0.7)
d = buf(1.8)
for k, f in enumerate([392, 370, 330, 262, 196]):
    tone(d, k * 0.24, 0.8, f, kind="tri", vol=0.7, curve=2.0, vib=0.01); tone(d, k * 0.24, 0.8, f / 2, kind="saw", vol=0.25, curve=2.2)
save("lose", d, 0.65)

# ---------------------------------------------------------------- música: vals tétrico en bucle (La menor)
BPM = 104
beat = 60 / BPM
bar = beat * 3
chords = [("Am", [220.0, 261.63, 329.63]), ("F", [174.61, 220.0, 261.63]), ("Dm", [146.83, 220.0, 293.66]), ("E", [164.81, 207.65, 246.94]),
          ("Am", [220.0, 261.63, 329.63]), ("C", [130.81, 261.63, 329.63]), ("Dm", [146.83, 220.0, 293.66]), ("E", [164.81, 207.65, 329.63])]
melody = [  # (compás, tiempo, frecuencia, duración en tiempos)
    (0, 0, 659.25, 2), (0, 2, 587.33, 1), (1, 0, 523.25, 2), (1, 2, 440.0, 1), (2, 0, 587.33, 1), (2, 1, 698.46, 1), (2, 2, 587.33, 1), (3, 0, 493.88, 3),
    (4, 0, 659.25, 1), (4, 1, 880.0, 2), (5, 0, 783.99, 2), (5, 2, 659.25, 1), (6, 0, 698.46, 1), (6, 1, 587.33, 1), (6, 2, 440.0, 1), (7, 0, 415.3, 3),
]
m = buf(bar * len(chords) * 2)
total_bars = len(chords) * 2
for b in range(total_bars):
    name, notes = chords[b % len(chords)]
    t0 = b * bar
    root = notes[0] / 2
    tone(m, t0, beat * 2.6, root, kind="sine", vol=0.55, attack=0.01, curve=2.2, wrap=True)
    tone(m, t0, beat * 2.6, root * 2, kind="tri", vol=0.12, attack=0.01, curve=3, wrap=True)
    for k in (1, 2):
        for f in notes[1:]:
            tone(m, t0 + k * beat, beat * 0.9, f, kind="tri", vol=0.13, attack=0.004, curve=4, wrap=True)
    # colchón suave y desafinado
    for f in notes:
        tone(m, t0, bar * 1.1, f * 1.003, kind="sine", vol=0.035, attack=0.3, curve=0.6, wrap=True)
        tone(m, t0, bar * 1.1, f * 0.997 * 2, kind="sine", vol=0.02, attack=0.3, curve=0.6, wrap=True)
for rep in range(2):
    for (b, bt, f, dur) in melody:
        t0 = (b + rep * len(chords)) * bar + bt * beat
        oct_ = 1.0 if rep == 0 else 2.0   # la segunda vuelta, una octava arriba (cajita de música)
        vol = 0.22 if rep == 0 else 0.12
        tone(m, t0, beat * dur * 1.3, f * oct_, kind="sine", vol=vol, attack=0.003, curve=3, wrap=True)
        tone(m, t0, beat * dur * 0.8, f * oct_ * 2, kind="sine", vol=vol * 0.3, attack=0.003, curve=5, wrap=True)
        tone(m, t0, beat * dur * 0.5, f * oct_ * 3.01, kind="sine", vol=vol * 0.12, attack=0.003, curve=7, wrap=True)
save("music", m, 0.6)
