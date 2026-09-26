extends Node
## Real launcher/load-distribution regression. Run only in the isolated QA profile.
## This Node survives unloading the mod that started it; main's dispatcher must
## also guard repeated --atlas-distribution-test dispatches with root metadata.

const NEW_ID: String = "earth_atlas"
const OLD_ID: String = "earth_atlas_hd"
const EXPECTED_PROFILE: String = "C:/Users/usarg/AppData/Roaming/Pax Universe Atlas QA"
const HARNESS_META: String = "atlas_distribution_test_running"
const SettingsMigration = preload("../settings_migration.gd")
const MARKER: String = "_migration_earth_atlas_hd_v1"
const MOD_SETTINGS: String = "user://mods.json"
const OLD_SETTINGS: String = "user://mod_settings/earth_atlas_hd.json"
const NEW_SETTINGS: String = "user://mod_settings/earth_atlas.json"
const SETTINGS_KEYS: Array[String] = ["enabled", "quality", "natural", "political", "urban"]
const DEFAULTS: Dictionary = {"enabled": true, "quality": 1.0, "natural": 0.80,
    "political": 0.25, "urban": 0.08}
const QA_FILES: Array[String] = [MOD_SETTINGS, OLD_SETTINGS, NEW_SETTINGS]

class FixturePackages extends RefCounted:
    func пакет_есть(_package: String) -> bool:
        return true

class FixtureLauncher extends Control:
    # The real mod-page script owns scanning, checkboxes, order and saving.
    # This host supplies only presentation helpers and suppresses package offers.
    const ТЕКСТ: Color = Color(0.92, 0.94, 0.97)
    const ТУСКЛЫЙ: Color = Color(0.6, 0.66, 0.75)
    const ТИХИЙ: Color = Color(0.4, 0.45, 0.53)
    const АКЦЕНТ: Color = Color(0.93, 0.74, 0.38)
    const ЖЁЛТЫЙ: Color = Color(0.93, 0.76, 0.4)
    const КРАСНЫЙ: Color = Color(0.92, 0.48, 0.44)
    var язык: Dictionary = {"код": "ru"}
    var Обн: FixturePackages = FixturePackages.new()
    var list: VBoxContainer = VBoxContainer.new()

    func _ready() -> void:
        list.size = Vector2(1000, 720)
        add_child(list)

    func _т(key: String) -> String:
        match key:
            "мод_включено":
                return "%d / %d"
            "мод_пусто_пояснение", "мод_авторы":
                return "%s"
        return key

    func _кнопка(label: String) -> Button:
        var button: Button = Button.new()
        button.text = label
        return button

    func _метка(value: String, font_size: int, color: Color, wrap: bool = false) -> Label:
        var label: Label = Label.new()
        label.text = value
        label.add_theme_font_size_override("font_size", font_size)
        label.add_theme_color_override("font_color", color)
        if wrap:
            label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        return label

    # LauncherMod rows pass four arguments, but their tag chips pass only two.
    # Match the real launcher's optional parameters so both calls return a style.
    func _сб(color: Color, radius: int = 10, border: Color = Color(0, 0, 0, 0), width: int = 0) -> StyleBoxFlat:
        var box: StyleBoxFlat = StyleBoxFlat.new()
        box.bg_color = color
        box.border_color = border
        box.set_border_width_all(width)
        box.set_corner_radius_all(radius)
        return box

    func _карточка() -> PanelContainer:
        var panel: PanelContainer = PanelContainer.new()
        panel.add_child(VBoxContainer.new())
        return panel

var _tree: SceneTree
var _output: String = ""
var _checks: Array[String] = []
var _errors: Array[String] = []
var _events: Array[Dictionary] = []
var _backups: Dictionary = {}
var _host: FixtureLauncher
var _page: RefCounted
var _initial_instance: WeakRef
var _initial_instance_id: int = 0
var _initial_manifest: Dictionary = {}
var _initial_legacy: Dictionary = {}
var _finished: bool = false

