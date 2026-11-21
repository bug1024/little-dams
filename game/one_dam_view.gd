extends Node2D

const Flow = preload("res://game/one_dam_grid.gd")
const Breach = preload("res://game/one_dam_breach.gd")
const Summer = preload("res://game/one_dam_summer.gd")
const Pool = preload("res://game/one_dam_water.gd")
const RockArt = preload("res://game/one_dam_rock_art.gd")
const SAFE_BANK := Rect2(35, 15, 275, 162)
const SIZE := Vector2(320, 200)
const PAPER := Color("#f7dda2")
const FOAM := Color("#c2f8ef")
# Centers and half widths traced from the near-view shoreline at sixteen-pixel intervals.
const CHANNEL_Y := [89.2, 94.6, 100.3, 108.1, 111.5, 118.2, 117.9, 113.7, 117.0, 114.7, 112.4, 109.2, 105.0, 100.9, 96.8, 89.9, 84.3, 78.0, 72.1, 68.8, 66.0]
const CHANNEL_RADIUS := [19.8, 19.8, 22.4, 24.1, 22.1, 23.6, 24.9, 26.5, 30.6, 31.7, 32.8, 31.4, 26.0, 25.6, 27.7, 23.1, 24.4, 23.2, 20.8, 21.3, 22.2]

class Floater:
	var point: Vector2
	var shore: Vector2
	var twig: bool
	var afloat := false
	var ambient := false
	var age := 0.0
	var drift := Vector2.ZERO
	var caught := false
	var angle := 0.0

	func _init(at: Vector2, is_twig: bool, turn: float) -> void:
		point = at
		shore = at
		twig = is_twig
		angle = turn

var water: Flow
var model: Pool
var lower: Pool
var upper_breach: Breach
var lower_breach: Breach
var foam_strength := 1.0
var bank: Array[Pool.Piece] = []
var rolling: Array[Dictionary] = []
var riffle: Array[Pool.Piece] = []
var floaters: Array[Floater] = []
var held_floater: Floater
var hovered_floater: Floater
var shake_time := 0.0
var droplets: Array[Vector4] = []
var ripples: Array[Vector4] = []
var hovered: Pool.Piece
var held: Pool.Piece
var pointer := Vector2.ZERO
var clear_drop := false
var preview_lift := 0.0
var clock := 0.0
var streaks := PackedVector2Array()
var water_pixels := Image.create_empty(Flow.COLUMNS, Flow.ROWS, false, Image.FORMAT_RGBA8)
var flow_texture := ImageTexture.create_from_image(water_pixels)
var surface := ShaderMaterial.new()
var ground_light := ShaderMaterial.new()
var summer := Summer.new()
var rock_art := RockArt.new()
var shore_memory := PackedFloat32Array()
var bed_deposit := PackedFloat32Array()
var surface_travel := PackedVector2Array()
var shore_image := Image.create_empty(Flow.COLUMNS, Flow.ROWS, false, Image.FORMAT_RGBAF)
var shore_texture := ImageTexture.create_from_image(shore_image)
var leaf_due := 6.4

func _ready() -> void:
	shore_memory.resize(Flow.COUNT)
	bed_deposit.resize(Flow.COUNT)
	surface_travel.resize(Flow.COUNT)
	var background := Sprite2D.new()
	background.centered = false
	background.texture_filter = TEXTURE_FILTER_NEAREST
	background.scale = Vector2(0.5, 0.5)
	background.texture = preload("res://game/one_dam_plate.png")
	background.z_index = -1
	surface.shader = preload("res://game/one_dam_surface.gdshader")
	ground_light.shader = preload("res://game/one_dam_ground.gdshader")
	var channel_profile := Image.create_empty(160, 1, false, Image.FORMAT_RGF)
	for i in channel_profile.get_width():
		var x := (i + 0.5) * SIZE.x / channel_profile.get_width()
		channel_profile.set_pixel(i, 0, Color(shoreline(CHANNEL_Y, x) / SIZE.y, shoreline(CHANNEL_RADIUS, x) / SIZE.y, 0))
	var profile_texture := ImageTexture.create_from_image(channel_profile)
	for material in [surface, ground_light]:
		material.set_shader_parameter("channel_mask", preload("res://game/one_dam_channel.png"))
		material.set_shader_parameter("channel_profile", profile_texture)
		material.set_shader_parameter("flow_state", flow_texture)
		material.set_shader_parameter("shore_memory", shore_texture)
	var ground := background.duplicate() as Sprite2D
	ground.z_index = -2
	ground.material = ground_light
	add_child(ground)
	background.material = surface
	add_child(background)

