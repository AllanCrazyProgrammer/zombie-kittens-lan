"""Genera los efectos de sonido y la música del juego por síntesis (sin grabaciones ni librerías externas).
Uso:  python3 tools/audio/gen_audio.py            →  genera TODO (efectos y música originales + los nuevos)
      python3 tools/audio/gen_audio.py crow tick  →  genera solo esos (nunca toca los originales)
      python3 tools/audio/gen_audio.py new        →  todos los nuevos (efectos PLUS + capas de música)
      python3 tools/audio/gen_audio.py layers     →  solo las 3 capas de música
La variable de entorno ZK_AUDIO_OUT cambia la carpeta de salida (para pruebas).
"""
import sys
import zlib
import math
import os
import random
import struct
import wave

SR = 22050
OUT = os.environ.get("ZK_AUDIO_OUT") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "godot", "assets", "audio")
os.makedirs(OUT, exist_ok=True)
rnd = random.Random(7)
TAU = math.tau


def buf(seconds):
    return [0.0] * int(SR * seconds)


def save(name, data, gain=0.9):
    check_name(name)
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


def noise(data, start, dur, vol=1.0, lp0=0.5, lp1=None, hp=False, attack=0.004, curve=3.0, wrap=False):
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
        j = s0 + i
        if wrap:
            j %= len(data)
        if j < len(data):
            data[j] += v * e * vol



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


def build_music():
    """La composición de la música (vals en La menor, 16 compases). Devuelve el buffer de music.wav."""
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
    return m


# ---------------------------------------------------------------- efectos originales
def gen_legacy():
    """Los 16 efectos y la música originales. Orden y semilla fijos: no tocar (los .wav existentes deben salir idénticos)."""
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

    save("music", build_music(), 0.6)



# ================================================================ NUEVOS (PLUS: A-01 capas de música, A-02 sonidos)
# Cada sonido nuevo usa su propia semilla (según su nombre) para que salga igual se genere solo o con todos.
LEGACY = {"tap", "card", "draw", "shuffle", "turn", "nope", "yup", "fuse", "explosion", "zombie", "attack", "alarm", "steal",
          "revive", "win", "lose", "music"}
NEW_SFX = ["targeted", "reverse", "bottom", "crow", "apocalypse", "alter", "bury", "swap", "haunt", "rotten",
           "emote", "tick", "tomb", "aim", "sudden"]
LAYERS = ["music_base", "music_drums", "music_tension"]


def fade(data, ms_in=3, ms_out=12):
    """Rampas cortas al inicio y al final: garantiza que el efecto empieza y termina en silencio (sin clics)."""
    a = int(SR * ms_in / 1000); b = int(SR * ms_out / 1000)
    for i in range(min(a, len(data))):
        data[i] *= i / a
    for i in range(min(b, len(data))):
        data[len(data) - 1 - i] *= i / b


def lowpass(data, a):
    y = 0.0
    for i in range(len(data)):
        y += a * (data[i] - y); data[i] = y


def mix(dst, src, start, vol=1.0):
    s0 = int(start * SR)
    for i, v in enumerate(src):
        if s0 + i < len(dst):
            dst[s0 + i] += v * vol


def sfx_targeted():
    d = buf(0.45)
    noise(d, 0.0, 0.14, 0.7, 0.8, 0.35, hp=True, attack=0.02, curve=-1.0)       # silbido del dardo
    tone(d, 0.0, 0.14, 700, 1900, "tri", 0.25, attack=0.03, curve=-1.0)
    tone(d, 0.13, 0.12, 190, 85, "sine", 1.0, attack=0.002, curve=3.5)           # impacto
    noise(d, 0.13, 0.08, 0.6, 0.35, 0.15, attack=0.001, curve=5)
    tone(d, 0.14, 0.28, 1500, 1250, "tri", 0.22, attack=0.001, curve=4, vib=0.03)  # el dardo vibrando clavado
    return d, 0.7


def sfx_reverse():
    d = buf(0.62)
    tone(d, 0.0, 0.28, 260, 1500, "tri", 0.7, attack=0.04, curve=-1.2)
    noise(d, 0.0, 0.28, 0.5, 0.9, 0.5, hp=True, attack=0.05, curve=-1.0)
    tone(d, 0.27, 0.32, 1500, 240, "sine", 0.8, attack=0.01, curve=2.0)
    tone(d, 0.27, 0.32, 750, 120, "tri", 0.3, attack=0.01, curve=2.5)
    noise(d, 0.27, 0.3, 0.35, 0.5, 0.9, hp=True, attack=0.01, curve=2.5)
    return d, 0.65


