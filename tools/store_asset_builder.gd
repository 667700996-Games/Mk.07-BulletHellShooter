extends SceneTree

const OUTPUT_ROOT := "res://dist/store/steam"
const LANDSCAPE_SOURCE := "res://assets/store/psychic_vector_store_landscape_v1.png"
const PORTRAIT_SOURCE := "res://assets/store/psychic_vector_store_portrait_v1.png"
const TITLE_SOURCE := "res://assets/backgrounds/title_megacity.png"
const OFFICIAL_SPEC_URL := "https://partner.steamgames.com/doc/store/assets"
const OFFICIAL_RULES_URL := "https://partner.steamgames.com/doc/store/assets/rules"

var outputs: Array[Dictionary] = []
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_build")

func _build() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_ROOT))
	var landscape := _load_image(LANDSCAPE_SOURCE)
	var portrait := _load_image(PORTRAIT_SOURCE)
	var title := _load_image(TITLE_SOURCE)
	if landscape == null or portrait == null or title == null:
		_finish()
		return

	var logo := _create_logo(1280, 400)
	_save_png(logo, "logo/library_logo.png", "library_logo", true)
	_save_png(_capsule(landscape, Vector2i(920, 430), Vector2(0.52, 0.43), logo, Rect2i(28, 24, 350, 109), 0.78), "store/header_capsule.png", "store_header", true)
	_save_png(_capsule(landscape, Vector2i(462, 174), Vector2(0.40, 0.42), logo, Rect2i(20, 19, 422, 132), 0.52), "store/small_capsule.png", "store_small", true)
	_save_png(_capsule(landscape, Vector2i(1232, 706), Vector2(0.53, 0.51), logo, Rect2i(36, 25, 410, 128), 0.82), "store/main_capsule.png", "store_main", true)
	_save_png(_capsule(portrait, Vector2i(748, 896), Vector2(0.50, 0.52), logo, Rect2i(130, 285, 488, 153), 0.84), "store/vertical_capsule.png", "store_vertical", true)
	var page_background := _cover(title, Vector2i(1438, 810), Vector2(0.50, 0.38))
	page_background = _soften(page_background, Vector2i(220, 124))
	_multiply_rgb(page_background, 0.44)
	_save_png(page_background, "store/page_background.png", "store_page_background", false)

	_save_png(_capsule(portrait, Vector2i(600, 900), Vector2(0.50, 0.52), logo, Rect2i(96, 276, 408, 128), 0.84), "library/library_capsule.png", "library_capsule", true)
	_save_png(_capsule(landscape, Vector2i(920, 430), Vector2(0.52, 0.43), logo, Rect2i(28, 24, 350, 109), 0.78), "library/library_header.png", "library_header", true)
	var library_hero := _cover(landscape, Vector2i(3840, 1240), Vector2(0.51, 0.47))
	_save_png(library_hero, "library/library_hero.png", "library_hero", false)

	var icon := _create_icon(512)
	var shortcut := icon.duplicate()
	shortcut.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	_save_png(shortcut, "community/shortcut_icon.png", "shortcut_icon", true)
	var app_icon := icon.duplicate()
	app_icon.resize(184, 184, Image.INTERPOLATE_LANCZOS)
	_save_jpg(app_icon, "community/app_icon.jpg", "app_icon", true)

	var screenshot_sources := [
		["source_captures/01_neon_route.png", "screenshots/01_neon_route_english.png"],
		["source_captures/02_tempest_route.png", "screenshots/02_tempest_route_english.png"],
		["source_captures/03_forge_route.png", "screenshots/03_forge_route_english.png"],
		["source_captures/04_neon_boss.png", "screenshots/04_neon_boss_english.png"],
		["source_captures/05_tempest_boss.png", "screenshots/05_tempest_boss_english.png"],
		["source_captures/06_forge_boss.png", "screenshots/06_forge_boss_english.png"],
	]
	for pair in screenshot_sources:
		var source := _load_image(OUTPUT_ROOT.path_join(String(pair[0])))
		if source != null:
			_save_png(_frame_vertical_gameplay(source), String(pair[1]), "gameplay_screenshot", false, "en")

	_write_manifest()
	_finish()

func _load_image(path: String) -> Image:
	var image := Image.new()
	var error := image.load(ProjectSettings.globalize_path(path))
	if error != OK:
		failures.append("could not load %s: %s" % [path, error_string(error)])
		return null
	return image

func _capsule(source: Image, size: Vector2i, focus: Vector2, logo: Image, logo_rect: Rect2i, brightness: float) -> Image:
	var result := _cover(source, size, focus)
	result.convert(Image.FORMAT_RGBA8)
	_multiply_rgb(result, brightness)
	_apply_scrim(result, logo_rect.grow(20))
	var placed_logo := logo.duplicate()
	placed_logo.resize(logo_rect.size.x, logo_rect.size.y, Image.INTERPOLATE_LANCZOS)
	result.blend_rect(placed_logo, Rect2i(Vector2i.ZERO, placed_logo.get_size()), logo_rect.position)
	return result