func start(source_mod: Node, output_dir: String) -> void:
    _tree = get_tree()
    # Main reserves this same key with true before creating the runner. The
    # runner replaces that reservation with its instance id; repeat runners stop.
    var owner: Variant = _tree.root.get_meta(HARNESS_META, null)
    if typeof(owner) == TYPE_INT and int(owner) != get_instance_id():
        queue_free()
        return
    _tree.root.set_meta(HARNESS_META, get_instance_id())
    _output = output_dir if output_dir != "" else "user://mod_tests/atlas_distribution"
    var profile: String = OS.get_user_data_dir().replace("\\", "/")
    var safe_profile: bool = profile == EXPECTED_PROFILE
    assert(safe_profile, "Distribution regression requires the isolated Atlas QA profile.")
    if not _check(safe_profile, "exact isolated QA profile assertion"):
        push_error("Atlas distribution test refused a non-QA profile")
        _tree.quit(2)
        return
    if not _check(get_parent() == _tree.root, "harness lives independently under tree.root"):
        _finish()
        return
    if not _check(is_instance_valid(source_mod) and str(source_mod.get("id")) == NEW_ID,
            "started by the new mod id"):
        _finish()
        return
    for path: String in QA_FILES:
        var exists: bool = FileAccess.file_exists(path)
        _backups[path] = {"exists": exists,
            "bytes": FileAccess.get_file_as_bytes(path) if exists else PackedByteArray()}
    _initial_instance = weakref(source_mod)
    _initial_instance_id = source_mod.get_instance_id()
    _initial_manifest = (source_mod.get("manifest") as Dictionary).duplicate(true)
    _initial_legacy = _read_json(OLD_SETTINGS)
    # No coroutine on the caller is retained: it will be freed during the test.
    call_deferred("_run")

