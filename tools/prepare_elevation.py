"""Resample NASA/GEBCO elevation data for the atlas visual shader.

The source is EPSG:4326, upper-left (-180, 90), 21600 x 10800,
8-bit grayscale with 0..255 representing 0..6400 m (NASA metadata).
This numerical 2x2 mean does not invent detail or change gameplay geography.
16-bit output preserves fractional means; source accuracy remains 8-bit.
"""
from pathlib import Path
import argparse
import hashlib
import json

import numpy as np
from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(".local/sources/nasa_gebco_elev_21600x10800.tif"))
    parser.add_argument("--output", type=Path, default=Path(".local/sources/elevation.png"))
    args = parser.parse_args()
    Image.MAX_IMAGE_PIXELS = 250_000_000
    with Image.open(args.source) as source:
        if source.mode != "L" or source.size != (21600, 10800):
            raise ValueError(f"Unexpected input encoding: {source.mode}, {source.size}")
        tiepoint = source.tag_v2.get(33922)
        if tiepoint is None or tuple(tiepoint[3:5]) != (-180.0, 90.0):
            raise ValueError(f"Unexpected geographic origin: {tiepoint}")
        samples = np.asarray(source)
        sums = samples[0::2, 0::2].astype(np.uint32)
        sums += samples[0::2, 1::2]
        sums += samples[1::2, 0::2]
        sums += samples[1::2, 1::2]
        output = ((sums * 257 + 2) // 4).astype(np.uint16)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(output).save(args.output)
    with Image.open(args.output) as check:
        assert check.size == (10800, 5400)
        assert np.array_equal(np.asarray(check), output)
    metadata = {
        "source_page": "https://science.nasa.gov/earth/earth-observatory/blue-marble-next-generation/topography-bathymetry-maps/",
        "source_url": "https://assets.science.nasa.gov/content/dam/science/esd/eo/images/bmng/topography/gebco_08_rev_elev_21600x10800.tif",
        "usage_guidelines": "https://www.nasa.gov/nasa-brand-center/images-and-media/",
        "credit": "NASA Earth Observatory / GEBCO",
        "source_encoding": "8-bit grayscale, 0..255 = 0..6400 meters; elevations above 6400 m clip",
        "output_encoding": "16-bit grayscale, 0..65535 = 0..6400 meters; 2x2 arithmetic mean",
        "projection": "EPSG:4326, longitude -180..180, latitude 90..-90, equirectangular",
        "purpose": "visual shaded relief only; not a replacement for game terrain/ocean masks",
        "output_size": [10800, 5400],
        "source_sha256": hashlib.file_digest(args.source.open("rb"), "sha256").hexdigest(),
        "output_sha256": hashlib.file_digest(args.output.open("rb"), "sha256").hexdigest(),
    }
    args.output.with_suffix(".json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(args.output), "size": metadata["output_size"], "bytes": args.output.stat().st_size, "verified": True}))


if __name__ == "__main__":
    main()
