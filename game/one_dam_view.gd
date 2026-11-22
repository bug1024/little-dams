extends Node2D

const Flow = preload("res://game/one_dam_grid.gd")
const Breach = preload("res://game/one_dam_breach.gd")
const Summer = preload("res://game/one_dam_summer.gd")
const Pool = preload("res://game/one_dam_water.gd")
const RockArt = preload("res://game/one_dam_rock_art.gd")
const Wind = preload("res://game/one_dam_wind.gd")
const Air = preload("res://game/one_dam_air.gd")
const Rain = preload("res://game/one_dam_rain.gd")
const GroundInsects = preload("res://game/one_dam_ground_insects.gd")
const Frog = preload("res://game/one_dam_frog.gd")
const SIZE := Vector2(320, 200)
const CHANNEL_MASK := preload("res://game/one_dam_channel.png")
const PLATE := preload("res://game/one_dam_plate.png")
const PAPER := Color("#f7dda2")
const FOAM := Color("#c2f8ef")
const LEAF_CLEARANCE := 1.45
const ROCK_LEDGE_FEET := [
	Rect2(67, 78, 20, 9), Rect2(117, 74, 29, 11), Rect2(172, 64, 27, 10),
	Rect2(230, 54, 18, 10), Rect2(266, 153, 35, 13), Rect2(284, 175, 26, 11),
]
signal stone_splash(mass: float, strength: float)
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

class RollingPiece:
	var piece: Pool.Piece
	var point: Vector2
	var velocity: Vector2
	var age := 0.0
	var lift := 0.0
	var fall := 0.0
	var turn := 0.0
	var impact := false
	var force := 0.0

var water: Flow
var model: Pool
var lower: Pool
var upper_breach: Breach
var lower_breach: Breach
var foam_strength := 1.0
var bank: Array[Pool.Piece] = []
var rolling: Array[RollingPiece] = []
var riffle: Array[Pool.Piece] = []
var floaters: Array[Floater] = []
var held_floater: Floater
var hovered_floater: Floater
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
var ground_insects := GroundInsects.new()
var frog := Frog.new()
var wind := Wind.new()
var rain := Rain.new()
var painted_ground := PLATE.get_image()
var air := Air.new()
var rock_art := RockArt.new()
var shore_memory := PackedFloat32Array()
var bed_deposit := PackedFloat32Array()
var surface_travel := PackedVector2Array()
var shore_image := Image.create_empty(Flow.COLUMNS, Flow.ROWS, false, Image.FORMAT_RGBAF)
var shore_texture := ImageTexture.create_from_image(shore_image)
var leaf_due := 6.4
var release_time := 0.0
var release_start := 0.0
var painted_channel := CHANNEL_MASK.get_image()
var quiet_flow := PackedFloat32Array()
var surge_field := PackedFloat32Array()
var surge_image := Image.create_empty(Flow.COLUMNS, 1, false, Image.FORMAT_RF)
var surge_texture := ImageTexture.create_from_image(surge_image)
var last_crest_x := -1.0

func _ready() -> void:
	shore_memory.resize(Flow.COUNT)
	bed_deposit.resize(Flow.COUNT)
	quiet_flow.resize(Flow.COLUMNS)
	surge_field.resize(Flow.COLUMNS)
	surface_travel.resize(Flow.COUNT)
	var background := Sprite2D.new()
	background.centered = false
	background.texture_filter = TEXTURE_FILTER_NEAREST
	background.scale = Vector2(0.5, 0.5)
	background.texture = PLATE
	background.z_index = -1
	surface.shader = preload("res://game/one_dam_surface.gdshader")
	surface.set_shader_parameter("surge_field", surge_texture)
	ground_light.shader = preload("res://game/one_dam_ground.gdshader")
	var channel_profile := Image.create_empty(160, 1, false, Image.FORMAT_RGF)
	for i in channel_profile.get_width():
		var x := (i + 0.5) * SIZE.x / channel_profile.get_width()
		channel_profile.set_pixel(i, 0, Color(shoreline(CHANNEL_Y, x) / SIZE.y, shoreline(CHANNEL_RADIUS, x) / SIZE.y, 0))
	var profile_texture := ImageTexture.create_from_image(channel_profile)
	for material in [surface, ground_light]:
		material.set_shader_parameter("channel_mask", CHANNEL_MASK)
		material.set_shader_parameter("channel_profile", profile_texture)
		material.set_shader_parameter("flow_state", flow_texture)
		material.set_shader_parameter("shore_memory", shore_texture)
	var ground := background.duplicate() as Sprite2D
	ground.z_index = -2
	ground.material = ground_light
	add_child(ground)
	background.material = surface
	add_child(background)

	summer.wind = wind
	summer.fish_surface.connect(func(point: Vector2) -> void:
		ripples.append(Vector4(point.x, point.y, 0.0, 0.23)))
	frog.landed.connect(on_frog_landed)
	air.wind = wind
	air.view = self
	air.z_index = 2
	add_child(air)

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

