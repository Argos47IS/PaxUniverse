"""Build separate, deterministic ZIPs; validate them in the game before release."""
import argparse
import hashlib
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parents[1]
IDS = ("earth_atlas", "pax_interface")


def package(mod_id: str, output: Path) -> dict:
    source = ROOT / "mods" / mod_id
    manifest = json.loads((source / "mod.json").read_text(encoding="utf-8-sig"))
    if manifest["id"] != mod_id:
        raise ValueError("Manifest ID does not match its directory")
    if (source / "dev").exists() or (source / "tests").exists():
        raise ValueError("External QA scripts must stay outside installable mods")
    files = [p for p in sorted(source.rglob("*")) if p.is_file()
             and not any(part in {".godot", "__pycache__", ".git"} for part in p.parts)
             and p.suffix not in {".uid", ".import", ".pyc"}]
    output.mkdir(parents=True, exist_ok=True)
    destination = output / f"{mod_id}-{manifest['version']}.zip"
    with ZipFile(destination, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        for path in files:
            info = ZipInfo(path.relative_to(source).as_posix(), (2026, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, path.read_bytes())
    with ZipFile(destination) as archive:
        if archive.testzip() is not None:
            raise ValueError("Archive integrity check failed")
    return {"id": mod_id, "version": manifest["version"], "path": str(destination),
            "files": len(files), "bytes": destination.stat().st_size,
            "sha256": hashlib.sha256(destination.read_bytes()).hexdigest()}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mods", nargs="*", metavar="MOD_ID", help="earth_atlas and/or pax_interface")
    parser.add_argument("--output", type=Path, help="Shared staging folder; default is dist/<id>")
    args = parser.parse_args()
    if any(mod_id not in IDS for mod_id in args.mods):
        parser.error("Supported mods: " + ", ".join(IDS))
    for mod_id in args.mods or IDS:
        print(json.dumps(package(mod_id, args.output or ROOT / "dist" / mod_id), ensure_ascii=False))