func _run() -> void:
    _check(str(_initial_manifest.get("version", "")) == "0.2.0", "new distribution version is 0.2.0")
    _check(str(_initial_manifest.get("kind", "")) == "zip"
        and str(_initial_manifest.get("source", "")).get_extension().to_lower() == "zip",
        "new mod was loaded from its ZIP distribution")
    _check(Pax.get_mod(NEW_ID) != null, "new ZIP code loaded before test despite old id next to it")
    _check(_read_json(NEW_SETTINGS).get(MARKER, false) == true, "initial launch completed migration")
    _check(_initial_legacy.has_all(SETTINGS_KEYS), "startup fixture provides all five legacy settings")
    if _initial_legacy.has_all(SETTINGS_KEYS):
        _check_preferences(_initial_legacy, "first launch imports legacy preferences")

    _host = FixtureLauncher.new()
    _tree.root.add_child(_host)
    var page_script: Script = load("res://scripts/ЛаунчерМоды.gd")
    _page = page_script.new(_host) as RefCounted
    _page.call("построить", _host.list)
    await _frames(3)
    var legacy_record: Dictionary = _record(OLD_ID)
    if not _check(not legacy_record.is_empty(), "legacy id is discovered beside new ZIP"):
        _finish()
        return
    _check(str(legacy_record.get("kind", "")) == "folder", "legacy fixture remains a separate folder mod")
    _check(not _record(NEW_ID).is_empty(), "real launcher page lists the new mod")

    await _toggle(false, "launcher off")
    _check(_initial_instance.get_ref() == null, "original mod instance is destroyed while harness survives")
    await _toggle(true, "launcher on")
    var current: PaxMod = Pax.get_mod(NEW_ID)
    _check(current != null and current.get_instance_id() != _initial_instance_id,
        "launcher on creates a fresh real mod instance")

    _page.call("построить", _host.list)
    var before_order: Array[String] = _ids()
    var index: int = before_order.find(NEW_ID)
    if _check(index >= 0 and before_order.size() >= 2, "reorder fixture has both mod ids"):
        var direction: int = 1 if index < before_order.size() - 1 else -1
        var expected_order: Array[String] = before_order.duplicate()
        var displaced: String = expected_order[index + direction]
        expected_order[index + direction] = NEW_ID
        expected_order[index] = displaced
        _page.call("_сдвинуть", index, direction)
        await _frames(4)
        _check(_read_json(MOD_SETTINGS).get("order", []) == expected_order,
            "real launcher reorder persists the requested order")
        _check(Pax.get_mod(NEW_ID) != null, "new mod survives two-argument save during reorder")
        _check(not _disabled(NEW_ID), "reorder does not silently disable the new id")

    # Remove seen while no new instance exists, then use the real loader again.
    await _toggle(false, "off before absent-seen reload")
    var no_seen: Dictionary = _read_json(MOD_SETTINGS)
    var disabled: Array = no_seen.get("disabled", []).duplicate()
    disabled.erase(NEW_ID)
    no_seen["disabled"] = disabled
    no_seen.erase("seen")
    if not _write_json(MOD_SETTINGS, no_seen):
        _finish()
        return
    _check(not _read_json(MOD_SETTINGS).has("seen"), "QA reload fixture has no seen field")
    Pax.reload_mods()
    await _frames(5)
    _check(Pax.get_mod(NEW_ID) != null, "new ZIP loads from absent-seen settings")
    _check(not _disabled(NEW_ID), "absent seen does not add new id to disabled")
    _check(_disabled(OLD_ID) and Pax.get_mod(OLD_ID) == null,
        "legacy auto-disable remains confined to the old id")
    _page.call("построить", _host.list)

    # Real unload/load cycle re-runs production migration with a controlled source.
    await _toggle(false, "off before migration fixture")
    var legacy: Dictionary = {"enabled": true, "quality": 1.5, "natural": 0.61,
        "political": 0.31, "urban": 0.12, "qa_legacy_extra": "leave unchanged"}
    if not _write_json(OLD_SETTINGS, legacy) or not _remove_file(NEW_SETTINGS):
        _finish()
        return
    var legacy_bytes: PackedByteArray = FileAccess.get_file_as_bytes(OLD_SETTINGS)
    await _toggle(true, "on with legacy-only preferences")
    _check_preferences(legacy, "real load migrates all five preferences")
    _check(_read_json(NEW_SETTINGS).get(MARKER, false) == true, "production load persists migration marker")
    _check(FileAccess.get_file_as_bytes(OLD_SETTINGS) == legacy_bytes, "migration does not change legacy settings")

    # Existing new values must win; only absent supported keys may be imported.
    await _toggle(false, "off before partial-new fixture")
    var partial: Dictionary = {"quality": 1.75, "natural": 0.23, "qa_new_extra": "preserve"}
    if not _write_json(NEW_SETTINGS, partial):
        _finish()
        return
    await _toggle(true, "on with partial new preferences")
    var expected: Dictionary = legacy.duplicate(true)
    expected["quality"] = 1.75
    expected["natural"] = 0.23
    _check_preferences(expected, "new values take precedence while missing values migrate")
    _check(_read_json(NEW_SETTINGS).get("qa_new_extra", "") == "preserve", "migration retains unrelated new preference")

    current = Pax.get_mod(NEW_ID)
    if current != null:
        current.set_setting("quality", 0.75)
        current.set_setting("urban", 0.05)
        expected["quality"] = 0.75
        expected["urban"] = 0.05
    else:
        _check(false, "new instance exists before saving its own preferences")
    var new_bytes: PackedByteArray = FileAccess.get_file_as_bytes(NEW_SETTINGS)
    legacy["quality"] = 2.0
    legacy["natural"] = 0.9
    legacy["enabled"] = false
    if not _write_json(OLD_SETTINGS, legacy):
        _finish()
        return
    legacy_bytes = FileAccess.get_file_as_bytes(OLD_SETTINGS)
    await _toggle(false, "off after saving new preferences")
    await _toggle(true, "on after legacy values changed")
    _check_preferences(expected, "reload preserves new preferences after old preferences change")
    _check(FileAccess.get_file_as_bytes(NEW_SETTINGS) == new_bytes,
        "completed migration leaves new settings byte-identical across reload")
    _check(FileAccess.get_file_as_bytes(OLD_SETTINGS) == legacy_bytes,
        "reload never rewrites the legacy preference file")

    await _toggle(false, "off before missing-legacy fixture")
    if not _remove_file(OLD_SETTINGS) or not _remove_file(NEW_SETTINGS):
        _finish()
        return
    await _toggle(true, "on without legacy preferences")
    _check_defaults("missing legacy uses defaults after real load")
    _check(not FileAccess.file_exists(OLD_SETTINGS), "missing legacy file is not recreated")
    _check_migration_does_not_write_loader_settings("missing legacy")

    await _toggle(false, "off before corrupt-legacy fixture")
    var corrupt: PackedByteArray = "{\"quality\": ".to_utf8_buffer()
    if not _write_file(OLD_SETTINGS, corrupt) or not _remove_file(NEW_SETTINGS):
        _finish()
        return
    await _toggle(true, "on with corrupt legacy JSON")
    _check_defaults("corrupt legacy uses defaults after real load")
    _check(FileAccess.get_file_as_bytes(OLD_SETTINGS) == corrupt, "corrupt legacy bytes remain untouched")
    _check_migration_does_not_write_loader_settings("corrupt legacy")

    await _toggle(false, "off before invalid-values fixture")
    var invalid: Dictionary = {"enabled": "false", "quality": 9.0,
        "natural": true, "political": -0.25, "urban": [0.12]}
    if not _write_json(OLD_SETTINGS, invalid) or not _remove_file(NEW_SETTINGS):
        _finish()
        return
    legacy_bytes = FileAccess.get_file_as_bytes(OLD_SETTINGS)
    await _toggle(true, "on with invalid legacy types and ranges")
    _check_defaults("invalid legacy types and ranges use defaults after real load")
    _check(FileAccess.get_file_as_bytes(OLD_SETTINGS) == legacy_bytes,
        "invalid legacy preferences remain untouched")
    _check_migration_does_not_write_loader_settings("invalid legacy values")
    _finish()

