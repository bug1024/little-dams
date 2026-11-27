extends RefCounted

const Controls = preload("res://game/one_dam_controls.gd")

# Hand-crafted calligraphic pixel-art title emblem rendered on the exact 2x game pixel grid.
const UNIT := 2
const GLYPH_SIZE := 44
const GLYPH_GAP := 12
const PAD_LEFT := 18
const PAD_RIGHT := 26
const PAD_TOP := 7
const WAVE_BAND := 18

# Each glyph is authored as tapered calligraphic brush strokes (起笔顿笔 -> 提按行笔 -> 挑钩收笔):
# waypoints are Vector3(x, y, brush_radius) in 0..44 glyph space.
const CALLIGRAPHY := {
	"小": [
		# Center vertical spine: firm top-left brush press, poised waist, rich anchor and brisk upturned hook.
		[
			Vector3(20.2, 4.4, 2.10),
			Vector3(22.4, 5.8, 2.95),
			Vector3(22.2, 13.5, 2.55),
			Vector3(22.0, 26.5, 2.65),
			Vector3(21.6, 36.2, 2.85),
			Vector3(19.6, 38.0, 2.35),
			Vector3(14.6, 34.4, 1.05),
		],
		# Left sweeping teardrop dot: slender top, plump outer belly, tapered lower tip.
		[
			Vector3(12.8, 16.4, 1.25),
			Vector3(11.0, 21.8, 2.55),
			Vector3(8.5, 27.6, 2.30),
			Vector3(5.2, 31.8, 1.00),
		],
		# Right expressive brushstroke dot: light start swelling into a warm rounded teardrop foot.
		[
			Vector3(30.6, 17.0, 1.15),
			Vector3(33.8, 21.8, 2.15),
			Vector3(37.4, 27.4, 2.85),
			Vector3(38.8, 30.2, 2.15),
		],
	],
	"沟": [
		# Three-drop water radical (氵): rhythmic angled teardrops + crisp rising flick toward 勾.
		[
			Vector3(5.4, 6.2, 1.10),
			Vector3(8.4, 8.6, 2.20),
			Vector3(10.6, 10.6, 1.75),
		],
		[
			Vector3(3.0, 16.6, 1.10),
			Vector3(6.2, 19.0, 2.30),
			Vector3(8.6, 20.8, 1.70),
		],
		[
			Vector3(4.2, 36.8, 2.55),
			Vector3(7.4, 32.6, 2.05),
			Vector3(11.4, 26.0, 1.00),
		],
		# Right component (勾): sweeping upper-left pie with proud shoulder.
		[
			Vector3(21.4, 4.4, 2.45),
			Vector3(22.6, 6.0, 2.60),
			Vector3(19.8, 12.2, 2.25),
			Vector3(16.8, 17.8, 1.75),
			Vector3(14.2, 21.2, 1.00),
		],
		# Gently rising arched roof + pronounced corner press + graceful outer sweep & inward hook.
		[
			Vector3(19.8, 12.2, 1.90),
			Vector3(28.8, 10.6, 2.15),
			Vector3(36.8, 10.2, 2.85),
			Vector3(37.8, 12.2, 2.70),
			Vector3(37.8, 21.0, 2.55),
			Vector3(36.7, 30.8, 2.65),
			Vector3(34.5, 37.4, 2.80),
			Vector3(31.8, 38.4, 2.20),
			Vector3(27.2, 35.0, 1.00),
		],
		# Cozy inner 厶 with open breathing space inside the 勾 canopy.
		[
			Vector3(23.6, 17.6, 1.90),
			Vector3(20.4, 23.4, 1.80),
			Vector3(17.2, 28.4, 2.10),
		],
		[
			Vector3(17.6, 28.8, 1.90),
			Vector3(22.4, 27.6, 1.75),
			Vector3(26.6, 26.4, 1.40),
		],
		[
			Vector3(27.2, 21.8, 1.25),
			Vector3(29.4, 25.4, 2.00),
			Vector3(31.0, 28.6, 1.75),
		],
	],
}

# Miniature hand-carved vermilion picture-book seal (11x11 art px, stylized seal-script water "水").
const SEAL_CARVING := [
	"...........",
	".....#.....",
	"..#..#..#..",
	".#...#...#.",
	"..#..#..#..",
	"...#.#.#...",
	"..#..#..#..",
	".#...#...#.",
	"....##.....",
	".....#.....",
	"...........",
]

