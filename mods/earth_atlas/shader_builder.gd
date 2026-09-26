extends RefCounted
## Patch only the visual map shaders; no replacement of game data or scripts.
## Exact anchors make incompatible updates fail closed instead of corrupting a shader.

var errors: PackedStringArray = []

func _replace(source: String, before: String, after: String) -> String:
	if source.count(before) != 1:
		errors.append("Shader anchor missing or ambiguous: " + before.left(90))
		return source
	return source.replace(before, after)

func build(sources: Dictionary) -> Dictionary:
	errors.clear()
	var common: String = str(sources.get("common", ""))
	var surface: String = str(sources.get("surface", ""))
	var political: String = str(sources.get("political", ""))
	if common.is_empty() or surface.is_empty() or political.is_empty():
		errors.append("Game map shader sources are unavailable; original map retained.")
		return {}
	common = "uniform float atlas_natural = 0.80;\nuniform float atlas_urban = 0.08;\n" + common
	common = _replace(common,
		"float k_tint = map_tint * (1.0 - (use_regions > 0.5 ? reg_dev * reg_owned : our_dev) * 0.85) * (1.0 - burn) * (1.0 - B * 0.9);",
		"float k_tint = atlas_natural * (1.0 - burn) * (1.0 - RAD * 0.55);\n\t\tfloat atlas_luma = dot(map_col, vec3(0.2126, 0.7152, 0.0722));\n\t\tmap_col = mix(vec3(atlas_luma), map_col, 0.82);")
	common = _replace(common, "col = mix(col, concrete, city_land);",
		"col = mix(col, concrete, city_land * atlas_urban);")
	common = _replace(common,
		"col = mix(col, vec3(0.66, 0.70, 0.74), ice * (1.0 - max(city, city_sea) * 0.92));",
		"col = mix(col, vec3(0.66, 0.70, 0.74), ice * (1.0 - max(city * atlas_urban, city_sea) * 0.92));")
	# Keep inhabited seas, climate, ice, discovery and lights fully functional.
	surface = _replace(surface, '#include "res://shaders/planet_surface.gdshaderinc"', common)
	# The alpha channel also carries city lights into the political pass.
	# Keep their visual strength consistent with the land development slider.
	surface = _replace(surface,
		"float lights = clamp(s.lit * (s.city_land + s.city_sea), 0.0, 1.0) * lights_on;",
		"float lights = clamp(s.lit * (s.city_land * atlas_urban + s.city_sea), 0.0, 1.0) * lights_on;")
	surface = _replace(surface, "uniform float view_zoom = 1.0;", """uniform float view_zoom = 1.0;
// Real NASA/GEBCO elevation: visual shading only, never simulation or coastlines.
uniform sampler2D atlas_elevation : filter_linear_mipmap, repeat_enable;
uniform float atlas_has_elevation = 0.0;
float atlas_hillshade(vec2 uv, vec2 screen_step) {
    vec2 step_uv = max(screen_step, vec2(1.0 / 10800.0, 1.0 / 5400.0));
    float west = textureLod(atlas_elevation, uv - vec2(step_uv.x, 0.0), 0.0).r;
    float east = textureLod(atlas_elevation, uv + vec2(step_uv.x, 0.0), 0.0).r;
    float north = textureLod(atlas_elevation, uv - vec2(0.0, step_uv.y), 0.0).r;
    float south = textureLod(atlas_elevation, uv + vec2(0.0, step_uv.y), 0.0).r;
    float lat_scale = max(cos((0.5 - uv.y) * PI), 0.18);
    vec2 slope = vec2((east - west) * 6400.0 / (2.0 * step_uv.x * 40075000.0 * lat_scale),
                      (south - north) * 6400.0 / (2.0 * step_uv.y * 20037500.0));
    vec3 normal_h = normalize(vec3(-slope * 9.0, 1.0));
    float light = dot(normal_h, normalize(vec3(-0.55, -0.65, 1.0)));
    return clamp(0.63 + 0.49 * light, 0.70, 1.10);
}""")
	surface = _replace(surface, "vec3 col = vec3(1.0) - exp(-s.col * 2.6);",
		"vec3 col = vec3(1.0) - exp(-s.col * 2.35);\n\t\tfloat atlas_lum = dot(col, vec3(0.2126, 0.7152, 0.0722));\n\t\tcol = mix(vec3(atlas_lum), col, 0.86);")
	surface = _replace(surface,
		"col *= clamp(1.0 + ((h0 - hx) + (h0 - hy)) * 9.0 * s.land, 0.72, 1.25);",
		"float atlas_shade = atlas_hillshade(uv, px);\n\t\tcol *= mix(clamp(1.0 + ((h0 - hx) + (h0 - hy)) * 4.0 * s.land, 0.88, 1.10), mix(1.0, atlas_shade, s.land), atlas_has_elevation);")
	political = _replace(political, "uniform float use_regions = 0.0;",
		"uniform float atlas_political = 0.25;\nuniform float use_regions = 0.0;")
	political = _replace(political, "vec4 region_at(vec2 uv, out vec4 flags, out float id_out) {", """// Bilinear categorical reconstruction: blend coverage, never integer region ids.
vec4 atlas_region(vec2 uv, ivec2 size_r) {
    vec2 pos = vec2(fract(uv.x), clamp(uv.y, 0.0, 0.99999)) * vec2(size_r) - 0.5;
    ivec2 cell = ivec2(floor(pos));
    vec2 f = fract(pos);
    vec4 a = texelFetch(region_map, ivec2((cell.x + size_r.x) % size_r.x, clamp(cell.y, 0, size_r.y - 1)), 0);
    vec4 b = texelFetch(region_map, ivec2((cell.x + 1 + size_r.x) % size_r.x, clamp(cell.y, 0, size_r.y - 1)), 0);
    vec4 c = texelFetch(region_map, ivec2((cell.x + size_r.x) % size_r.x, clamp(cell.y + 1, 0, size_r.y - 1)), 0);
    vec4 d = texelFetch(region_map, ivec2((cell.x + 1 + size_r.x) % size_r.x, clamp(cell.y + 1, 0, size_r.y - 1)), 0);
    vec4 weights = vec4((1.0-f.x)*(1.0-f.y), f.x*(1.0-f.y), (1.0-f.x)*f.y, f.x*f.y);
    float ab = 1.0-step(0.001, distance(a.rg,b.rg));
    float ac = 1.0-step(0.001, distance(a.rg,c.rg));
    float ad = 1.0-step(0.001, distance(a.rg,d.rg));
    float bc = 1.0-step(0.001, distance(b.rg,c.rg));
    float bd = 1.0-step(0.001, distance(b.rg,d.rg));
    float cd = 1.0-step(0.001, distance(c.rg,d.rg));
    vec4 score = vec4(dot(weights,vec4(1.0,ab,ac,ad)), dot(weights,vec4(ab,1.0,bc,bd)),
                      dot(weights,vec4(ac,bc,1.0,cd)), dot(weights,vec4(ad,bd,cd,1.0)));
    vec4 result = a;
    float best = score.x;
    if (score.y > best) { result=b; best=score.y; }
    if (score.z > best) { result=c; best=score.z; }
    if (score.w > best) { result=d; }
    return result;
}
vec4 region_at(vec2 uv, out vec4 flags, out float id_out) {""")
	political = _replace(political,
		"uv += (vec2(noise_b(tp * 0.17), noise_b(tp * 0.17 + vec2(17.3, 5.1))) - 0.5) * 1.1 / vec2(rs);",
		"// Atlas preserves the data boundary without artificial noisy displacement.")
	political = _replace(political, "vec4 rid = texelFetch(region_map, px, 0);", "vec4 rid = atlas_region(uv, rs);")
	political = _replace(political, "void fragment() {", """float atlas_river_at(ivec2 point, ivec2 size_w) {
    ivec2 safe = ivec2((point.x + size_w.x) % size_w.x, clamp(point.y, 0, size_w.y - 1));
    float value = texelFetch(region_water, safe, 0).r * 255.0;
    return step(0.5, value) * (1.0 - step(1.5, value));
}
float atlas_river(vec2 uv) {
    ivec2 size_w = textureSize(region_water, 0);
    vec2 point = uv * vec2(size_w) - 0.5;
    ivec2 cell = ivec2(floor(point));
    vec2 f = fract(point);
    float coverage = mix(mix(atlas_river_at(cell, size_w), atlas_river_at(cell + ivec2(1,0), size_w), f.x),
                         mix(atlas_river_at(cell + ivec2(0,1), size_w), atlas_river_at(cell + ivec2(1,1), size_w), f.x), f.y);
    float aa = max(fwidth(coverage), 0.07);
    return smoothstep(0.56 - aa, 0.56 + aa, coverage);
}
void fragment() {""")
	political = _replace(political,
		"float river = step(0.5, w) * (1.0 - step(1.5, w)) * rivers_visible;",
		"float river = atlas_river(uv) * rivers_visible;")
	political = _replace(political,
		"col = mix(col, vec3(0.16, 0.30, 0.44), river * mix(0.35, 0.7, smoothstep(2.0, 8.0, view_zoom)));",
		"col = mix(col, vec3(0.20, 0.34, 0.43), river * mix(0.28, 0.48, smoothstep(2.0, 8.0, view_zoom)));")
	political = _replace(political,
		"col = mix(col, pal.rgb, owned * mix(0.26, 0.18, fl.r) * show_borders);",
		"vec3 atlas_owner = mix(vec3(dot(pal.rgb, vec3(0.2126, 0.7152, 0.0722))), pal.rgb, 0.68);\n\t\t\tcol = mix(col, atlas_owner, owned * atlas_political * show_borders);")
	political = _replace(political,
		"float hatch = step(0.5, fract((sc.x + sc.y) / 14.0)) * claim * show_borders;",
		"float hatch_phase = fract((sc.x + sc.y) / 20.0);\n\t\t\tfloat hatch = (1.0 - smoothstep(0.055, 0.12, abs(hatch_phase - 0.5))) * claim * show_borders;")
	political = _replace(political, "col = mix(col, our_color, hatch * 0.22);",
		"col = mix(col, our_color, hatch * 0.15);")
	political = _replace(political, "col = mix(col, col * 0.45, edge * near * 0.7 * show_borders);",
		"col = mix(col, vec3(0.10, 0.14, 0.15), edge * near * 0.32 * show_borders);")
	political = _replace(political,
		"col = mix(col, (owned > 0.5 ? pal.rgb * 1.2 : col * 0.5), own_edge * 0.8 * show_borders);",
		"vec3 atlas_border = mix(vec3(0.14, 0.18, 0.20), atlas_owner, 0.42);\n\t\t\tcol = mix(col, atlas_border, own_edge * 0.92 * show_borders);")
	if not errors.is_empty():
		return {}
	var surface_shader := Shader.new()
	surface_shader.code = surface
	var political_shader := Shader.new()
	political_shader.code = political
	return {"surface": surface_shader, "political": political_shader}