func _toggle(on: bool, label: String) -> void:
    var record: Dictionary = _record(NEW_ID)
    if not _check(not record.is_empty(), label + ": launcher record exists"):
        return
    _page.call("_переключить", record, on)
    await _frames(4)
    var present: bool = Pax.get_mod(NEW_ID) != null
    _check(present == on, label + ": real Pax instance agrees with requested state")
    _check(bool(record.get("enabled", not on)) == present, label + ": launcher state agrees with loader")
    _check(_disabled(NEW_ID) == (not on), label + ": persisted disabled list agrees")
    _events.append({"action": label, "requested": on, "instance_present": present,
        "new_id_disabled": _disabled(NEW_ID)})

func _record(id: String) -> Dictionary:
    var records: Array = _page.get("_список")
    for record: Dictionary in records:
        if str(record.get("id", "")) == id:
            return record
    return {}

func _ids() -> Array[String]:
    var result: Array[String] = []
    var records: Array = _page.get("_список")
    for record: Dictionary in records:
        result.append(str(record.get("id", "")))
    return result

func _disabled(id: String) -> bool:
    var settings: Dictionary = _read_json(MOD_SETTINGS)
    var disabled: Array = settings.get("disabled", [])
    return disabled.has(id)

func _check_preferences(expected: Dictionary, label: String) -> void:
    var current: PaxMod = Pax.get_mod(NEW_ID)
    var values: Dictionary = _read_json(NEW_SETTINGS)
    var matches: bool = current != null
    for key: String in SETTINGS_KEYS:
        if not expected.has(key) or not values.has(key):
            matches = false
            continue
        var value: Variant = current.get_setting(key, null) if current != null else null
        var applied: Variant = current.get("_" + key) if current != null else null
        if key == "enabled":
            matches = matches and values[key] == expected[key] and value == expected[key] and applied == expected[key]
        else:
            matches = matches and value != null and applied != null
            if value != null and applied != null:
                matches = matches and is_equal_approx(float(values[key]), float(expected[key]))
                matches = matches and is_equal_approx(float(value), float(expected[key]))
                matches = matches and is_equal_approx(float(applied), float(expected[key]))
    _check(matches, label)

func _check_defaults(label: String) -> void:
    var current: PaxMod = Pax.get_mod(NEW_ID)
    var saved: Dictionary = _read_json(NEW_SETTINGS)
    var matches: bool = current != null and saved.get(MARKER, false) == true
    for key: String in SETTINGS_KEYS:
        # Defaults need not be persisted; rejected input must not be persisted.
        matches = matches and not saved.has(key)
        var value: Variant = current.get_setting(key, DEFAULTS[key]) if current != null else null
        var applied: Variant = current.get("_" + key) if current != null else null
        if key == "enabled":
            matches = matches and value == true and applied == true
        elif value == null or applied == null:
            matches = false
        else:
            matches = matches and is_equal_approx(float(value), float(DEFAULTS[key]))
            matches = matches and is_equal_approx(float(applied), float(DEFAULTS[key]))
    _check(matches, label)

