"""Procedural sound design for the whole game (original synthesis, no samples).

Regenerates every WAV in assets/audio/. The game loops some streams on the
FIRST HALF of the file (loop_end = sample_count / 2), so loopable sounds are
built by tiling one seamless segment twice.

Usage:  python3 tools/gen_audio.py    (from starwars-duel/)
"""
import numpy as np
import wave
import os

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")


def save(name: str, x: np.ndarray, peak_db: float = -1.0) -> None:
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x))
    if m > 0:
        x = x / m * (10.0 ** (peak_db / 20.0))
    pcm = (x * 32767.0).astype(np.int16)
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"{name:18s} {len(x)/SR:6.2f}s  peak {peak_db} dB")


def t_axis(dur: float) -> np.ndarray:
    return np.arange(int(SR * dur)) / SR


def env_ar(n: int, attack: float, release: float) -> np.ndarray:
    """Attack/release envelope in seconds over n samples."""
    e = np.ones(n)
    a = max(1, int(attack * SR))
    r = max(1, int(release * SR))
    e[:a] = np.linspace(0, 1, a)
    e[-r:] *= np.linspace(1, 0, r)
    return e


def lowpass(x: np.ndarray, alpha: float) -> np.ndarray:
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y


def bandpass_noise(n: int, lo: float, hi: float, rng) -> np.ndarray:
    """White noise filtered to [lo, hi] Hz via FFT brick-wall + soft edges."""
    x = rng.standard_normal(n)
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    mask = np.clip((f - lo * 0.7) / (lo * 0.3 + 1), 0, 1) * np.clip((hi * 1.3 - f) / (hi * 0.3 + 1), 0, 1)
    return np.fft.irfft(spec * mask, n)


def loopable(seg: np.ndarray) -> np.ndarray:
    """Make seg seamless (circular crossfade), then tile it twice: the game
    loops on the first half, the second half covers pre-loop playback."""
    n = len(seg)
    f = int(0.04 * SR)
    fade = np.linspace(0, 1, f)
    seg = seg.copy()
    seg[:f] = seg[:f] * fade + seg[-f:] * (1 - fade)
    seg = seg[: n - f]
    return np.concatenate([seg, seg])


rng = np.random.default_rng(1977)

# ---------------------------------------------------------------- saber hum
dur = 1.2
t = t_axis(dur)
# two slightly detuned low oscillators that beat against each other
f1, f2 = 58.0, 91.0
base = (np.sin(2 * np.pi * f1 * t) * 0.9
        + np.sin(2 * np.pi * f2 * t) * 0.55
        + np.sin(2 * np.pi * (2 * f1 + 1.3) * t) * 0.3
        + np.sin(2 * np.pi * (3 * f1 - 0.7) * t) * 0.18)
base = np.tanh(base * 1.8)                          # gentle saturation
trem = 1.0 + 0.13 * np.sin(2 * np.pi * 7.3 * t) + 0.05 * np.sin(2 * np.pi * 11.9 * t)
hiss = bandpass_noise(len(t), 900, 2600, rng) * 0.05
hum = base * trem + hiss
# force whole periods so the circular crossfade has little work to do
save("saber_hum.wav", loopable(hum), -6.0)

# -------------------------------------------------------------- saber swing
dur = 0.5
t = t_axis(dur)
n = len(t)
# doppler glide of the hum
glide = np.exp(np.linspace(np.log(1.9), np.log(0.8), n))
phase1 = np.cumsum(2 * np.pi * f1 * 2.2 * glide) / SR
phase2 = np.cumsum(2 * np.pi * f2 * 2.2 * glide) / SR
body = np.tanh((np.sin(phase1) + 0.6 * np.sin(phase2)) * 1.5)
# whoosh: noise through a falling band
sweep = bandpass_noise(n, 500, 3800, rng)
swfade = np.exp(np.linspace(np.log(3000), np.log(500), n)) / 3000.0
whoosh = sweep * swfade
sw = (body * 0.7 + whoosh * 1.4) * env_ar(n, 0.02, 0.16)
save("saber_swing.wav", sw, -2.0)

