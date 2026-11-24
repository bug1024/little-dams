extends RefCounted

enum Action { RELEASE, RESTART, RAIN, MUSIC }

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
	"下": [
		"............", "############", ".....#......", ".....#......",
		".....##.....", ".....#.#....", ".....#..#...", ".....#...#..",
		".....#......", ".....#......", ".....#......", ".....#......",
	],
	"雨": [
		".##########.", ".....#......", ".##########.", ".#...#....#.",
		".#.#.#.#..#.", ".#..##..#.#.", ".#...#....#.", ".#.#.#.#..#.",
		".#..##..#.#.", ".#...#....#.", ".#...#..###.", ".#..........",
	],
	"停": [
		"..#....#....", "..#.########", ".#..........", ".##..#####..",
		"#.#..#...#..", "..#..#####..", "..#.########", "..#.#......#",
		"..#..######.", "..#.....#...", "..#.....#...", "..#...###...",
	],
	"音": [
		".....##.....", ".##########.", "...#...#....", "....#.#.....",
		"############", "............", "..########..", "..#......#..",
		"..########..", "..#......#..", "..########..", "............",
	],
	"乐": [
		".......###..", "..#####.....", "..#..#......", "..#..#......",
		".##########.", ".....#......", ".....#......", "..#..#..#...",
		"..#..#...#..", ".#...#....#.", ".....#......", "...###......",
	],
	"开": [
		"............", ".##########.", "....#..#....", "....#..#....",
		"....#..#....", "############", "....#..#....", "....#..#....",
		"...#...#....", "...#...#....", "..#....#....", ".#.....#....",
	],
	"关": [
		"..#......#..", "...#....#...", ".##########.", ".....##.....",
		".....##.....", "############", ".....##.....", "....#..#....",
		"...#....#...", "..#......#..", ".#........#.", "#..........#",
	],
	"空": [
		".....##.....", ".##########.", ".#........#.", "...#....#...",
		"..#......#..", ".#........#.", "............", "..########..",
		".....#......", ".....#......", ".....#......", ".##########.",
	],
	"格": [
		"..#.........", "..#...#.....", "#####.#####.", "..#..#...#..",
		"..##..#.#...", ".###...#....", "#.#.#.#.#...", "..#.##...##.",
		"..#..#####..", "..#..#...#..", "..#..#...#..", "..#..#####..",
	],
	"R": [
		"............", "..#######...", "..#......#..", "..#......#..",
		"..#......#..", "..#######...", "..#...#.....", "..#....#....",
		"..#.....#...", "..#......#..", "..#......#..", "............",
	],
}
const RIPPLE := ["....#....", "...###...", "..#####..", "..#####..", "...###...", ".........", ".##...##.", "...###..."]
const RETURN := ["..#......", ".##.###..", "###....#.", ".##.....#", "..#.....#", "........#", ".#.....#.", "..#####.."]
const CLOUD := ["...###...", "..#...#..", ".#.....#.", "#########", ".........", ".#..#..#.", "#..#..#..", "........."]
const NOTE := [".....###.", ".....#..#", ".....#...", ".....#...", ".....#...", "..####...", ".#####...", "..###...."]
const NOTE_OFF := ["#....###.", ".#...#..#", "..#..#...", "...#.#...", "....##...", "..##.#...", ".####..#.", "..###..#."]
const UNIT := 2
const FONT_SIZE := 24
const CELL := FONT_SIZE + UNIT
const BUTTON_HEIGHT := 48
const BUTTON_WIDTHS := [118, 110, 118, 148]

var lettering := make_lettering()

func configure(button: Button, title: String, variant: Action, action: Callable, shortcut := "") -> void:
	button.text = title
	button.icon = make_icon(variant)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", lettering)
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	button.add_theme_constant_override("h_separation", 8)
	var width: int = BUTTON_WIDTHS[variant]
	var wood: Color = [Color("#735a36"), Color("#594735"), Color("#48574e"), Color("#605343")][variant]
	var highlight: Color = Color("#d1b26b") if variant == Action.RELEASE else Color.TRANSPARENT
	apply_plaque_theme(button, width, wood, highlight, variant == Action.RELEASE)
	button.add_theme_color_override("icon_disabled_color", Color("#989b91"))
	button.custom_minimum_size = Vector2(width, BUTTON_HEIGHT)
	button.pressed.connect(action)
	if not shortcut.is_empty():
		attach_shortcut_badge(button, width, shortcut)