func shoreline(samples: Array, x: float) -> float:
	var along := clampf(x / 16.0, 0.0, samples.size() - 1.0)
	var index := mini(floori(along), samples.size() - 2)
	return lerpf(samples[index], samples[index + 1], along - index)

func to_screen(point: Vector2) -> Vector2:
	return Vector2(point.x, shoreline(CHANNEL_Y, point.x) + point.y * shoreline(CHANNEL_RADIUS, point.x) / Pool.BANK)

func piece_screen(piece: Pool.Piece) -> Vector2:
	return to_screen(piece.point) - Vector2(0, piece.visible_lift)

func from_screen(point: Vector2) -> Vector2:
	var center := shoreline(CHANNEL_Y, point.x)
	var radius := shoreline(CHANNEL_RADIUS, point.x)
	return Vector2(point.x, (point.y - center) * Pool.BANK / radius)

func clear() -> void:
	bank.clear()
	rolling.clear()
	droplets.clear()
	ripples.clear()
	shore_memory.fill(0.0)
	bed_deposit.fill(0.0)
	surface_travel.fill(Vector2.ZERO)
	leaf_due = clock + 6.4
	riffle.clear()
	floaters.clear()
	for row in [[57, 60, false, 0.5], [63, -77, true, -0.22], [123, 71, false, -0.39],
			[221, 58, true, 0.18], [256, -79, false, 1.1], [281, 56, false, -0.7]]:
		floaters.append(Floater.new(Vector2(row[0], row[1]), row[2], row[3]))
	held_floater = null
	hovered_floater = null
	for row in [[266, -13, 5, 2], [273, -6, 8, 1], [265, 4, 4, 0]]:
		riffle.append(Pool.Piece.new(Vector2(row[0], row[1]), row[2], Pool.STONE, row[3]))
	shake_time = 0.0
	streaks.clear()
	for i in 150:
		streaks.append(streak_origin(i, 0.0))
	held = null
	hovered = null

func burst(point: Vector2, strength: float) -> void:
	var screen := to_screen(point)
	droplets.append(Vector4(screen.x, screen.y, 0.0, strength))
	if is_wet(point):
		ripples.append(Vector4(point.x, point.y, 0.0, strength))

func material_touch(point: Vector2, mud: bool) -> void:
	if not is_wet(point):
		return
	burst(point, 0.40 if mud else 0.62)
	if mud:
		water.cloud(point, 0.28)
	else:
		summer.disturb_water(point, 0.62, false)

func launch(piece: Pool.Piece, strength: float) -> void:
	rolling.append({"piece": piece, "origin": piece.point, "age": 0.0, "force": strength})
	var wet := water.depth_at(piece.point + Vector2(4.0, 0.0))
	if wet > 0.06:
		burst(piece.point, clampf(strength * wet, 0.15, 1.0))

func wave_impact(point: Vector2, strength: float) -> void:
	summer.disturb_water(point, strength, true)
	shake_time = 0.16
	burst(point + Vector2(7.0, 0.0), strength)

func shake_offset() -> Vector2:
	if shake_time <= 0.0:
		return Vector2.ZERO
	var amount := minf(1.2, shake_time * 8.0)
	return Vector2(cos(shake_time * 62.0) * amount, sin(shake_time * 41.0) * amount * 0.7).round()

func advance_riffle(dt: float) -> void:
	for i in range(riffle.size() - 1, -1, -1):
		var stone := riffle[i]
		if stone == held:
			continue
		var speed := water.velocity_at(stone.point).length()
		var hold := 26.0 + stone.radius * 2.1
		stone.wear = clampf(stone.wear + (speed - hold) * dt * 0.15, 0.0, 1.0)
		if stone.wear >= 1.0:
			riffle.remove_at(i)
			launch(stone, 1.1)
			wave_impact(stone.point, 0.9)

func is_wet(at: Vector2) -> bool:
	return absf(at.y) <= Pool.BANK and water.depth_at(at) > 0.046

func floater_at(cursor: Vector2) -> Floater:
	for item in floaters:
		var radius := 10.0 if item.twig else 7.0
		if cursor.distance_to(to_screen(item.point)) <= radius:
			return item
	return null

func blocked_at(basin: Pool, at: Vector2, clearance: float) -> bool:
	for piece in basin.wall:
		if piece.support == null and absf(at.x - piece.point.x) < piece.radius * 0.65 + clearance:
			if absf(at.y - piece.point.y) < piece.radius * 0.70 + clearance:
				return true
	return false

func clear_float_path(start: Vector2, end: Vector2, clearance: float) -> bool:
	for i in range(1, 4):
		var point := start.lerp(end, i / 3.0)
		if not is_wet(point) or blocked_at(model, point, clearance) or blocked_at(lower, point, clearance):
			return false
	return true