func on_bank(point: Vector2) -> bool:
	if absf(from_screen(point).y) > Pool.BANK + 4.0:
		return true
	var pixel := Vector2i(point / SIZE * Vector2(painted_channel.get_size()))
	return painted_channel.get_pixelv(pixel).r < 0.5

func rain_contact(point: Vector2) -> Rain.Contact:
	if not on_bank(point) and is_wet(from_screen(point)):
		return Rain.Contact.WATER
	var pixel := Vector2i(point / SIZE * Vector2(painted_ground.get_size()))
	var paint := painted_ground.get_pixelv(pixel)
	if paint.g - paint.b > 0.065 and paint.g > paint.r * 0.89:
		return Rain.Contact.LEAVES
	return Rain.Contact.GROUND

func clear() -> void:
	rain.clear()
	ground_insects.reset(to_screen)
	frog.reset()
	summer.fish_held = false
	summer.fish_stranded = false
	summer.fish_released = false
	summer.fish_time = -1.0
	summer.fish_due = summer.clock + 4.0
	summer.insect_held = false
	summer.temporary_perch = false
	bank.clear()
	rolling.clear()
	droplets.clear()
	ripples.clear()
	shore_memory.fill(0.0)
	bed_deposit.fill(0.0)
	surge_field.fill(0.0)
	release_time = 0.0
	last_crest_x = -1.0
	surface_travel.fill(Vector2.ZERO)
	leaf_due = clock + 6.4
	riffle.clear()
	floaters.clear()
	for row in [[57, 60, false, 0.5], [63, -77, true, -0.22], [123, 71, false, -0.39],
			[221, 58, true, 0.18], [256, -79, false, 1.1], [281, 56, false, -0.7]]:
		floaters.append(Floater.new(Vector2(row[0], row[1]), row[2], row[3]))
	held_floater = null
	hovered_floater = null
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
	var mass := smoothstep(5.0, 15.0, piece.radius)
	var flow := water.velocity_at(piece.point + Vector2(5, 0)).limit_length(70.0)
	var rock := RollingPiece.new()
	rock.piece = piece
	rock.point = piece.point
	rock.velocity = (flow * 0.64 + Vector2(9.0 + strength * 11.0, 0.0)) * lerpf(1.10, 0.42, mass)
	rock.lift = piece.visible_lift + lerpf(4.5, 2.0, mass)
	rock.force = strength
	rolling.append(rock)
	if piece.kind == Pool.EARTH:
		water.cloud(piece.point, 0.25)

func wave_impact(point: Vector2, strength: float) -> void:
	summer.disturb_water(point, strength, true)
	burst(point + Vector2(7.0, 0.0), strength)

func track_release(origin_x: float) -> void:
	if release_time <= 0.0:
		for x in Flow.COLUMNS:
			quiet_flow[x] = water.discharge_at((x + 0.5) * Flow.DX)
		last_crest_x = -1.0
		release_start = origin_x
	else:
		release_start = minf(release_start, origin_x)
	release_time = 6.5

func advance_surge(dt: float) -> void:
	release_time = maxf(0.0, release_time - dt)
	var crest_x := -1.0
	for x in Flow.COLUMNS:
		var at := (x + 0.5) * Flow.DX
		var gain := water.discharge_at(at) - quiet_flow[x]
		var push := smoothstep(0.07, 0.45, gain) if release_time > 0.0 and at >= release_start - Flow.DX else 0.0
		surge_field[x] = lerpf(surge_field[x], push, 1.0 - exp(-dt * (21.0 if push > surge_field[x] else 3.2)))
		surge_image.set_pixel(x, 0, Color(surge_field[x], 0.0, 0.0))
		if at < SIZE.x - 12.0 and surge_field[x] > 0.28:
			crest_x = at
	surge_texture.update(surge_image)
	if crest_x > 0.0 and (last_crest_x < 0.0 or crest_x > last_crest_x + 26.0):
		last_crest_x = crest_x
		var at := Vector2(crest_x, 0.0)
		summer.disturb_water(at, 0.72, true)
		if crest_x > release_start + 27.0 and is_wet(at):
			ripples.append(Vector4(crest_x, 0.0, 0.0, 0.43))

