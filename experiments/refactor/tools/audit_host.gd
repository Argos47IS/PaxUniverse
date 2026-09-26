extends Node
## Read-only metadata audit through the running game's public Godot reflection API.
## No source extraction, bytecode conversion, encryption keys or protected-data dumps.

var _output: String
var _scripts: Dictionary = {}
var _files: Array[Dictionary] = []

func _ready() -> void:
    call_deferred("_run")

func _run() -> void:
    if not OS.get_user_data_dir().replace("\\", "/").ends_with("/Pax Universe Refactor QA"):
        get_tree().quit(2)
        return
    _output = OS.get_environment("PAX_REFACTOR_OUTPUT")
    if not _output.is_absolute_path():
        get_tree().quit(2)
        return
    var autoloads: Dictionary = {}
    for setting: Dictionary in ProjectSettings.get_property_list():
        var key: String = str(setting.name)
        if key.begins_with("autoload/"):
            autoloads[key] = str(ProjectSettings.get_setting(key))
    _walk_files("res://")
    for item: Dictionary in _files:
        var path: String = str(item.path)
        if path.begins_with("res://scripts/") and path.ends_with(".gd.remap"):
            _inspect_script(load(path.trim_suffix(".remap")) as Script)
        elif path.begins_with("res://scripts/") and path.ends_with(".gd"):
            _inspect_script(load(path) as Script)
    # Exported resources can be remapped and hidden from a directory listing.
    for path: String in ["res://scripts/Main.gd", "res://scripts/моды/PaxGame.gd", "res://scripts/Лаунчер.gd"]:
        _inspect_script(load(path) as Script)
    var report: Dictionary = {
        "version": FileAccess.get_file_as_string("res://data/version.txt").strip_edges(),
        "engine": Engine.get_version_info(), "autoloads": autoloads,
        "files": _files, "scripts": _scripts,
        "method": "Godot resource metadata and script reflection; no code extraction"
    }
    DirAccess.make_dir_recursive_absolute(_output)
    var file: FileAccess = FileAccess.open(_output.path_join("runtime-inventory.json"), FileAccess.WRITE)
    file.store_string(JSON.stringify(report, "\t"))
    file.close()
    print("REFACTOR_AUDIT_COMPLETE scripts=", _scripts.size(), " files=", _files.size())
    get_tree().quit(0)

func _walk_files(path: String) -> void:
    var directory: DirAccess = DirAccess.open(path)
    if directory == null:
        return
    for name: String in directory.get_files():
        var full_path: String = path.path_join(name)
        _files.append({"path": full_path})
    for name: String in directory.get_directories():
        if name == "mods" or name.begins_with("."):
            continue
        _walk_files(path.path_join(name))

func _inspect_script(script: Script) -> void:
    if script == null or _scripts.has(script.resource_path):
        return
    var path: String = script.resource_path
    var methods: Array = script.get_script_method_list()
    var properties: Array = script.get_script_property_list()
    var signals: Array = script.get_script_signal_list()
    var dependencies: Dictionary = {}
    _scripts[path] = {
        "has_source": script.has_source_code(), "source_chars": script.get_source_code().length(),
        "method_count": methods.size(), "property_count": properties.size(), "signal_count": signals.size(),
        "methods": methods, "properties": properties, "signals": signals, "dependencies": dependencies
    }
    var base: Script = script.get_base_script()
    if base != null:
        dependencies["extends"] = base.resource_path
        _inspect_script(base)
    for key: Variant in script.get_script_constant_map():
        var value: Variant = script.get_script_constant_map()[key]
        if value is Script:
            var dependency: Script = value as Script
            dependencies[str(key)] = dependency.resource_path
            _inspect_script(dependency)