func _cover(source: Image, size: Vector2i, focus: Vector2) -> Image:
	var result := source.duplicate()
	var scale := maxf(float(size.x) / float(result.get_width()), float(size.y) / float(result.get_height()))
	var scaled_size := Vector2i(ceili(result.get_width() * scale), ceili(result.get_height() * scale))
	result.resize(scaled_size.x, scaled_size.y, Image.INTERPOLATE_LANCZOS)
	var origin := Vector2i(
		clampi(roundi(focus.x * scaled_size.x - size.x * 0.5), 0, scaled_size.x - size.x),
		clampi(roundi(focus.y * scaled_size.y - size.y * 0.5), 0, scaled_size.y - size.y)
	)
	return result.get_region(Rect2i(origin, size))

func _soften(image: Image, low_size: Vector2i) -> Image:
	var result := image.duplicate()
	result.resize(low_size.x, low_size.y, Image.INTERPOLATE_BILINEAR)
	result.resize(image.get_width(), image.get_height(), Image.INTERPOLATE_BILINEAR)
	return result

func _frame_vertical_gameplay(source: Image) -> Image:
	var size := Vector2i(1920, 1080)
	var result := _cover(source, size, Vector2(0.50, 0.50))
	result = _soften(result, Vector2i(96, 54))
	_multiply_rgb(result, 0.38)
	var gameplay := source.duplicate()
	gameplay.resize(608, 1080, Image.INTERPOLATE_LANCZOS)
	var origin := Vector2i((size.x - gameplay.get_width()) / 2, 0)
	_fill_rect_alpha(result, Rect2i(origin - Vector2i(6, 0), gameplay.get_size() + Vector2i(12, 0)), Color(0.10, 0.90, 1.0, 0.24))
	result.blit_rect(gameplay, Rect2i(Vector2i.ZERO, gameplay.get_size()), origin)
	return result

