extends RefCounted
## Import preferences only through an active legacy mod's public settings API.

const TARGET_ID: String = "earth_atlas"
const LEGACY_ID: String = "earth_atlas_hd"
const MIGRATION_MARKER: String = "_migration_earth_atlas_hd_v1"
const KEYS: Array[String] = ["enabled", "quality", "natural", "political", "urban"]

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

    # The sandbox owns file access. A disabled legacy mod's settings are private;
    # leave our existing preferences intact and never read another mod's files.
    var legacy: PaxMod = Pax.get_mod(LEGACY_ID)
    if not is_instance_valid(legacy):
        report.status = "legacy_not_active"
        return report
    report.status = "migrated"
    var absent: RefCounted = RefCounted.new()
    for key: String in KEYS:
        var source: Variant = legacy.get_setting(key, absent)
        if is_same(source, absent):
            continue
        # Existing new values, including null/false/zero, always take priority.
        var current: Variant = mod.get_setting(key, absent)
        if not is_same(current, absent):
            report.preserved.append(key)
            continue
        var value: Variant = _validated_value(key, source)
        if value == null:
            report.rejected.append(key)
            continue
        mod.set_setting(key, value)
        report.copied.append(key)
    mod.set_setting(MIGRATION_MARKER, true)
    return report

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
