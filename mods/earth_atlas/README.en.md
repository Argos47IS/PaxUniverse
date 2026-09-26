# Earth: Atlas HD 0.2.1

Replace the previous mod ZIP with `earth_atlas-0.2.1.zip` in the game's `mods` folder and restart the game. Extraction and repair scripts are not required. Enable **Earth: Atlas HD 0.2.1** in the launcher if needed. Open Earth's flat map; the Atlas HD button provides map appearance and quality controls.

This release uses the internal ID `earth_atlas`. Pax Universe 0.13.0's repeated automatic disabling targets the previous ID `earth_atlas_hd`; the new ID follows the normal launcher switch. The game executable and PCK files are not modified.

The map uses NASA/GEBCO elevation at 10800×5400 for lighting, the game's existing color imagery, quieter development patterns and clearer political borders. The default surface renders at native resolution; quality options are 50%, 100%, 150% and 200%, capped at 4096 pixels on the longer side. Increased quality costs GPU performance. Province geometry, click accuracy, world state and the globe are unchanged.

Preferences are stored through Pax API, separately from saved worlds. Upgrading from 0.2.0 preserves them. Legacy preferences can only be imported through an already active `earth_atlas_hd` instance's settings API. Existing `earth_atlas` preferences win. When the legacy mod is inactive, the new mod uses its own saved preferences or defaults. Legacy files and loader preferences are not read or rewritten directly.

The old 0.1.1 release may remain installed. When both releases are loaded, the new one yields to the old adapter to prevent duplicate controls and effects. It takes over automatically after the old instance unloads. Disabling the old release is optional.

Version 0.2.1 targets **Pax Universe 0.15.1**. It uses Pax resource helpers and keeps development scripts outside the installable mod to comply with the game's new sandbox. It does not disable sandbox restrictions. The game may block the old `earth_atlas_hd` 0.1.1 and `earth_atlas` 0.2.0 packages. The manifest accommodates the stale internal loader version (0.13.2); it does not claim support for older games without `load_resource`.

Other mods replacing the same map shaders may conflict. The adapter checks internal game properties and source shader anchors; future game changes may require an update. Saves are not migrated because this mod stores no per-world state.

Elevation source and licensing references: [NASA Blue Marble topography](https://science.nasa.gov/earth/earth-observatory/blue-marble-next-generation/topography-bathymetry-maps/), [NASA media guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/). Processing details and hashes are in `textures/elevation-source.json`.

Validate with `PaxUniverse.exe --headless -- --check-mods earth_atlas` and confirm a nonzero number of checked files; exit code 0 alone does not prove that the mod was loaded. Historical development scripts are preserved separately under `tests/earth_atlas/` in the repository and are excluded from the mod ZIP. Previous `--atlas-…-test` launch flags are no longer dispatched by the installed mod. Current compatibility results and limitations are recorded under `docs/` in the repository.
