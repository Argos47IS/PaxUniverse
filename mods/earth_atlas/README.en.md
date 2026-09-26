# Earth: Atlas HD 0.2.0

Place `earth_atlas-0.2.0.zip` in the game's `mods` folder and restart the game. Extraction and repair scripts are not required. Enable **Earth: Atlas HD 0.2.0** in the launcher if needed. Open Earth's flat map; the Atlas HD button provides map appearance and quality controls.

This release uses the internal ID `earth_atlas`. Pax Universe 0.13.0's repeated automatic disabling targets the previous ID `earth_atlas_hd`; the new ID follows the normal launcher switch. The game executable and PCK files are not modified.

The map uses NASA/GEBCO elevation at 10800×5400 for lighting, the game's existing color imagery, quieter development patterns and clearer political borders. The default surface renders at native resolution; quality options are 50%, 100%, 150% and 200%, capped at 4096 pixels on the longer side. Increased quality costs GPU performance. Province geometry, click accuracy, world state and the globe are unchanged.

Valid preferences from `user://mod_settings/earth_atlas_hd.json` are copied once to the new `earth_atlas.json`: enabled, quality, natural, political and urban. Existing new preferences win. Missing or damaged legacy preferences do not prevent startup. Legacy files and loader preferences are not rewritten.

The old 0.1.1 release may remain installed. When both releases are loaded, the new one yields to the old adapter to prevent duplicate controls and effects. It takes over automatically after the old instance unloads. Disabling the old release is optional.

Other mods replacing the same map shaders may conflict. The adapter checks internal game properties and source shader anchors; future game changes may require an update. Saves are not migrated because this mod stores no per-world state.

Elevation source and licensing references: [NASA Blue Marble topography](https://science.nasa.gov/earth/earth-observatory/blue-marble-next-generation/topography-bathymetry-maps/), [NASA media guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/). Processing details and hashes are in `textures/elevation-source.json`.

Development scripts under `dev/` only run with explicit test flags. Full-world and distribution tests require the isolated Atlas QA profile. Validate with `PaxUniverse.exe --headless -- --check-mods earth_atlas`.
