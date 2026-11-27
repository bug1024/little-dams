extends RefCounted

# Unified Hi-Bit painterly pixel-art stone & clay generator (Witchbrook 2B autumn palette):
# clean faceted violet-grey rocks and clustered warm-cinnamon clay with soft sel-out outlines.
const STONE_COLORS := [Color("#8d7b89"), Color("#817586"), Color("#948187"), Color("#787283")]
const EARTH_COLORS := [Color("#966544"), Color("#895a3c"), Color("#9f6f4c"), Color("#7f5337")]
const SUN := Vector3(0.56, -0.50, 0.66)
const SLICES := 20

class Rock:
	var texture: ImageTexture
	var rim := PackedVector2Array()

var rocks: Dictionary = {}
var earths: Dictionary = {}

func for_piece(radius: float, shade: int) -> Rock:
	var key := Vector2i(roundi(radius * 2), shade)
	if not rocks.has(key):
		rocks[key] = carve(key.x, shade)
	return rocks[key]

func for_earth(radius: float, shade: int) -> Rock:
	var key := Vector2i(roundi(radius * 2), shade)
	if not earths.has(key):
		earths[key] = carve_earth(key.x, shade)
	return earths[key]

func carve(radius_pixels: int, shade: int) -> Rock:
	var seed := shade * 8.73 + radius_pixels * 0.17
	var angle := sin(seed) * 0.40
	var aspect := 0.82 + sin(seed * 3.0) * 0.12
	var rise := 0.72 + cos(seed * 1.7) * 0.15
	var half_width := ceili(radius_pixels * 1.18) + 1
	var half_height := ceili(radius_pixels * 0.92) + 1
	var w := half_width * 2
	var h := half_height * 2
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var rock := Rock.new()
	for y in h:
		for x in w:
			var screen := Vector2(x - half_width + 0.5, y - half_height + 0.5) / radius_pixels
			for i in range(SLICES, -1, -1):
				var level := float(i) / SLICES
				var ground := Vector2(screen.x - (level - 0.5) * 0.10 * sin(seed), (screen.y - 0.36 + level * rise) / 0.50)
				# Subtle flat-faceted rock cap with chiseled bevels.
				var cap := 0.90 + ground.x * (0.09 + sin(seed) * 0.11) - ground.y * 0.11
				if level > cap:
					continue
				var across := ground.rotated(angle) / Vector2(1.0, aspect)
				var bearing := across.angle()
				# Quantized angular facets give chiseled storybook stones instead of round potatoes.
				var facet_a := roundf(bearing * 2.55) / 2.55
				var outline := 0.90 + sin(facet_a * 3.0 + seed) * 0.13 + cos(facet_a * 5.0 - seed) * 0.08
				outline *= (0.83 + 0.17 * smoothstep(0.0, 0.30, level)) * (1.0 - smoothstep(0.48, 1.0, level) * 0.20)
				if across.length_squared() > outline * outline:
					continue
				var surface := Vector3(ground.x, ground.y, level)
				var normal := Vector3(ground.x, ground.y / aspect, 0.22 + level * 0.52).normalized()
				var on_top := level + 1.2 / SLICES >= cap or i == SLICES
				if on_top:
					var bevel := smoothstep(0.68, 0.96, across.length() / outline)
					normal = Vector3(0.16, -0.24, 0.96).lerp(normal, bevel).normalized()
				image.set_pixel(x, y, weather(surface, normal, Vector2i(x, y), seed, shade, on_top))
				break
	apply_sel_out(image, Color("#2f2429"), Color("#4b3b44"))
	compute_rim(image, rock)
	rock.texture = ImageTexture.create_from_image(image)
	return rock

func weather(surface: Vector3, normal: Vector3, pixel: Vector2i, seed: float, shade: int, on_top: bool) -> Color:
	var sunlit := clampf(normal.dot(SUN), 0.0, 1.0)
	var base: Color = STONE_COLORS[shade % STONE_COLORS.size()]
	# Clean 4-band painterly cel-shading with true 2x2 checkerboard dither on band borders.
	var bayer := 0.20 if ((pixel.x + pixel.y) & 1) == 0 else -0.20
	var band := floorf(clampf(sunlit * 3.6 + bayer * 0.24, 0.0, 3.0)) / 3.0
	var shadow_col := base.lerp(Color("#473d4e"), 0.62)
	var mid_col := base
	var lit_col := base.lerp(Color("#d4c0bb"), 0.52)
	var tone := shadow_col.lerp(mid_col, smoothstep(0.0, 0.55, band))
	tone = tone.lerp(lit_col, smoothstep(0.45, 1.0, band))
	# Crisp horizontal cliff fracture seam on side faces.
	var surface_pos := Vector2(surface.x * 3.2 + seed, surface.y * 3.2 + surface.z * 2.2)
	var patch := patches(surface_pos)
	var seam := fposmod(surface.z * 2.6 + surface.x * 0.22 + patch * 0.25 + seed, 1.0)
	if not on_top and seam < 0.10:
		tone = tone.lerp(Color("#3a303f"), 0.45)
	elif on_top and sunlit > 0.66:
		tone = tone.lerp(Color("#e8d6cc"), 0.26)
	# Clustered autumn olive-gold moss tufts hugging the stone rim.
	var moss := patches(surface_pos * 1.15 + Vector2(6.4, 3.9))
	if shade != 1 and surface.z > 0.48 and moss > 0.72:
		var moss_col := Color("#8fa144") if sunlit > 0.48 else Color("#5b6b33")
		tone = moss_col
	if surface.z < 0.16:
		tone = tone.lerp(Color("#3a313e"), 0.36)
	return tone