func make_title_texture(title: String) -> ImageTexture:
	var count := maxi(1, title.length())
	var content_w := count * GLYPH_SIZE + (count - 1) * GLYPH_GAP
	var w := PAD_LEFT + content_w + PAD_RIGHT
	var h := PAD_TOP + GLYPH_SIZE + WAVE_BAND
	var art := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)

	# 1. Subtle pixel-quantized warm shadow halo so the floating emblem reads effortlessly over bright sand.
	draw_soft_halo(art, Vector2(w * 0.49, PAD_TOP + GLYPH_SIZE * 0.56), Vector2(content_w * 0.64 + 14.0, GLYPH_SIZE * 0.64 + 9.0))

	# 2. Rasterize tapered calligraphic strokes onto the 1x game art pixel grid.
	var mask := PackedByteArray()
	mask.resize(w * h)
	mask.fill(0)
	var cursor_x := PAD_LEFT
	for i in count:
		var ch := title.substr(i, 1)
		if CALLIGRAPHY.has(ch):
			rasterize_glyph(mask, w, h, CALLIGRAPHY[ch], Vector2(cursor_x, PAD_TOP))
		elif Controls.GLYPHS.has(ch):
			rasterize_fallback_glyph(mask, w, h, Controls.GLYPHS[ch], Vector2i(cursor_x + 4, PAD_TOP + 4))
		cursor_x += GLYPH_SIZE + GLYPH_GAP

	# 3. Paint deep offset shadow, crisp warm-umber contour, and sunlit pixel-dithered carved ivory body.
	paint_lettering_shadow(art, mask, w, h)
	paint_lettering_outline(art, mask, w, h)
	paint_lettering_body(art, mask, w, h)

	# 4. Graceful double-ripple pixel creek flourish underneath both characters.
	var wave_y := PAD_TOP + GLYPH_SIZE + 5
	draw_creek_wave(art, PAD_LEFT - 2, PAD_LEFT + content_w + 4, wave_y)

	# 5. Miniature hand-stamped vermilion picture-book seal beside the lower-right foot of "沟".
	var seal_pos := Vector2i(PAD_LEFT + content_w + 4, PAD_TOP + GLYPH_SIZE - 14)
	draw_vermilion_seal(art, seal_pos)

	art.resize(w * UNIT, h * UNIT, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(art)

func rasterize_fallback_glyph(mask: PackedByteArray, w: int, h: int, rows: Array, origin: Vector2i) -> void:
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if row.substr(x, 1) != "#":
				continue
			for dy in 3:
				for dx in 3:
					var px := origin.x + x * 3 + dx
					var py := origin.y + y * 3 + dy
					if px >= 0 and px < w and py >= 0 and py < h:
						mask[py * w + px] = 1

func rasterize_glyph(mask: PackedByteArray, w: int, h: int, strokes: Array, origin: Vector2) -> void:
	for stroke: Array in strokes:
		var pts := stroke.size()
		if pts == 0:
			continue
		if pts == 1:
			stamp_disc(mask, w, h, origin + Vector2(stroke[0].x, stroke[0].y), stroke[0].z)
			continue
		for seg in pts - 1:
			var p0: Vector3 = stroke[maxi(0, seg - 1)]
			var p1: Vector3 = stroke[seg]
			var p2: Vector3 = stroke[seg + 1]
			var p3: Vector3 = stroke[mini(pts - 1, seg + 2)]
			var dist := Vector2(p1.x, p1.y).distance_to(Vector2(p2.x, p2.y))
			var steps := maxi(10, ceili(dist * 4.5))
			for s in steps + 1:
				var t := float(s) / float(steps)
				var pos := catmull_rom(Vector2(p0.x, p0.y), Vector2(p1.x, p1.y), Vector2(p2.x, p2.y), Vector2(p3.x, p3.y), t)
				var radius := lerpf(p1.z, p2.z, t)
				stamp_disc(mask, w, h, origin + pos, radius)

func catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		(2.0 * p1) +
		(-p0 + p2) * t +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)

func stamp_disc(mask: PackedByteArray, w: int, h: int, center: Vector2, radius: float) -> void:
	var r2 := radius * radius
	var x0 := maxi(0, floori(center.x - radius - 1.0))
	var x1 := mini(w - 1, ceili(center.x + radius + 1.0))
	var y0 := maxi(0, floori(center.y - radius - 1.0))
	var y1 := mini(h - 1, ceili(center.y + radius + 1.0))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := float(x) + 0.5 - center.x
			var dy := float(y) + 0.5 - center.y
			if dx * dx + dy * dy <= r2:
				mask[y * w + x] = 1