func drift_floater(item: Floater, step: float) -> void:
	var flow := water.velocity_at(item.point).limit_length(72.0)
	var response := (5.5 if item.twig else 8.0)
	item.drift = item.drift.lerp(flow, 1.0 - exp(-step * response))
	var clearance := 3.8 if item.twig else 1.45
	var delta := item.drift * step
	var target := item.point + delta
	var touching := not clear_float_path(item.point, target, clearance)
	if touching:
		target = item.point
		var side := signf(flow.y) if absf(flow.y) > 0.6 else signf(item.point.y)
		if side == 0.0:
			side = 1.0
		var slide := minf(18.0, (flow.length() * 0.60) + absf(flow.y))
		for direction in [side, -side]:
			var lane := item.point + Vector2(0.0, direction * slide * step)
			var outlet := lane + Vector2(maxf(0.7, absf(delta.x)), 0.0)
			if clear_float_path(item.point, lane, clearance) and (not item.twig or clear_float_path(lane, outlet, clearance)):
				target = lane
				break
		item.drift.x *= 0.45
	var moved := target - item.point
	item.caught = touching and moved.length_squared() < 0.01
	if flow.length_squared() > 0.4:
		var tug := sin(clock * 3.2 + item.shore.x) * (0.21 if touching else 0.045)
		var heading := flow.angle() if moved.length_squared() < 0.012 else moved.angle()
		item.angle = lerp_angle(item.angle, heading + tug, minf(1.0, step * 3.5))
	item.point = target

func advance_floaters(dt: float) -> void:
	if clock >= leaf_due:
		leaf_due = clock + randf_range(15.0, 25.0)
		if not floaters.any(func(item: Floater) -> bool: return item.ambient):
			for lane in [0.0, -9.0, 8.0]:
				var start := Vector2(-4.0, lane)
				if is_wet(start):
					var leaf := Floater.new(start, false, 0.2)
					leaf.afloat = true
					leaf.ambient = true
					floaters.append(leaf)
					break
	for i in range(floaters.size() - 1, -1, -1):
		var item := floaters[i]
		if item == held_floater or not item.afloat:
			continue
		item.age += dt
		drift_floater(item, minf(dt, 0.04))
		if item.ambient and (item.age > 39.0 or item.point.x > SIZE.x + 8.0):
			floaters.remove_at(i)
		elif item.point.x > SIZE.x + 8.0:
			item.point = item.shore
			item.afloat = false
			item.drift = Vector2.ZERO
			item.caught = false

func streak_origin(i: int, time: float) -> Vector2:
	return Vector2(fposmod(i * 37.316 + floorf(time * 7.0) * 23.23, SIZE.x), fposmod(i * 17.9 + time * 25, 62.0) - 31.0)

func advance_streaks(dt: float) -> void:
	for i in streaks.size():
		var mark := streaks[i]
		var next := mark + water.velocity_at(mark).limit_length(70.0) * dt
		streaks[i] = next if next.x >= 0.0 and next.x < SIZE.x and is_wet(next) else streak_origin(i, clock)

func sync_surface(dt: float) -> void:
	var dry_down := exp(-dt * 0.14)
	for y in Flow.ROWS:
		for x in Flow.COLUMNS:
			var i := water.index(x, y)
			var h := water.depth[i]
			shore_memory[i] = maxf(shore_memory[i] * dry_down, smoothstep(0.014, 0.100, h))
			var v := water.velocity_cell(x, y).limit_length(90.0) / 90.0
			var silt := water.silt_at(x, y)
			var wash := smoothstep(0.18, 0.50, v.length())
			var settle := silt * smoothstep(0.016, 0.065, h) * (1.0 - wash) * 0.72
			bed_deposit[i] = clampf(bed_deposit[i] + dt * (settle - bed_deposit[i] * (0.032 + wash * 1.25)), 0.0, 1.0)
			# Integrate each cell's travel so a changing current doesn't jump its highlights.
			surface_travel[i] += v * (31.0 * dt)
			var travel := surface_travel[i]
			shore_image.set_pixel(x, y, Color(shore_memory[i], travel.x, travel.y, bed_deposit[i]))
			water_pixels.set_pixel(x, y, Color(clampf(h / 1.5, 0, 1), 0.5 + v.x * 0.5, 0.5 + v.y * 0.5, silt))
	flow_texture.update(water_pixels)
	shore_texture.update(shore_image)

