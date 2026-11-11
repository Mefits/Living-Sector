#!/usr/bin/env python3
"""Generate the client_bevy SFX OGG files.

Ported from `client/scripts/autoload/procedural_audio.gd` — the Godot
client synthesised every sound at runtime; the Bevy client loads
pre-baked OGG/Vorbis from `crates/client_bevy/assets/sfx/`. Re-run
this script whenever you tune a synth (and re-commit the OGGs).

OGG over WAV: Bevy 0.14's default audio feature set includes
`vorbis` but not `wav`, so WAV files panic with UnrecognizedFormat
in `play_queued_audio_system`. OGG also matches the music files'
format. We pipe raw PCM through ffmpeg's libvorbis encoder rather
than carrying a heavy Python OGG dep.

Stdlib for synthesis (math + struct + random); ffmpeg for encoding.

Usage:
    python3 tools/gen_sfx.py
"""

from __future__ import annotations

import math
import os
import random
import struct
import subprocess
from pathlib import Path

SAMPLE_RATE = 22_050
TAU = 2 * math.pi

OUT_DIR = (
    Path(__file__).resolve().parent.parent
    / "crates"
    / "client_bevy"
    / "assets"
    / "sfx"
)


# ---------------------------------------------------------------------------
# OGG writer (raw PCM → ffmpeg → libvorbis)
# ---------------------------------------------------------------------------


def write_ogg(path: Path, samples: list[float]) -> None:
    """Write a mono OGG/Vorbis from float samples in [-1, 1].

    Encoding goes through ffmpeg: we pack samples as little-endian
    s16 PCM, pipe to ffmpeg over stdin, and let it run libvorbis.
    Quality 5 (-q:a 5) is plenty for short SFX one-shots — keeps
    the file small without artefacting the click attack transients.
    """
    pcm = bytearray()
    for s in samples:
        s = max(-1.0, min(1.0, s))
        pcm += struct.pack("<h", int(s * 32_767))
    cmd = [
        "ffmpeg",
        "-y",                  # overwrite
        "-loglevel", "error",  # quiet unless something breaks
        "-f", "s16le",         # raw input format
        "-ar", str(SAMPLE_RATE),
        "-ac", "1",            # mono
        "-i", "pipe:0",        # stdin
        "-c:a", "libvorbis",
        "-q:a", "5",
        str(path),
    ]
    proc = subprocess.run(cmd, input=bytes(pcm), capture_output=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"ffmpeg failed for {path}: "
            f"{proc.stderr.decode('utf-8', errors='replace')}"
        )


def env_attack_release(i: int, n: int, attack_n: int, release_n: int) -> float:
    """Standard attack/sustain/release envelope (linear ramps)."""
    if i < attack_n:
        return i / max(1, attack_n)
    release_start = n - release_n
    if i > release_start:
        return max(0.0, 1.0 - (i - release_start) / max(1, release_n))
    return 1.0


# ---------------------------------------------------------------------------
# Generators (mirror procedural_audio.gd)
# ---------------------------------------------------------------------------


def gen_explosion(size_hint: float, seed: int) -> list[float]:
    """Two-layer: pitch-sweeping rumble + fast-decaying noise crack.
    Bigger size = lower pitch, longer decay.
    """
    rng = random.Random(seed)
    size = max(0.25, min(2.0, size_hint))
    duration = max(0.5, min(1.5, 0.65 + size * 0.35))
    n = int(SAMPLE_RATE * duration)

    rf_start = 280.0 / math.sqrt(size + 0.3)
    rf_end = 40.0 / math.sqrt(size + 0.3)
    rumble_phase = 0.0
    lfo_phase = 0.0
    lfo_freq = 5.0
    rumble_decay = 2.2 / size  # slower tail for bigger bangs
    noise_decay = 6.0

    out: list[float] = []
    for i in range(n):
        t = i / n
        lfo_phase += TAU * lfo_freq / SAMPLE_RATE
        wobble = math.sin(lfo_phase) * 8.0
        rumble_f = rf_start + (rf_end - rf_start) * (t**0.5) + wobble
        rumble_phase += TAU * rumble_f / SAMPLE_RATE
        rumble = math.sin(rumble_phase) * math.exp(-t * rumble_decay)
        noise = rng.uniform(-1.0, 1.0)
        noise_amp = math.exp(-t * noise_decay)
        mixed = rumble * 0.55 + noise * noise_amp * 0.85
        # cheap soft-clip
        s = mixed / (1.0 + abs(mixed) * 0.5)
        out.append(s * 0.85)
    return out


