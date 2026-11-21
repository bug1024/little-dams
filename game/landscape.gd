extends Node2D

const Water = preload("res://game/water.gd")

const FIELD := Rect2(16, 102, 1248, 528)
const PIXEL_SCALE := 3.0
const TILE_PIXELS := 16
const ROCK_COLORS := [Color("#73767d"), Color("#8a8278"), Color("#656f75"), Color("#8d837a")]
const SURFACE_SAMPLES := 312

var water: Water
var clock := 0.0
var surface_material := ShaderMaterial.new()
var surface_image := Image.create_empty(SURFACE_SAMPLES, 1, false, Image.FORMAT_RGB8)
var surface_state := ImageTexture.create_from_image(surface_image)
var held: Water.Piece
var held_position := Vector2.ZERO
var valid_drop := false
var stacking := false
var hovered: Water.Piece
var highlight := Color("#f1dfaa")
var debris: Array[Dictionary] = []
var splashes: Array[Vector4] = []
var leaves: Array[Vector2] = []
var phase := 0.0

func _ready() -> void:
	var atlas: Texture2D = load("res://game/creek_pixel.png")
	var terrain := build_terrain(atlas)
	add_child(terrain)

	var surface := Sprite2D.new()
	surface.texture = atlas
	surface.scale = Vector2.ONE * PIXEL_SCALE
	surface.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	surface.position = FIELD.position
	surface.centered = false
	surface.z_index = -1
	surface_material.shader = preload("res://game/creek_surface.gdshader")
	surface_material.set_shader_parameter("channel_mask", load("res://game/creek_flow_mask.png"))
	surface_material.set_shader_parameter("flow_state", surface_state)
	surface.material = surface_material
	add_child(surface)

func build_terrain(texture: Texture2D) -> TileMapLayer:
	var terrain := TileMapLayer.new()
	terrain.name = "CreekTerrain"
	terrain.position = FIELD.position
	terrain.scale = Vector2.ONE * PIXEL_SCALE
	terrain.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	terrain.z_index = -2
	var tile_size := Vector2i(TILE_PIXELS, TILE_PIXELS)
	var tiles := TileSet.new()
	tiles.tile_size = tile_size
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = tile_size
	source.use_texture_padding = false
	var source_id := tiles.add_source(source)
	terrain.tile_set = tiles
	var tiles_wide := texture.get_width() / TILE_PIXELS
	var tiles_high := texture.get_height() / TILE_PIXELS
	for y in tiles_high:
		for x in tiles_wide:
			var cell := Vector2i(x, y)
			source.create_tile(cell)
			terrain.set_cell(cell, source_id, cell)
	return terrain

func reset() -> void:
	debris.clear()
	splashes.clear()
	leaves.clear()
	phase = 0.0

func center(x: float) -> float:
	return Water.center(x)

func bank_width(x: float) -> float:
	return Water.channel_half_width(x)

func parcel_at(x: float) -> Vector2:
	for site in range(Water.SITES - 1, -1, -1):
		if x >= water.dams[site].mouth:
			var right: float = water.dams[site + 1].mouth if site < Water.SITES - 1 else FIELD.end.x
			return water.reaches[site].sample(inverse_lerp(water.dams[site].mouth, right, x))
	return Vector2(Water.SUPPLY, 0.0)

func pool_at(x: float) -> float:
	for site in Water.SITES:
		if x < water.dams[site].mouth + 2.0:
			var pool := clampf((water.dams[site].mouth + 2.0 - x) / 221.0, 0.0, 1.0)
			return maxf(water.dams[site].head - 0.25, 0.0) * (1.0 - pool * pool)
	return 0.0

func water_width(x: float, flow: float, pool: float) -> float:
	return minf(bank_width(x) - 5.0, 31.0 + minf(9.0, flow * 0.44) + pool * 16.0)