func _check_migration_does_not_write_loader_settings(label: String) -> void:
    var current: PaxMod = Pax.get_mod(NEW_ID)
    if not _check(current != null, label + ": real loaded instance exists for isolated migration check"):
        return
    # Replay the actual migration path, not its completed-marker early return.
    # The preceding real reload already verified initial production integration.
    current.set_setting(MARKER, false)
    var before: PackedByteArray = FileAccess.get_file_as_bytes(MOD_SETTINGS)
    var result: Dictionary = SettingsMigration.migrate(current)
    _check(FileAccess.get_file_as_bytes(MOD_SETTINGS) == before,
        label + ": migration leaves mods.json byte-identical")
    _check(_read_json(NEW_SETTINGS).get(MARKER, false) == true,
        label + ": standalone migration completes its own marker")
    _events.append({"action": label + " migration replay", "migration_status": result.get("status", ""),
        "loader_settings_unchanged": FileAccess.get_file_as_bytes(MOD_SETTINGS) == before})

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parser: JSON = JSON.new()
    var error: Error = parser.parse(FileAccess.get_file_as_string(path))
    return parser.data as Dictionary if error == OK and parser.data is Dictionary else {}

func _write_json(path: String, data: Dictionary) -> bool:
    return _write_file(path, JSON.stringify(data, "  ").to_utf8_buffer())

func _write_file(path: String, bytes: PackedByteArray) -> bool:
    if not _safe_file(path):
        return _check(false, "refused write outside enumerated QA fixture files")
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
    var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return _check(false, "cannot write QA fixture file: " + path)
    file.store_buffer(bytes)
    file.close()
    return true

func _remove_file(path: String) -> bool:
    if not _safe_file(path):
        return _check(false, "refused removal outside enumerated QA fixture files")
    if not FileAccess.file_exists(path):
        return true
    return _check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK,
        "removed only requested QA fixture file: " + path)

func _safe_file(path: String) -> bool:
    if OS.get_user_data_dir().replace("\\", "/") != EXPECTED_PROFILE or not QA_FILES.has(path):
        return false
    var resolved: String = ProjectSettings.globalize_path(path).replace("\\", "/")
    return resolved == EXPECTED_PROFILE + "/" + path.trim_prefix("user://")

func _frames(count: int) -> void:
    for frame: int in range(count):
        await _tree.process_frame

func _check(condition: bool, label: String) -> bool:
    if condition:
        _checks.append(label)
    else:
        _errors.append(label)
    return condition

func _finish() -> void:
    if _finished:
        return
    _finished = true
    var restored: bool = true
    for path: String in _backups:
        var saved: Dictionary = _backups[path]
        if bool(saved.exists):
            restored = _write_file(path, saved.bytes) and restored
            restored = FileAccess.get_file_as_bytes(path) == saved.bytes and restored
        else:
            restored = _remove_file(path) and restored
            restored = not FileAccess.file_exists(path) and restored
    if not _backups.is_empty():
        _check(restored, "all enumerated QA files restored to harness-entry bytes/existence")
    if is_instance_valid(_host):
        _host.queue_free()
    _page = null
    var report: Dictionary = {"ok": _errors.is_empty(), "checks": _checks, "errors": _errors,
        "profile": OS.get_user_data_dir(), "mod_id": NEW_ID,
        "source_kind": _initial_manifest.get("kind", ""), "source": _initial_manifest.get("source", ""),
        "version": _initial_manifest.get("version", ""), "events": _events,
        "qa_files_restored": restored,
        "limitations": "Real mod-page scan/toggle/reorder, Pax loader and ZIP code; fixture launcher supplies presentation only. No full world, render-coexistence, user profile or UI automation tested. Initial pre-launch empty-seen/legacy seed must be prepared by the external QA runner."}
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
    var file: FileAccess = FileAccess.open(_output.path_join("distribution-report.json"), FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(report, "\t"))
        file.close()
    else:
        push_error("Could not save Atlas distribution report")
        _tree.quit(4)
        return
    print("ATLAS_DISTRIBUTION_RESULT ", JSON.stringify(report))
    _tree.quit(0 if bool(report.ok) else 1)