def gen_click(pitch_mult: float) -> list[float]:
    """Square-heavy tick with brief attack + release."""
    duration = 0.055
    n = int(SAMPLE_RATE * duration)
    freq = 1200.0 * pitch_mult
    phase = 0.0
    attack_n = int(0.0015 * SAMPLE_RATE)
    release_n = int(0.015 * SAMPLE_RATE)
    out: list[float] = []
    for i in range(n):
        phase += TAU * freq / SAMPLE_RATE
        s_val = math.sin(phase)
        wave_v = (1 if s_val > 0 else (-1 if s_val < 0 else 0)) * 0.35 + s_val * 0.25
        env = env_attack_release(i, n, attack_n, release_n)
        out.append(wave_v * env * 0.5)
    return out


def gen_ui_blip(pitch_mult: float) -> list[float]:
    """Triangle/square mix with 4 ms attack + 40 ms release. Chiptune ping."""
    duration = 0.10
    n = int(SAMPLE_RATE * duration)
    freq = 880.0 * pitch_mult
    phase = 0.0
    attack_n = int(0.004 * SAMPLE_RATE)
    release_n = int(0.040 * SAMPLE_RATE)
    out: list[float] = []
    for i in range(n):
        phase += TAU * freq / SAMPLE_RATE
        s_val = math.sin(phase)
        wave_v = s_val * 0.55 + (1 if s_val > 0 else (-1 if s_val < 0 else 0)) * 0.18
        env = env_attack_release(i, n, attack_n, release_n)
        out.append(wave_v * env * 0.55)
    return out


def gen_two_tone(f1: float, f2: float, tone_dur: float, gap: float) -> list[float]:
    """Two sequential sine+square mixes with a brief gap."""
    total_dur = tone_dur * 2.0 + gap
    n = int(SAMPLE_RATE * total_dur)
    tone_n = int(tone_dur * SAMPLE_RATE)
    gap_n = int(gap * SAMPLE_RATE)
    attack_n = int(0.004 * SAMPLE_RATE)
    release_n = int(0.018 * SAMPLE_RATE)
    phase = 0.0
    out: list[float] = []
    for i in range(n):
        if i < tone_n:
            freq = f1
            local_i = i
            local_n = tone_n
        elif i < tone_n + gap_n:
            out.append(0.0)
            continue
        else:
            freq = f2
            local_i = i - (tone_n + gap_n)
            local_n = tone_n
            if local_i == 0:
                phase = 0.0
        phase += TAU * freq / SAMPLE_RATE
        s_val = math.sin(phase)
        wave_v = s_val * 0.55 + (1 if s_val > 0 else (-1 if s_val < 0 else 0)) * 0.18
        env = env_attack_release(local_i, local_n, attack_n, release_n)
        out.append(wave_v * env * 0.5)
    return out


# ---------------------------------------------------------------------------
# Bake
# ---------------------------------------------------------------------------


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"writing to {OUT_DIR}")

    # Three explosion sizes — let the play layer pick by ship class
    # (Tiny → small, Massive → large) when the SFX-on-retire wires
    # land. Seed is fixed so re-running this script is deterministic.
    write_ogg(OUT_DIR / "explosion_small.ogg", gen_explosion(0.5, 1))
    write_ogg(OUT_DIR / "explosion_med.ogg", gen_explosion(1.0, 2))
    write_ogg(OUT_DIR / "explosion_large.ogg", gen_explosion(1.6, 3))

    # UI cues — direct ports of the Godot helpers.
    write_ogg(OUT_DIR / "click.ogg", gen_click(1.0))
    write_ogg(OUT_DIR / "close.ogg", gen_click(0.55))
    write_ogg(OUT_DIR / "ui_blip.ogg", gen_ui_blip(1.0))
    write_ogg(OUT_DIR / "select.ogg", gen_ui_blip(1.25))
    write_ogg(OUT_DIR / "confirm.ogg", gen_two_tone(660.0, 990.0, 0.06, 0.015))
    write_ogg(OUT_DIR / "deny.ogg", gen_two_tone(440.0, 294.0, 0.08, 0.02))
    write_ogg(OUT_DIR / "warn.ogg", gen_two_tone(550.0, 550.0, 0.05, 0.03))

    # Gate-jump warp ping — higher pitched ui_blip with a longer tail.
    write_ogg(OUT_DIR / "gate_jump.ogg", gen_ui_blip(1.6))

    # Pentatonic-chain clicks — 6 pitched variants to walk up a scale
    # on rapid presses (mirrors GDScript's CLICK_PENTATONIC_SEMITONES).
    semitones = [0, 2, 4, 7, 9, 12]
    for idx, st in enumerate(semitones):
        mult = 2 ** (st / 12.0)
        write_ogg(OUT_DIR / f"click_{idx}.ogg", gen_click(mult))

    print(f"baked {len(list(OUT_DIR.glob('*.ogg')))} files")


if __name__ == "__main__":
    main()