func advance(delta: float) -> void:
	clock += delta
	phase += delta * 28.0
	for i in SURFACE_SAMPLES:
		var x := FIELD.position.x + (i + 0.5) * FIELD.size.x / SURFACE_SAMPLES
		var parcel := parcel_at(x)
		var depth := clampf(pool_at(x) * 0.87, 0.0, 1.0)
		var rush := clampf((parcel.x - 5.0) / 22.0, 0.0, 1.0)
		surface_image.set_pixel(i, 0, Color(depth, rush, parcel.y))
	surface_state.update(surface_image)
	surface_material.set_shader_parameter("creek_time", clock)
	for item in debris:
		item.age += delta
		item.x += item.speed * delta
		item.speed = move_toward(item.speed, 30.0, delta * 32.0)
	while not debris.is_empty() and debris[0].age > 1.45:
		debris.pop_front()
	for i in range(splashes.size() - 1, -1, -1):
		splashes[i].z += delta
		if splashes[i].z > 0.65:
			splashes.remove_at(i)
	for i in leaves.size():
		var p := leaves[i]
		var flow := parcel_at(p.x).x
		var speed := 16.0 + flow * 4.5
		for dam in water.dams:
			if absf(p.x - dam.mouth) > 35.0 or dam.pieces.is_empty():
				continue
			var current := Water.jet_lane(p.y)
			if dam.jets[current] < 0.4 and p.x < dam.mouth + 17.0:
				var fastest := current
				for lane in Water.LANES:
					var bias := absf(lane - current) * 0.022
					if dam.jets[lane] - bias > dam.jets[fastest]:
						fastest = lane
				speed = minf(speed, 3.5 + dam.jets[current] * 14.0)
				var target := lerpf(-Water.FLOW_HALF_WIDTH, Water.FLOW_HALF_WIDTH, float(fastest) / (Water.LANES - 1))
				p.y = move_toward(p.y, target, delta * 19.0)
		p.x += delta * speed
		leaves[i] = p
	for i in range(leaves.size() - 1, -1, -1):
		if leaves[i].x > FIELD.end.x - 9.0:
			leaves.remove_at(i)

func add_debris(piece: Water.Piece, force: float) -> void:
	var p := piece.position
	splash(p, clampf(force * 0.64, 0.6, 2.5))
	debris.append({
		"x": p.x, "lane": Water.flow_offset(p), "age": 0.0, "speed": 38.0 + force * 29.0,
		"material": piece.material, "seed": piece.shape_seed, "radius": piece.radius,
	})

func splash(point: Vector2, strength: float) -> void:
	splashes.append(Vector4(point.x, point.y, 0.0, strength))

func draw_splashes() -> void:
	for splash_data in splashes:
		var elapsed := splash_data.z
		var force := splash_data.w
		var origin := Vector2(splash_data.x, splash_data.y)
		for i in 12:
			var spread := (i * 0.74 + origin.x) * 3.27
			var speed := 5.0 + fposmod(i * 1.819, 1.0) * 28.0
			var delta := Vector2(cos(spread), sin(spread) * 0.56) * minf(elapsed, 0.45) * speed * force
			delta.x += elapsed * 37.0
			delta.y -= sin(minf(1.0, elapsed * 2.8) * PI) * (4.0 + i % 4 * 2.4) * force
			var opacity := (1.0 - smoothstep(0.1, 0.65, elapsed)) * 0.92
			var pixels := Vector2(4, 2) if i % 4 == 0 else Vector2(2, 2)
			draw_rect(Rect2(origin + delta, pixels), Color(0.79, 0.98, 0.92, opacity))

func _draw() -> void:
	if water == null:
		return
	draw_water()
	draw_pieces()
	for item in debris:
		var x: float = item.x
		if x > FIELD.end.x - 15:
			continue
		var p := Vector2(x, center(x) + Water.visual_offset(x, item.lane * 0.86) + sin(item.age * 9.0) * 8.0)
		var fade := clampf(1.4 - item.age, 0.0, 1.0)
		if item.material == Water.STONE:
			stone(self, p, item.radius * (0.62 + fade * 0.38), item.seed, false, item.age * 5.2)
		else:
			draw_circle(p, 10.0 + item.age * 11.0, Color(0.59, 0.43, 0.25, fade * 0.29), true)
		draw_arc(p, 8.0 + item.age * 8.0, 2.1, 4.5, 9, Color(0.93, 0.96, 0.83, fade * 0.74), PIXEL_SCALE)
	draw_overtopping()
	draw_splashes()
	for p in leaves:
		var q := Vector2(p.x, center(p.x) + Water.visual_offset(p.x, p.y) + 5 * sin(clock * 3.0 + p.x * 0.04))
		draw_colored_polygon(PackedVector2Array([q + Vector2(-7, 1), q + Vector2(-3, -4), q + Vector2(5, -3), q + Vector2(8, 1), q + Vector2(1, 4)]), Color("#b9b85a"))
		draw_line(q - Vector2(5, 0), q + Vector2(5, 0), Color("#75803c"), PIXEL_SCALE)
	if is_instance_valid(held):
		draw_piece(held, held_position, true)
		var ground := held_position + Vector2(0.0, held.half_height() + 4.0)
		var color := highlight if valid_drop else Color("#b96345")
		draw_line(ground - Vector2(held.radius * 0.7, 0), ground + Vector2(held.radius * 0.7, 0), color, 2.0)
		if stacking and valid_drop:
			draw_line(ground + Vector2(0, -3), ground + Vector2(0, 4), color, 2.0)