def sfx_bottom():
    d = buf(0.5)
    noise(d, 0.0, 0.34, 0.9, 0.12, 0.35, attack=0.06, curve=1.2)                 # roce grave
    noise(d, 0.04, 0.26, 0.3, 0.6, 0.3, hp=True, attack=0.05, curve=1.5)
    tone(d, 0.27, 0.2, 120, 70, "tri", 0.7, attack=0.004, curve=3.5)             # la carta queda debajo
    noise(d, 0.27, 0.07, 0.35, 0.3, 0.1, attack=0.001, curve=5)
    return d, 0.65


def _caw(f0, f1, dur):
    c = buf(dur + 0.02)
    tone(c, 0, dur, f0, f1, "saw", 1.0, attack=0.012, curve=1.8, vib=0.05)
    tone(c, 0, dur, f0 * 1.5, f1 * 1.5, "saw", 0.4, attack=0.012, curve=2.2, vib=0.05)
    for i in range(len(c)):                       # voz rasposa: modulación de amplitud rápida
        c[i] *= 0.65 + 0.35 * (1.0 if (i * 78 / SR) % 1.0 < 0.5 else -0.2)
    lowpass(c, 0.4)
    return c


def sfx_crow():
    d = buf(0.62)
    mix(d, _caw(620, 400, 0.2), 0.0, 1.0)
    mix(d, _caw(560, 360, 0.22), 0.27, 0.85)
    noise(d, 0.0, 0.2, 0.08, 0.15, 0.1, attack=0.01, curve=2)
    return d, 0.65


def sfx_apocalypse():
    d = buf(2.4)
    noise(d, 0.0, 0.2, 0.9, 0.9, 0.3, hp=True, attack=0.001, curve=5)             # restallido
    t = buf(2.4)
    noise(t, 0.02, 2.0, 1.4, 0.18, 0.015, attack=0.01, curve=2.0)               # trueno que rueda
    tone(t, 0.0, 1.2, 70, 38, "sine", 1.0, attack=0.005, curve=2.5)
    mix(d, t, 0, 1.0)
    ch = buf(2.4)                                                                  # coro grave
    for k, f in enumerate([55.0, 82.5, 110.0, 130.8]):
        tone(ch, 0.35 + 0.05 * k, 1.9, f, f * 0.97, "saw", 0.55, attack=0.45, curve=1.4, vib=0.015)
    lowpass(ch, 0.12)
    mix(d, ch, 0, 1.2)
    return d, 0.8


def sfx_alter():
    d = buf(1.35)
    for k, f in enumerate([1319, 1568, 1976, 2349, 1760, 2637]):
        t0 = k * 0.085
        tone(d, t0, 0.8, f, kind="sine", vol=0.5, attack=0.002, curve=3.5)
        tone(d, t0, 0.6, f * 2.76, kind="sine", vol=0.12, attack=0.002, curve=5)
        tone(d, t0, 0.8, f * 1.004, kind="sine", vol=0.2, attack=0.002, curve=3.5, vib=0.004)   # destello
    tone(d, 0.0, 1.2, 330, kind="sine", vol=0.12, attack=0.2, curve=1.5, vib=0.01)
    return d, 0.6


def sfx_bury():
    d = buf(0.95)
    noise(d, 0.0, 0.16, 0.8, 0.5, 0.15, hp=True, attack=0.03, curve=2.5)           # la pala rasca
    tone(d, 0.0, 0.14, 900, 600, "tri", 0.12, attack=0.01, curve=4)
    for k, (t0, v) in enumerate([(0.22, 1.0), (0.45, 0.7), (0.65, 0.45)]):         # paladas de tierra
        noise(d, t0, 0.18, v, 0.14, 0.05, attack=0.003, curve=3.5)
        tone(d, t0, 0.14, 110, 60, "sine", 0.6 * v, attack=0.002, curve=4)
        noise(d, t0, 0.08, 0.3 * v, 0.5, 0.25, hp=True, attack=0.001, curve=6)
    return d, 0.65


def sfx_swap():
    d = buf(0.75)
    tone(d, 0.0, 0.62, 260, 1200, "sine", 0.7, attack=0.06, curve=1.0, vib=0.03)
    tone(d, 0.0, 0.62, 1200, 260, "sine", 0.7, attack=0.06, curve=1.0, vib=0.03)
    tone(d, 0.05, 0.55, 400, 900, "tri", 0.25, attack=0.08, curve=1.2, vib=0.05)
    tone(d, 0.05, 0.55, 900, 400, "tri", 0.25, attack=0.08, curve=1.2, vib=0.05)
    noise(d, 0.0, 0.6, 0.35, 0.8, 0.5, hp=True, attack=0.1, curve=1.0)
    return d, 0.6