func surge_at(x: float) -> float:
	return surge_field[clampi(floori(x / Flow.DX), 0, Flow.COLUMNS - 1)]

func support_impact(piece: Pool.Piece, speed: float) -> void:
	if not is_wet(piece.point):
		return
	var mass := smoothstep(5.0, 15.0, piece.radius)
	var strength := clampf(speed * (0.012 + mass * 0.012), 0.15, 1.15)
	burst(piece.point, strength)
	water.cloud(piece.point, strength * 0.16)
	summer.disturb_water(piece.point, strength, false)
	if piece.kind == Pool.STONE:
		stone_splash.emit(mass, strength)

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

func advance_rolls(dt: float) -> void:
	for i in range(rolling.size() - 1, -1, -1):
		var rock := rolling[i]
		var piece: Pool.Piece = rock.piece
		var mass := smoothstep(5.0, 15.0, piece.radius)
		var at: Vector2 = rock.point
		var velocity: Vector2 = rock.velocity
		rock.age += dt
		var contact := rock.lift <= 0.0
		var current := water.velocity_at(at).limit_length(65.0) if is_wet(at) else Vector2.ZERO
		var drag := lerpf(0.50, 0.20, mass) * exp(-rock.age * 0.8)
		velocity = velocity.lerp(current * drag, 1.0 - exp(-dt * (3.8 if contact else 1.1)))
		var next := at + velocity * dt
		if next.x > 5.0 and next.x < SIZE.x - 7.0 and absf(next.y) <= Pool.BANK + 13.0 and (
				not blocked_at(model, next, 0.2) and not blocked_at(lower, next, 0.2)
				or blocked_at(model, at, 0.2) or blocked_at(lower, at, 0.2)):
			rock.point = next
		else:
			velocity *= 0.16
		rock.velocity = velocity
		rock.turn += velocity.length() * dt / maxf(piece.radius * 0.8, 2.0)
		rock.fall += dt * 96.0
		rock.lift = maxf(0.0, rock.lift - rock.fall * dt)
		if not rock.impact and rock.lift <= 0.0:
			rock.impact = true
			if is_wet(rock.point):
				var strength := clampf(rock.force * lerpf(0.34, 0.69, mass), 0.17, 1.23)
				burst(rock.point, strength)
				water.cloud(rock.point, strength * (0.31 if piece.kind == Pool.EARTH else 0.18))
				if piece.kind == Pool.STONE:
					stone_splash.emit(mass, strength)
					summer.disturb_water(rock.point, strength, false)
		if rock.age >= 1.45 or (rock.age > 0.50 and velocity.length() < 2.5):
			piece.point = rock.point
			piece.visible_lift = 0.0
			piece.notch = 0.0
			piece.wear = 0.0
			if not is_wet(piece.point):
				bank.append(piece)
			elif piece.kind == Pool.STONE:
				riffle.append(piece)
			rolling.remove_at(i)

func is_wet(at: Vector2) -> bool:
	return absf(at.y) <= Pool.BANK and water.depth_at(at) > 0.046

func settle_leaf(screen: Vector2, turn: float) -> bool:
	var target := from_screen(screen)
	if not Rect2(Vector2.ZERO, SIZE).has_point(screen) or not can_float_at(target, LEAF_CLEARANCE):
		return false
	var leaf := Floater.new(target, false, turn)
	leaf.afloat = true
	leaf.ambient = true
	floaters.append(leaf)
	ripples.append(Vector4(target.x, target.y, 0.0, 0.18))
	return true

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

func can_float_at(point: Vector2, clearance: float) -> bool:
	return is_wet(point) and not blocked_at(model, point, clearance) and not blocked_at(lower, point, clearance)

func clear_float_path(start: Vector2, end: Vector2, clearance: float) -> bool:
	for i in range(1, 4):
		var point := start.lerp(end, i / 3.0)
		if not can_float_at(point, clearance):
			return false
	return true