func advance(dt: float) -> void:
	clock += dt
	shake_time = maxf(0.0, shake_time - dt)
	advance_riffle(dt)
	advance_floaters(dt)
	advance_streaks(dt)
	summer.advance(dt, water)
	sync_surface(dt)
	surface.set_shader_parameter("creek_time", clock)
	ground_light.set_shader_parameter("afternoon_time", clock)

	for i in range(rolling.size() - 1, -1, -1):
		var item := rolling[i]
		item.age += dt
		if item.age >= 1.78:
			var piece: Pool.Piece = item.piece
			var shore := 51.0 if int(piece.shade) % 2 == 0 else -51.0
			var x := clampf(item.origin.x + 50 + piece.shade * 18, 60, 272)
			piece.point = Vector2(x, shore + cos(x) * 5.0)
			piece.wear = 0.0
			bank.append(piece)
			rolling.remove_at(i)
	for i in range(droplets.size() - 1, -1, -1):
		droplets[i].z += dt
		if droplets[i].z >= 0.7:
			droplets.remove_at(i)
	for i in range(ripples.size() - 1, -1, -1):
		ripples[i].z += dt
		if ripples[i].z > 1.85:
			ripples.remove_at(i)
	queue_redraw()

func _draw() -> void:
	if water == null:
		return
	summer.draw_fish(self, to_screen)
	draw_pond_edge(model, 146.0)
	draw_pond_edge(lower, 262.0)
	draw_current()
	draw_ripples()
	draw_shore_bubbles()
	summer.draw_land(self)
	draw_materials()
	draw_seams(model)
	draw_seams(lower)
	draw_breach_jet(upper_breach)
	draw_breach_jet(lower_breach)
	draw_froth()
	draw_floaters()
	summer.draw_insect(self)

func draw_pond_edge(basin: Pool, fallback: float) -> void:
	if basin.wall.is_empty():
		return
	var lip := basin.center(fallback) - 9.0
	var head := water.pool_head(lip + 9.0)
	var height := smoothstep(0.24, 1.0, head)
	if height < 0.02:
		return
	for side in [-1, 1]:
		var edge := PackedVector2Array()
		for x in range(maxi(0, roundi(lip) - 105), roundi(lip) + 1, 4):
			var local_depth := water.depth_at(Vector2(x, 0.0))
			var y := 0.0
			for lane in range(Flow.ROWS / 2, Flow.ROWS):
				var offset: float = absf(water.row_y(lane)) * side
				if water.depth_at(Vector2(x, offset)) > 0.145:
					y = offset
			if local_depth > 0.26:
				var lift := minf(9.0, (local_depth - 0.26) * 10.0)
				edge.append(snap_pixel(to_screen(Vector2(x, y)) - Vector2(0, lift)))
		if edge.size() > 1:
			draw_polyline(edge, Color(0.49, 0.82, 0.77, height * 0.36), 0.5)
	for piece in basin.wall:
		if piece.support != null:
			continue
		var at := piece.point - Vector2(piece.radius * 0.90, 0.0)
		var h := water.depth_at(at)
		if h <= 0.18:
			continue
		var p := to_screen(at) - Vector2(0, minf(7.0, (h - 0.18) * 7.0))
		var shimmer := 0.68 + sin(clock * 3.7 + piece.point.y * 0.36) * 0.23
		var curve := PackedVector2Array([snap_pixel(p + Vector2(1.0, -2.0)), snap_pixel(p),
			snap_pixel(p + Vector2(0.0, 1.0 + piece.radius * 0.16)), snap_pixel(p + Vector2(1.0, 2.5 + piece.radius * 0.16))])
		draw_polyline(curve, Color(0.60, 0.78, 0.74, height * shimmer * 0.52), 0.5)

func draw_current() -> void:
	for i in streaks.size():
		var at := streaks[i]
		if not is_wet(at):
			continue
		var v := water.velocity_at(at)
		var speed := v.length()
		if speed < 0.75:
			continue
		var from := snap_pixel(to_screen(at))
		var end := at + v.normalized() * minf(10.0, 1.0 + speed * 0.125)
		if not is_wet(end):
			continue
		var strength := smoothstep(7.0, 57.0, speed)
		draw_line(from, snap_pixel(to_screen(end)), Color(FOAM, clampf(0.13 + strength * 0.62 * foam_strength, 0.0, 1.0)), 0.5 if strength < 0.78 else 1.0)

func draw_ripples() -> void:
	for ripple in ripples:
		var center := Vector2(ripple.x, ripple.y)
		var elapsed := ripple.z
		center += water.velocity_at(center).limit_length(32.0) * (elapsed * 0.32)
		var radius := 1.8 + elapsed * (8.7 + ripple.w * 3.1)
		var ink := Color(FOAM, (1.0 - smoothstep(0.13, 1.85, elapsed)) * minf(0.75, ripple.w * 0.91))
		for i in 18:
			var angle := i * TAU / 18.0
			var sample := center + Vector2.from_angle(angle) * radius
			var follow := center + Vector2.from_angle(angle + TAU / 18.0) * radius
			if is_wet(sample) and is_wet(follow) and not blocked_at(model, sample, 0.2) and not blocked_at(lower, sample, 0.2):
				draw_line(snap_pixel(to_screen(sample)), snap_pixel(to_screen(follow)), ink, 0.5)

