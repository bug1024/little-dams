extends RefCounted

const STONE_COLORS := [Color("#81756b"), Color("#88745e"), Color("#6b7470"), Color("#88776b")]
const EARTH_COLORS := [Color("#7a5c43"), Color("#836347"), Color("#6f553e"), Color("#7d6048")]
const SUN := Vector3(0.58, -0.48, 0.66)
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
	var angle := sin(seed) * 0.42
	var aspect := 0.84 + sin(seed * 3.0) * 0.13
	var rise := 0.75 + cos(seed * 1.7) * 0.17
	var half_width := ceili(radius_pixels * 1.15)
	var half_height := ceili(radius_pixels * 0.91)
	var image := Image.create_empty(half_width * 2, half_height * 2, false, Image.FORMAT_RGBA8)
	var rock := Rock.new()
	for y in image.get_height():
		var left := image.get_width()
		var right := 0
		for x in image.get_width():
			var screen := Vector2(x - half_width + 0.5, y - half_height + 0.5) / radius_pixels
			for i in range(SLICES, -1, -1):
				var level := float(i) / SLICES
				# Look down onto the top and the near wall of the same solid.
				var ground := Vector2(screen.x - (level - 0.5) * 0.12 * sin(seed), (screen.y - 0.38 + level * rise) / 0.51)
				var cap := 0.92 + ground.x * (0.08 + sin(seed) * 0.13) - ground.y * 0.12
				cap += sin(ground.x * 4.6 + seed) * 0.035
				if level > cap:
					continue
				var across := ground.rotated(angle) / Vector2(1.0, aspect)
				var bearing := across.angle()
				var outline := 0.92 + sin(bearing * 3.0 + seed) * 0.13 + cos(bearing * 5.0 - seed) * 0.08
				outline += sin(bearing * 9.0 + seed * 1.43) * 0.031
				outline *= (0.81 + 0.19 * smoothstep(0.0, 0.32, level)) * (1.0 - smoothstep(0.44, 1.0, level) * 0.23)
				outline += sin(level * 39.0 + bearing * 2.0) * 0.018
				if across.length_squared() > outline * outline:
					continue
				var surface := Vector3(ground.x, ground.y, level)
				var normal := Vector3(ground.x, ground.y / aspect, 0.19 + level * 0.47).normalized()
				if level + 1.1 / SLICES >= cap or i == SLICES:
					var bevel := smoothstep(0.72, 0.97, across.length() / outline)
					normal = Vector3(0.15, -0.26, 0.95).lerp(normal, bevel).normalized()
				image.set_pixel(x, y, weather(surface, normal, Vector2i(x, y), seed, shade))
				left = mini(left, x)
				right = x + 1
				break
		rock.rim.append(Vector2(left, right))
	rock.texture = ImageTexture.create_from_image(image)
	return rock

func weather(surface: Vector3, normal: Vector3, pixel: Vector2i, seed: float, shade: int) -> Color:
	var sunlit := maxf(0.0, normal.dot(SUN))
	var base: Color = STONE_COLORS[shade]
	var tone := base.darkened(0.49).lerp(base.lerp(Color("#b49b77"), 0.48), sunlit)
	var grain := hashf(Vector2(pixel) + Vector2(seed * 2.1, seed))
	var surface_pos := Vector2(surface.x * 5.0 + seed, surface.y * 5.0 + surface.z * 3.1)
	var weathering := patches(surface_pos)
	var seam := fposmod(surface.z * 3.3 + surface.x * 0.29 + surface.y * 0.23 + weathering * 0.33 + seed, 1.0)
	if seam < 0.09 and normal.z < 0.83:
		tone = tone.darkened(0.22)
	elif seam < 0.21 and normal.z < 0.88:
		tone = tone.lerp(Color("#a89478"), 0.16 + sunlit * 0.15)
	tone = tone.lerp(Color("#9b846b"), smoothstep(0.54, 0.85, weathering) * (0.10 + sunlit * 0.30))
	var chips := patches(surface_pos * 1.9 + Vector2(3.8, 9.2))
	tone = tone.lerp(Color("#d5ad76"), smoothstep(0.63, 0.89, chips + weathering * 0.22) * smoothstep(0.46, 0.89, sunlit) * 0.32)
	var moss := patches(surface_pos * 1.42 + Vector2(9.3, 7.2))
	if shade != 1 and surface.z < 0.66 and moss + weathering * 0.22 + grain * 0.12 > 0.77:
		tone = tone.lerp(Color("#697044"), (0.27 + sunlit * 0.25) * smoothstep(0.77, 0.90, moss + weathering * 0.22 + grain * 0.12))
	if sunlit > 0.65 and surface.z > 0.72:
		tone = tone.lerp(Color("#f7e5c4"), smoothstep(0.65, 0.94, sunlit) * smoothstep(0.72, 0.90, surface.z) * 0.08)
	tone = tone.darkened(0.27 * (1.0 - smoothstep(0.03, 0.28, surface.z)))
	return tone.lightened((grain - 0.55) * 0.067)