func mask_at(mask: PackedByteArray, w: int, h: int, x: int, y: int) -> bool:
	if x < 0 or x >= w or y < 0 or y >= h:
		return false
	return mask[y * w + x] != 0

func draw_soft_halo(img: Image, center: Vector2, radii: Vector2) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			var nx := (float(x) - center.x) / radii.x
			var ny := (float(y) - center.y) / radii.y
			var d := sqrt(nx * nx + ny * ny)
			if d < 1.0:
				var falloff := pow(1.0 - d, 1.85) * 0.22
				var quant := floorf(falloff * 18.0 + ((x + y) % 2) * 0.35) / 18.0
				if quant > 0.01:
					img.set_pixel(x, y, Color(0.10, 0.10, 0.07, quant))

func paint_lettering_shadow(img: Image, mask: PackedByteArray, w: int, h: int) -> void:
	for y in h:
		for x in w:
			if mask[y * w + x] == 0:
				continue
			blend_pixel(img, x + 2, y + 3, Color(0.08, 0.08, 0.05, 0.34))
			blend_pixel(img, x + 3, y + 3, Color(0.08, 0.08, 0.05, 0.22))
			blend_pixel(img, x + 1, y + 2, Color(0.09, 0.08, 0.06, 0.56))
			blend_pixel(img, x + 2, y + 2, Color(0.09, 0.08, 0.06, 0.48))

func paint_lettering_outline(img: Image, mask: PackedByteArray, w: int, h: int) -> void:
	var outer := Color("#271f16")
	var soft_corner := Color("#392d1f", 0.90)
	for y in h:
		for x in w:
			if mask[y * w + x] != 0:
				continue
			var cardinal := (
				mask_at(mask, w, h, x - 1, y) or mask_at(mask, w, h, x + 1, y) or
				mask_at(mask, w, h, x, y - 1) or mask_at(mask, w, h, x, y + 1)
			)
			if cardinal:
				img.set_pixel(x, y, outer)
				continue
			var diagonal := (
				mask_at(mask, w, h, x - 1, y - 1) or mask_at(mask, w, h, x + 1, y - 1) or
				mask_at(mask, w, h, x - 1, y + 1) or mask_at(mask, w, h, x + 1, y + 1)
			)
			if diagonal:
				blend_pixel(img, x, y, soft_corner)

func paint_lettering_body(img: Image, mask: PackedByteArray, w: int, h: int) -> void:
	# Authentic 4-step pixel-art sunlit parchment/ivory ramp with subtle checker dithering between bands.
	var hi_rim := Color("#fffef4")
	var ramp := [
		Color("#fcf2d4"),
		Color("#f3dba0"),
		Color("#e4be76"),
		Color("#cc9a54"),
	]
	var shade_bevel := Color("#9e6e36")
	for y in h:
		for x in w:
			if mask[y * w + x] == 0:
				continue
			var gy := clampf(float(y - PAD_TOP) / float(GLYPH_SIZE), 0.0, 1.0)
			# Classic 2x2 Bayer pixel-art dither between vertical sunlit bands.
			var bayer := float(((x & 1) * 2 + ((x ^ y) & 1))) * 0.25 - 0.375
			var band_f := clampf(gy * 3.15 + bayer * 0.38, 0.0, 3.0)
			var band_i := mini(3, int(roundf(band_f)))
			var tone: Color = ramp[band_i]
			# Subtle 1px carved top-left catchlight and bottom-right warm bronze bevel.
			var top_edge := not mask_at(mask, w, h, x, y - 1)
			var left_edge := not mask_at(mask, w, h, x - 1, y)
			var bottom_edge := not mask_at(mask, w, h, x, y + 1)
			var right_edge := not mask_at(mask, w, h, x + 1, y)
			if top_edge:
				tone = tone.lerp(hi_rim, 0.85)
			elif left_edge and not bottom_edge:
				tone = tone.lerp(hi_rim, 0.45)
			elif bottom_edge:
				tone = tone.lerp(shade_bevel, 0.72)
			elif right_edge:
				tone = tone.lerp(shade_bevel, 0.32)
			img.set_pixel(x, y, tone)