func draw_shore_bubbles() -> void:
	var rocks: Array[Pool.Piece] = riffle.duplicate()
	rocks.append_array(model.wall)
	rocks.append_array(lower.wall)
	for stone in rocks:
		if stone.support != null or stone.kind != Pool.STONE:
			continue
		var v := water.velocity_at(stone.point + Vector2(stone.radius * 0.64, 0.0))
		if not is_wet(stone.point) or v.x < 3.0:
			continue
		var side := v.normalized().orthogonal()
		for i in 3:
			var phase := fposmod(clock * (0.56 + v.x * 0.013) + i * 0.29 + stone.shade * 0.11, 1.0)
			var turn := phase * TAU
			var along := stone.radius * 0.58 + phase * 6.0 + sin(turn) * 1.6
			var at := stone.point + v.normalized() * along
			at += side * (stone.radius * 0.63 + cos(turn) * 1.8) * (-1.0 if i % 2 == 0 else 1.0)
			if is_wet(at):
				var p := snap_pixel(to_screen(at))
				draw_rect(Rect2(p, Vector2(1.0, 0.5)), Color(0.68, 0.87, 0.79, sin(phase * PI) * 0.35))

func draw_seams(basin: Pool) -> void:
	if basin.wall.is_empty():
		return
	var center := basin.center(146.0)
	var chosen: Array[int] = []
	for slot in 3:
		var best := 8.0
		var jet := Vector2.ZERO
		var selected := -1
		for lane in Flow.ROWS:
			if chosen.has(lane) or chosen.has(lane - 1) or chosen.has(lane + 1):
				continue
			var at := Vector2(center + 9.0, water.row_y(lane))
			var speed := water.velocity_at(at).x
			if is_wet(at) and speed > best:
				best = speed
				jet = at
				selected = lane
		if selected < 0:
			break
		chosen.append(selected)
		var force := smoothstep(8.0, 50.0, best)
		for fleck in 6:
			var v := water.velocity_at(jet).normalized()
			var offset := fposmod(clock * (12.0 + best) + fleck * 3.7, 7.0 + force * 15.0)
			var at := jet + v * offset + Vector2(0, sin(fleck * 2.0 + clock * 11.0) * 1.9 * force)
			if is_wet(at):
				draw_rect(Rect2(snap_pixel(to_screen(at)), Vector2(1.0 + force * 3.0, 0.5)), Color(FOAM, 0.26 + force * 0.68))

func draw_breach_jet(event: Breach) -> void:
	if event == null or event.phase not in [Breach.Phase.JET, Breach.Phase.SURGE] or event.strength < 0.035:
		return
	var wide := event.phase == Breach.Phase.SURGE
	var rows := 9 if wide else 3
	var fullness := clampf(event.strength * foam_strength, 0, 1)
	var axis := event.direction
	var side := axis.orthogonal()
	for i in rows:
		var cross := (i - (rows - 1) * 0.5) * (1.1 + fullness)
		var progress := fposmod(clock * (28.0 + 48.0 * fullness) + i * 4.17, 8.0 + 22.0 * fullness)
		var at := event.origin + axis * (4.0 + progress) + side * cross
		if not is_wet(at):
			continue
		var local := water.velocity_at(at)
		if local.length() < 4.0:
			continue
		var back := at - local.normalized() * (1.4 + fullness * (4.0 if wide else 2.5))
		draw_line(snap_pixel(to_screen(back)), snap_pixel(to_screen(at)), Color(FOAM, fullness * (0.49 + i % 3 * 0.25)), 1.0 if wide else 0.5)
		if wide and i % 2 == 0:
			var spray := snap_pixel(to_screen(at) + Vector2(0.5, -2.0 - fposmod(i * 2.4 + clock * 16.0, 3.5)))
			draw_rect(Rect2(spray, Vector2(1, 0.5)), Color(FOAM, fullness * 0.64))

