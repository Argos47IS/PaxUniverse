extends RefCounted
## Development-only GPU harness. It does not create/load a world or touch saves.
## Call: await load(path).new().start(mod, shaders, absolute_output_directory).
## shaders: {surface: Shader, political: Shader}; returns {ok, files, error?}.
## Political ownership and development are deterministic test fixtures, not a save.

func start(mod: Node, shaders: Dictionary, output_dir: String) -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {"ok": false, "error": "GPU rendering requires a non-headless process"}
	if not (shaders.get("surface") is Shader) or not (shaders.get("political") is Shader):
		return {"ok": false, "error": "Missing modified Shader resources"}
	var err: Error = DirAccess.make_dir_recursive_absolute(output_dir)
	if err != OK:
		return {"ok": false, "error": "Cannot create output directory: %s" % err}
	var originals: Dictionary = {
		"surface": load("res://shaders/map_surface.gdshader"),
		"political": load("res://shaders/map.gdshader")
	}
	var common: Dictionary = _earth_uniforms()
	if common.is_empty():
		return {"ok": false, "error": "Earth assets or province fixtures unavailable"}
	var elevation: Texture2D = mod.call("texture", "textures/elevation.png") as Texture2D
	if elevation == null:
		return {"ok": false, "error": "Mod elevation texture unavailable"}
	var scenarios: Array[Dictionary] = [
		{"name": "eastern_europe", "center": Vector2(0.5806, 0.2111), "zoom": 13.0},
		{"name": "europe", "center": Vector2(0.55, 0.2389), "zoom": 5.0},
		{"name": "world", "center": Vector2(0.5, 0.5), "zoom": 1.0},
		{"name": "ruined_europe", "center": Vector2(0.5806, 0.2111), "zoom": 13.0,
		 "climate": {"temperature": 0.15, "water": 0.35, "biomass": 0.02,
		 "biomass_nat": 0.02, "radiation": 0.85, "radiation_nat": 0.85, "urban": 0.01}},
	]
	var files: Array[String] = []
	var root: Node = Node.new()
	root.name = "AtlasRenderTest"
	mod.get_tree().root.add_child(root)
	for scenario: Dictionary in scenarios:
		for variant: String in ["original", "modified"]:
			var pair: Dictionary = originals if variant == "original" else shaders
			var uniforms: Dictionary = common.duplicate()
			if variant == "modified":
				uniforms["atlas_elevation"] = elevation
				uniforms["atlas_has_elevation"] = 1.0
			uniforms.merge(scenario.get("climate", {}), true)
			uniforms["view_center"] = scenario["center"]
			uniforms["view_zoom"] = scenario["zoom"]
			uniforms["rect_px"] = Vector2(1920.0, 1080.0)
			var size: Vector2i = Vector2i(1920, 1080)
			var surface_size: Vector2i = Vector2i(960, 540) if variant == "original" else size
			var surface: SubViewport = _viewport(root, surface_size, pair["surface"], uniforms)
			# Surface alpha is a data channel (land + lights), preserve it exactly.
			surface.transparent_bg = true
			await _settle(mod.get_tree())
			uniforms["surface_tex"] = surface.get_texture()
			var result: SubViewport = _viewport(root, size, pair["political"], uniforms)
			await _settle(mod.get_tree())
			var img: Image = result.get_texture().get_image()
			var filename: String = output_dir.path_join("%s_%s.png" % [scenario["name"], variant])
			if img == null or img.is_empty():
				root.queue_free()
				return {"ok": false, "files": files, "error": "GPU returned an empty image"}
			err = img.save_png(filename)
			if err != OK:
				root.queue_free()
				return {"ok": false, "files": files, "error": "PNG save failed: %s" % err}
			files.append(filename)
			print("ATLAS_RENDER_IMAGE ", filename)
			result.queue_free()
			surface.queue_free()
			await mod.get_tree().process_frame
	root.queue_free()
	var report: Dictionary = {
		"ok": true, "files": files, "renderer": RenderingServer.get_video_adapter_name(),
		"output_size": [1920, 1080], "original_surface_size": [960, 540],
		"modified_surface_size": [1920, 1080], "earth_albedo_size": [8192, 4096],
		"province_geometry": "Game data/regions.bin; unmodified 4096 x 2048 uint16 ids",
		"ownership": "Synthetic fixed country colors, known owned provinces, uniform development",
		"limitations": "Shader-only GPU comparison; no game UI, labels, simulation or saved world"
	}
	var report_file: FileAccess = FileAccess.open(output_dir.path_join("render-report.json"), FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report, "\t"))
	return report