func _create_logo(width: int, height: int) -> Image:
	var supersample := 2
	var image := Image.create(width * supersample, height * supersample, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var mark_center := Vector2(280, 400)
	_draw_ring(image, mark_center, 210.0, 17.0, Color(0.20, 0.92, 1.0, 0.34))
	_draw_ring(image, mark_center, 150.0, 12.0, Color(0.64, 0.31, 1.0, 0.50))
	_draw_segment(image, Vector2(145, 220), Vector2(280, 570), 58.0, Color(0.20, 0.90, 1.0, 0.38))
	_draw_segment(image, Vector2(415, 220), Vector2(280, 570), 58.0, Color(0.63, 0.30, 1.0, 0.38))
	_draw_segment(image, Vector2(145, 220), Vector2(280, 570), 32.0, Color("bffcff"))
	_draw_segment(image, Vector2(415, 220), Vector2(280, 570), 32.0, Color("d7b4ff"))
	_draw_disc(image, mark_center, 45.0, Color(0.15, 0.93, 1.0, 0.30))
	_draw_disc(image, mark_center, 23.0, Color.WHITE)
	_draw_word(image, "PSYCHIC", Rect2(560, 85, 1880, 285), Color("63f4ff"), Color("f2fdff"))
	_draw_word(image, "VECTOR", Rect2(560, 430, 1880, 285), Color("ad66ff"), Color("f4eaff"))
	image.resize(width, height, Image.INTERPOLATE_LANCZOS)
	return image

func _create_icon(size: int) -> Image:
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var nx := float(x) / float(size - 1)
			var ny := float(y) / float(size - 1)
			var glow := maxf(0.0, 1.0 - Vector2(nx - 0.5, ny - 0.48).length() * 1.7)
			image.set_pixel(x, y, Color(0.015 + glow * 0.04, 0.025 + glow * 0.05, 0.075 + glow * 0.11))
	var center := Vector2(size * 0.5, size * 0.49)
	_draw_ring(image, center, size * 0.34, size * 0.018, Color(0.22, 0.90, 1.0, 0.38))
	_draw_ring(image, center, size * 0.22, size * 0.012, Color(0.66, 0.32, 1.0, 0.62))
	_draw_segment(image, Vector2(size * 0.27, size * 0.25), Vector2(size * 0.50, size * 0.75), size * 0.078, Color("51efff"))
	_draw_segment(image, Vector2(size * 0.73, size * 0.25), Vector2(size * 0.50, size * 0.75), size * 0.078, Color("a95cff"))
	_draw_disc(image, center, size * 0.052, Color.WHITE)
	return image

func _draw_word(image: Image, text: String, bounds: Rect2, glow_color: Color, core_color: Color) -> void:
	var segment_map := _glyph_segments()
	var glyph_width := bounds.size.y * 0.62
	var spacing := bounds.size.y * 0.16
	var total_width := glyph_width * text.length() + spacing * maxi(0, text.length() - 1)
	var start_x := bounds.position.x + (bounds.size.x - total_width) * 0.5
	for glyph_index in text.length():
		var glyph := text.substr(glyph_index, 1)
		var segments: Array = segment_map.get(glyph, [])
		var origin := Vector2(start_x + glyph_index * (glyph_width + spacing), bounds.position.y)
		for segment in segments:
			var start := origin + Vector2(segment[0].x * glyph_width, segment[0].y * bounds.size.y)
			var end := origin + Vector2(segment[1].x * glyph_width, segment[1].y * bounds.size.y)
			_draw_segment(image, start, end, bounds.size.y * 0.115, Color(glow_color, 0.26))
			_draw_segment(image, start, end, bounds.size.y * 0.060, glow_color)
			_draw_segment(image, start, end, bounds.size.y * 0.020, core_color)

func _glyph_segments() -> Dictionary:
	var top := [Vector2(0.08, 0.0), Vector2(0.92, 0.0)]
	var middle := [Vector2(0.08, 0.5), Vector2(0.92, 0.5)]
	var bottom := [Vector2(0.08, 1.0), Vector2(0.92, 1.0)]
	var left_top := [Vector2(0.0, 0.08), Vector2(0.0, 0.48)]
	var left_bottom := [Vector2(0.0, 0.52), Vector2(0.0, 0.92)]
	var right_top := [Vector2(1.0, 0.08), Vector2(1.0, 0.48)]
	var right_bottom := [Vector2(1.0, 0.52), Vector2(1.0, 0.92)]
	var center_bottom := [Vector2(0.5, 0.5), Vector2(0.5, 1.0)]
	return {
		"P": [top, left_top, middle, right_top, left_bottom],
		"S": [top, left_top, middle, right_bottom, bottom],
		"Y": [[Vector2(0.0, 0.0), Vector2(0.5, 0.5)], [Vector2(1.0, 0.0), Vector2(0.5, 0.5)], center_bottom],
		"C": [top, left_top, left_bottom, bottom],
		"H": [left_top, left_bottom, right_top, right_bottom, middle],
		"I": [top, [Vector2(0.5, 0.0), Vector2(0.5, 1.0)], bottom],
		"V": [[Vector2(0.0, 0.0), Vector2(0.5, 1.0)], [Vector2(1.0, 0.0), Vector2(0.5, 1.0)]],
		"E": [top, left_top, left_bottom, middle, bottom],
		"T": [top, [Vector2(0.5, 0.0), Vector2(0.5, 1.0)]],
		"O": [top, left_top, left_bottom, right_top, right_bottom, bottom],
		"R": [top, left_top, left_bottom, middle, right_top, [Vector2(0.48, 0.5), Vector2(1.0, 1.0)]],
	}

func _draw_segment(image: Image, start: Vector2, end: Vector2, width: float, color: Color) -> void:
	var distance := start.distance_to(end)
	var steps := maxi(1, ceili(distance / maxf(1.0, width * 0.22)))
	for step in steps + 1:
		_draw_disc(image, start.lerp(end, float(step) / float(steps)), width * 0.5, color)

func _draw_ring(image: Image, center: Vector2, radius: float, width: float, color: Color) -> void:
	var steps := maxi(64, ceili(TAU * radius / maxf(1.0, width * 0.35)))
	var previous := center + Vector2(radius, 0)
	for step in steps + 1:
		var angle := TAU * float(step) / float(steps)
		var point := center + Vector2(cos(angle), sin(angle)) * radius
		_draw_segment(image, previous, point, width, color)
		previous = point

func _draw_disc(image: Image, center: Vector2, radius: float, color: Color) -> void:
	var min_x := maxi(0, floori(center.x - radius))
	var max_x := mini(image.get_width() - 1, ceili(center.x + radius))
	var min_y := maxi(0, floori(center.y - radius))
	var max_y := mini(image.get_height() - 1, ceili(center.y + radius))
	var radius_squared := radius * radius
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if Vector2(x + 0.5, y + 0.5).distance_squared_to(center) <= radius_squared:
				_blend_pixel(image, x, y, color)

func _blend_pixel(image: Image, x: int, y: int, source: Color) -> void:
	var destination := image.get_pixel(x, y)
	var alpha := source.a + destination.a * (1.0 - source.a)
	if alpha <= 0.0001:
		return
	var rgb := (Vector3(source.r, source.g, source.b) * source.a + Vector3(destination.r, destination.g, destination.b) * destination.a * (1.0 - source.a)) / alpha
	image.set_pixel(x, y, Color(rgb.x, rgb.y, rgb.z, alpha))

func _multiply_rgb(image: Image, factor: float) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			image.set_pixel(x, y, Color(color.r * factor, color.g * factor, color.b * factor, color.a))

func _apply_scrim(image: Image, rectangle: Rect2i) -> void:
	var clipped := rectangle.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			var edge_x := minf(float(x - clipped.position.x), float(clipped.end.x - x)) / maxf(1.0, clipped.size.x * 0.16)
			var edge_y := minf(float(y - clipped.position.y), float(clipped.end.y - y)) / maxf(1.0, clipped.size.y * 0.20)
			var strength := clampf(minf(edge_x, edge_y), 0.0, 1.0) * 0.64
			var color := image.get_pixel(x, y)
			image.set_pixel(x, y, Color(color.r * (1.0 - strength), color.g * (1.0 - strength), color.b * (1.0 - strength), color.a))

func _fill_rect_alpha(image: Image, rectangle: Rect2i, color: Color) -> void:
	var clipped := rectangle.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			_blend_pixel(image, x, y, color)

func _save_png(image: Image, relative_path: String, role: String, logo_present: bool, locale: String = "neutral") -> void:
	_save(image, relative_path, role, logo_present, locale, "png")

func _save_jpg(image: Image, relative_path: String, role: String, logo_present: bool) -> void:
	_save(image, relative_path, role, logo_present, "neutral", "jpg")

func _save(image: Image, relative_path: String, role: String, logo_present: bool, locale: String, format: String) -> void:
	var resource_path := OUTPUT_ROOT.path_join(relative_path)
	var absolute_path := ProjectSettings.globalize_path(resource_path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var error := image.save_png(absolute_path) if format == "png" else image.save_jpg(absolute_path, 0.94)
	if error != OK:
		failures.append("could not write %s: %s" % [relative_path, error_string(error)])
		return
	outputs.append({
		"path": relative_path,
		"role": role,
		"format": format,
		"width": image.get_width(),
		"height": image.get_height(),
		"logo_present": logo_present,
		"locale": locale,
		"size": FileAccess.get_file_as_bytes(absolute_path).size(),
		"sha256": FileAccess.get_sha256(absolute_path),
	})

func _write_manifest() -> void:
	outputs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.path) < String(b.path))
	var release_metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://release/release_metadata.json"))
	if not release_metadata is Dictionary:
		failures.append("release metadata is unavailable")
		return
	var candidate_id: String = "%s-%s-build.%d-%s" % [
		String(release_metadata.get("artifact_name", "")),
		String(release_metadata.get("version", "")),
		int(release_metadata.get("build_number", 0)),
		"unsigned" if bool(release_metadata.get("unsigned", false)) else "signed",
	]
	var sources: Array[Dictionary] = []
	for path in [LANDSCAPE_SOURCE, PORTRAIT_SOURCE, TITLE_SOURCE]:
		var absolute_path := ProjectSettings.globalize_path(path)
		sources.append({"path": path.trim_prefix("res://"), "sha256": FileAccess.get_sha256(absolute_path)})
	for output in outputs:
		if output.role == "gameplay_screenshot":
			var source_name := String(output.path).get_file().replace("_english", "")
			var source_path := OUTPUT_ROOT.path_join("source_captures").path_join(source_name)
			if FileAccess.file_exists(source_path):
				sources.append({"path": source_path.trim_prefix("res://"), "sha256": FileAccess.get_sha256(ProjectSettings.globalize_path(source_path))})
	var manifest := {
		"schema_version": 1,
		"platform": "Steam",
		"product": "PSYCHIC VECTOR",
		"candidate_id": candidate_id,
		"generation_profile": "steam-graphical-assets-v1",
		"generator": "tools/store_asset_builder.gd",
		"official_spec_url": OFFICIAL_SPEC_URL,
		"official_rules_url": OFFICIAL_RULES_URL,
		"source_art": sources,
		"outputs": outputs,
		"content_rules": {
			"capsules": "artwork and product logotype only",
			"library_hero": "artwork only; no text",
			"library_logo": "product logotype and logomark only; transparent background",
			"screenshots": "actual gameplay only; 16:9; English locale",
		},
	}
	var path := ProjectSettings.globalize_path(OUTPUT_ROOT.path_join("manifest.json"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		failures.append("could not write manifest.json")
		return
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	file.close()

func _finish() -> void:
	if failures.is_empty():
		print("STORE_ASSET_BUILD_OK outputs=%d screenshots=6 platform=Steam" % outputs.size())
		quit(0)
		return
	for failure in failures:
		push_error("STORE_ASSET_BUILD_ERROR %s" % failure)
	print("STORE_ASSET_BUILD_FAILED count=%d" % failures.size())
	quit(1)