func drift_floater(item: Floater, step: float) -> void:
	var flow := water.velocity_at(item.point).limit_length(72.0)
	flow += Wind.DIRECTION * wind.strength_at(item.point.x / SIZE.x) * (2.0 if item.twig else 3.5)
	var response := (5.5 if item.twig else 8.0) * (1.0 + surge_at(item.point.x) * 0.65)
	item.drift = item.drift.lerp(flow, 1.0 - exp(-step * response))
	var clearance := 3.8 if item.twig else LEAF_CLEARANCE
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
	wind.advance(dt)
	advance_surge(dt)
	advance_riffle(dt)
	advance_floaters(dt)
	advance_streaks(dt)
	summer.advance(dt, water)
	ground_insects.frog_blocker = frog.position if frog.duration <= 0.0 else Vector2.INF
	refresh_insect_terrain()
	ground_insects.advance(dt, to_screen, from_screen, insect_in_water, insect_ripple)
	frog.advance(dt, frog_clear)
	for crawler in [ground_insects.mole, ground_insects.mantis]:
		if crawler != ground_insects.held:
			summer.disturb_perch(crawler.position)
	air.advance(dt)
	rain.advance_drops(dt, self)
	sync_surface(dt)
	surface.set_shader_parameter("creek_time", clock)
	surface.set_shader_parameter("upper_pool", pool_profile(model, 146.0))
	surface.set_shader_parameter("lower_pool", pool_profile(lower, 262.0))
	var trail := wind.trail()
	ground_light.set_shader_parameter("wind_trail", trail)
	ground_light.set_shader_parameter("canopy_flutter", wind.canopy_flutter())
	ground_light.set_shader_parameter("sun_drift", wind.sunlight)
	surface.set_shader_parameter("wind_trail", trail)
	surface.set_shader_parameter("wind_travel", wind.travel)
	surface.set_shader_parameter("sun_drift", wind.sunlight)
	ground_light.set_shader_parameter("rain_wetness", rain.wetness)
	ground_light.set_shader_parameter("rain_intensity", rain.intensity)
	surface.set_shader_parameter("rain_intensity", rain.intensity)

	advance_rolls(dt)
	for i in range(droplets.size() - 1, -1, -1):
		droplets[i].z += dt
		if droplets[i].z >= 0.7:
			droplets.remove_at(i)
	for i in range(ripples.size() - 1, -1, -1):
		ripples[i].z += dt
		if ripples[i].z > 1.85:
			ripples.remove_at(i)
	queue_redraw()

func refresh_insect_terrain() -> void:
	ground_insects.rocks.clear()
	for ledge: Rect2 in ROCK_LEDGE_FEET:
		ground_insects.add_rock(ledge.get_center(), ledge.size * 0.5, 8.0)
	for pieces in [bank, model.wall, lower.wall, riffle]:
		for piece: Pool.Piece in pieces:
			if piece == held:
				continue
			var footprint := Vector2(0.82, 0.51) * piece.radius
			var height := piece.radius * (0.53 if piece.kind == Pool.STONE else 0.31) + piece.visible_lift
			ground_insects.add_rock(piece_screen(piece) + Vector2(0, piece.radius * 0.13), footprint, height)
	for crawler: GroundInsects.Crawler in [ground_insects.mole, ground_insects.mantis]:
		var at := crawler.position.clamp(Vector2.ZERO, SIZE - Vector2.ONE)
		var substrate := rain_contact(at)
		var speed := 0.72 if substrate == Rain.Contact.LEAVES else 1.0
		if substrate != Rain.Contact.WATER:
			speed *= 1.0 - rain.wetness * 0.16
		crawler.surface_pace = speed

func insect_in_water(point: Vector2) -> bool:
	return is_wet(point) and not on_bank(to_screen(point))

func insect_ripple(point: Vector2) -> void:
	ripples.append(Vector4(point.x, point.y, 0.0, 0.15))

func frog_clear(point: Vector2) -> bool:
	return point.distance_to(ground_insects.mole.position) >= GroundInsects.CLEARANCE and point.distance_to(ground_insects.mantis.position) >= 12.0 and (
		summer.insect_state != Summer.Flight.PERCHED or point.distance_to(summer.insect_position) >= 9.0)

func on_frog_landed(point: Vector2) -> void:
	var local := from_screen(point)
	if insect_in_water(local):
		burst(local, 0.31)

func holding_animal() -> bool:
	return ground_insects.held != null or summer.insect_held or summer.fish_held or frog.held