func _settle(tree: SceneTree) -> void:
	# Let dependency viewports render before sampling their textures.
	for frame: int in range(3):
		await tree.process_frame
		await RenderingServer.frame_post_draw

func _viewport(parent: Node, size: Vector2i, shader: Shader, uniforms: Dictionary) -> SubViewport:
	var vp: SubViewport = SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	var rect: ColorRect = ColorRect.new()
	rect.size = Vector2(size)
	rect.color = Color.WHITE
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	for key: String in uniforms:
		material.set_shader_parameter(key, uniforms[key])
	rect.material = material
	vp.add_child(rect)
	parent.add_child(vp)
	return vp

func _earth_uniforms() -> Dictionary:
	# Imported game textures can use load; external mod images must use Pax.texture.
	var albedo: Texture2D = load("res://maps/earth_albedo.jpg") as Texture2D
	var ocean: Texture2D = load("res://maps/earth_ocean.jpg") as Texture2D
	var metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/regions.json"))
	if albedo == null or ocean == null or not metadata is Dictionary:
		return {}
	var data: Dictionary = metadata
	var width: int = int(data.get("ширина", 4096))
	var height: int = int(data.get("высота", 2048))
	var map_data: PackedByteArray = FileAccess.get_file_as_bytes("res://data/regions.bin").decompress(width * height * 2, FileAccess.COMPRESSION_GZIP)
	var water_data: PackedByteArray = FileAccess.get_file_as_bytes("res://data/regions_water.bin").decompress(width * height, FileAccess.COMPRESSION_GZIP)
	var grow_width: int = int(data.get("очередь_ширина", width / 2))
	var grow_height: int = int(data.get("очередь_высота", height / 2))
	var grow_data: PackedByteArray = FileAccess.get_file_as_bytes("res://data/regions_grow.bin").decompress(grow_width * grow_height, FileAccess.COMPRESSION_GZIP)
	if map_data.size() != width * height * 2 or water_data.size() != width * height or grow_data.size() != grow_width * grow_height:
		return {}
	var regions: Array = data.get("регионы", [])
	var count: int = 1
	for row: Dictionary in regions:
		count = maxi(count, int(row["id"]) + 1)
	var palette: Image = Image.create(count, 1, false, Image.FORMAT_RGBA8)
	var flags: Image = Image.create(count, 1, false, Image.FORMAT_RGBA8)
	var clear: Image = Image.create(count, 1, false, Image.FORMAT_RGBA8)
	clear.fill(Color(0, 0, 0, 0))
	palette.fill(Color(0, 0, 0, 0))
	flags.fill(Color(0, 0, 0, 0))
	for row: Dictionary in regions:
		var id: int = int(row["id"])
		var country: String = str(row.get("страна", ""))
		var hue: float = float(absi(country.hash()) % 1000) / 1000.0
		var color: Color = Color.from_hsv(hue, 0.48, 0.72, 0.55)
		palette.set_pixel(id, 0, color)
		flags.set_pixel(id, 0, Color(0.0, 1.0, 0.0, 1.0))
	return {
		"map_albedo": albedo, "map_ocean": ocean, "use_map": 1.0, "use_ocean": 1.0,
		"use_height": 0.0, "map_sea": 0.5, "map_tint": 0.14,
		"temperature": 0.35, "water": 0.71, "biomass": 0.55, "radiation": 0.08,
		"atmosphere": 0.7, "urban": 0.08, "biomass_nat": 0.55, "radiation_nat": 0.08,
		"world_seed": 0.0, "lights_on": 1.0, "night_shade": 0.0,
		"use_regions": 1.0, "show_borders": 1.0, "use_nets": 0.0,
		"use_trans": 0.0, "use_region_set": 0.0, "use_overlay": 0.0,
		"region_map": ImageTexture.create_from_image(Image.create_from_data(width, height, false, Image.FORMAT_RG8, map_data)),
		"region_water": ImageTexture.create_from_image(Image.create_from_data(width, height, false, Image.FORMAT_R8, water_data)),
		"region_grow": ImageTexture.create_from_image(Image.create_from_data(grow_width, grow_height, false, Image.FORMAT_R8, grow_data)),
		"region_pal": ImageTexture.create_from_image(palette),
		"region_flags": ImageTexture.create_from_image(flags),
		"region_eco": ImageTexture.create_from_image(clear),
		"region_set": ImageTexture.create_from_image(clear)
	}