func draw_materials() -> void:
	var pieces := bank.duplicate()
	pieces.append_array(model.wall)
	pieces.append_array(lower.wall)
	pieces.append_array(riffle)
	pieces.sort_custom(func(a: Pool.Piece, b: Pool.Piece) -> bool:
		if not is_equal_approx(a.visible_lift, b.visible_lift):
			return a.visible_lift < b.visible_lift
		return to_screen(a.point).y < to_screen(b.point).y)
	for piece in pieces:
		if piece == held:
			continue
		var p := piece_screen(piece)
		# Show the uneven shoulder of each piece without moving its physical contact.
		if absf(piece.point.y) <= Pool.BANK:
			p.x += sin(piece.point.y * 0.69 + piece.shade * 1.51) * 2.0
		if riffle.has(piece) and piece.wear > 0.06:
			p.x += roundf(sin(clock * 33.0 + piece.shade) * piece.wear * 2.4)
		if (model.wall.has(piece) or lower.wall.has(piece)) and piece.wear > 0.32:
			p.x += roundf(sin(clock * (20.0 + piece.shade * 5.0)) * piece.wear * 1.8)
			if piece.kind == Pool.EARTH:
				var progress := fposmod(clock * 0.68 + piece.point.y * 3.7, 1.0)
				for j in 3:
					var grain := p + Vector2(2.0 + progress * 17.0 + j * 2.0, sin(progress * PI + j * 1.1) * 4.0)
					draw_rect(Rect2(grain.floor(), Vector2(2, 1)), Color(0.77, 0.57, 0.35, (1.0 - progress) * 0.89))
		var damp := dampness(piece)
		var submersion := 0.0
		if absf(piece.point.y) <= Pool.BANK:
			var water_height: float = water.depth_at(piece.point) * 12.0 - piece.visible_lift
			submersion = clampf(water_height / (piece.radius * 0.80), 0.0, 0.88)
		draw_piece(piece, p, 0.0, damp, submersion, piece.support == null)
		if piece == hovered:
			draw_brackets(p, piece.radius)
	for item in rolling:
		var piece: Pool.Piece = item.piece
		var from: Vector2 = item.origin
		var age: float = item.age
		var force: float = item.force
		var x := from.x + (13.0 + force * 30.0) * age + minf(22.0, age * 32.0)
		var y := from.y + sin(age * 5.6 + piece.shade) * minf(14.0, age * 15.0)
		var p := to_screen(Vector2(x, y)) - Vector2(0, absf(sin(age * 11.5)) * maxf(0.0, 7.6 - age * 4.0))
		draw_piece(piece, p, age * (4.0 if piece.kind == Pool.STONE else 1.0), 0.8)
	if held != null:
		draw_piece(held, (pointer - Vector2(0, maxf(5.0, preview_lift))).round(), 0.0)
		var center := snap_pixel((pointer + Vector2(0, 5)).clamp(Vector2(8, 2), SIZE - Vector2(8, 3)))
		var bar := Rect2(center - Vector2(5.5, 1), Vector2(11, 2)) if clear_drop else Rect2(center - Vector2(6.5, 1.5), Vector2(13, 3))
		var outline := Color("#173324") if clear_drop else Color("#4c151d")
		var fill := Color("#8ae27b") if clear_drop else Color("#ff595f")
		draw_rect(bar.grow(0.5), outline)
		draw_rect(bar, fill)
		draw_rect(Rect2(bar.position + Vector2(0.5, 0), Vector2(bar.size.x - 1, 0.5)),
			Color("#ceffad") if clear_drop else Color("#ffc2ab"))

func draw_brackets(p: Vector2, radius: float) -> void:
	var color := Color(PAPER, 0.57)
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var tip: Vector2 = (p + corner * Vector2(radius + 3, radius * 0.72 + 3)).round()
		draw_line(tip, tip - Vector2(corner.x * 4, 0), color)
		draw_line(tip, tip - Vector2(0, corner.y * 3), color)

func draw_floaters() -> void:
	for item in floaters:
		var carried := item == held_floater
		var point := (pointer - Vector2(0, 3)) if carried else to_screen(item.point)
		if item.afloat and not carried and item.drift.length_squared() > 4.0 and not item.caught:
			var axis := Vector2.from_angle(item.angle)
			var wake := Color(FOAM, minf(0.48, item.drift.length() * 0.018))
			var spread := axis.orthogonal() * 1.7
			var tail := point - axis * 5.0
			draw_line(snap_pixel(tail + spread), snap_pixel(tail - axis * 5.0 + spread * 1.8), wake, 0.5)
			draw_line(snap_pixel(tail - spread), snap_pixel(tail - axis * 5.0 - spread * 1.8), wake, 0.5)
		if item.twig:
			var axis := Vector2.from_angle(item.angle)
			var tail := (point - axis * 7.0).round()
			var tip := (point + axis * 7.0).round()
			draw_line(tail + Vector2(0, 1), tip + Vector2(0, 1), Color("#422f23"), 3.0)
			draw_line(tail, tip, Color("#956044"), 2.0)
			draw_line(point.round(), (point + Vector2(4, -4).rotated(item.angle)).round(), Color("#bd9060"), 1.0)
		else:
			var form := PackedVector2Array()
			for corner in [Vector2(-5, 0), Vector2(-2, -2), Vector2(2, -2), Vector2(5, 0), Vector2(1, 3), Vector2(-2, 2)]:
				form.append((point + corner.rotated(item.angle)).round())
			draw_colored_polygon(form, Color("#557545"))
			draw_line((point - Vector2(3, 0).rotated(item.angle)).round(), (point + Vector2(4, 0).rotated(item.angle)).round(), Color("#cad26e"), 1.0)
		if item == hovered_floater and held_floater == null:
			draw_brackets(point, 7.0)