func cancel_animal_grab() -> void:
	ground_insects.held = null
	summer.insect_held = false
	summer.fish_held = false
	frog.held = false

func grab_animal(point: Vector2) -> bool:
	if ground_insects.grab(point):
		return true
	summer.insect_held = summer.insect_position.distance_to(point) <= 9.0
	if summer.insect_held:
		return true
	frog.held = frog.screen_point().distance_to(point) <= 7.0
	if frog.held:
		return true
	summer.fish_held = summer.fish_time >= 0.25 and to_screen(summer.fish).distance_to(point) <= 7.0
	return summer.fish_held

func can_place_animal(point: Vector2) -> bool:
	if not Rect2(Vector2(2, 2), SIZE - Vector2(4, 4)).has_point(point):
		return false
	if not frog.held and point.distance_to(frog.position) < GroundInsects.CLEARANCE:
		return false
	if frog.held or summer.fish_held:
		return frog_clear(point)
	if ground_insects.held != null:
		return ground_insects.can_place_at(point) and (
			summer.insect_state != Summer.Flight.PERCHED or point.distance_to(summer.insect_position) >= 8.0)
	return point.distance_to(ground_insects.mole.position) >= 8.0 and point.distance_to(ground_insects.mantis.position) >= 10.0

func place_animal(point: Vector2) -> void:
	if not holding_animal() or not can_place_animal(point):
		return
	var local := from_screen(point)
	var wet := insect_in_water(local)
	if frog.held:
		frog.place(point)
		on_frog_landed(point)
		return
	elif summer.fish_held:
		summer.place_fish(local, wet and water.depth_at(local) >= 0.13)
	elif ground_insects.held != null:
		var side := -1.0 if local.y < 0.0 else 1.0
		var bank := to_screen(Vector2(local.x, side * 48.0)).clamp(Vector2(9, 9), SIZE - Vector2(9, 9))
		ground_insects.place(point, bank, side, wet)
	else:
		summer.place_insect(point, wet)
	if wet:
		burst(local, 0.13)

func pool_profile(basin: Pool, fallback: float) -> Vector2:
	var center := basin.center(fallback)
	var head := maxf(0.0, water.pool_head(center) - water.channel_depth(center + 19.0))
	return Vector2(center / SIZE.x, head if not basin.wall.is_empty() else 0.0)

func _draw() -> void:
	if water == null:
		return
	summer.draw_fish(self, to_screen, pointer)
	draw_pond_edge(model, 146.0)
	draw_pond_edge(lower, 262.0)
	draw_current()
	draw_surge_current()
	draw_ripples()
	draw_shore_bubbles()
	rain.draw_puddles(self)
	summer.draw_land(self)
	ground_insects.draw(self, pointer, true)
	draw_materials()
	draw_seams(model)
	draw_seams(lower)
	draw_breach_jet(upper_breach)
	draw_breach_jet(lower_breach)
	draw_froth()
	draw_floaters()
	ground_insects.draw(self, pointer, false)
	summer.draw_insect(self, pointer)
	summer.draw_fish(self, to_screen, pointer, true)
	frog.draw(self, pointer)
	rain.draw_drops(self)
	if holding_animal():
		draw_drop_hint()

func draw_pond_edge(basin: Pool, fallback: float) -> void:
	if basin.wall.is_empty():
		return
	var head := pool_profile(basin, fallback).y
	var height := smoothstep(0.08, 0.65, head)
	if height < 0.02:
		return
	for piece in basin.wall:
		if piece.support != null:
			continue
		var at := piece.point - Vector2(piece.radius * 0.90, 0.0)
		var h := water.depth_at(at)
		if h <= 0.18:
			continue
		var p := to_screen(at) - Vector2(0, minf(8.0, (h - 0.18) * 8.0) * height)
		var shimmer := 0.68 + sin(clock * 3.7 + piece.point.y * 0.36) * 0.23
		var extent := piece.radius * 0.42
		var curve := PackedVector2Array([snap_pixel(p + Vector2(2.2, -extent)), snap_pixel(p + Vector2(0.4, -extent * 0.5)),
			snap_pixel(p + Vector2(0.0, extent * 0.38)), snap_pixel(p + Vector2(1.4, extent))])
		draw_polyline(curve, Color(0.61, 0.79, 0.75, height * shimmer * 0.75), 0.5)
		if height > 0.35:
			var eddy := p + Vector2(-6.0 - shimmer * 4.0, extent * 0.2)
			draw_line(snap_pixel(eddy), snap_pixel(eddy + Vector2(3.2, -1.1)), Color(FOAM, height * shimmer * 0.27), 0.5)

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
		var push := surge_at(at.x)
		var end := at + v.normalized() * minf(16.0, 1.0 + speed * (0.125 + push * 0.08))
		if not is_wet(end):
			continue
		var strength := smoothstep(7.0, 57.0, speed)
		draw_line(from, snap_pixel(to_screen(end)), Color(FOAM, clampf(0.11 + (strength * 0.58 + push * 0.43) * foam_strength, 0.0, 0.95)), 0.5 if strength + push * 0.3 < 0.78 else 1.0)

