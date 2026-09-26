# Instructions for AI coding assistants (Claude Code, Cursor, Copilot, Codex…)

This folder is a **Pax Universe mod** — a 3D space strategy about restoring Earth after a nuclear war,
built on **Godot 4.7** with **GDScript**. Read this whole file before writing anything.

## Where things are

| What | Where |
|---|---|
| Mod manifest | `mod.json` (schema: `docs/modding/schemas/mod.schema.json` in the game folder) |
| Mod code entry | `main.gd` — must start with `extends PaxMod` |
| Changes to game data | `data/<file>.patch.json` — mirrors the game's `data/<file>.json` |
| Translations | `data/lang/<code>.json` — merged into the game dictionary |
| Your assets | anywhere in the mod; address them as `res://mods/<id>/…` or `path("…")` in code |
| Full guide | `docs/modding/en/README.md` (RU: `docs/modding/ru/README.md`) |
| API reference | `docs/modding/en/api-reference.md` (generated from code — trust it) |
| Working examples | `mods/example_theia` (planet + UI + save), `mods/example_alpha_centauri` (star system + arks) |

If the game folder is not open next to the mod, ask the user where the game is installed: the docs,
schemas and the game's own `data/*.json` (the source of truth for field names) are there.

## Hard rules

1. **Never copy a whole game data file** into the mod. Use `*.patch.json` with `$append`, `$edit` + `$match`,
   `$remove`, `$insert_after`, `$replace`, or plain object merge (`null` deletes a key). Otherwise mods conflict.
2. **Game data keys are Russian** (`"тела"`, `"имя"`, `"род"`, `"параметры"`). Copy them exactly from the game's
   `data/*.json`. Do not translate keys. Body names (`"Земля"`, `"Марс"`) are ids — also exact.
3. **No player-visible text in code.** Put it into `data/lang/en.json` and `data/lang/ru.json` (at least these two)
   and read with `tr_key("key")`. Prefix keys with the mod id to avoid collisions.
4. **GDScript is strict here**: inferring a type from an untyped value is a compile error.
   Write `var x: float = dict["a"]`, not `var x := dict["a"]`. Same for results of untyped calls.
5. Use the **stable API** (`PaxGame` methods, `Pax` signals, `PaxMod` callbacks). `game.main`, `game.sim`,
   `game.world`, `game.stock` are raw internals with Russian identifiers — allowed, but may change between versions.
6. Save state only through `_save_state` → `_game_loaded` (JSON types only: no Vector3, no Objects).
7. Textures, sounds and models from the mod load at runtime without Godot import: use `texture()`, `sound()`,
   `model()`, `shader()` helpers (or `Pax.texture(path)`), never `load()` for png/jpg/ogg/glb.

## Verify your work — always

```
godot --headless --path <game folder> -- --check-mods <mod id>
```
Exit code 0 = no errors. Fix every ERROR and read every WARNING. In the running game press **F8** for the dev
console: `check <id>`, `json res://data/bodies.json` (final data after all patches), `eval game.body_names()`,
`reload` (re-read JSON/text/images without restarting).

Enable/disable mods in the launcher → **Mods** (restart applies). Package for sharing: `--pack-mod <id>`.