func snap_pixel(point: Vector2) -> Vector2:
	return (point * 2.0).round() * 0.5

func dampness(piece: Pool.Piece) -> float:
	if absf(piece.point.y) > Pool.BANK + 1.0:
		return 0.0
	var cell := water.cell_at(piece.point)
	var i := water.index(cell.x, cell.y)
	var wet := maxf(shore_memory[i] * 0.84, smoothstep(0.015, 0.12, water.depth[i]))
	return wet * (1.0 - smoothstep(0.0, 12.0, piece.visible_lift))

func draw_piece(piece: Pool.Piece, p: Vector2, roll: float, damp := 0.0, submersion := 0.0, seated := false) -> void:
	if piece.kind == Pool.STONE:
		draw_rock(piece, p, roll, damp, submersion, seated)
		return
	var r := piece.radius * (1.0 - piece.wear * 0.35)
	var seed := fposmod(piece.radius * 0.317 + piece.shade * 0.247, 1.0)
	var squash := lerpf(0.58, 0.83, seed)
	var turn := roll + lerpf(-0.28, 0.31, seed)
	p = snap_pixel(p + Vector2(0, seed * 1.4 if seated else 0.0))
	var shape := PackedVector2Array()
	var sides := 8 + piece.shade % 3
	for i in sides:
		var phase := i + fposmod(i * 3.53 + piece.radius * 0.13, 1.0) * 0.37
		var angle := TAU * phase / sides + piece.shade * 0.2
		var size := r * (0.80 + fposmod(i * 1.29 + piece.shade * 0.27, 1.0) * 0.27)
		shape.append(snap_pixel(p + (Vector2(cos(angle), sin(angle) * squash) * size).rotated(turn)))
	if seated:
		var bed := p + Vector2(r * 0.11, r * 0.46)
		var contact := PackedVector2Array([Vector2(-0.90, -0.16), Vector2(0.54, -0.45), Vector2(1.05, 0.05), Vector2(0.57, 0.24), Vector2(-0.35, 0.26)])
		for i in contact.size():
			contact[i] = snap_pixel(bed + contact[i] * r)
		draw_colored_polygon(contact, Color("#65523b94").lerp(Color("#233b397b"), damp))
		if seed > 0.42 and r >= 6.0:
			for i in 3:
				var pebble := snap_pixel(bed + Vector2((0.50 + i * 0.22) * r, (i % 2) * 1.5))
				draw_rect(Rect2(pebble, Vector2(1.0 + (i % 2) * 0.5, 1.0)), Color("#7f745b").lerp(Color("#435752"), damp))
				draw_rect(Rect2(pebble + Vector2(0, 0.5), Vector2(1, 0.5)), Color("#4c4a3c"))
	draw_colored_polygon(shape, Color("#554037"))

	var face := PackedVector2Array()
	for tip in shape:
		face.append(snap_pixel(p + (tip - p) * 0.90 - Vector2(0, 0.6)))
	var base := Color("#97694a")
	draw_colored_polygon(face, base)
	var ridge := snap_pixel(p + Vector2(-r * 0.26, -r * lerpf(0.13, 0.31, seed)).rotated(turn))
	for i in face.size():
		var next := (i + 1) % face.size()
		var midpoint := (face[i] + face[next]) * 0.5
		var light := (midpoint - p).normalized().dot(Vector2(-0.48, -0.88))
		var facet := base.lerp(Color("#c4aa88"), light * 0.47) if light > 0.0 else base.darkened(-light * 0.33)
		var lower_face := smoothstep(-0.15, 0.55, (midpoint.y - p.y) / maxf(1.0, r * 0.65))
		facet = facet.lerp(Color("#354b4c").lerp(facet, 0.36), damp * lower_face * 0.7)
		draw_colored_polygon(PackedVector2Array([ridge, face[i], face[next]]), facet)
		if light > 0.52 and i % 2 == 0:
			draw_line(snap_pixel(face[i].lerp(midpoint, 0.36)), snap_pixel(midpoint.lerp(face[next], 0.40)), Color("#dfb6899a"), 0.5)
	for i in 16:
		var x := fposmod(i * 0.618 + piece.shade * 0.093, 1.0) - 0.5
		var y := fposmod(i * 0.267 + piece.radius * 0.053, 1.0) - 0.5
		var position := snap_pixel(p + (Vector2(x * 1.2, y * 0.68) * r).rotated(turn))
		var tone := Color(base.lightened(0.17) if i % 3 == 0 else base.darkened(0.27), 0.70)
		if y > 0.13:
			tone = tone.lerp(Color("#384c47ad"), damp * 0.55)
		draw_rect(Rect2(position, Vector2(0.5 if i % 2 == 0 else 1.0, 0.5)), tone)
	if submersion > 0.13:
		draw_stone_waterline(shape, p.y + r * (0.51 - submersion * 0.69))