func carve_earth(radius_pixels: int, shade: int) -> Rock:
	var seed := shade * 11.31 + radius_pixels * 0.23
	var angle := sin(seed) * 0.34
	var aspect := 0.78 + sin(seed * 2.4) * 0.10
	var rise := 0.54 + cos(seed * 1.9) * 0.10
	var half_width := ceili(radius_pixels * 1.18) + 1
	var half_height := ceili(radius_pixels * 0.84) + 1
	var w := half_width * 2
	var h := half_height * 2
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var mound := Rock.new()
	for y in h:
		for x in w:
			var screen := Vector2(x - half_width + 0.5, y - half_height + 0.5) / radius_pixels
			for i in range(SLICES, -1, -1):
				var level := float(i) / SLICES
				var ground := Vector2(screen.x - (level - 0.35) * 0.08 * sin(seed), (screen.y - 0.34 + level * rise) / 0.52)
				var across := ground.rotated(angle) / Vector2(1.0, aspect)
				var radial := across.length()
				var bearing := across.angle()
				var clod := patches(ground * 2.6 + Vector2(seed, seed * 0.7))
				var cap := 0.88 + (clod - 0.5) * 0.18 - radial * 0.28
				if level > cap:
					continue
				var outline := 0.86 + sin(bearing * 3.0 + seed) * 0.10 + cos(bearing * 5.0 - seed * 1.3) * 0.06 + (clod - 0.5) * 0.16
				var max_r := outline * (1.0 - smoothstep(0.16, 1.0, level) * 0.54)
				if radial > max_r:
					continue
				var normal := Vector3(ground.x * 0.76, (ground.y / aspect) * 0.76, 0.48 + (1.0 - minf(1.0, radial)) * 0.50).normalized()
				var surface := Vector3(ground.x, ground.y, level)
				image.set_pixel(x, y, weather_earth(surface, normal, Vector2i(x, y), seed, shade))
				break
	apply_sel_out(image, Color("#332118"), Color("#563928"))
	compute_rim(image, mound)
	mound.texture = ImageTexture.create_from_image(image)
	return mound

func weather_earth(surface: Vector3, normal: Vector3, pixel: Vector2i, seed: float, shade: int) -> Color:
	var sunlit := clampf(normal.dot(SUN), 0.0, 1.0)
	var base: Color = EARTH_COLORS[shade % EARTH_COLORS.size()]
	var bayer := 0.20 if ((pixel.x + pixel.y) & 1) == 0 else -0.20
	var band := floorf(clampf(sunlit * 3.2 + bayer * 0.24, 0.0, 3.0)) / 3.0
	var dark_clay := base.lerp(Color("#4c3021"), 0.62)
	var warm_clay := base.lerp(Color("#cc9a69"), 0.48)
	var tone := dark_clay.lerp(base, smoothstep(0.0, 0.52, band))
	tone = tone.lerp(warm_clay, smoothstep(0.48, 1.0, band))
	var clump := patches(Vector2(surface.x * 3.6 + seed, surface.y * 3.6 + surface.z * 2.0))
	if clump < 0.28:
		tone = tone.lerp(dark_clay, 0.42)
	elif clump > 0.74 and sunlit > 0.42:
		tone = tone.lerp(Color("#dbb07e"), 0.32)
	if surface.z < 0.16:
		tone = tone.lerp(Color("#432a1d"), 0.35)
	return tone

func apply_sel_out(image: Image, dark_edge: Color, lit_edge: Color) -> void:
	var w := image.get_width()
	var h := image.get_height()
	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in h:
		for x in w:
			mask[y * w + x] = 1 if image.get_pixel(x, y).a > 0.5 else 0
	for y in h:
		for x in w:
			if mask[y * w + x] != 0:
				continue
			var has_below := y + 1 < h and mask[(y + 1) * w + x] != 0
			var has_above := y - 1 >= 0 and mask[(y - 1) * w + x] != 0
			var has_left := x - 1 >= 0 and mask[y * w + (x - 1)] != 0
			var has_right := x + 1 < w and mask[y * w + (x + 1)] != 0
			if has_below or has_above or has_left or has_right:
				# Soft sel-out: slightly warmer/lighter contour along top-left lit rim, richer umber underneath.
				var top_rim := has_below and not has_above
				image.set_pixel(x, y, lit_edge if top_rim else dark_edge)

func compute_rim(image: Image, target: Rock) -> void:
	var w := image.get_width()
	var h := image.get_height()
	target.rim.clear()
	for y in h:
		var left := w
		var right := 0
		for x in w:
			if image.get_pixel(x, y).a > 0.5:
				left = mini(left, x)
				right = x + 1
		target.rim.append(Vector2(left, right))

func hashf(at: Vector2) -> float:
	return fposmod(sin(at.dot(Vector2(127.1, 311.7))) * 43758.5453, 1.0)

func patches(at: Vector2) -> float:
	var cell := at.floor()
	var f := at - cell
	f *= f * (Vector2(3, 3) - 2.0 * f)
	var a := lerpf(hashf(cell), hashf(cell + Vector2.RIGHT), f.x)
	var b := lerpf(hashf(cell + Vector2.DOWN), hashf(cell + Vector2.ONE), f.x)
	return lerpf(a, b, f.y)