func draw_surge_current() -> void:
	for x in Flow.COLUMNS:
		var push := surge_field[x]
		if push < 0.12:
			continue
		for y in range(1 + x % 3, Flow.ROWS - 1, 3):
			var local := water.velocity_cell(x, y)
			if local.x < 4.0:
				continue
			var seed := x * 0.37 + y * 1.61
			var phase := fposmod(clock * (0.64 + local.x * 0.027) + seed, 1.0)
			var life := sin(phase * PI) * smoothstep(0.12, 0.74, push)
			var axis := local.normalized()
			var at := water.cell_point(x, y) + axis * ((phase - 0.5) * Flow.DX * 2.6)
			at.y += sin(seed + phase * 3.6) * 1.4
			var behind := at - axis * (2.2 + push * 10.0)
			if not is_wet(at) or not is_wet(behind):
				continue
			var start := snap_pixel(to_screen(behind))
			var end := snap_pixel(to_screen(at))
			draw_line(start, end, Color("#83b9b2", life * 0.39), 2.0)
			draw_line(snap_pixel(start.lerp(end, 0.51)), end, Color("#e4f8ed", life * 0.90), 1.0)
			if push > 0.42:
				var foam := to_screen(at + axis.orthogonal() * sin(seed) * 2.1)
				draw_rect(Rect2(snap_pixel(foam), Vector2(1.5, 0.5)), Color(FOAM, life * 0.73))

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
		var push := surge_at(stone.point.x)
		for i in (6 if push > 0.26 else 3):
			var phase := fposmod(clock * (0.56 + v.x * 0.013) + i * 0.29 + stone.shade * 0.11, 1.0)
			var turn := phase * TAU
			var along := stone.radius * 0.58 + phase * 6.0 + sin(turn) * 1.6
			var at := stone.point + v.normalized() * along
			at += side * (stone.radius * 0.63 + cos(turn) * 1.8) * (-1.0 if i % 2 == 0 else 1.0)
			if is_wet(at):
				var p := snap_pixel(to_screen(at))
				draw_rect(Rect2(p, Vector2(1.0 + push, 0.5)), Color(0.68, 0.87, 0.79, sin(phase * PI) * (0.35 + push * 0.36)))

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
			if speed > best and can_float_at(at, 0.1):
				best = speed
				jet = at
				selected = lane
		if selected < 0:
			break
		chosen.append(selected)
		var pressure := smoothstep(0.08, 0.53, pool_profile(basin, center).y)
		var force := smoothstep(8.0, 49.0, best) * (0.50 + pressure * 0.50)
		var seam_axis := water.velocity_at(jet).normalized()
		var spill := jet + seam_axis * (3.0 + force * 6.0)
		if can_float_at(spill, 0.1):
			draw_line(snap_pixel(to_screen(jet)), snap_pixel(to_screen(spill)), Color(FOAM, force * 0.45), 0.5)
		for fleck in 6:
			var offset := fposmod(clock * (12.0 + best) + fleck * 3.7, 7.0 + force * 15.0)
			var at := jet + seam_axis * offset + Vector2(0, sin(fleck * 2.0 + clock * 11.0) * 1.9 * force)
			if is_wet(at):
				draw_rect(Rect2(snap_pixel(to_screen(at)), Vector2(1.0 + force * 3.0, 0.5)), Color(FOAM, 0.26 + force * 0.68))