func draw_creek_wave(img: Image, x_start: int, x_end: int, base_y: int) -> void:
	var span := float(maxi(1, x_end - x_start))
	var ink_edge := Color("#20302c", 0.90)
	var teal_deep := Color("#467e79")
	var teal_mid := Color("#74b1a6")
	var foam_hi := Color("#e0f4e8")
	for x in range(x_start, x_end + 1):
		var u := float(x - x_start) / span
		var arch := sin(u * PI)
		var ripple := sin(u * TAU * 1.5 - 0.35) * 1.6 * smoothstep(0.0, 0.22, u) * smoothstep(1.0, 0.78, u)
		var wy := roundi(float(base_y) + ripple)
		var thick := 2 if arch > 0.30 else 1
		blend_pixel(img, x, wy + thick, ink_edge)
		if arch > 0.14:
			blend_pixel(img, x, wy - 1, Color("#202e2a", 0.45))
		var crest := foam_hi if sin(u * TAU * 1.5 + 0.35) > 0.08 else teal_mid
		img.set_pixel(x, wy, crest.lerp(teal_mid, 0.22) if arch > 0.20 else Color(teal_mid, 0.84))
		if thick > 1:
			img.set_pixel(x, wy + 1, teal_deep)
	# Delicate shorter secondary ripple echoing underneath the center of the wave.
	var sub_start := x_start + int(span * 0.28)
	var sub_end := x_start + int(span * 0.72)
	var sub_span := float(maxi(1, sub_end - sub_start))
	for x in range(sub_start, sub_end + 1):
		var u := float(x - sub_start) / sub_span
		var sy := base_y + 4 + roundi(sin(u * PI * 2.0 + 0.5) * 0.7)
		var a := sin(u * PI) * 0.82
		blend_pixel(img, x, sy + 1, Color("#20302c", a * 0.65))
		blend_pixel(img, x, sy, Color("#96cbc0", a))
	# Floating water-sparkle dots framing both ends of the wave.
	for speck: Vector2i in [
		Vector2i(x_start - 4, base_y),
		Vector2i(x_start - 7, base_y + 1),
		Vector2i(x_end + 4, base_y),
		Vector2i(x_end + 7, base_y + 1),
	]:
		blend_pixel(img, speck.x, speck.y + 1, Color("#20302c", 0.48))
		blend_pixel(img, speck.x, speck.y, Color("#d8f0e4", 0.88))

func draw_vermilion_seal(img: Image, origin: Vector2i) -> void:
	var size := SEAL_CARVING.size()
	var body := Color("#b84733")
	var hi := Color("#d8664b")
	var dark := Color("#832e22")
	var ink := Color("#faeccb")
	var outline := Color("#2a1c14", 0.92)
	# Build rounded-square mask so the outline wraps smoothly with zero stray corner dots.
	var seal_mask := PackedByteArray()
	seal_mask.resize(size * size)
	for y in size:
		for x in size:
			var corner := (x == 0 or x == size - 1) and (y == 0 or y == size - 1)
			seal_mask[y * size + x] = 0 if corner else 1
	# Drop shadow + crisp 1px dark perimeter.
	for y in range(-1, size + 1):
		for x in range(-1, size + 1):
			var inside := x >= 0 and x < size and y >= 0 and y < size and seal_mask[y * size + x] == 1
			if inside:
				blend_pixel(img, origin.x + x + 1, origin.y + y + 2, Color(0.08, 0.07, 0.05, 0.42))
				continue
			var touches := false
			for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var nx := x + d.x
				var ny := y + d.y
				if nx >= 0 and nx < size and ny >= 0 and ny < size and seal_mask[ny * size + nx] == 1:
					touches = true
					break
			if touches:
				blend_pixel(img, origin.x + x, origin.y + y, outline)
	# Stamp body & carved cream-white seal script.
	for y in size:
		for x in size:
			if seal_mask[y * size + x] == 0:
				continue
			var px := origin.x + x
			var py := origin.y + y
			if SEAL_CARVING[y].substr(x, 1) == "#":
				img.set_pixel(px, py, ink)
			else:
				var tone := body
				if y == 0 or x == 0:
					tone = hi
				elif y == size - 1 or x == size - 1:
					tone = dark
				if (x == 0 and y == 7) or (x == size - 1 and y == 3):
					tone = tone.darkened(0.18)
				img.set_pixel(px, py, tone)

func blend_pixel(img: Image, x: int, y: int, src: Color) -> void:
	if x < 0 or x >= img.get_width() or y < 0 or y >= img.get_height():
		return
	var dst := img.get_pixel(x, y)
	var out_a := src.a + dst.a * (1.0 - src.a)
	if out_a <= 0.0001:
		return
	var out_rgb := (Vector3(src.r, src.g, src.b) * src.a + Vector3(dst.r, dst.g, dst.b) * dst.a * (1.0 - src.a)) / out_a
	img.set_pixel(x, y, Color(out_rgb.x, out_rgb.y, out_rgb.z, out_a))
