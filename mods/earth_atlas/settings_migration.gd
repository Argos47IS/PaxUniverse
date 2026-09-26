extends RefCounted
## Import legacy visual preferences once without changing the legacy mod or loader.

const TARGET_ID: String = "earth_atlas"
const LEGACY_SETTINGS: String = "user://mod_settings/earth_atlas_hd.json"
const MIGRATION_MARKER: String = "_migration_earth_atlas_hd_v1"
const KEYS: Array[String] = ["enabled", "quality", "natural", "political", "urban"]
const MAX_SETTINGS_BYTES: int = 65536

static func migrate(mod: PaxMod) -> Dictionary:
    var report: Dictionary = {"status": "skipped", "copied": [], "preserved": [], "rejected": []}
    # Guard against accidentally running this helper from the legacy mod.
    if mod.id != TARGET_ID:
        report.status = "wrong_target"
        return report
    var completed: Variant = mod.get_setting(MIGRATION_MARKER, false)
    if typeof(completed) == TYPE_BOOL and bool(completed):
        report.status = "already_complete"
        return report

    var source_result: Dictionary = _read_legacy()
    report.status = source_result.status
    if source_result.has("settings"):
        var source: Dictionary = source_result.settings
        var absent: RefCounted = RefCounted.new()
        for key: String in KEYS:
            if not source.has(key):
                continue
            # A private object sentinel distinguishes a missing value from an
            # existing null/false/zero. Every existing new preference takes priority.
            var current: Variant = mod.get_setting(key, absent)
            if not is_same(current, absent):
                report.preserved.append(key)
                continue
            var value: Variant = _validated_value(key, source[key])
            if value == null:
                report.rejected.append(key)
                continue
            mod.set_setting(key, value)
            report.copied.append(key)

    # Missing or corrupt legacy settings are also a completed attempt: future
    # reloads must not suddenly import old values over the new mod's defaults.
    mod.set_setting(MIGRATION_MARKER, true)
    return report

static func _read_legacy() -> Dictionary:
    if not FileAccess.file_exists(LEGACY_SETTINGS):
        return {"status": "legacy_missing"}
    var file: FileAccess = FileAccess.open(LEGACY_SETTINGS, FileAccess.READ)
    if file == null:
        return {"status": "legacy_unreadable"}
    if file.get_length() > MAX_SETTINGS_BYTES:
        file.close()
        return {"status": "legacy_too_large"}
    var contents: String = file.get_as_text()
    file.close()
    var parser: JSON = JSON.new()
    var parse_error: Error = parser.parse(contents)
    if parse_error != OK or not parser.data is Dictionary:
        return {"status": "legacy_invalid"}
    return {"status": "migrated", "settings": parser.data}

static func _validated_value(key: String, value: Variant) -> Variant:
    if key == "enabled":
        return value if typeof(value) == TYPE_BOOL else null
    if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
        return null
    var number: float = float(value)
    if not is_finite(number):
        return null
    var lower: float = 0.0
    var upper: float = 1.0
    match key:
        "quality":
            lower = 0.5
            upper = 2.0
        "political":
            upper = 0.6
        "natural", "urban":
            pass
        _:
            return null
    return number if number >= lower and number <= upper else null
