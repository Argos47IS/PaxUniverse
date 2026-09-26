# Pax Units — prototype

Read ../../docs/modding-notes-ru.md. Keep all user changes. This is a separate visual-only mod; never change simulation, troops, ownership, save data or installed game files as a side effect of asset development.

Use strict GDScript types, runtime PaxMod.model for GLB, original Russian API names and matching RU/EN localization keys. Fail safely on unknown game API. Keep native selection/counters authoritative. Clean up adapter changes on unload and world changes.

Generated model source lives in ../../tools/build_tank_asset.py. Store coordinate axes, bounds, triangles and materials in the companion stats JSON. Native orientation is established by runtime checks, not guessed from screenshots.

Development runs use an isolated QA profile and fresh test worlds. A successful validation is not a visual test. Clearly distinguish prototype assets and screenshots of actual renders from generated concepts. Do not claim the complete unit set or HOI4-level asset quality from one prototype.
