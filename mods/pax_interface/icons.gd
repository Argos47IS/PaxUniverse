extends RefCounted
## Original vector line icons, rendered at runtime without an import cache.

static func make(id: String) -> Texture2D:
	var paths: Dictionary = {
		"orders": '<path d="M5 5h14v14H5zM8 9h8M8 12h8M8 15h5"/>',
		"plans": '<path d="M3 5h2v2H3zM3 11h2v2H3zM3 17h2v2H3zM9 6h12M9 12h12M9 18h12"/>',
		"laws": '<path d="M12 3v17M5 20h14M4 7h16M6 7l-4 7h8zM18 7l-4 7h8z"/>',
		"objects": '<path d="M3 21V10l6 4V9l6 4V3h4v18zM7 18h1M12 18h1M17 18h1"/>',
		"mining": '<path d="M6 4l14 14M4 10l6-6M10 4c5-1 8 2 10 6M4 20L15 9"/>',
		"research": '<path d="M9 3h6M10 3v7L4 19q0 2 2 2h12q2 0 2-2l-6-9V3M7 15h10"/>',
		"settings": '<circle cx="12" cy="12" r="3"/><path d="M9 2h6l1 4 4 1 2 5-3 3-1 5-6 2-3-3-5-1-2-6 3-3 1-5z"/>',
		"atlas": '<circle cx="12" cy="12" r="9"/><ellipse cx="12" cy="12" rx="4" ry="9"/><path d="M3 12h18M5 7h14M5 17h14"/>',
		"pause": '<path d="M8 5v14M16 5v14"/>',
		"assistant": '<path d="M4 22V3M6 4h14v11H6z"/>',
		"relations": '<circle cx="8" cy="8" r="3"/><circle cx="17" cy="9" r="2"/><path d="M2 21v-3a6 6 0 0112 0v3M16 15a5 5 0 016 5"/>',
		"state": '<path d="M3 9l9-6 9 6zM4 21h16M5 11v7M12 11v7M19 11v7"/>',
		"person": '<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="2"/><path d="M5 17a4 4 0 018 0M15 9h3M15 13h3"/>',
		"organization": '<path d="M4 21V3h11v18M15 9h5v12M8 7h3M8 11h3M8 15h3M8 21v-3h3v3M18 13v1M18 17v1"/>',
		"business": '<rect x="3" y="7" width="18" height="14" rx="2"/><path d="M8 7V3h8v4M3 12l9 3 9-3M10 13h4v4h-4z"/>',
		"principles": '<path d="M4 4h6l2 2 2-2h6v16h-6l-2 2-2-2H4zM12 6v16M7 9h2M7 13h2M15 9h2M15 13h2"/>',
		"charter": '<path d="M6 2h9l4 4v16H6zM15 2v5h4M9 10h7M9 14h7M9 18h4"/>',
		"development": '<path d="M3 21h18M5 18v-5h3v5M11 18V9h3v9M17 18V4h3v14M3 9l6-4 5 1 5-4"/>',
		"resources": '<path d="M3 7l9-5 9 5v11l-9 5-9-5zM3 7l9 5 9-5M12 12v11M7 5l10 5v5"/>',
		"goals": '<circle cx="11" cy="13" r="8"/><circle cx="11" cy="13" r="4"/><path d="M11 13L21 3M16 3h5v5"/>',
		"history": '<path d="M7 3h14v15H9M7 3v15a3 3 0 11-6 0h14v1a3 3 0 006 0M11 7h6M11 11h6"/>',
		"market": '<path d="M3 20h18M5 20V10h14v10M3 10l2-7h14l2 7M3 10q3 4 6 0 3 4 6 0 3 4 6 0M9 20v-5h6v5"/>',
		"clock": '<circle cx="12" cy="12" r="9"/><path d="M12 5v7l5 3"/>',
		"observe": '<path d="M5 4h4l1 9H2zM15 4h4l3 9h-8zM10 11h4"/><circle cx="6" cy="16" r="4"/><circle cx="18" cy="16" r="4"/>',
		"layers": '<path d="M2 8l10-6 10 6-10 6zM2 12l10 6 10-6M2 16l10 6 10-6"/>',
		"mail": '<path d="M2 5h20v14H2zM2 5l10 8L22 5"/>',
		"diplomacy": '<path d="M2 8l5-4 5 3 5-3 5 4-7 11-3 2L2 8zM7 10l4-3 5 5M5 14l5 5M17 16l-4-4"/>',
		"generic": '<path d="M5 5h14v14H5zM9 9h6v6H9z"/>'
	}
	var svg: String = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="#e6edf5" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">' + str(paths.get(id, paths.generic)) + '</g></svg>'
	var image: Image = Image.new()
	if image.load_svg_from_string(svg, 2.0) != OK:
		return null
	return ImageTexture.create_from_image(image)