func draw_water() -> void:
	# A pixelated foam crest travels with the steep edge of the incoming surge.
	for i in range(2, 123):
		var x := FIELD.position.x + i * 10.0
		var ahead := parcel_at(x + 12.0).x
		var behind := parcel_at(x - 12.0).x
		var crest := clampf((behind - ahead - 2.0) / 17.0, 0.0, 0.9)
		if crest < 0.07 or ahead > behind * 0.76:
			continue
		var bow := PackedVector2Array()
		for j in 9:
			var lane := (j - 4.0) / 4.0
			bow.append(Vector2(x + 10.0 * (1.0 - lane * lane), center(x) + lane * bank_width(x) * 0.73))
		draw_polyline(bow, Color(0.73, 0.98, 0.93, crest * 0.7), 2.0 + crest)

	for i in 165:
		var fraction := fposmod(i * 0.61803398875, 1.0)
		var seed_x := 22.0 + fposmod(i * 119.23, 1210.0)
		var flow := parcel_at(seed_x).x
		var cycle := fposmod(phase * (0.74 + minf(flow, 25.0) * 0.10) + i * 19.11, 65.0)
		var x := 21.0 + fposmod(seed_x + cycle - 21.0, 1238.0)
		var surge := maxf(0.0, parcel_at(x).x - 7.0)
		var y := center(x) + (fraction - 0.5) * water_width(x, flow, pool_at(x)) * 1.9
		var length := minf(1258.0 - x, 4.0 + fposmod(i * 3.76, 17.0) + surge * 0.64)
		var opacity := sin(cycle / 65.0 * PI) * (0.31 + minf(0.55, surge * 0.037))
		draw_line(Vector2(x, y), Vector2(x + length, y + center(x + length) - center(x)), Color(0.68, 0.96, 0.95, opacity), 2.0 + surge * 0.037)

	for dam in water.dams:
		if dam.pieces.is_empty():
			continue
		for lane in range(1, Water.LANES - 1, 2):
			var jet := dam.jets[lane]
			if jet < 0.12:
				continue
			var offset := lerpf(-Water.FLOW_HALF_WIDTH, Water.FLOW_HALF_WIDTH, float(lane) / (Water.LANES - 1))
			for i in 4:
				var travel := fposmod(clock * (17.0 + jet * 42.0) + i * 10.0 + lane * 6.7, 46.0)
				var opening := dam.jet_mouths[lane]
				if opening < 0.0:
					opening = dam.mouth
				var x := opening + travel
				if x > FIELD.end.x - 10:
					continue
				var y := center(x) + Water.visual_offset(x, offset) + sin(i * 3.1 + clock * 5.0) * 2.4
				var alpha := (1.0 - travel / 46.0) * minf(0.94, 0.35 + jet * 0.32)
				draw_line(Vector2(x, y), Vector2(x + 4.0 + jet * 3.0, y + 0.6), Color(0.79, 1.0, 0.97, alpha), 2.0 + jet * 0.45)

func draw_overtopping() -> void:
	for dam in water.dams:
		for lane in Water.LANES:
			var strength := dam.overflow[lane]
			if strength < 0.09 or dam.jet_mouths[lane] < 0.0:
				continue
			var offset := lerpf(-Water.FLOW_HALF_WIDTH, Water.FLOW_HALF_WIDTH, float(lane) / (Water.LANES - 1))
			for dot in 3:
				var drift := fposmod(clock * (5.5 + strength * 17.0) + lane * 3.71 + dot * 5.0, 17.0)
				var x := dam.jet_mouths[lane] - 10.0 + drift
				var y := center(x) + Water.visual_offset(x, offset) - 3.0 + sin(dot * 1.8) * 2.0
				draw_rect(Rect2(x, y, 2.0 + strength * 3.0, 2.0), Color(0.78, 0.99, 0.93, minf(0.85, strength * 1.6)))

func draw_pieces() -> void:
	var pieces: Array[Water.Piece] = water.bank_stones.duplicate()
	for dam in water.dams:
		pieces.append_array(dam.pieces)
	pieces.sort_custom(func(a: Water.Piece, b: Water.Piece) -> bool:
		if a.tier() != b.tier():
			return a.tier() < b.tier()
		return a.position.y < b.position.y)
	for piece in pieces:
		if piece != held:
			draw_piece(piece, piece.top())