# -------------------------------------------------------------- saber clash
dur = 0.85
t = t_axis(dur)
n = len(t)
imp = bandpass_noise(n, 1200, 9000, rng) * np.exp(-t * 38)         # crack
crackle = bandpass_noise(n, 2000, 7000, rng) * (rng.random(n) > 0.985) * np.exp(-t * 6) * 2.0
ring = sum(np.sin(2 * np.pi * f * t + rng.random() * 6) * np.exp(-t * d) * a
           for f, d, a in [(820, 9, 0.5), (1310, 11, 0.38), (2140, 14, 0.27), (3270, 18, 0.15)])
thump = np.sin(2 * np.pi * 70 * t) * np.exp(-t * 22) * 0.9
clash = (imp * 1.6 + crackle + ring + thump) * env_ar(n, 0.001, 0.1)
save("saber_clash.wav", clash, -1.0)

# ------------------------------------------------------------------ blasters
def blaster(f_hi: float, f_lo: float, dur: float) -> np.ndarray:
    t = t_axis(dur)
    n = len(t)
    freq = np.exp(np.linspace(np.log(f_hi), np.log(f_lo), n))
    ph = np.cumsum(2 * np.pi * freq) / SR
    x = np.sin(ph) + 0.45 * np.sin(2 * ph) + 0.2 * np.sin(3 * ph)
    x = np.tanh(x * 2.2)
    x += bandpass_noise(n, 1500, 6000, rng) * np.exp(-t * 30) * 0.4
    return x * env_ar(n, 0.002, 0.12)

save("laser_red.wav", blaster(2100, 380, 0.36), -1.5)
save("laser_green.wav", blaster(2600, 520, 0.3), -1.5)

# ---------------------------------------------------------------------- hit
dur = 0.42
t = t_axis(dur)
n = len(t)
thud = np.sin(2 * np.pi * np.exp(np.linspace(np.log(160), np.log(55), n)) * t) * np.exp(-t * 13)
sizzle = bandpass_noise(n, 2500, 8000, rng) * np.exp(-t * 9) * 0.5
save("hit.wav", (thud * 1.4 + sizzle) * env_ar(n, 0.002, 0.1), -1.5)

# ----------------------------------------------------------------- footstep
dur = 0.16
t = t_axis(dur)
n = len(t)
knock = np.sin(2 * np.pi * 95 * t) * np.exp(-t * 60)
clang = (np.sin(2 * np.pi * 612 * t) + 0.6 * np.sin(2 * np.pi * 1080 * t)) * np.exp(-t * 45) * 0.16
tex = bandpass_noise(n, 300, 1800, rng) * np.exp(-t * 70) * 0.5
save("footstep.wav", (knock + clang + tex) * env_ar(n, 0.001, 0.05), -8.0)

# -------------------------------------------------------------------- boost
dur = 0.6
t = t_axis(dur)
n = len(t)
arc = np.sin(np.pi * np.clip(t / dur, 0, 1))                       # up then down
center = 600 + 1800 * arc
ws = bandpass_noise(n, 250, 5000, rng)
spec_mod = np.sin(2 * np.pi * center * t) * 0.12
save("boost.wav", (ws * (0.25 + arc) + spec_mod) * env_ar(n, 0.05, 0.2), -3.0)

# ---------------------------------------------------------------- explosion
dur = 1.5
t = t_axis(dur)
n = len(t)
boom = bandpass_noise(n, 30, 220, rng) * np.exp(-t * 3.2) * 2.2
sub = np.sin(2 * np.pi * np.exp(np.linspace(np.log(70), np.log(32), n)) * t) * np.exp(-t * 2.5)
debris = bandpass_noise(n, 800, 5000, rng) * (rng.random(n) > 0.995) * np.exp(-t * 2.5) * 1.6
crack0 = bandpass_noise(n, 400, 7000, rng) * np.exp(-t * 26)
save("explosion.wav", (boom + sub * 1.2 + debris + crack0) * env_ar(n, 0.002, 0.5), -0.8)