def sfx_haunt():
    d = buf(1.1)
    w = buf(1.1)
    tone(w, 0.0, 1.0, 520, 330, "sine", 0.8, attack=0.18, curve=1.6, vib=0.035)
    tone(w, 0.05, 1.0, 523 * 1.01, 332, "sine", 0.5, attack=0.2, curve=1.8, vib=0.045)
    tone(w, 0.1, 0.9, 1040, 660, "sine", 0.12, attack=0.25, curve=2, vib=0.05)
    noise(w, 0.0, 1.0, 0.18, 0.12, 0.05, attack=0.2, curve=1.6)                    # aliento
    lowpass(w, 0.35)
    mix(d, w, 0, 1.0)
    return d, 0.6


def sfx_rotten():
    d = buf(1.0)
    for k in range(11):                                                             # burbujeo
        t0 = 0.02 + k * 0.047 + rnd.uniform(0, 0.02)
        f = rnd.uniform(140, 260)
        tone(d, t0, 0.08, f, f * rnd.uniform(1.8, 2.6), "sine", rnd.uniform(0.35, 0.7), attack=0.004, curve=3.5)
    noise(d, 0.0, 0.6, 0.35, 0.1, 0.05, attack=0.05, curve=1.5)
    tone(d, 0.6, 0.38, 100, 48, "sine", 1.1, attack=0.003, curve=3.5)               # golpe sordo
    noise(d, 0.6, 0.15, 0.5, 0.2, 0.08, attack=0.002, curve=5)
    return d, 0.7


def sfx_emote():
    d = buf(0.24)
    tone(d, 0.0, 0.1, 480, 1050, "sine", 1.0, attack=0.004, curve=3)
    tone(d, 0.0, 0.1, 960, 2100, "sine", 0.2, attack=0.004, curve=4)
    tone(d, 0.075, 0.13, 700, 1500, "tri", 0.6, attack=0.004, curve=3.5)
    return d, 0.55


def sfx_tick():
    d = buf(0.36)
    for t0, f in ((0.0, 2000), (0.18, 1500)):                                       # tic... tac
        tone(d, t0, 0.04, f, f * 0.8, "sine", 1.0, attack=0.001, curve=5)
        noise(d, t0, 0.02, 0.5, 0.8, 0.4, hp=True, attack=0.0005, curve=4)
        tone(d, t0, 0.07, f * 0.25, f * 0.2, "sine", 0.35, attack=0.001, curve=4)   # madera
    return d, 0.5


def sfx_tomb():
    d = buf(1.1)
    tone(d, 0.0, 0.26, 700, 140, "sine", 0.3, attack=0.03, curve=0.5)                # cae
    noise(d, 0.0, 0.26, 0.2, 0.7, 0.4, hp=True, attack=0.05, curve=-0.5)
    tone(d, 0.26, 0.7, 66, 36, "sine", 1.3, attack=0.002, curve=3.0)                 # golpe de piedra
    tone(d, 0.26, 0.4, 130, 70, "tri", 0.5, attack=0.002, curve=4)
    noise(d, 0.26, 0.5, 0.9, 0.25, 0.04, attack=0.001, curve=3.5)
    noise(d, 0.26, 0.08, 0.4, 0.9, 0.5, hp=True, attack=0.001, curve=6)
    for k in range(4):                                                              # tierra y polvo que cae
        noise(d, 0.45 + rnd.uniform(0, 0.4), 0.07, 0.15, 0.3, 0.1, curve=5)
    return d, 0.85


def sfx_aim():
    d = buf(0.16)
    tone(d, 0.0, 0.12, 820, 1120, "sine", 1.0, attack=0.006, curve=3.5)
    tone(d, 0.0, 0.1, 1640, 2240, "sine", 0.15, attack=0.006, curve=4.5)
    return d, 0.4


def sfx_sudden():
    d = buf(2.0)
    for t0, f, v in ((0.0, 311.0, 1.0), (0.5, 233.0, 0.85)):                         # dos campanadas
        for ratio, vol, cur in ((1.0, 1.0, 1.6), (2.0, 0.5, 2.0), (2.76, 0.35, 2.4), (5.4, 0.15, 3.5), (8.9, 0.07, 4.5)):
            tone(d, t0, 1.4, f * ratio, kind="sine", vol=vol * v, attack=0.002, curve=cur)
        tone(d, t0, 1.4, f * 1.006, kind="sine", vol=0.25 * v, attack=0.002, curve=1.8, vib=0.002)
        noise(d, t0, 0.04, 0.3 * v, 0.9, 0.5, hp=True, attack=0.0005, curve=5)
    return d, 0.7