func draw_breach_jet(event: Breach) -> void:
	if event == null or event.phase == Breach.Phase.READY or event.strength < 0.035:
		return
	var wide := event.phase == Breach.Phase.SURGE
	var rows := 16 if wide else (3 if event.prying else 6)
	var fullness := clampf(event.strength * foam_strength, 0, 1)
	var axis := Vector2.RIGHT.lerp(event.direction, 0.58).normalized()
	var side := axis.orthogonal()
	var mouth := event.origin + axis * (7.0 if event.prying else 3.5)
	var out := mouth + axis * (5.0 + fullness * (12.0 if wide else 5.0))
	if is_wet(mouth) and is_wet(out):
		var start := snap_pixel(to_screen(mouth))
		var end := snap_pixel(to_screen(out))
		draw_line(start, end, Color("#74aeaa", fullness * 0.57), 3.5 if wide else 1.5)
		var head := start.lerp(end, 0.33 + sin(clock * 28.0) * 0.11)
		draw_line(start, snap_pixel(head), Color("#ecf7e9", fullness * 0.87), 1.0 if wide else 0.5)
	for i in rows:
		var spread := event.mouth_width * (0.70 if wide else 0.44)
		var cross := (i / float(rows - 1) - 0.5) * spread
		var progress := fposmod(clock * (24.0 + 54.0 * fullness) + i * 4.17, 7.0 + (25.0 if wide else 9.0) * fullness)
		var at := mouth + axis * progress + side * cross * (1.0 + progress * 0.033)
		if not is_wet(at):
			continue
		var local := water.velocity_at(at)
		if local.length() < 4.0:
			continue
		var back := at - local.normalized() * minf(progress, 1.4 + fullness * (6.2 if wide else 3.1))
		var white := Color("#e3f9eb") if i % 3 == 0 else FOAM
		draw_line(snap_pixel(to_screen(back)), snap_pixel(to_screen(at)), Color(white, fullness * (0.62 + i % 3 * 0.17)), (1.5 if i % 4 == 0 else 1.0) if wide else 0.5)
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
		var built := model.wall.has(piece) or lower.wall.has(piece)
		if built and piece.wear > 0.24:
			p.x += sin(clock * (20.0 + piece.shade * 5.0)) * smoothstep(0.24, 1.0, piece.wear) * 1.9
			if piece.kind == Pool.EARTH:
				var progress := fposmod(clock * 0.68 + piece.point.y * 3.7, 1.0)
				for j in 3:
					var grain := p + Vector2(2.0 + progress * 17.0 + j * 2.0, sin(progress * PI + j * 1.1) * 4.0)
					draw_rect(Rect2(grain.floor(), Vector2(2, 1)), Color(0.77, 0.57, 0.35, (1.0 - progress) * 0.89))
		var damp := dampness(piece)
		var submersion := 0.0
		if absf(piece.point.y) <= Pool.BANK:
			var depth := water.depth_at(piece.point)
			if built:
				depth = maxf(depth, water.depth_at(piece.point - Vector2(piece.radius * 0.76, 0)))
			var water_height: float = depth * 15.0 - piece.visible_lift
			submersion = clampf(water_height / (piece.radius * 0.80), 0.0, 0.88)
		p.x += piece.notch * 4.5
		draw_piece(piece, p, piece.notch * 0.27, damp, submersion, piece.support == null, 0.84 if built else 1.0)
		if piece == hovered:
			draw_brackets(p, piece.radius)
	for item in rolling:
		var piece: Pool.Piece = item.piece
		var p := to_screen(item.point) - Vector2(0, item.lift)
		draw_piece(piece, p, item.turn if piece.kind == Pool.STONE else item.turn * 0.35, 0.8)
	if held != null:
		draw_piece(held, (pointer - Vector2(0, maxf(5.0, preview_lift))).round(), 0.0)
		draw_drop_hint()

func draw_drop_hint() -> void:
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

func draw_piece(piece: Pool.Piece, p: Vector2, roll: float, damp := 0.0, submersion := 0.0, seated := false, squash := 1.0) -> void:
	if piece.kind == Pool.STONE:
		draw_rock(piece, p, roll, damp, submersion, seated, squash)
		return
	var r := piece.radius * (1.0 - piece.wear * 0.35)
	var seed := fposmod(piece.radius * 0.317 + piece.shade * 0.247, 1.0)
	squash *= lerpf(0.58, 0.83, seed)
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

func draw_rock(piece: Pool.Piece, p: Vector2, roll: float, damp: float, submersion: float, seated: bool, squash: float) -> void:
	var r := piece.radius
	p = snap_pixel(p)
	if seated:
		var foot := p + Vector2(-r * 0.15, r * 0.66 * squash)
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
	draw_set_transform(p, roll, Vector2(1.0, squash))
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