func apply_plaque_theme(button: Button, width: int, wood: Color, highlight := Color.TRANSPARENT,
		primary := false, muted := false) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, make_plaque(width, wood, state, highlight, primary))
		var text_color := Color("#fae9bd")
		if state == "disabled":
			text_color = Color("#b5b29e")
		elif muted:
			text_color = Color("#cfc4a8")
		button.add_theme_color_override("font_color" if state == "normal" else "font_" + state + "_color", text_color)

func set_rain_active(button: Button, active: bool) -> void:
	var width: int = BUTTON_WIDTHS[Action.RAIN]
	if active:
		apply_plaque_theme(button, width, Color("#3d5958"), Color("#8ec5c0"))
		button.icon = make_icon(Action.RAIN, false, true)
	else:
		apply_plaque_theme(button, width, Color("#48574e"))
		button.icon = make_icon(Action.RAIN, false, false)

func set_music_enabled(button: Button, enabled: bool) -> void:
	var width: int = BUTTON_WIDTHS[Action.MUSIC]
	if enabled:
		apply_plaque_theme(button, width, Color("#605343"))
		button.icon = make_icon(Action.MUSIC, false, false)
	else:
		apply_plaque_theme(button, width, Color("#49453d"), Color.TRANSPARENT, false, true)
		button.icon = make_icon(Action.MUSIC, true, false)

func make_lettering() -> FontFile:
	var font := FontFile.new()
	font.fixed_size = FONT_SIZE
	var atlas := Image.create_empty(CELL * GLYPHS.size(), CELL, false, Image.FORMAT_RGBA8)
	var cache_size := Vector2i(FONT_SIZE, 0)
	font.set_cache_ascent(0, FONT_SIZE, 22.0)
	font.set_cache_descent(0, FONT_SIZE, 4.0)
	var x := 0
	for caption: String in GLYPHS:
		ink(atlas, GLYPHS[caption], Vector2i(x + UNIT, UNIT), UNIT, Color(0.10, 0.09, 0.06, 0.78))
		ink(atlas, GLYPHS[caption], Vector2i(x, 0), UNIT, Color.WHITE)
		var glyph := caption.unicode_at(0)
		font.set_glyph_advance(0, FONT_SIZE, glyph, Vector2(26, 0))
		font.set_glyph_offset(0, cache_size, glyph, Vector2(0, -22))
		font.set_glyph_size(0, cache_size, glyph, Vector2(CELL, CELL))
		font.set_glyph_uv_rect(0, cache_size, glyph, Rect2(x, 0, CELL, CELL))
		font.set_glyph_texture_idx(0, cache_size, glyph, 0)
		x += CELL
	font.set_texture_image(0, cache_size, 0, atlas)
	return font

func make_icon(variant: Action, muted := false, active := false) -> ImageTexture:
	var bitmap := Image.create_empty(20, 20, false, Image.FORMAT_RGBA8)
	var pattern: Array = [RIPPLE, RETURN, CLOUD, NOTE_OFF if muted else NOTE][variant]
	var tint: Color = [Color("#9ed6c1"), Color("#ddba83"),
		Color("#c4f0f5") if active else Color("#b7cfd4"),
		Color("#958e7c") if muted else Color("#e1c79b")][variant]
	ink(bitmap, pattern, Vector2i(0, UNIT), UNIT, tint)
	return ImageTexture.create_from_image(bitmap)

func ink(bitmap: Image, rows: Array, origin: Vector2i, pixel: int, color: Color) -> void:
	for y in rows.size():
		for x in rows[y].length():
			if rows[y][x] == "#":
				bitmap.fill_rect(Rect2i(origin + Vector2i(x, y) * pixel, Vector2i.ONE * pixel), color)