# --- música por capas: misma composición, mismo tempo y misma duración que music.wav
def _wrap_note(m, t0, dur, f, kind, vol, attack, curve, vib=0.0):
    tone(m, t0, dur, f, kind=kind, vol=vol, attack=attack, curve=curve, wrap=True, vib=vib)


def build_drums(n):
    """Percusión de vals: bombo grave en el 1, escobilla/aro en 2 y 3, y un tom en el último tiempo de cada 4 compases."""
    m = [0.0] * n
    for b in range(len(chords) * 2):
        t0 = b * bar
        tone(m, t0, 0.3, 120, 48, "sine", 0.75, attack=0.002, curve=4, wrap=True)            # bombo
        noise(m, t0, 0.04, 0.35, 0.3, 0.1, attack=0.001, curve=5, wrap=True)
        for k in (1, 2):
            tt = t0 + k * beat
            noise(m, tt, 0.09, 0.22, 0.85, 0.5, hp=True, attack=0.002, curve=5, wrap=True)    # escobilla
            tone(m, tt, 0.05, 1900, 1500, "tri", 0.05, attack=0.001, curve=6, wrap=True)
        for k in (0.5, 1.5, 2.5):                                                             # medios tiempos suaves
            noise(m, t0 + k * beat, 0.04, 0.09, 0.9, 0.6, hp=True, attack=0.001, curve=6, wrap=True)
        if b % 4 == 3:
            tone(m, t0 + 2 * beat, 0.3, 150, 90, "sine", 0.6, attack=0.002, curve=4, wrap=True)  # tom de remate
    return m


def build_tension(n):
    """Pads disonantes (segunda menor y tritono sobre cada fundamental) y un ostinato inquietante."""
    m = [0.0] * n
    for b in range(len(chords) * 2):
        name, notes = chords[b % len(chords)]
        t0 = b * bar
        root = notes[0]
        _wrap_note(m, t0, bar * 1.15, root, "sine", 0.16, 0.5, 0.4, 0.004)
        _wrap_note(m, t0, bar * 1.15, root * 1.0595, "sine", 0.1, 0.6, 0.4, 0.005)           # roce de semitono
        _wrap_note(m, t0, bar * 1.15, root * 1.4142 * 2, "sine", 0.05, 0.7, 0.5, 0.01)       # tritono arriba
        pat = [1.0, 1.0595, 1.0, 1.4142, 1.0595, 1.0]
        for k, r in enumerate(pat):                                                          # ostinato en corcheas
            _wrap_note(m, t0 + k * beat / 2, beat * 0.55, root * 2 * r, "tri", 0.075 if k % 2 == 0 else 0.05, 0.003, 5)
        if b % 2 == 0:
            _wrap_note(m, t0, bar * 2.1, 1175 + 20 * (b % 4), "sine", 0.025, 0.8, 0.5, 0.02)  # lamento agudo lejano
    return m


def gen_layers(want):
    base = build_music()
    n = len(base)
    peak = max(abs(x) for x in base)
    k = 0.6 / peak                       # la misma escala que music.wav: así las capas conservan su proporción real
    if "music_base" in want:
        save("music_base", base, 0.6)
    if "music_drums" in want:
        save_k("music_drums", build_drums(n), k)
    if "music_tension" in want:
        save_k("music_tension", build_tension(n), k)


def save_k(name, data, k):
    """Como save() pero con escala fija k (para las capas, que deben mantener su proporción con la base)."""
    check_name(name)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, math.tanh(x * k * 1.2) / math.tanh(1.2))) * 32767)) for x in data))
    print(name, round(len(data) / SR, 2), "s")


def check_name(name):
    if name in LEGACY and not ALLOW_LEGACY:
        raise SystemExit("negado: %s es un archivo original; solo se regenera con la ejecución completa" % name)


ALLOW_LEGACY = True   # gen_legacy() (ejecución completa) puede escribir los originales; los nuevos nunca los tocan


def main(argv):
    global rnd, ALLOW_LEGACY
    if not argv:
        gen_legacy()
        argv = ["new"]
    ALLOW_LEGACY = False
    want = []
    for a in argv:
        want += NEW_SFX + LAYERS if a == "new" else LAYERS if a == "layers" else [a]
    for a in want:
        if a not in NEW_SFX and a not in LAYERS:
            raise SystemExit("nombre desconocido: %s (nuevos: %s, capas: %s)" % (a, " ".join(NEW_SFX), " ".join(LAYERS)))
    for name in want:
        if name in NEW_SFX:
            rnd = random.Random(zlib.crc32(name.encode()))
            data, gain = globals()["sfx_" + name]()
            fade(data)
            save(name, data, gain)
    if any(w in LAYERS for w in want):
        gen_layers([w for w in want if w in LAYERS])


if __name__ == "__main__":
    main(sys.argv[1:])