func carve_earth(radius_pixels: int, shade: int) -> Rock:
	var seed := shade * 11.31 + radius_pixels * 0.23
	var angle := sin(seed) * 0.35
	var aspect := 0.80 + sin(seed * 2.4) * 0.11
	var rise := 0.56 + cos(seed * 1.9) * 0.10
	var half_width := ceili(radius_pixels * 1.18)
	var half_height := ceili(radius_pixels * 0.84)
	var image := Image.create_empty(half_width * 2, half_height * 2, false, Image.FORMAT_RGBA8)
	var mound := Rock.new()
	for y in image.get_height():
		var left := image.get_width()
		var right := 0
		for x in image.get_width():
			var screen := Vector2(x - half_width + 0.5, y - half_height + 0.5) / radius_pixels
			var crumb := hashf(Vector2(x, y) + Vector2(seed * 1.3, seed * 0.9))
			for i in range(SLICES, -1, -1):
				var level := float(i) / SLICES
				var ground := Vector2(screen.x - (level - 0.35) * 0.08 * sin(seed), (screen.y - 0.34 + level * rise) / 0.54)
				var across := ground.rotated(angle) / Vector2(1.0, aspect)
				var radial := across.length()
				var bearing := across.angle()
				var clod := patches(ground * 3.4 + Vector2(seed, seed * 0.7))
				var cap := 0.90 + (clod - 0.5) * 0.22 - radial * 0.30
				if level > cap:
					continue
				var outline := 0.88 + sin(bearing * 3.0 + seed) * 0.09 + cos(bearing * 5.0 - seed * 1.3) * 0.06 + (clod - 0.5) * 0.22
				var skirt := (1.0 - smoothstep(0.0, 0.28, level)) * (0.04 + (clod - 0.45) * 0.14)
				var max_r := outline * (1.0 - smoothstep(0.14, 1.0, level) * 0.58) + skirt
				if level == 0.0 and radial > max_r - 0.07 and crumb > 0.72:
					continue
				if radial > max_r:
					continue
				var dx := patches((ground + Vector2(0.09, 0.0)) * 3.8 + Vector2(seed, seed * 0.7)) - patches((ground - Vector2(0.09, 0.0)) * 3.8 + Vector2(seed, seed * 0.7))
				var dy := patches((ground + Vector2(0.0, 0.09)) * 3.8 + Vector2(seed, seed * 0.7)) - patches((ground - Vector2(0.0, 0.09)) * 3.8 + Vector2(seed, seed * 0.7))
				var normal := Vector3(ground.x * 0.80 - dx * 1.15, (ground.y / aspect) * 0.80 - dy * 1.15, 0.44 + (1.0 - minf(1.0, radial)) * 0.54).normalized()
				var surface := Vector3(ground.x, ground.y, level)
				image.set_pixel(x, y, weather_earth(surface, normal, Vector2i(x, y), seed, shade))
				left = mini(left, x)
				right = x + 1
				break
		mound.rim.append(Vector2(left, right))
	mound.texture = ImageTexture.create_from_image(image)
	return mound

func weather_earth(surface: Vector3, normal: Vector3, pixel: Vector2i, seed: float, shade: int) -> Color:
	var sunlit := clampf(normal.dot(SUN), 0.0, 1.0)
	var base: Color = EARTH_COLORS[shade % EARTH_COLORS.size()]
	var dither := 0.04 if ((pixel.x + pixel.y) % 2 == 0) else -0.04
	var lit_weight := clampf(sunlit + dither, 0.0, 1.0)
	var tone := base.lerp(Color("#3c2e24"), 0.56).lerp(base.lerp(Color("#b5926b"), 0.52), lit_weight)
	var grain := hashf(Vector2(pixel) + Vector2(seed * 3.1, seed * 1.7))
	var pos := Vector2(surface.x * 4.6 + seed, surface.y * 4.6 + surface.z * 2.5)
	var clod := patches(pos * 1.45)
	var seam := patches(pos * 2.9 + Vector2(5.2, 2.7))
	if seam < 0.34:
		tone = tone.darkened(0.24 * (1.0 - seam / 0.34))
	elif clod > 0.62:
		tone = tone.lerp(Color("#b8956d"), (clod - 0.62) * (0.28 + sunlit * 0.35))
	if grain > 0.87 and sunlit > 0.30:
		tone = tone.lerp(Color("#cbb08a"), 0.42)
	elif grain < 0.14:
		tone = tone.darkened(0.18)
	var fiber := patches(pos * 2.3 + Vector2(8.1, 4.4))
	if fiber > 0.74 and grain > 0.52 and grain < 0.74:
		tone = tone.lerp(Color("#7d824b"), 0.48)
	tone = tone.darkened(0.26 * (1.0 - smoothstep(0.02, 0.28, surface.z)))
	return tone.lightened((grain - 0.5) * 0.085)

func hashf(at: Vector2) -> float:
	return fposmod(sin(at.dot(Vector2(127.1, 311.7))) * 43758.5453, 1.0)

func patches(at: Vector2) -> float:
	var cell := at.floor()
	var f := at - cell
	f *= f * (Vector2(3, 3) - 2.0 * f)
	var a := lerpf(hashf(cell), hashf(cell + Vector2.RIGHT), f.x)
	var b := lerpf(hashf(cell + Vector2.DOWN), hashf(cell + Vector2.ONE), f.x)
	return lerpf(a, b, f.y)