func draw_rock(piece: Pool.Piece, p: Vector2, roll: float, damp: float, submersion: float, seated: bool) -> void:
	var r := piece.radius
	p = snap_pixel(p)
	if seated:
		var foot := p + Vector2(-r * 0.15, r * 0.66)
		var shadow := PackedVector2Array([Vector2(-1.02, 0.02), Vector2(-0.68, -0.33),
			Vector2(0.54, -0.34), Vector2(0.91, -0.11), Vector2(0.53, 0.21), Vector2(-0.57, 0.27)])
		for i in shadow.size():
			shadow[i] = snap_pixel(foot + shadow[i] * r)
		draw_colored_polygon(shadow, Color("#26251f99").lerp(Color("#112a2a80"), damp))

	var carving := rock_art.for_piece(r, piece.shade)
	var size := carving.texture.get_size()
	var origin := -size * 0.25
	var sunlight := smoothstep(0.18, 0.77, p.x / SIZE.x + (1.0 - p.y / SIZE.y) * 0.34)
	var dry := Color("#c3cdd2").lerp(Color("#fff6e5"), sunlight)
	var wet := dry * Color("#779997")
	var water_row := clampi(roundi((r * (0.71 - submersion * 0.92) - origin.y) * 2.0), 0, int(size.y))
	draw_set_transform(p, roll)
	draw_texture_rect(carving.texture, Rect2(origin, size * 0.5), false, dry)
	if damp > 0.0 and water_row < int(size.y):
		var lower_strip := Rect2(0, water_row, size.x, size.y - water_row)
		draw_texture_rect_region(carving.texture, Rect2(origin + lower_strip.position * 0.5, lower_strip.size * 0.5),
			lower_strip, Color(wet, damp * 0.80))
		if submersion > 0.13:
			var rim := carving.rim[water_row]
			var width := (rim.y - rim.x) * 0.5
			if width >= 2.0:
				var start := origin + Vector2(rim.x, water_row) * 0.5
				draw_rect(Rect2(start + Vector2(0.5, 0), Vector2(width * 0.23, 0.5)), Color("#b6c2a990"))
				draw_rect(Rect2(start + Vector2(floorf(width * 1.28) * 0.5, 0), Vector2(width * 0.18, 0.5)), Color("#a3c2ae79"))
	draw_set_transform(Vector2.ZERO)

func draw_stone_waterline(shape: PackedVector2Array, level: float) -> void:
	var left := INF
	var right := -INF
	for i in shape.size():
		var a := shape[i]
		var b := shape[(i + 1) % shape.size()]
		if (a.y <= level) == (b.y <= level):
			continue
		var crossing := lerpf(a.x, b.x, (level - a.y) / (b.y - a.y))
		left = minf(left, crossing)
		right = maxf(right, crossing)
	var width := right - left
	if width < 1.5:
		return
	var at := snap_pixel(Vector2(left, level))
	draw_rect(Rect2(at, Vector2(width, 1.0)), Color("#304b49b8"))
	draw_rect(Rect2(at, Vector2(width * 0.30, 0.5)), Color("#b0be9b9b"))
	draw_rect(Rect2(snap_pixel(at + Vector2(width * 0.68, 0.5)), Vector2(width * 0.24, 0.5)), Color("#90b0a381"))

func draw_froth() -> void:
	for item in droplets:
		var origin := Vector2(item.x, item.y)
		var age := item.z
		var strength := item.w
		var alpha := 1.0 - smoothstep(0.16, 0.7, age)
		for i in 24:
			var angle := i * 2.47
			var speed := 7.0 + fposmod(i * 0.791, 1.0) * 37.0
			var delta := Vector2(cos(angle), sin(angle) * 0.64) * age * speed * strength
			delta += Vector2(age * 42.0, -sin(age / 0.7 * PI) * (3.0 + i % 5) * strength)
			var size := Vector2(2, 1) if i % 3 == 0 else Vector2.ONE
			draw_rect(Rect2((origin + delta).floor(), size), Color(FOAM, alpha))