func draw_piece(piece: Water.Piece, position: Vector2, in_hand := false) -> void:
	var p := position
	if in_hand:
		draw_circle(p + Vector2(5, 10), piece.radius * 0.66, Color(0.15, 0.22, 0.16, 0.22), true)
		p.y -= 4.0
	else:
		p.x += sin(clock * 23.0 + piece.shape_seed) * smoothstep(0.51, 1.0, piece.wear) * 1.7
	var offset := absf(Water.lane_at(position))
	if not in_hand and not piece.loose and piece.support == null and offset < bank_width(position.x) - 4.0:
		var foot := p + Vector2(1.0, piece.half_height() * 0.41)
		var span := piece.radius
		var wake := PackedVector2Array([
			foot + Vector2(span - 1, span * 0.15), foot + Vector2(-span * 0.43, span * 0.35),
			foot + Vector2(-span * 0.9, 0), foot + Vector2(-span * 0.87, -span * 0.35),
		])
		draw_polyline(wake, Color(0.38, 0.85, 0.82, 0.36 + 0.12 * sin(clock * 5.0 + piece.shape_seed)), PIXEL_SCALE)
	if piece.material == Water.STONE:
		stone(self, p, piece.radius, piece.shape_seed, true, 0.0, piece.half_height() / piece.radius)
	else:
		soil(p, piece.radius, piece.shape_seed, piece.wear, piece.half_height() / piece.radius)
	if piece == hovered and not is_instance_valid(held):
		var left := p - Vector2(piece.radius * 0.65, -piece.half_height() - 3.0)
		draw_line(left, left + Vector2(piece.radius * 1.30, 0), highlight, PIXEL_SCALE)

func soil(p: Vector2, radius: float, seed: int, wear: float, aspect: float) -> void:
	var base := Color("#9b643b") if wear < 0.52 else Color("#b17a49")
	var points := outline(p, radius, aspect, seed, 0.0)
	draw_colored_polygon(points, Color("#4d4034"))
	var face := PackedVector2Array()
	for pt in points:
		face.append(p + (pt - p) * 0.83 - Vector2(0, PIXEL_SCALE))
	draw_colored_polygon(face, base)
	var light := p - Vector2(radius * 0.22, radius * aspect * 0.38)
	draw_rect(Rect2(light, Vector2(PIXEL_SCALE * 2, PIXEL_SCALE)), Color("#cc9255"))

func outline(p: Vector2, radius: float, aspect: float, seed: int, roll: float) -> PackedVector2Array:
	var shape := PackedVector2Array()
	var count := 6 + posmod(seed, 5)
	for i in count:
		var theta := TAU * (i + fposmod(i * 1.53 + seed * 0.31, 1.0) * 0.39) / count
		theta += sin(seed * 2.43) * 0.59
		var r := radius * (0.76 + fposmod(i * 0.77 + seed * 0.341, 1.0) * 0.36)
		var point := Vector2(cos(theta) * r, sin(theta) * r * aspect).rotated(roll)
		shape.append(p + point)
	return shape

func stone(canvas: Node2D, p: Vector2, radius: float, seed: int, shadow: bool, roll := 0.0, aspect := 0.64) -> void:
	var base: Color = ROCK_COLORS[posmod(seed, ROCK_COLORS.size())]
	var shape := outline(p, radius, aspect, seed, roll)
	if shadow:
		canvas.draw_set_transform(Vector2(PIXEL_SCALE, PIXEL_SCALE))
		canvas.draw_colored_polygon(shape, Color("#142f37a8"))
		canvas.draw_set_transform(Vector2.ZERO)
	canvas.draw_colored_polygon(shape, Color("#26343d"))
	var face := PackedVector2Array()
	for point in shape:
		face.append(p + (point - p) * Vector2(0.91, 0.80) - Vector2(0, radius * 0.09))
	canvas.draw_colored_polygon(face, base)
	var ridge := p + Vector2(-radius * 0.18, -radius * 0.17).rotated(roll)
	for i in face.size():
		var next := (i + 1) % face.size()
		var lighting := ((face[i] + face[next]) * 0.5 - p).normalized().dot(Vector2(-0.52, -0.85))
		if lighting > 0.37:
			canvas.draw_colored_polygon(PackedVector2Array([ridge, face[i], face[next]]), base.lerp(Color("#dfc39e"), 0.58))
		elif lighting < -0.33:
			canvas.draw_colored_polygon(PackedVector2Array([ridge, face[i], face[next]]), base.lerp(Color("#283846"), 0.55))
	if radius > Water.LIFT_LIMIT:
		var moss := p + Vector2(radius * -0.29, radius * -0.06)
		canvas.draw_rect(Rect2(moss, Vector2(PIXEL_SCALE * 3, PIXEL_SCALE)), Color("#647850"))
		canvas.draw_rect(Rect2(moss + Vector2(PIXEL_SCALE, -PIXEL_SCALE), Vector2(PIXEL_SCALE * 2, PIXEL_SCALE)), Color("#98aa59"))
