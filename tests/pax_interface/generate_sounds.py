"""Generate the original Pax Interface soft UI taps using only Python stdlib.

Run from any directory. Outputs deterministic mono PCM WAVs beside this mod.
No recordings, third-party samples or network access are used.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
import struct
import wave

RATE = 44_100
OUT = Path(__file__).resolve().parents[2] / "mods" / "pax_interface" / "sounds"


def make_tap(name: str, duration: float, peak: float,
             modes: tuple[tuple[float, float, float], ...], attack: float) -> dict:
    count = round(duration * RATE)
    values: list[float] = []
    for index in range(count):
        time = index / RATE
        # Sine-squared attack and release have zero slope at the endpoints.
        onset = math.sin(min(1.0, time / attack) * math.pi / 2) ** 2
        release = math.cos(time / ((count - 1) / RATE) * math.pi / 2) ** 2
        value = sum(weight * math.sin(2 * math.pi * frequency * time)
                    * math.exp(-decay * time)
                    for frequency, weight, decay in modes)
        values.append(value * onset * release)
    scale = peak / max(abs(value) for value in values)
    integers = [round(value * scale * 32767) for value in values]
    integers[0] = integers[-1] = 0
    with wave.open(str(OUT / f"{name}.wav"), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(struct.pack(f"<{len(integers)}h", *integers))
    normalized = [value / 32768 for value in integers]
    measured_peak = max(abs(value) for value in normalized)
    rms = math.sqrt(sum(value * value for value in normalized) / count)
    return {
        "file": f"{name}.wav",
        "sample_rate": RATE,
        "channels": 1,
        "pcm_bits": 16,
        "frames": count,
        "duration_ms": count / RATE * 1000,
        "attack_ms": attack * 1000,
        "peak": measured_peak,
        "peak_dbfs": 20 * math.log10(measured_peak),
        "rms": rms,
        "rms_dbfs": 20 * math.log10(rms),
        "first_last_sample": [integers[0], integers[-1]],
        "max_adjacent_step": max(abs(b - a) for a, b in zip(normalized, normalized[1:])),
        "modes_hz": [entry[0] for entry in modes],
    }


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    results = [
        make_tap("hover", .072, .095, ((440., .75, 28.), (680., .20, 40.), (960., .05, 52.)), .009),
        make_tap("click", .096, .135, ((370., .70, 23.), (610., .24, 33.), (890., .06, 46.)), .008),
    ]
    for result in results:
        assert result["peak"] <= .15
        assert 60 <= result["duration_ms"] <= 100
        assert result["first_last_sample"] == [0, 0]
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