# ------------------------------------------------------------------- engine
dur = 1.6
t = t_axis(dur)
fe = 47.0
eng = (np.sin(2 * np.pi * fe * t) + 0.6 * np.sin(2 * np.pi * fe * 2.02 * t)
       + 0.4 * np.sin(2 * np.pi * fe * 2.98 * t) + 0.25 * np.sin(2 * np.pi * fe * 4.05 * t))
eng = np.tanh(eng * 1.4)
flutter = 1.0 + 0.1 * np.sin(2 * np.pi * 13.7 * t) + 0.06 * np.sin(2 * np.pi * 27.1 * t)
eng = eng * flutter + bandpass_noise(len(t), 300, 1200, rng) * 0.08
save("engine.wav", loopable(eng), -6.0)

# ------------------------------------------------------------------ ambient
dur = 5.0
t = t_axis(dur)
n = len(t)
drone = (np.sin(2 * np.pi * 41 * t) * 0.8 + np.sin(2 * np.pi * 61.7 * t) * 0.5
         + np.sin(2 * np.pi * 82.4 * t) * 0.3)
slow = (np.sin(2 * np.pi * 0.4 * t) * 0.5 + 0.5)
shimmer = np.sin(2 * np.pi * 329 * t) * 0.08 * slow + np.sin(2 * np.pi * 493 * t) * 0.05 * (1 - slow)
airr = bandpass_noise(n, 120, 700, rng) * 0.07
save("ambient.wav", loopable(drone + shimmer + airr), -10.0)

# --------------------------------------------------------------------- wind
dur = 3.5
t = t_axis(dur)
n = len(t)
gust = 0.55 + 0.45 * np.sin(2 * np.pi * t / dur)                   # whole period -> loops
wd = bandpass_noise(n, 90, 800, rng) * gust + bandpass_noise(n, 40, 200, rng) * 0.5
save("wind.wav", loopable(wd), -8.0)

# ------------------------------------------------------------- vader breath
# mechanical respirator: inhale (brighter, rising) then exhale (deeper, louder)
def breath_phase(dur: float, lo: float, hi: float, swell_shape: float, rng) -> np.ndarray:
    t = t_axis(dur)
    n = len(t)
    body = bandpass_noise(n, lo, hi, rng)
    swell = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** swell_shape
    return body * swell

inhale = breath_phase(1.15, 380, 950, 1.4, rng) * 0.8
click_t = t_axis(0.07)
click = np.sin(2 * np.pi * 480 * click_t) * np.exp(-click_t * 90) * 0.35
gap1 = np.zeros(int(0.06 * SR))
exhale = breath_phase(1.45, 230, 620, 1.1, rng) * 1.25
gap2 = np.zeros(int(0.55 * SR))
cycle = np.concatenate([inhale, gap1, click, exhale, gap2])
save("vader_breath.wav", loopable(cycle), -7.0)

# --------------------------------------------------------------- force push
# deep telekinetic whoomp: sub swell into an airy burst
dur = 0.9
t = t_axis(dur)
n = len(t)
swell = np.sin(np.pi * np.clip(t / 0.32, 0, 1)) ** 2 * (t < 0.32)
sub = np.sin(2 * np.pi * np.exp(np.linspace(np.log(34), np.log(58), n)) * t) * swell * 1.6
burst_env = np.exp(-np.maximum(t - 0.3, 0) * 9) * (t >= 0.3)
burst = bandpass_noise(n, 120, 2400, rng) * burst_env * 1.3
airr2 = bandpass_noise(n, 600, 5200, rng) * np.exp(-np.maximum(t - 0.3, 0) * 16) * (t >= 0.3) * 0.6
save("force_push.wav", (sub + burst + airr2) * env_ar(n, 0.01, 0.25), -1.2)

print("done.")
