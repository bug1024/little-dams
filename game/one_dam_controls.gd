extends RefCounted

# Each character is drawn on the same pixel grid as the scene and cursor.
const GLYPHS := {
	"放": [
		"....#...#...", "....#...#...", ".######.####", "...#...#..#.",
		"...#..##..#.", "...###.#..#.", "...#.#.#.#..", "...#.#..##..",
		"..#..#..#...", "..#..#.#.#..", ".#...##...#.", "....#.#....#",
	],
	"水": [
		".....#......", ".....#......", ".....#...#..", ".###.#..#...",
		"...#.#.#....", "...#.##.....", "..#..#.#....", "..#..#..#...",
		".#...#...#..", "#....#....#.", ".....#.....#", "...###......",
	],
	"重": [
		".......###..", "..#####.....", ".....#......", ".##########.",
		".....#......", "..########..", "..#..#...#..", "..########..",
		"..#..#...#..", "..########..", ".....#......", ".##########.",
	],
	"来": [
		".....#......", ".....#......", ".##########.", ".....#......",
		"...#.#.#....", "....###.....", "############", "....###.....",
		"...#.#.#....", "..#..#..#...", ".#...#...##.", ".....#......",
	],
}
const RIPPLE := ["....#....", "...###...", "..#####..", "..#####..", "...###...", ".........", ".##...##.", "...###..."]
const RETURN := ["..#......", ".##.###..", "###....#.", ".##.....#", "..#.....#", "........#", ".#.....#.", "..#####.."]
const UNIT := 2
const FONT_SIZE := 24
const BUTTON_HEIGHT := 44

var lettering := make_lettering()

func configure(button: Button, title: String, release_water: bool, action: Callable) -> void:
	button.text = title
	button.icon = make_icon(release_water)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", lettering)
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	button.add_theme_constant_override("h_separation", 8)
	var width := 106 if release_water else 100
	var wood := Color("#64583b") if release_water else Color("#594735")
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, make_plaque(width, wood, state))
		button.add_theme_color_override("font_color" if state == "normal" else "font_" + state + "_color",
			Color("#a6a390") if state == "disabled" else Color("#fae9bd"))
	button.add_theme_color_override("icon_disabled_color", Color("#a2a39f"))
	button.custom_minimum_size = Vector2(width, BUTTON_HEIGHT)
	button.pressed.connect(action)

func make_lettering() -> FontFile:
	var font := FontFile.new()
	font.fixed_size = FONT_SIZE
	var atlas := Image.create_empty(FONT_SIZE * GLYPHS.size(), FONT_SIZE, false, Image.FORMAT_RGBA8)
	var cache_size := Vector2i(FONT_SIZE, 0)
	font.set_cache_ascent(0, FONT_SIZE, 22.0)
	font.set_cache_descent(0, FONT_SIZE, 2.0)
	var x := 0
	for caption: String in GLYPHS:
		ink(atlas, GLYPHS[caption], Vector2i(x, 0), UNIT, Color.WHITE)
		var glyph := caption.unicode_at(0)
		font.set_glyph_advance(0, FONT_SIZE, glyph, Vector2(26, 0))
		font.set_glyph_offset(0, cache_size, glyph, Vector2(0, -22))
		font.set_glyph_size(0, cache_size, glyph, Vector2(FONT_SIZE, FONT_SIZE))
		font.set_glyph_uv_rect(0, cache_size, glyph, Rect2(x, 0, FONT_SIZE, FONT_SIZE))
		font.set_glyph_texture_idx(0, cache_size, glyph, 0)
		x += FONT_SIZE
	font.set_texture_image(0, cache_size, 0, atlas)
	return font

func make_icon(release_water: bool) -> ImageTexture:
	var bitmap := Image.create_empty(20, 18, false, Image.FORMAT_RGBA8)
	ink(bitmap, RIPPLE if release_water else RETURN, Vector2i.ZERO, UNIT,
		Color("#9ed6c1") if release_water else Color("#ddba83"))
	return ImageTexture.create_from_image(bitmap)

func ink(bitmap: Image, rows: Array, origin: Vector2i, pixel: int, color: Color) -> void:
	for y in rows.size():
		for x in rows[y].length():
			if rows[y][x] == "#":
				bitmap.fill_rect(Rect2i(origin + Vector2i(x, y) * pixel, Vector2i.ONE * pixel), color)

func make_plaque(width: int, wood: Color, state: String) -> StyleBoxTexture:
	var w := floori(float(width) / UNIT)
	var h := floori(float(BUTTON_HEIGHT) / UNIT)
	var face_y := 1 if state == "pressed" else 0
	var bitmap := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	if state == "hover":
		wood = wood.lightened(0.12)
	elif state == "disabled":
		wood = wood.lerp(Color("#414438"), 0.72)
	var edge := Color("#2b2b20")
	for y in range(face_y, h):
		var corner := 2 if y == face_y or y == h - 1 else (1 if y == 1 + face_y or y == h - 2 else 0)
		var color := wood if y < h - 3 else wood.darkened(0.32)
		bitmap.fill_rect(Rect2i(corner, y, w - 2 * corner, 1), edge)
		if y > face_y and y < h - 1:
			bitmap.fill_rect(Rect2i(corner + 1, y, w - 2 * corner - 2, 1), color)
	bitmap.fill_rect(Rect2i(3, face_y + 1, w - 6, 1), wood.lightened(0.25))
	for i in 8:
		var start := 3 + (i * 19) % (w - 14)
		var row := 3 + (i * 7) % 14 + face_y
		bitmap.fill_rect(Rect2i(start, row, 4 + (i * 3) % 7, 1), wood.lightened(0.055) if i % 2 == 0 else wood.darkened(0.12))
	for x in [3, w - 4]:
		bitmap.fill_rect(Rect2i(x, 3 + face_y, 1, 2), wood.lightened(0.32))
		bitmap.set_pixel(x, 5 + face_y, edge)
	bitmap.resize(width, BUTTON_HEIGHT, Image.INTERPOLATE_NEAREST)
	var plaque := StyleBoxTexture.new()
	plaque.texture = ImageTexture.create_from_image(bitmap)
	plaque.content_margin_left = 10
	plaque.content_margin_right = 10
	plaque.content_margin_top = face_y * UNIT
	plaque.content_margin_bottom = 2 - face_y * UNIT
	return plaque