func make_plaque(width: int, wood: Color, state: String, highlight := Color.TRANSPARENT, primary := false) -> StyleBoxTexture:
	var w := floori(float(width) / UNIT)
	var h := floori(float(BUTTON_HEIGHT) / UNIT)
	var face_y := 1 if state == "pressed" else 0
	var bottom_y := h - 2 if state == "pressed" else h - 3
	var bitmap := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	if state == "hover":
		wood = wood.lightened(0.12)
	elif state == "disabled":
		wood = Color("#46493f") if primary else wood.lerp(Color("#414438"), 0.72)
	var edge := Color("#2b2b20")
	# Pixel drop shadow beneath the wooden plaque; shrinks when pressed down.
	if state == "pressed":
		bitmap.fill_rect(Rect2i(3, h - 1, w - 6, 1), Color(0.07, 0.08, 0.06, 0.42))
	else:
		bitmap.fill_rect(Rect2i(2, h - 2, w - 4, 1), Color(0.07, 0.08, 0.06, 0.50))
		bitmap.fill_rect(Rect2i(3, h - 1, w - 6, 1), Color(0.07, 0.08, 0.06, 0.28))
	for y in range(face_y, bottom_y + 1):
		var corner := 2 if y == face_y or y == bottom_y else (1 if y == 1 + face_y or y == bottom_y - 1 else 0)
		var color := wood if y < bottom_y - 1 else wood.darkened(0.32)
		bitmap.fill_rect(Rect2i(corner, y, w - 2 * corner, 1), edge)
		if y > face_y and y < bottom_y:
			bitmap.fill_rect(Rect2i(corner + 1, y, w - 2 * corner - 2, 1), color)
	var top_rim := wood.lightened(0.25)
	if highlight.a > 0.0 and state != "disabled":
		top_rim = highlight.lightened(0.10) if state == "hover" else highlight
	bitmap.fill_rect(Rect2i(3, face_y + 1, w - 6, 1), top_rim)
	for i in 8:
		var start := 4 + (i * 19) % (w - 14)
		var row := 3 + (i * 7) % 14 + face_y
		bitmap.fill_rect(Rect2i(start, row, 4 + (i * 3) % 7, 1), wood.lightened(0.055) if i % 2 == 0 else wood.darkened(0.12))
	for x in [3, w - 4]:
		bitmap.fill_rect(Rect2i(x, 3 + face_y, 1, 2), wood.lightened(0.32))
		bitmap.set_pixel(x, 5 + face_y, edge)
	bitmap.resize(width, BUTTON_HEIGHT, Image.INTERPOLATE_NEAREST)
	var plaque := StyleBoxTexture.new()
	plaque.texture = ImageTexture.create_from_image(bitmap)
	plaque.content_margin_left = 14
	plaque.content_margin_right = 14
	plaque.content_margin_top = 2 + face_y * UNIT
	plaque.content_margin_bottom = 6 - face_y * UNIT
	return plaque

func attach_shortcut_badge(button: Button, width: int, shortcut: String) -> void:
	var glyphs := shortcut.length()
	var text_w := glyphs * 12 + maxi(0, glyphs - 1) * 2
	var badge_w := text_w + 14
	var badge_h := 22
	var bitmap := Image.create_empty(badge_w, badge_h, false, Image.FORMAT_RGBA8)
	var edge := Color("#2b2b20")
	var fill := Color(0.24, 0.21, 0.16, 0.92)
	for y in badge_h - 1:
		var corner := 2 if y == 0 or y == badge_h - 2 else (1 if y == 1 or y == badge_h - 3 else 0)
		bitmap.fill_rect(Rect2i(corner, y, badge_w - 2 * corner, 1), edge)
		if y > 0 and y < badge_h - 2:
			bitmap.fill_rect(Rect2i(corner + 1, y, badge_w - 2 * corner - 2, 1), fill)
	bitmap.fill_rect(Rect2i(2, 1, badge_w - 4, 1), Color("#7a684a"))
	bitmap.fill_rect(Rect2i(2, badge_h - 1, badge_w - 4, 1), Color(0.07, 0.08, 0.06, 0.45))
	var cursor_x := 7
	for i in glyphs:
		var ch := shortcut.substr(i, 1)
		if GLYPHS.has(ch):
			ink(bitmap, GLYPHS[ch], Vector2i(cursor_x + 1, 5), 1, Color(0.08, 0.07, 0.05, 0.85))
			ink(bitmap, GLYPHS[ch], Vector2i(cursor_x, 4), 1, Color("#f7e5b6"))
		cursor_x += 14
	var badge := TextureRect.new()
	badge.texture = ImageTexture.create_from_image(bitmap)
	badge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.position = Vector2(floorf((width - badge_w) * 0.5), -badge_h - 4)
	badge.visible = false
	button.add_child(badge)
	button.mouse_entered.connect(func() -> void: badge.visible = true)
	button.mouse_exited.connect(func() -> void: badge.visible = false)
