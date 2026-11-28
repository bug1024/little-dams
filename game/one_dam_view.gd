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
const Crab = preload("res://game/one_dam_crab.gd")
const Bird = preload("res://game/one_dam_bird.gd")
const Boat = preload("res://game/one_dam_boat.gd")
const SquirtGun = preload("res://game/one_dam_squirt_gun.gd")
const SeasonProfile = preload("res://game/world/season_profile.gd")
const WorldState = preload("res://game/world/world_state.gd")
const WorldStimulus = preload("res://game/world/world_stimulus.gd")
const CreekFlora = preload("res://game/world/creek_flora.gd")
const GroundTraces = preload("res://game/world/ground_traces.gd")
const Hearth = preload("res://game/one_dam_hearth.gd")
const Scenery = preload("res://game/one_dam_scenery.gd")
const SIZE := Vector2(320, 200)
const CHANNEL_MASK := preload("res://game/one_dam_channel.png")
const PLATE := preload("res://game/one_dam_plate.png")
const PAPER := Color("#f7dda2")
const FOAM := Color("#d7ebe0")
const LEAF_CLEARANCE := 1.45
const ROCK_LEDGE_FEET := [
	Rect2(67, 78, 20, 9), Rect2(117, 74, 29, 11), Rect2(172, 64, 27, 10),
	Rect2(230, 54, 18, 10), Rect2(266, 153, 35, 13), Rect2(284, 175, 26, 11),
]
signal stone_splash(mass: float, strength: float)
# Centers and half widths traced from the near-view shoreline at sixteen-pixel intervals.
const CHANNEL_Y := [89.2, 94.6, 100.3, 108.1, 111.5, 118.2, 117.9, 113.7, 117.0, 114.7, 112.4, 109.2, 105.0, 100.9, 96.8, 89.9, 84.3, 78.0, 72.1, 68.8, 66.0]
const CHANNEL_RADIUS := [19.8, 19.8, 22.4, 24.1, 22.1, 23.6, 24.9, 26.5, 30.6, 31.7, 32.8, 31.4, 26.0, 25.6, 27.7, 23.1, 24.4, 23.2, 20.8, 21.3, 22.2]

enum Forage { NONE, FLOWER, FOXTAIL, THIN_BRANCH, DRY_GRASS }

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
	var forage := Forage.NONE
	var tint := Color.WHITE
	var rooted := false
	var planted := false
	var host: Pool.Piece
	var host_offset := Vector2.ZERO
	var soaked := 0.0

	func _init(at: Vector2, is_twig: bool, turn: float) -> void:
		point = at
		shore = at
		twig = is_twig
		angle = turn

	func is_firewood() -> bool:
		return twig or forage == Forage.THIN_BRANCH

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
var pipes: Array[Pool.DrainPipe] = []
var held_pipe: Pool.DrainPipe
var rolling: Array[RollingPiece] = []
var riffle: Array[Pool.Piece] = []
var floaters: Array[Floater] = []
var held_floater: Floater
var hovered_floater: Floater
var droplets: Array[Vector4] = []
var ripples: Array[Vector4] = []
var hovered: Pool.Piece
var hovered_pipe: Pool.DrainPipe
var hovered_animal := Vector3.ZERO
var hovered_hearth := false
var hovered_boat := false
var hovered_squirt_gun := false
var squirt_mouse_down := false
var held: Pool.Piece
var pointer := Vector2.ZERO
var clear_drop := false
var preview_lift := 0.0
var preview_support: Pool.Piece
var preview_target := Vector2.ZERO
var preview_pipe_host: Pool.Piece
var preview_bank_drop := false
var preview_active := false
var pry_mode := false
var clock := 0.0
var day_phase := 0.0
var day_target := -1.0
var auto_day_cycle := true
var post_rain_nudged := false
var snapshot_flash := 0.0
var streaks := PackedVector2Array()
var water_pixels := Image.create_empty(Flow.COLUMNS, Flow.ROWS, false, Image.FORMAT_RGBA8)
var flow_texture := ImageTexture.create_from_image(water_pixels)
var surface := ShaderMaterial.new()
var ground_light := ShaderMaterial.new()
var summer := Summer.new()
var ground_insects := GroundInsects.new()
var frog := Frog.new()
var crab := Crab.new()
var bird := Bird.new()
var boat := Boat.new()
var squirt_gun := SquirtGun.new()
var world := WorldState.new()
var stimuli := WorldStimulus.new()
var flora := CreekFlora.new()
var ground_traces := GroundTraces.new()
var terrain_sprite: Sprite2D
var water_sprite: Sprite2D
var wind := Wind.new()
var rain := Rain.new()
var hearth := Hearth.new()
var scenery := Scenery.new()
var painted_ground := Scenery.GROUND.get_image()
var air := Air.new()
var rock_art := RockArt.new()
var hearth_rim: Array[Pool.Piece] = []
var hearth_warm_faces: Dictionary[Pool.Piece, ImageTexture] = {}
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
var quiet_depth := PackedFloat32Array()
var surge_field := PackedFloat32Array()
var surge_image := Image.create_empty(Flow.COLUMNS, 1, false, Image.FORMAT_RF)
var surge_texture := ImageTexture.create_from_image(surge_image)
var last_crest_x := -1.0

func _ready() -> void:
	for stone: Vector3 in [Vector3(-13, 0, 3.2), Vector3(-8, -5, 3.9), Vector3(2, -6, 2.9),
			Vector3(12, -2, 3.4), Vector3(10, 4, 2.5), Vector3(-5, 5, 2.7)]:
		var rim := Pool.Piece.new(Vector2(stone.x, stone.y), stone.z, Pool.STONE, hearth_rim.size() % 4)
		hearth_rim.append(rim)
		hearth_warm_faces[rim] = make_hearth_warm_face(rim)
	shore_memory.resize(Flow.COUNT)
	bed_deposit.resize(Flow.COUNT)
	quiet_flow.resize(Flow.COLUMNS)
	quiet_depth.resize(Flow.COLUMNS)
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
	ground.name = &"TerrainPlate"
	ground.texture = Scenery.GROUND
	ground.z_index = -2
	ground.material = ground_light
	add_child(ground)
	terrain_sprite = ground
	background.name = &"WaterSurface"
	background.material = surface
	add_child(background)
	water_sprite = background
	scenery.install(self, ground_light)
	scenery.foreground.draw.connect(draw_shore_foreground)

	summer.wind = wind
	summer.fish_surface.connect(func(point: Vector2) -> void:
		ripples.append(Vector4(point.x, point.y, 0.0, 0.23)))
	frog.landed.connect(on_frog_landed)
	crab.landed.connect(on_crab_landed)
	air.wind = wind
	air.view = self
	air.z_index = 2
	add_child(air)
	register_stimulus_listeners()

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
	if scenery.plant_at(point):
		return Rain.Contact.LEAVES
	var pixel := Vector2i(point / SIZE * Vector2(painted_ground.get_size()))
	var paint := painted_ground.get_pixelv(pixel)
	var is_green := paint.g - paint.b > 0.065 and paint.g > paint.r * 0.89
	var is_autumn_canopy := (point.y < 60.0 and point.x < 125.0 or point.x > 282.0 or point.y > 142.0 and point.x < 60.0) and paint.r - paint.b > 0.20 and paint.r > 0.36
	if is_green or is_autumn_canopy:
		return Rain.Contact.LEAVES
	return Rain.Contact.GROUND

func clear() -> void:
	rain.clear()
	hearth.reset()
	ground_insects.reset(to_screen)
	frog.reset()
	crab.reset()
	bird.reset()
	boat.reset(from_screen)
	hovered_boat = false
	squirt_gun.reset()
	hovered_squirt_gun = false
	squirt_mouse_down = false
	world.reset(SeasonProfile.Season.SPRING)
	apply_season_visuals(world.season)
	flora.reset()
	ground_traces.clear()
	summer.fish_held = false
	summer.fish_stranded = false
	summer.fish_released = false
	summer.fish_time = -1.0
	summer.fish_due = summer.clock + 4.0
	summer.insect_held = false
	summer.temporary_perch = false
	summer.reset_ecosystem()
	day_phase = 0.0
	day_target = -1.0
	post_rain_nudged = false
	snapshot_flash = 0.0
	bank.clear()
	pipes.clear()
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
	var fcols: Array[Color] = world.profile.flower_colors
	var fxcols: Array[Color] = world.profile.foxtail_colors
	for row in [
		[Vector2(49, 135), Forage.FLOWER, fcols[0]], [Vector2(55, 138), Forage.FLOWER, fcols[1]],
		[Vector2(104, 78), Forage.FLOWER, fcols[2]], [Vector2(110, 80), Forage.FLOWER, fcols[3]],
		[Vector2(202, 148), Forage.FLOWER, fcols[4]], [Vector2(207, 150), Forage.FLOWER, fcols[5]],
		[Vector2(83, 147), Forage.FOXTAIL, fxcols[0]], [Vector2(89, 146), Forage.FOXTAIL, fxcols[1]],
		[Vector2(178, 70), Forage.FOXTAIL, fxcols[2]], [Vector2(272, 116), Forage.FOXTAIL, fxcols[0]],
		[Vector2(30, 123), Forage.FOXTAIL, fxcols[1]], [Vector2(148, 152), Forage.FOXTAIL, fxcols[2]],
		[Vector2(250, 117), Forage.FOXTAIL, fxcols[0]],
		[Vector2(81, 175), Forage.THIN_BRANCH, Color("#9d7652")], [Vector2(236, 35), Forage.THIN_BRANCH, Color("#a37c57")],
		[Vector2(210, 170), Forage.DRY_GRASS, Color("#cfa768")], [Vector2(247, 168), Forage.DRY_GRASS, Color("#bd9559")],
		[Vector2(198, 178), Forage.DRY_GRASS, Color("#d4ae6d")], [Vector2(267, 151), Forage.DRY_GRASS, Color("#c7a063")],
	]:
		var item := Floater.new(from_screen(row[0]), false, -0.28 if row[0].y > 100.0 else 0.31)
		item.forage = row[1]
		item.tint = row[2]
		item.rooted = item.forage in [Forage.FLOWER, Forage.FOXTAIL]
		floaters.append(item)
	held_floater = null
	hovered_floater = null
	streaks.clear()
	for i in 150:
		streaks.append(streak_origin(i, 0.0))
	held = null
	hovered = null
	hovered_pipe = null
	hovered_animal = Vector3.ZERO
	hovered_hearth = false
	preview_support = null
	preview_pipe_host = null
	preview_bank_drop = false
	preview_active = false
	pry_mode = false

func burst(point: Vector2, strength: float) -> void:
	var screen := to_screen(point)
	droplets.append(Vector4(screen.x, screen.y, 0.0, strength))
	if is_wet(point):
		ripples.append(Vector4(point.x, point.y, 0.0, strength))

func material_touch(point: Vector2, mud: bool) -> void:
	var screen := to_screen(point)
	var wet := is_wet(point)
	stimuli.emit_event(WorldStimulus.Kind.SPLASH, screen, point, Vector2.ZERO, 78.0, 0.40 if mud else 0.62, wet, &"material")
	if not wet:
		return
	burst(point, 0.40 if mud else 0.62)
	if mud:
		water.cloud(point, 0.28)

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
	stimuli.emit_event(WorldStimulus.Kind.SURGE, to_screen(point), point, Vector2.RIGHT * strength * 40.0, 78.0, strength, true, &"surge")
	if is_wet(point + Vector2(7.0, 0.0)):
		ripples.append(Vector4(point.x + 7.0, point.y, 0.0, minf(strength * 0.27, 0.40)))

func track_release(origin_x: float) -> void:
	if release_time <= 0.0:
		for x in Flow.COLUMNS:
			var at := (x + 0.5) * Flow.DX
			quiet_flow[x] = water.discharge_at(at)
			quiet_depth[x] = water.channel_depth(at)
		last_crest_x = -1.0
		release_start = origin_x
	else:
		release_start = minf(release_start, origin_x)
	release_time = 9.0

func advance_surge(dt: float) -> void:
	release_time = maxf(0.0, release_time - dt)
	var crest_x := -1.0
	for x in Flow.COLUMNS:
		var at := (x + 0.5) * Flow.DX
		var gain := water.discharge_at(at) - quiet_flow[x]
		var rise := water.channel_depth(at) - quiet_depth[x]
		var push := smoothstep(0.009, 0.085, rise) * smoothstep(0.06, 0.39, gain)
		if release_time <= 0.0 or at < release_start + Flow.DX:
			push = 0.0
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
				burst(rock.point, strength * (0.52 if release_time > 0.0 else 1.0))
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
	var closest: Floater
	var best := INF
	for item in floaters:
		if item.forage != Forage.NONE:
			if world.season == SeasonProfile.Season.WINTER and item.rooted and item.forage == Forage.FLOWER:
				continue
			var base := forage_screen(item)
			var tip := base + forage_axis(item)
			var near := Geometry2D.get_closest_point_to_segment(cursor, base, tip).distance_to(cursor)
			if near < best and near <= (3.8 if item.forage == Forage.FLOWER else 3.0):
				closest = item
				best = near
			continue
		var radius := 10.0 if item.twig else 7.0
		var distance := cursor.distance_to(to_screen(item.point))
		if distance <= radius and distance < best:
			closest = item
			best = distance
	return closest

func decoration_host(cursor: Vector2) -> Pool.Piece:
	var best: Pool.Piece
	var distance := INF
	for group in [model.wall, lower.wall]:
		for piece: Pool.Piece in group:
			var offset := cursor - piece_screen(piece)
			var score := Vector2(offset.x, offset.y * 1.25).length()
			if score < distance and score <= piece.radius * 0.84:
				best = piece
				distance = score
	return best

func can_place_floater(item: Floater, cursor: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, SIZE).has_point(cursor):
		return false
	if hearth.contains(cursor):
		return can_fuel_hearth(item)
	if item.forage == Forage.THIN_BRANCH and not on_bank(cursor):
		return not blocked_at(model, from_screen(cursor), 1.0) and not blocked_at(lower, from_screen(cursor), 1.0)
	return true

func place_floater(item: Floater, cursor: Vector2) -> void:
	if not can_place_floater(item, cursor):
		return
	if hearth.contains(cursor):
		if item.forage == Forage.NONE and not item.twig:
			hearth.flare_tinder(0.20, 5)
			floaters.erase(item)
			return
		if item.soaked >= 0.35 and hearth.burning:
			hearth.douse(0.22, true)
		hearth.add(item.is_firewood())
		floaters.erase(item)
		return
	if item.rooted and item.forage in [Forage.FLOWER, Forage.FOXTAIL]:
		ground_traces.add_pluck_mark(to_screen(item.shore))
	item.point = from_screen(cursor)
	item.rooted = false
	item.host = null
	var wet := is_wet(item.point)
	item.planted = item.forage == Forage.THIN_BRANCH and not on_bank(cursor)
	item.age = 0.0
	if item.forage in [Forage.FLOWER, Forage.FOXTAIL]:
		item.host = decoration_host(cursor)
		if item.host != null:
			item.host_offset = cursor - piece_screen(item.host)
	item.afloat = wet and item.host == null and not item.planted
	item.drift = Vector2.ZERO
	item.caught = false
	if item.ambient:
		item.ambient = false
		item.shore = Vector2(57.0, 60.0)
	if wet and item.host == null and not item.planted:
		burst(item.point, 0.15)

func can_fuel_hearth(item: Floater) -> bool:
	if item.forage == Forage.NONE and not item.twig:
		return hearth.burning and not item.afloat and item.soaked < 0.35
	var dry_ok := item.soaked < 0.35 or (hearth.burning and hearth.heat > 0.25)
	return (item.is_firewood() or item.forage == Forage.DRY_GRASS) and dry_ok and (
		not item.afloat and (not item.planted or not is_wet(item.point))) and hearth.can_add(item.is_firewood())

func ignite_hearth(point: Vector2) -> bool:
	if hearth.contains(point) and hearth.can_ignite():
		hearth.ignite()
		stimuli.emit_event(WorldStimulus.Kind.HEAT_IGNITE, Hearth.CENTER, from_screen(Hearth.CENTER), Vector2.ZERO, 72.0, 1.0, false, &"hearth")
		return true
	return false

func set_day_stage(stage: int) -> void:
	day_target = float(clampi(stage, 0, 2))

func set_season(next_season: SeasonProfile.Season) -> void:
	world.set_season(next_season)
	apply_season_visuals(next_season)
	# Sync wildflowers and foxtails to the active season palette.
	var fcols: Array[Color] = world.profile.flower_colors
	var fxcols: Array[Color] = world.profile.foxtail_colors
	var f_idx := 0
	var fx_idx := 0
	for item in floaters:
		if item.forage == Forage.FLOWER and not fcols.is_empty():
			item.tint = fcols[f_idx % fcols.size()]
			f_idx += 1
		elif item.forage == Forage.FOXTAIL and not fxcols.is_empty():
			item.tint = fxcols[fx_idx % fxcols.size()]
			fx_idx += 1
	if world.profile.species_weight(&"cicada") <= 0.05:
		summer.cicada_singing = false
		summer.cicada_sing_level = 0.0
	queue_redraw()

func apply_season_visuals(season: SeasonProfile.Season) -> void:
	var ground_tex := Scenery.ground_for_season(season)
	if terrain_sprite != null:
		terrain_sprite.texture = ground_tex
	if water_sprite != null:
		water_sprite.texture = PLATE if season == SeasonProfile.Season.AUTUMN else ground_tex
	painted_ground = ground_tex.get_image()
	scenery.set_season(season)
	var winter_val := 1.0 if season == SeasonProfile.Season.WINTER else 0.0
	ground_light.set_shader_parameter("winter_amount", winter_val)
	surface.set_shader_parameter("winter_amount", winter_val)

func current_day_stage() -> int:
	if day_phase < 0.5:
		return 0
	return 1 if day_phase < 1.45 else 2

func trigger_snapshot_flash() -> void:
	snapshot_flash = 1.0

func has_discovery_hint() -> bool:
	if held_pipe != null:
		for basin: Pool in [model, lower]:
			for piece in basin.wall:
				if piece.kind == Pool.EARTH and not basin.pipes.any(func(p: Pool.DrainPipe) -> bool: return p != held_pipe and p.host == piece):
					return true
		return false
	if held_floater != null:
		if can_fuel_hearth(held_floater):
			return true
		if held_floater.forage in [Forage.FLOWER, Forage.FOXTAIL]:
			return not model.wall.is_empty() or not lower.wall.is_empty()
		return false
	if squirt_gun.held:
		return squirt_gun.water_fill < 0.08 and not squirt_gun.drawing
	return not holding_animal() and held == null and hearth.can_ignite()

func screen_in_water(point: Vector2) -> bool:
	return not on_bank(point) and is_wet(from_screen(point))

func on_squirt_draw_ripple(screen_pt: Vector2) -> void:
	var local := from_screen(screen_pt)
	if is_wet(local) and ripples.size() < 28:
		ripples.append(Vector4(local.x, local.y, 0.0, 0.16))

func register_stimulus_listeners() -> void:
	stimuli.clear_listeners()
	stimuli.subscribe(&"water_ripples", func(ev: WorldStimulus.Stimulus) -> void:
		if ev.kind == WorldStimulus.Kind.WATER_JET and ev.wet:
			if ripples.size() < 28 and fposmod(clock * 19.0 + ev.screen_pos.x * 0.37, 1.0) < 0.36:
				ripples.append(Vector4(ev.world_pos.x, ev.world_pos.y, 0.0, 0.14 + ev.strength * 0.12))
			summer.disturb_water(ev.world_pos, 0.32 * ev.strength, false)
		elif ev.kind == WorldStimulus.Kind.SPLASH and ev.wet:
			summer.disturb_water(ev.world_pos, ev.strength, false)
		elif ev.kind == WorldStimulus.Kind.SURGE:
			summer.disturb_water(ev.world_pos, ev.strength, true)
	)
	stimuli.subscribe(&"floaters_and_boat", func(ev: WorldStimulus.Stimulus) -> void:
		if ev.kind == WorldStimulus.Kind.WATER_JET:
			var dir := ev.velocity.normalized() if ev.velocity.length_squared() > 0.01 else Vector2.RIGHT
			if boat.burned_timer <= 0.0 and not boat.held and boat.screen_pos(to_screen, pointer).distance_to(ev.screen_pos) < 13.0:
				boat.soak(0.11 * ev.strength)
				if boat.afloat:
					boat.nudge(dir * (14.5 * ev.strength))
			for item in floaters:
				if item == held_floater:
					continue
				var item_pt := forage_screen(item) if item.forage != Forage.NONE else to_screen(item.point)
				if item_pt.distance_to(ev.screen_pos) < 10.5:
					if item.afloat:
						item.drift = (item.drift + dir * (9.5 * ev.strength)).limit_length(74.0)
					if item.is_firewood() or item.forage == Forage.DRY_GRASS or (item.forage == Forage.NONE and not item.twig):
						item.soaked = minf(1.0, item.soaked + 0.28 * ev.strength)
		elif ev.kind == WorldStimulus.Kind.SPLASH and ev.wet:
			# Radial splash wave from dropped stones rocks and pushes nearby paper boat & floaters.
			if boat.afloat and not boat.held and boat.burned_timer <= 0.0:
				var boat_pt := boat.screen_pos(to_screen, pointer)
				var delta := boat_pt - ev.screen_pos
				var dist := delta.length()
				if dist < 38.0:
					var falloff := 1.0 - dist / 38.0
					var push_dir := delta.normalized() if dist > 0.5 else Vector2.RIGHT
					boat.nudge(push_dir * (22.0 * falloff * ev.strength))
					boat.soak(0.06 * falloff * ev.strength)
			for item in floaters:
				if item.afloat and item != held_floater:
					var delta := to_screen(item.point) - ev.screen_pos
					var dist := delta.length()
					if dist < 34.0:
						var falloff := 1.0 - dist / 34.0
						var push_dir := delta.normalized() if dist > 0.5 else Vector2.RIGHT
						item.drift = (item.drift + push_dir * (16.0 * falloff * ev.strength)).limit_length(72.0)
	)
	stimuli.subscribe(&"hearth", func(ev: WorldStimulus.Stimulus) -> void:
		if ev.kind == WorldStimulus.Kind.WATER_JET and (hearth.contains(ev.screen_pos) or ev.screen_pos.distance_to(Hearth.CENTER) < 15.0):
			hearth.douse(0.12 * ev.strength, true)
		elif ev.kind == WorldStimulus.Kind.SPLASH and ev.wet and ev.screen_pos.distance_to(Hearth.CENTER) < 30.0:
			hearth.douse(0.08 * ev.strength, true)
	)
	stimuli.subscribe(&"dam_earth", func(ev: WorldStimulus.Stimulus) -> void:
		if ev.kind != WorldStimulus.Kind.WATER_JET:
			return
		for basin: Pool in [model, lower]:
			for piece in basin.wall:
				if piece.kind == Pool.EARTH and piece_screen(piece).distance_to(ev.screen_pos) <= piece.radius + 2.0:
					water.cloud(piece.point, 0.055 * ev.strength)
					piece.wear = minf(0.95, piece.wear + 0.007 * ev.strength)
	)
	stimuli.subscribe(&"fauna", func(ev: WorldStimulus.Stimulus) -> void:
		bird.disturb(ev.screen_pos, ev.radius)
		if ev.kind == WorldStimulus.Kind.WATER_JET:
			summer.disturb_perch(ev.screen_pos)
			if not crab.held and crab.position.distance_to(ev.screen_pos) < 12.0:
				crab.alert = maxf(crab.alert, 0.95)
				crab.snip = maxf(crab.snip, 0.85)
			if not frog.held and frog.duration <= 0.0 and frog.screen_point().distance_to(ev.screen_pos) < 11.0:
				frog.pause = minf(frog.pause, 0.08)
			if not summer.cicada_held and summer.cicada_position.distance_to(ev.screen_pos) < 11.0 and summer.cicada_singing:
				summer.cicada_singing = false
				summer.cicada_sing_level = 0.0
				summer.cicada_startled.emit()
		elif ev.kind == WorldStimulus.Kind.SPLASH and ev.wet:
			if not crab.held and crab.position.distance_to(ev.screen_pos) < 26.0:
				crab.alert = maxf(crab.alert, 0.90)
				crab.snip = maxf(crab.snip, 0.80)
			if not frog.held and frog.duration <= 0.0 and frog.screen_point().distance_to(ev.screen_pos) < 24.0:
				frog.pause = minf(frog.pause, 0.06)
	)
	stimuli.subscribe(&"ground_traces", func(ev: WorldStimulus.Stimulus) -> void:
		if ev.kind == WorldStimulus.Kind.WATER_JET and not ev.wet and on_bank(ev.screen_pos) and not hearth.contains(ev.screen_pos):
			ground_traces.add_damp_spot(ev.screen_pos, 3.2 + ev.strength * 1.8)
	)

func on_squirt_impact(screen_pt: Vector2, vel: Vector2, pressure: float, wet_hit: bool) -> void:
	stimuli.emit_event(WorldStimulus.Kind.WATER_JET, screen_pt, from_screen(screen_pt), vel, 28.0, pressure, wet_hit, &"squirt_gun")

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
		if item.is_firewood() or item.forage == Forage.DRY_GRASS:
			if item.afloat or (item.planted and is_wet(item.point)):
				item.soaked = 1.0
			else:
				item.soaked = clampf(item.soaked + dt * (rain.intensity * 0.31 - 0.15), 0.0, 1.0)
		if item.planted and item != held_floater:
			item.age = minf(1.0, item.age + dt)
		if item.host != null:
			item.point = from_screen(forage_screen(item))
			if not model.wall.has(item.host) and not lower.wall.has(item.host):
				item.host = null
				item.afloat = is_wet(item.point)
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
	snapshot_flash = move_toward(snapshot_flash, 0.0, dt * 2.1)
	if day_target >= 0.0:
		day_phase = move_toward(day_phase, day_target, dt * 0.45)
	elif auto_day_cycle:
		day_phase = minf(2.0, day_phase + dt * 0.0032)
	wind.advance(dt)
	hearth.advance(dt, rain.intensity, wind)
	flora.advance(dt, surge_at)
	var hearth_glow := Vector3(Hearth.CENTER.x / SIZE.x, Hearth.CENTER.y / SIZE.y, hearth.firelight)
	scenery.advance(dt, wind, rain.wetness, rain.intensity, hearth_glow, day_phase)
	advance_surge(dt)
	advance_riffle(dt)
	advance_floaters(dt)
	for piece in bank:
		piece.bounce = move_toward(piece.bounce, 0.0, dt * 4.6)
	for piece in riffle:
		piece.bounce = move_toward(piece.bounce, 0.0, dt * 4.6)
	boat.advance(dt, water, wind, rain.intensity, surge_at, clear_float_path, can_float_at, is_wet, pipes, boat_ripple)
	squirt_gun.advance(dt, pointer, wind, screen_in_water, on_squirt_impact, on_squirt_draw_ripple, squirt_mouse_down)
	advance_streaks(dt)
	summer.flower_perches.clear()
	for item in floaters:
		if item.host != null and item.forage in [Forage.FLOWER, Forage.FOXTAIL]:
			summer.flower_perches.append(forage_screen(item) + Vector2(0.0, -4.5))
	var upper_p := pool_profile(model, 146.0)
	var lower_p := pool_profile(lower, 262.0)
	var pool_richness := smoothstep(0.16, 0.52, maxf(upper_p.y, lower_p.y))
	world.sync(day_phase, rain.intensity, rain.wetness, rain.after_rain, wind.strength_at(0.5), pool_richness, hearth.firelight)
	ground_traces.advance(dt, world, Hearth.CENTER, hearth.firelight)
	# Cross-object thermal & flood physics: campfire warmth dries nearby damp items; high water douses fire.
	if hearth.firelight > 0.12:
		if not boat.afloat and not boat.held and boat.burned_timer <= 0.0:
			var b_dist := boat.screen_pos(to_screen, pointer).distance_to(Hearth.CENTER)
			if b_dist < 46.0:
				boat.dry_near_fire(dt * hearth.firelight * (1.0 - b_dist / 46.0) * 0.55)
		for item in floaters:
			if item.soaked > 0.0 and not item.afloat and item != held_floater:
				var f_pt := forage_screen(item) if item.forage != Forage.NONE else to_screen(item.point)
				var f_dist := f_pt.distance_to(Hearth.CENTER)
				if f_dist < 46.0:
					item.soaked = maxf(0.0, item.soaked - dt * hearth.firelight * (1.0 - f_dist / 46.0) * 0.55)
	if hearth.burning and water.depth_at(from_screen(Hearth.CENTER)) > 0.06:
		hearth.douse(dt * 1.4, true)
	if rain.after_rain > 0.85 and not post_rain_nudged:
		post_rain_nudged = true
		frog.nudge_call(2.2)
	elif rain.after_rain < 0.10:
		post_rain_nudged = false
	summer.advance(dt, water, rain.intensity, day_phase, pool_richness, rain.after_rain)
	if world.profile.species_weight(&"cicada") <= 0.05:
		summer.cicada_singing = false
		summer.cicada_sing_level = 0.0
	ground_insects.frog_blocker = frog.position if (frog.duration <= 0.0 and world.profile.species_weight(&"frog") > 0.05) else Vector2.INF
	ground_insects.crab_blocker = crab.position if not crab.held else Vector2.INF
	refresh_insect_terrain()
	bird.advance(dt, pointer, rain.intensity, ground_insects.rocks, bird_spot_wet,
		day_phase, rain.after_rain, rain.active_puddle_spots(), Hearth.CENTER, hearth.firelight > 0.15)
	ground_insects.advance(dt, to_screen, from_screen, insect_in_water, insect_ripple, day_phase)
	var twilight_calm := smoothstep(1.10, 1.85, day_phase)
	var frog_activity := clampf(maxf(smoothstep(0.80, 1.85, day_phase), rain.after_rain * 0.85), 0.0, 1.0) * world.profile.species_weight(&"frog")
	frog.advance(dt, frog_clear, frog_activity, twilight_calm)
	var pointer_busy := holding_animal() or held != null or held_pipe != null or held_floater != null or squirt_gun.held
	crab.advance(dt, pointer, pointer_busy, ground_insects.rocks, to_screen, from_screen, insect_in_water,
		water, surge_at, crab_clear, insect_ripple, [ground_insects.mole.position, ground_insects.mantis.position, frog.position], day_phase)
	for crawler in [ground_insects.mole, ground_insects.mantis]:
		if crawler != ground_insects.held:
			summer.disturb_perch(crawler.position)
	if not crab.held:
		summer.disturb_perch(crab.position)
	air.advance(dt)
	rain.advance_drops(dt, self)
	sync_surface(dt)
	surface.set_shader_parameter("creek_time", clock)
	surface.set_shader_parameter("upper_pool", upper_p)
	surface.set_shader_parameter("lower_pool", lower_p)
	var trail := wind.trail()
	ground_light.set_shader_parameter("wind_trail", trail)
	ground_light.set_shader_parameter("canopy_flutter", wind.canopy_flutter())
	ground_light.set_shader_parameter("sun_drift", wind.sunlight)
	ground_light.set_shader_parameter("day_phase", day_phase)
	surface.set_shader_parameter("wind_trail", trail)
	surface.set_shader_parameter("wind_travel", wind.travel)
	surface.set_shader_parameter("sun_drift", wind.sunlight)
	surface.set_shader_parameter("day_phase", day_phase)
	surface.set_shader_parameter("hearth_light", hearth_glow)
	ground_light.set_shader_parameter("rain_wetness", rain.wetness)
	ground_light.set_shader_parameter("rain_intensity", rain.intensity)
	ground_light.set_shader_parameter("hearth_light", hearth_glow)
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
	if not summer.cicada_held:
		ground_insects.add_rock(summer.cicada_position, Vector2(4.5, 3.0), GroundInsects.CLIMB_LIMIT + 1.0)
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

func bird_spot_wet(point: Vector2) -> bool:
	return not on_bank(point) or insect_in_water(from_screen(point))

func insect_ripple(point: Vector2) -> void:
	ripples.append(Vector4(point.x, point.y, 0.0, 0.15))

func boat_ripple(point: Vector2, strength := 0.18) -> void:
	ripples.append(Vector4(point.x, point.y, 0.0, strength))

func frog_clear(point: Vector2) -> bool:
	if not summer.cicada_held and point.distance_to(summer.cicada_position) < 7.5:
		return false
	if not crab.held and point.distance_to(crab.position) < 10.0:
		return false
	return point.distance_to(ground_insects.mole.position) >= GroundInsects.CLEARANCE and point.distance_to(ground_insects.mantis.position) >= 12.0 and (
		summer.insect_state != Summer.Flight.PERCHED or point.distance_to(summer.insect_position) >= 9.0)

func crab_clear(point: Vector2) -> bool:
	if not summer.cicada_held and point.distance_to(summer.cicada_position) < 7.5:
		return false
	if not frog.held and point.distance_to(frog.position) < 10.0:
		return false
	return point.distance_to(ground_insects.mole.position) >= GroundInsects.CLEARANCE and point.distance_to(ground_insects.mantis.position) >= 11.0 and (
		summer.insect_state != Summer.Flight.PERCHED or point.distance_to(summer.insect_position) >= 8.5)

func on_frog_landed(point: Vector2) -> void:
	var local := from_screen(point)
	if insect_in_water(local):
		burst(local, 0.31)

func on_crab_landed(point: Vector2) -> void:
	var local := from_screen(point)
	if insect_in_water(local):
		burst(local, 0.25)

func holding_animal() -> bool:
	return ground_insects.held != null or summer.insect_held or summer.fish_held or frog.held or crab.held or summer.cicada_held

func cancel_animal_grab() -> void:
	ground_insects.held = null
	summer.insect_held = false
	summer.fish_held = false
	frog.held = false
	crab.held = false
	summer.cicada_held = false

func grab_animal(point: Vector2) -> bool:
	if ground_insects.grab(point):
		return true
	if crab.position.distance_to(point) <= 7.5:
		crab.held = true
		return true
	if world.profile.species_weight(&"cicada") > 0.05 and summer.cicada_position.distance_to(point) <= 6.0:
		summer.grab_cicada()
		return true
	if world.profile.species_weight(&"dragonfly") > 0.05:
		summer.insect_held = summer.insect_position.distance_to(point) <= 9.0
		if summer.insect_held:
			return true
	if world.profile.species_weight(&"frog") > 0.05:
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
	if not crab.held and point.distance_to(crab.position) < 9.5:
		return false
	if not summer.cicada_held and point.distance_to(summer.cicada_position) < 6.0:
		return false
	if summer.cicada_held and summer.insect_state == Summer.Flight.PERCHED and point.distance_to(summer.insect_position) < 8.0:
		return false
	if crab.held:
		return crab_clear(point)
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
	if crab.held:
		crab.place(point, wet)
		return
	if frog.held:
		frog.place(point)
		on_frog_landed(point)
		return
	elif summer.fish_held:
		summer.place_fish(local, wet and water.depth_at(local) >= 0.13)
	elif summer.cicada_held:
		summer.place_cicada(point, wet)
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

func animal_hover_target(point: Vector2) -> Vector3:
	var mole_pos := ground_insects.mole.position - Vector2(0, ground_insects.mole.elevation)
	var mantis_pos := ground_insects.mantis.position - Vector2(0, ground_insects.mantis.elevation)
	var mole_dist := mole_pos.distance_to(point)
	var mantis_dist := mantis_pos.distance_to(point)
	if mole_dist <= 5.0 and mole_dist <= mantis_dist:
		return Vector3(mole_pos.x, mole_pos.y, 5.5)
	if mantis_dist <= 7.0:
		return Vector3(mantis_pos.x, mantis_pos.y, 7.5)
	if crab.position.distance_to(point) <= 7.5:
		return Vector3(crab.position.x, crab.position.y, 6.5)
	if world.profile.species_weight(&"cicada") > 0.05 and summer.cicada_position.distance_to(point) <= 6.0:
		return Vector3(summer.cicada_position.x, summer.cicada_position.y, 6.0)
	if world.profile.species_weight(&"dragonfly") > 0.05 and summer.insect_position.distance_to(point) <= 9.0:
		return Vector3(summer.insect_position.x, summer.insect_position.y, 5.5)
	var frog_pos := frog.screen_point()
	if world.profile.species_weight(&"frog") > 0.05 and frog_pos.distance_to(point) <= 7.0:
		return Vector3(frog_pos.x, frog_pos.y, 6.0)
	if summer.fish_time >= 0.25:
		var fish_pos := to_screen(summer.fish)
		if fish_pos.distance_to(point) <= 7.0:
			return Vector3(fish_pos.x, fish_pos.y, 6.5)
	return Vector3.ZERO

func env_modulate(screen_pos: Vector2) -> Color:
	var uv := (screen_pos / SIZE).clamp(Vector2.ZERO, Vector2.ONE)
	var shade := Wind.canopy_cover(uv)
	var p := clampf(day_phase, 0.0, 2.0)
	var dusk := smoothstep(0.0, 1.0, p) * (1.0 - smoothstep(1.0, 2.0, p))
	var twi := smoothstep(0.85, 2.0, p)
	var sun_factor := (0.62 + wind.sunlight.z * 0.38) * (1.0 - rain.intensity * 0.75) * (1.0 - twi * 0.85)
	var light := Color.WHITE.lerp(Color(0.84, 0.89, 0.95), shade * 0.42)
	light = light.lerp(Color(1.04, 1.01, 0.95), (1.0 - shade) * sun_factor * 0.22)
	if dusk > 0.001:
		var sun_side := smoothstep(0.18, 0.77, uv.x + (1.0 - uv.y) * 0.34)
		var sunset_grade := Color(0.84, 0.81, 0.94).lerp(Color(1.13, 0.90, 0.70), sun_side)
		light = light.lerp(light * sunset_grade, dusk)
	if twi > 0.001:
		light = light.lerp(light * Color(0.58, 0.69, 0.90), twi)
	light *= Color.WHITE.lerp(Color(0.75, 0.82, 0.90), rain.wetness * 0.82)
	if hearth.firelight > 0.005:
		var reach := 48.0 * (1.0 + dusk * 0.12 + twi * 0.34)
		var d := screen_pos.distance_to(Hearth.CENTER)
		var evening_boost := 1.0 + dusk * 0.45 + twi * 1.15
		var glow := pow(maxf(0.0, 1.0 - d / reach), 2.0) * hearth.firelight * (0.72 + rain.wetness * 0.38) * evening_boost
		light += Color(0.28, 0.13, 0.035, 0.0) * glow
	return Color(light.r, light.g, light.b, 1.0)

func foam_ink(alpha := 1.0) -> Color:
	var p := clampf(day_phase, 0.0, 2.0)
	var dusk := smoothstep(0.0, 1.0, p) * (1.0 - smoothstep(1.0, 2.0, p))
	var twi := smoothstep(0.85, 2.0, p)
	var tone := Color("#dceee2").lerp(Color("#c7dfdf"), rain.intensity)
	tone = tone.lerp(Color("#e8c8a2"), dusk * 0.65)
	tone = tone.lerp(Color("#88a5c2"), twi * 0.72)
	return Color(tone, alpha)

func shade_color(base: Color, screen_pos: Vector2) -> Color:
	var mod := env_modulate(screen_pos)
	return Color(base.r * mod.r, base.g * mod.g, base.b * mod.b, base.a)

func _draw() -> void:
	if water == null:
		return
	summer.draw_fish(self, to_screen, pointer)
	if crab.wet and not crab.held:
		crab.draw(self, pointer, shade_color)
	draw_pond_edge(model, 146.0)
	draw_pond_edge(lower, 262.0)
	draw_current()
	draw_surge_current()
	draw_ripples()
	draw_shore_bubbles()
	flora.draw(self, world, shade_color, foam_ink())
	rain.draw_puddles(self)
	ground_traces.draw(self, shade_color)
	summer.draw_land(self, shade_color, world.profile.id)
	var hearth_hover := hearth.contains(pointer) and (hearth.can_ignite() if held_floater == null else can_fuel_hearth(held_floater))
	hearth.draw_bed(self, hearth_hover)
	if hovered_hearth:
		draw_hover_halo(self, Hearth.CENTER, Hearth.RADIUS.x + 1.5, Hearth.RADIUS.y + 1.5, Color("#f2bd74"))
	hearth.draw_fuel(self)
	for stone in hearth_rim:
		var reflection := hearth.firelight * (1.0 - smoothstep(5.0, 16.0, stone.point.length()))
		draw_rock(stone, Hearth.CENTER + stone.point, 0.0, maxf(hearth.dampness * 0.5, rain.wetness * 0.24), 0.0, true, 0.83, reflection)
	var mantis_ok := world.profile.species_weight(&"mantis") > 0.05
	ground_insects.draw(self, pointer, true, scenery.in_front_of_ledge, false, shade_color, mantis_ok)
	draw_materials()
	draw_pipes()
	draw_seams(model)
	draw_seams(lower)
	draw_breach_jet(upper_breach)
	draw_breach_jet(lower_breach)
	draw_froth()
	draw_floaters()
	ground_insects.draw(self, pointer, false, scenery.in_front_of_ledge, false, shade_color, mantis_ok)
	if world.profile.species_weight(&"dragonfly") > 0.05 or summer.insect_held:
		summer.draw_insect(self, pointer, shade_color)
	if (world.profile.species_weight(&"cicada") > 0.05 or summer.cicada_held) and not scenery.in_front_of_ledge(pointer if summer.cicada_held else summer.cicada_position):
		summer.draw_cicada(self, pointer, shade_color)
	summer.draw_fish(self, to_screen, pointer, true)
	if (world.profile.species_weight(&"frog") > 0.05 or frog.held) and not scenery.in_front_of_ledge(pointer if frog.held else frog.position):
		frog.draw(self, pointer, shade_color)
	if (not crab.wet or crab.held) and not scenery.in_front_of_ledge(pointer if crab.held else crab.position):
		crab.draw(self, pointer, shade_color)
	if not bird.is_airborne() and not scenery.in_front_of_ledge(bird.position):
		bird.draw(self, shade_color)
	hearth.draw_flame(self)

func draw_shore_foreground() -> void:
	var layer := scenery.foreground
	var mantis_ok := world.profile.species_weight(&"mantis") > 0.05
	ground_insects.draw(layer, pointer, true, scenery.in_front_of_ledge, true, shade_color, mantis_ok)
	ground_insects.draw(layer, pointer, false, scenery.in_front_of_ledge, true, shade_color, mantis_ok)
	if (world.profile.species_weight(&"cicada") > 0.05 or summer.cicada_held) and scenery.in_front_of_ledge(pointer if summer.cicada_held else summer.cicada_position):
		summer.draw_cicada(layer, pointer, shade_color)
	if (world.profile.species_weight(&"frog") > 0.05 or frog.held) and scenery.in_front_of_ledge(pointer if frog.held else frog.position):
		frog.draw(layer, pointer, shade_color)
	if (not crab.wet or crab.held) and scenery.in_front_of_ledge(pointer if crab.held else crab.position):
		crab.draw(layer, pointer, shade_color)
	if bird.is_airborne() or scenery.in_front_of_ledge(bird.position):
		bird.draw(layer, shade_color)
	rain.draw_drops(layer, world.season == SeasonProfile.Season.WINTER)
	squirt_gun.draw_stream(layer, shade_color, foam_ink())
	if squirt_gun.held:
		squirt_gun.draw_gun(layer, pointer, shade_color, foam_ink())
	draw_discovery_hints(layer)
	if hovered_animal.z > 0.0:
		draw_hover_halo(layer, Vector2(hovered_animal.x, hovered_animal.y), hovered_animal.z, hovered_animal.z * 0.78)
	if holding_animal() or held != null or held_pipe != null or held_floater != null or boat.held:
		draw_drop_hint(layer)
	if snapshot_flash > 0.01:
		draw_snapshot_frame(layer)

func draw_discovery_hints(canvas: Node2D) -> void:
	var pulse := 0.65 + 0.35 * sin(clock * 3.6)
	if held_pipe != null:
		for basin: Pool in [model, lower]:
			for piece in basin.wall:
				if piece.kind != Pool.EARTH or piece == preview_pipe_host:
					continue
				if basin.pipes.any(func(p: Pool.DrainPipe) -> bool: return p != held_pipe and p.host == piece):
					continue
				var at := piece_screen(piece)
				draw_dashed_ellipse(canvas, at, piece.radius * 0.90, piece.radius * 0.56,
					Color("#a8e8d8", 0.74 * pulse), Color("#162825", 0.56 * pulse), 10)
		return
	if held_floater != null:
		if can_fuel_hearth(held_floater) and not hearth.contains(pointer):
			draw_dashed_ellipse(canvas, Hearth.CENTER, Hearth.RADIUS.x + 1.5, Hearth.RADIUS.y + 1.5,
				Color("#f7c97e", 0.78 * pulse), Color("#26170e", 0.58 * pulse), 12)
			for i in 2:
				var lift := fposmod(clock * 0.65 + i * 0.5, 1.0)
				var speck := snap_pixel(Hearth.CENTER + Vector2((i - 0.5) * 8.0, -3.5 - lift * 6.0))
				canvas.draw_rect(Rect2(speck, Vector2(1.0, 1.0)), Color("#fde2a4", (1.0 - lift) * 0.80 * pulse))
		elif held_floater.forage in [Forage.FLOWER, Forage.FOXTAIL]:
			var hovered_host := decoration_host(pointer)
			for basin: Pool in [model, lower]:
				for piece in basin.wall:
					if piece == hovered_host or piece.kind != Pool.STONE:
						continue
					var crown := snap_pixel(piece_screen(piece) - Vector2(0.0, piece.radius * 0.35))
					var sparkle := Color("#fceab8", 0.78 * pulse)
					canvas.draw_rect(Rect2(crown - Vector2(1.5, 0.0), Vector2(3.5, 0.5)), sparkle)
					canvas.draw_rect(Rect2(crown - Vector2(0.0, 1.5), Vector2(0.5, 3.5)), sparkle)
		return
	if squirt_gun.held:
		if squirt_gun.water_fill < 0.08 and not squirt_gun.drawing:
			var gx := clampf(pointer.x, 42.0, 278.0)
			var water_spot := snap_pixel(Vector2(gx, shoreline(CHANNEL_Y, gx)))
			draw_dashed_ellipse(canvas, water_spot, 10.5, 4.8,
				Color("#a8e8d8", 0.72 * pulse), Color("#162825", 0.52 * pulse), 10)
			for i in 2:
				var drop_p := fposmod(clock * 0.9 + i * 0.5, 1.0)
				var bead := snap_pixel(water_spot + Vector2((i - 0.5) * 6.0, -4.5 + drop_p * 4.5))
				canvas.draw_rect(Rect2(bead, Vector2(1.0, 0.5)), Color("#d4f4e8", (1.0 - drop_p) * 0.85))
		return
	if not holding_animal() and held == null and hearth.can_ignite() and not hovered_hearth:
		for i in 2:
			var phase := fposmod(clock * 0.55 + i * 0.5, 1.0)
			var glint := snap_pixel(Hearth.CENTER + Vector2((i - 0.5) * 6.0 + sin(clock * 2.0 + i) * 1.2, -2.5 - phase * 4.5))
			canvas.draw_rect(Rect2(glint, Vector2(1.0, 1.0)), Color("#fad288", sin(phase * PI) * 0.82))

func draw_snapshot_frame(canvas: Node2D) -> void:
	var a := snapshot_flash * snapshot_flash
	canvas.draw_rect(Rect2(Vector2.ZERO, SIZE), Color(1.0, 0.97, 0.90, a * 0.14))
	var ink := Color(0.98, 0.94, 0.84, a * 0.82)
	var shadow := Color(0.12, 0.11, 0.08, a * 0.45)
	for corner in [
		[Vector2(8, 8), Vector2(1, 1)],
		[Vector2(SIZE.x - 8, 8), Vector2(-1, 1)],
		[Vector2(8, SIZE.y - 8), Vector2(1, -1)],
		[Vector2(SIZE.x - 8, SIZE.y - 8), Vector2(-1, -1)],
	]:
		var c: Vector2 = corner[0]
		var d: Vector2 = corner[1]
		var pts := PackedVector2Array([c + Vector2(d.x * 9.0, 0.0), c, c + Vector2(0.0, d.y * 9.0)])
		canvas.draw_polyline(pts, shadow, 2.0)
		canvas.draw_polyline(pts, ink, 0.75)

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
		var p := to_screen(at) - Vector2(0, minf(11.0, (h - 0.18) * 13.0) * height)
		var shimmer := 0.68 + sin(clock * 3.7 + piece.point.y * 0.36) * 0.23
		var extent := piece.radius * 0.42
		var curve := PackedVector2Array([snap_pixel(p + Vector2(2.2, -extent)), snap_pixel(p + Vector2(0.4, -extent * 0.5)),
			snap_pixel(p + Vector2(0.0, extent * 0.38)), snap_pixel(p + Vector2(1.4, extent))])
		draw_polyline(curve, Color(0.61, 0.79, 0.75, height * shimmer * 0.75), 0.5)
		if height > 0.35:
			var eddy := p + Vector2(-6.0 - shimmer * 4.0, extent * 0.2)
			draw_line(snap_pixel(eddy), snap_pixel(eddy + Vector2(3.2, -1.1)), foam_ink(height * shimmer * 0.27), 0.5)

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
		var end := at + v.normalized() * minf(8.5, 1.0 + speed * 0.105)
		if not is_wet(end):
			continue
		var strength := smoothstep(7.0, 57.0, speed)
		draw_line(from, snap_pixel(to_screen(end)), foam_ink(clampf(0.08 + (strength * 0.28 + push * 0.10) * foam_strength, 0.0, 0.52)), 0.5)

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
			var behind := at - axis * (2.2 + push * 5.0)
			if not is_wet(at) or not is_wet(behind):
				continue
			var start := snap_pixel(to_screen(behind))
			var end := snap_pixel(to_screen(at))
			draw_line(start, end, Color("#83b9b2", life * 0.30), 1.0)
			draw_line(snap_pixel(start.lerp(end, 0.51)), end, foam_ink(life * 0.48), 0.5)
			if push > 0.42:
				var foam := to_screen(at + axis.orthogonal() * sin(seed) * 2.1)
				draw_rect(Rect2(snap_pixel(foam), Vector2(1.5, 0.5)), foam_ink(life * 0.44))

func draw_ripples() -> void:
	for ripple in ripples:
		var center := Vector2(ripple.x, ripple.y)
		var elapsed := ripple.z
		center += water.velocity_at(center).limit_length(32.0) * (elapsed * 0.32)
		var radius := 1.8 + elapsed * (8.7 + ripple.w * 3.1)
		var ink := foam_ink((1.0 - smoothstep(0.13, 1.85, elapsed)) * minf(0.75, ripple.w * 0.91))
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
		var spill := jet + seam_axis * (2.0 + force * 3.0)
		if can_float_at(spill, 0.1):
			draw_line(snap_pixel(to_screen(jet)), snap_pixel(to_screen(spill)), Color(FOAM, force * 0.45), 0.5)
		for fleck in 3:
			var offset := fposmod(clock * (8.0 + best * 0.55) + fleck * 3.7, 5.0 + force * 6.0)
			var at := jet + seam_axis * offset + Vector2(0, sin(fleck * 2.0 + clock * 11.0) * 1.9 * force)
			if is_wet(at):
				draw_rect(Rect2(snap_pixel(to_screen(at)), Vector2(1.0 + force, 0.5)), Color(FOAM, 0.15 + force * 0.35))
	draw_dam_tension(basin, center)

func draw_dam_tension(basin: Pool, center: float) -> void:
	var head := pool_profile(basin, center).y
	var tension := smoothstep(0.34, 0.56, head)
	if tension <= 0.05:
		return
	# Pick at most 2 lowest, uncovered, highest-pressure points across the whole dam.
	var candidates: Array = []
	for piece in basin.wall:
		if piece.support != null:
			continue
		if basin.wall.any(func(other: Pool.Piece) -> bool: return other.support == piece):
			continue
		var up_depth := water.depth_at(piece.point - Vector2(piece.radius * 0.92, 0.0))
		if up_depth < 0.34:
			continue
		var emit_piece := piece
		for other in basin.wall:
			if other == piece or other.support != null:
				continue
			if other.point.x > emit_piece.point.x and other.point.x - piece.point.x < piece.radius + other.radius * 0.95 and absf(other.point.y - piece.point.y) < (piece.radius + other.radius) * 0.65:
				emit_piece = other
		var score := up_depth - piece.radius * 0.012 + (0.06 if emit_piece.kind == Pool.EARTH else 0.0)
		candidates.append([score, up_depth, emit_piece])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var shown := 0
	var used: Array[Pool.Piece] = []
	for item in candidates:
		if shown >= 2:
			break
		var up_depth: float = float(item[1])
		var piece: Pool.Piece = item[2]
		if used.has(piece):
			continue
		used.append(piece)
		var idx := shown
		shown += 1
		var p := piece_screen(piece)
		var wear_scale := (1.0 - piece.wear * 0.30) if piece.kind == Pool.EARTH else 1.0
		var reach := piece.radius * wear_scale
		var local_t := tension * lerpf(0.55, 1.0, smoothstep(0.34, 0.56, up_depth))
		# Subtle wet glint slipping off the downstream toe (no stiff lines across rocks).
		var seam_y := (0.18 if idx == 0 else -0.20) * reach
		var lip := snap_pixel(p + Vector2(reach * 0.62, seam_y))
		var glint := 0.45 + 0.55 * sin(clock * 3.0 + piece.shade * 1.7 + idx * 2.1)
		draw_rect(Rect2(lip, Vector2(1.0, 0.5)), foam_ink(local_t * glint * 0.34))
		# 2 tiny pixel seepage beads drifting from the outer downstream toe.
		for b in 2:
			var bp := fposmod(clock * (0.85 + b * 0.32) + piece.point.y * 0.17 + b * 0.52, 1.0)
			var drift_x := reach * 0.68 + bp * (2.5 + local_t * 2.2)
			var drift_y := seam_y + sin(bp * TAU + piece.shade) * 0.55 + bp * 0.65
			var drop_pos := snap_pixel(p + Vector2(drift_x, drift_y))
			var fade := sin(bp * PI) * local_t
			draw_rect(Rect2(drop_pos + Vector2(0.0, 0.5), Vector2(1.0, 0.5)), Color("#244747", fade * 0.28))
			draw_rect(Rect2(drop_pos, Vector2(0.5, 0.5)), foam_ink(fade * 0.44))
		# Faint silt wisp at a stressed mud toe.
		if piece.kind == Pool.EARTH:
			var sp := fposmod(clock * 0.68 + piece.point.y * 0.11, 1.0)
			var silt_pos := snap_pixel(p + Vector2(reach * 0.72 + sp * 3.5, seam_y + 0.5))
			draw_rect(Rect2(silt_pos, Vector2(1.5, 0.5)), Color("#6c5d45", local_t * sin(sp * PI) * 0.30))

func draw_breach_jet(event: Breach) -> void:
	if event == null or event.strength < 0.035 or event.phase not in [Breach.Phase.OPENING, Breach.Phase.JET]:
		return
	var mouth := event.origin + Vector2(7.0, 0.0)
	var flow := water.velocity_at(mouth)
	var end := mouth + flow.limit_length(24.0) * 0.18
	if flow.x > 3.0 and is_wet(mouth) and is_wet(end):
		draw_line(snap_pixel(to_screen(mouth)), snap_pixel(to_screen(end)), Color(FOAM, event.strength * 0.43 * foam_strength), 0.5)

func pipe_at(point: Vector2) -> Pool.DrainPipe:
	for pipe in pipes:
		var reach := Vector2(pipe.reach(), 0.0)
		var middle := pipe_screen(pipe)
		var start := middle - reach
		var end := middle + reach
		if pipe.host == null:
			if Geometry2D.get_closest_point_to_segment(point, start, end).distance_to(point) <= 3.0:
				return pipe
		elif point.distance_to(start + Vector2(2, 0)) <= 5.0 or point.distance_to(end - Vector2(2, 0)) <= 5.0:
			return pipe
	return null

func pipe_screen(pipe: Pool.DrainPipe) -> Vector2:
	var lift := pipe.host.visible_lift + 2.5 if pipe.host != null else 0.0
	return to_screen(pipe.position()) - Vector2(0, lift)

func draw_pipes() -> void:
	for pipe in pipes:
		var center := pipe_screen(pipe)
		if pipe == held_pipe:
			center = pointer - Vector2(0, 5)
		var reach := pipe.reach()
		var start := snap_pixel(center - Vector2(reach, 0.5))
		var end := snap_pixel(center + Vector2(reach, 0.5))
		if pipe.host == null and pipe != held_pipe:
			draw_line(start + Vector2(0.5, 2.0), end + Vector2(1.5, 2.5), Color("#26281e70"), 2.5)
		if pipe.host != null and pipe != held_pipe:
			var buried := Vector2(pipe.host.radius * 0.58, 0.0)
			var buried_l := snap_pixel(center - buried)
			var buried_r := snap_pixel(center + buried)
			draw_pipe_shaft(start, buried_l, false)
			draw_pipe_shaft(buried_r, end, false)
			var mud_collar := shade_color(Color("#2f241cc8"), center)
			draw_line(buried_l - Vector2(0, 1.5), buried_l + Vector2(0, 1.5), mud_collar, 1.5)
			draw_line(buried_r - Vector2(0, 1.5), buried_r + Vector2(0, 1.5), mud_collar, 1.5)
		else:
			draw_pipe_shaft(start, end, true)
		draw_rect(Rect2(start - Vector2(0.5, 1.5), Vector2(1.5, 3.0)), shade_color(Color("#9e9564"), start))
		draw_rect(Rect2(start - Vector2(0.5, 0.75), Vector2(0.75, 1.5)), Color("#242820"))
		draw_rect(Rect2(end - Vector2(0.5, 1.5), Vector2(2.0, 3.0)), shade_color(Color("#b3a872"), end))
		draw_rect(Rect2(end - Vector2(0.0, 0.75), Vector2(1.25, 1.5)), Color("#1d2624"))
		draw_rect(Rect2(end + Vector2(0.25, 0.25), Vector2(0.5, 0.5)), Color("#6a8f85"))
		if pipe == hovered_pipe and held_pipe == null:
			draw_hover_halo(self, center, reach + 2.5, 4.5)
		if pipe != held_pipe and pipe.rate > 0.012:
			draw_pipe_outflow(pipe, end)

func draw_pipe_shaft(start: Vector2, end: Vector2, full_span := true) -> void:
	var mid := start.lerp(end, 0.5)
	draw_line(start + Vector2(0, 1.5), end + Vector2(0, 1.5), Color("#1e282475"), 3.0)
	draw_line(start, end, shade_color(Color("#2c2a1d"), mid), 3.5)
	draw_line(start + Vector2(0, -0.25), end + Vector2(0, -0.25), shade_color(Color("#787549"), mid), 2.5)
	draw_line(start + Vector2(0, -0.75), end + Vector2(0, -0.75), shade_color(Color("#a49d67"), mid), 1.0)
	draw_line(start + Vector2(0.5, -1.0), end + Vector2(-1.0, -1.0), shade_color(Color("#c9c087"), mid), 0.5)
	draw_line(start + Vector2(0.5, 1.0), end + Vector2(-0.5, 1.0), shade_color(Color("#3c3926"), mid), 0.75)
	var span := end.x - start.x
	var nodes := [0.34, 0.67] if full_span else ([0.45] if span >= 4.5 else [])
	for t: float in nodes:
		var node_at := snap_pixel(start.lerp(end, t))
		draw_line(node_at - Vector2(0, 1.5), node_at + Vector2(0, 1.5), shade_color(Color("#3a3622"), node_at), 0.75)
		draw_line(node_at + Vector2(0.5, -1.25), node_at + Vector2(0.5, 1.0), shade_color(Color("#b8ae78"), node_at), 0.5)

func draw_pipe_outflow(pipe: Pool.DrainPipe, mouth: Vector2) -> void:
	var strength := smoothstep(0.012, Flow.PIPE_CAPACITY * 0.83, pipe.rate)
	var lip := mouth + Vector2(1.0, 0.5)
	var bend := lip + Vector2(1.5 + strength * 2.5, 0.5)
	var landing := bend + Vector2(1.5 + strength * 2.0, 2.0 + strength * 1.2)
	var arc := PackedVector2Array([lip, snap_pixel(bend), snap_pixel(landing)])
	draw_polyline(arc, Color("#5b9e9b", 0.54 + strength * 0.42), 0.5 + strength)
	draw_line(lip - Vector2(0, 0.5), snap_pixel(bend - Vector2(0, 0.5)), Color(FOAM, 0.30 + strength * 0.55), 0.5)
	for i in 3:
		var phase := fposmod(clock * (2.0 + strength) + i / 3.0, 1.0)
		var at := snap_pixel(landing + Vector2(phase * (3.0 + strength * 4.0), (i - 1) * phase * 2.0))
		draw_rect(Rect2(at, Vector2(1.5, 0.5)), Color(FOAM, (1.0 - phase) * strength * 0.8))

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
			var water_height: float = maxf(0.0, depth - 0.09) * 18.0 - piece.visible_lift
			submersion = clampf(water_height / (piece.radius * 0.80), 0.0, 0.88)
		p.x += piece.notch * 4.5
		var hover_lift := 1.0 if (piece == hovered and held == null) else 0.0
		draw_piece(piece, p, piece.notch * 0.27, damp, submersion, piece.support == null, 0.84 if built else 1.0, hover_lift)
		if piece == hovered:
			draw_hover_halo(self, p - Vector2(0.0, hover_lift), piece.radius + 2.5, piece.radius * 0.72 + 2.5)
	for item in rolling:
		var piece: Pool.Piece = item.piece
		var p := to_screen(item.point) - Vector2(0, item.lift)
		draw_piece(piece, p, item.turn if piece.kind == Pool.STONE else item.turn * 0.35, 0.8)
	if held != null:
		draw_piece(held, (pointer - Vector2(0, maxf(5.0, preview_lift))).round(), 0.0)

func draw_drop_hint(canvas: Node2D) -> void:
	if held != null:
		if pry_mode:
			draw_pry_arrow(canvas, piece_screen(held) + Vector2(held.radius + 3.5, 0.0))
		elif preview_active:
			if clear_drop:
				if preview_support != null:
					var base_pos := piece_screen(preview_support)
					draw_dashed_ellipse(canvas, base_pos - Vector2(0, preview_support.radius * 0.15),
						preview_support.radius * 0.72, preview_support.radius * 0.45,
						Color("#ffd97d", 0.86), Color("#2b2416b0"))
					draw_plus_badge(canvas, pointer - Vector2(0, maxf(7.0, preview_lift) + held.radius * 0.55))
				else:
					var spot := pointer if preview_bank_drop else to_screen(preview_target)
					var in_water := not preview_bank_drop and is_wet(preview_target)
					var ring := Color("#c7f2df", 0.84) if in_water else Color("#f2dfb2", 0.78)
					draw_dashed_ellipse(canvas, snap_pixel(spot + Vector2(0, held.radius * 0.25)),
						held.radius * 0.85, held.radius * 0.48, ring, Color("#1c2924a8"))
			else:
				var bad_at := snap_pixel((pointer + Vector2(0, 4.0)).clamp(Vector2(8, 2), SIZE - Vector2(8, 3)))
				draw_dashed_ellipse(canvas, bad_at, held.radius * 0.75, held.radius * 0.42,
					Color("#df7b68", 0.74), Color("#361915a8"))
				draw_cross_badge(canvas, bad_at)
	elif held_pipe != null:
		if preview_pipe_host != null:
			var host_p := piece_screen(preview_pipe_host)
			var r_reach := maxf(11.0, preview_pipe_host.radius + 5.0)
			var buried := preview_pipe_host.radius * 0.58
			var ghost := Color("#f5dc96", 0.78)
			canvas.draw_line(snap_pixel(host_p - Vector2(r_reach, 2.5)), snap_pixel(host_p - Vector2(buried, 2.5)), ghost, 2.0)
			canvas.draw_line(snap_pixel(host_p + Vector2(buried, 2.5)), snap_pixel(host_p + Vector2(r_reach, 2.5)), ghost, 2.0)
			draw_dashed_ellipse(canvas, host_p, preview_pipe_host.radius * 0.90, preview_pipe_host.radius * 0.58,
				Color("#ffd97d", 0.86), Color("#2b2416b0"))
			draw_plus_badge(canvas, host_p - Vector2(0, preview_pipe_host.radius * 0.75 + 2.0))
		elif clear_drop:
			draw_dashed_ellipse(canvas, snap_pixel(pointer), 9.5, 3.8, Color("#f2dfb2", 0.76), Color("#242920a8"))
		else:
			draw_cross_badge(canvas, pointer + Vector2(0, 3.0))
	elif held_floater != null:
		if hearth.contains(pointer):
			if clear_drop:
				draw_dashed_ellipse(canvas, Hearth.CENTER, Hearth.RADIUS.x + 1.0, Hearth.RADIUS.y + 1.0,
					Color("#f7ba6e", 0.88), Color("#2b1c12b0"))
				draw_plus_badge(canvas, Hearth.CENTER - Vector2(0, 9.0))
			else:
				draw_cross_badge(canvas, pointer + Vector2(0, 3.0))
		elif held_floater.forage in [Forage.FLOWER, Forage.FOXTAIL] and decoration_host(pointer) != null:
			var host := decoration_host(pointer)
			draw_dashed_ellipse(canvas, piece_screen(host), host.radius * 0.75, host.radius * 0.45,
				Color("#ffd97d", 0.84), Color("#2b2416b0"))
			draw_plus_badge(canvas, pointer - Vector2(0, 7.0))
		elif held_floater.forage == Forage.THIN_BRANCH and not on_bank(pointer):
			if clear_drop:
				draw_dashed_ellipse(canvas, snap_pixel(pointer + Vector2(0, 2.0)), 4.5, 2.4,
					Color("#c7f2df", 0.82), Color("#1c2924a8"))
			else:
				draw_cross_badge(canvas, pointer + Vector2(0, 2.0))
		elif not clear_drop:
			draw_cross_badge(canvas, pointer + Vector2(0, 2.0))
	elif holding_animal():
		if clear_drop:
			draw_dashed_ellipse(canvas, snap_pixel(pointer + Vector2(0, 2.0)), 4.5, 2.5,
				Color("#f2dfb2", 0.76), Color("#1c2924a8"), 10)
		else:
			draw_cross_badge(canvas, pointer + Vector2(0, 2.0))
	elif boat.held:
		if hearth.contains(pointer) and hearth.burning:
			var fire_ring := Color("#9de4dc", 0.86) if boat.soaked >= 0.45 else Color("#f79b59", 0.88)
			draw_dashed_ellipse(canvas, Hearth.CENTER, Hearth.RADIUS.x + 1.0, Hearth.RADIUS.y + 1.0, fire_ring, Color("#2b1c12b0"))
		elif clear_drop:
			var in_water := is_wet(from_screen(pointer)) and not on_bank(pointer)
			var ring := Color("#c7f2df", 0.84) if in_water else Color("#f2dfb2", 0.78)
			draw_dashed_ellipse(canvas, snap_pixel(pointer + Vector2(0, 2.0)), 6.5, 3.2, ring, Color("#1c2924a8"), 12)
		else:
			draw_cross_badge(canvas, pointer + Vector2(0, 2.0))

func draw_hover_halo(canvas: Node2D, center: Vector2, rx: float, ry: float, tint := PAPER) -> void:
	var pulse := 0.72 + 0.28 * sin(clock * 4.5)
	var shadow := Color(0.12, 0.11, 0.08, 0.48 * pulse)
	var glow := Color(tint, 0.72 * pulse)
	for base_angle: float in [0.28, PI * 0.5 + 0.28, PI + 0.28, PI * 1.5 + 0.28]:
		var pts := PackedVector2Array()
		var shadow_pts := PackedVector2Array()
		for i in 4:
			var a := base_angle + float(i) * 0.25
			var pt := snap_pixel(center + Vector2(cos(a) * rx, sin(a) * ry))
			pts.append(pt)
			shadow_pts.append(pt + Vector2(0, 0.5))
		canvas.draw_polyline(shadow_pts, shadow, 1.0)
		canvas.draw_polyline(pts, glow, 0.5)

func draw_dashed_ellipse(canvas: Node2D, center: Vector2, rx: float, ry: float, color: Color, outline: Color,
		segments := 14) -> void:
	for i in range(0, segments, 2):
		var a0 := float(i) * TAU / segments
		var a1 := float(i + 1) * TAU / segments
		var p0 := snap_pixel(center + Vector2(cos(a0) * rx, sin(a0) * ry))
		var p1 := snap_pixel(center + Vector2(cos(a1) * rx, sin(a1) * ry))
		canvas.draw_line(p0, p1, outline, 1.0)
		canvas.draw_line(p0, p1, color, 0.5)

func draw_plus_badge(canvas: Node2D, at: Vector2) -> void:
	var bob := snappedf(sin(clock * 5.0) * 0.5, 0.5)
	var c := snap_pixel(at.clamp(Vector2(6, 6), SIZE - Vector2(6, 6)) + Vector2(0, bob))
	canvas.draw_rect(Rect2(c - Vector2(2.5, 1.0), Vector2(5.0, 2.0)), Color("#2b2416d0"))
	canvas.draw_rect(Rect2(c - Vector2(1.0, 2.5), Vector2(2.0, 5.0)), Color("#2b2416d0"))
	canvas.draw_rect(Rect2(c - Vector2(2.0, 0.5), Vector2(4.0, 1.0)), Color("#ffd97d"))
	canvas.draw_rect(Rect2(c - Vector2(0.5, 2.0), Vector2(1.0, 4.0)), Color("#ffd97d"))

func draw_cross_badge(canvas: Node2D, at: Vector2) -> void:
	var c := snap_pixel(at.clamp(Vector2(6, 6), SIZE - Vector2(6, 6)))
	for s: float in [-1.0, 1.0]:
		canvas.draw_line(c + Vector2(-1.5, -1.5 * s), c + Vector2(1.5, 1.5 * s), Color("#331815d0"), 1.5)
		canvas.draw_line(c + Vector2(-1.5, -1.5 * s), c + Vector2(1.5, 1.5 * s), Color("#e07b67"), 0.75)

func draw_pry_arrow(canvas: Node2D, at: Vector2) -> void:
	var pulse := fposmod(clock * 2.2, 1.0)
	var c := snap_pixel(at + Vector2(pulse * 2.0, 0.0))
	var col := Color(FOAM, 0.85 * (1.0 - pulse * 0.35))
	var pts := PackedVector2Array([c + Vector2(-1.5, -2.0), c + Vector2(0.5, 0.0), c + Vector2(-1.5, 2.0)])
	canvas.draw_polyline(pts, Color("#1b332ed0"), 1.5)
	canvas.draw_polyline(pts, col, 0.75)

func draw_floaters() -> void:
	for item in floaters:
		var carried := item == held_floater
		if item.forage != Forage.NONE:
			draw_forage(item, carried)
			continue
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
			var side := axis.orthogonal()
			var tail := snap_pixel(point - axis * 7.5)
			var bend := snap_pixel(point + side * 0.8)
			var tip := snap_pixel(point + axis * 7.0 + side * 0.4)
			var shadow_col := Color("#1c2f295c") if (item.afloat and not carried) else Color("#2b261c66")
			if not carried:
				draw_polyline(PackedVector2Array([tail + Vector2(0.5, 1.5), bend + Vector2(0.5, 1.5), tip + Vector2(0.5, 1.5)]), shadow_col, 2.0)
			var bark_dark := shade_color(Color("#4a3628").darkened(item.soaked * 0.25), point)
			var bark_lit := shade_color(Color("#987250").darkened(item.soaked * 0.35), point)
			draw_polyline(PackedVector2Array([tail, bend, tip]), bark_dark, 2.0)
			draw_polyline(PackedVector2Array([tail + Vector2(0, -0.5), bend + Vector2(0, -0.5), tip + Vector2(0, -0.5)]), bark_lit, 0.75)
			var fork_a := snap_pixel(bend + Vector2(3.5, -3.2).rotated(item.angle))
			var fork_b := snap_pixel(point - axis * 2.5 + Vector2(1.0, 2.6).rotated(item.angle))
			draw_line(bend, fork_a, bark_dark, 1.25)
			draw_line(bend + Vector2(0, -0.25), fork_a, bark_lit, 0.5)
			draw_line(snap_pixel(point - axis * 2.5), fork_b, bark_lit.darkened(0.15), 0.75)
			draw_rect(Rect2(tip - Vector2(0.5, 0.5), Vector2(1.0, 1.0)), shade_color(Color("#cfb286"), tip))
		else:
			var hue_key := fposmod(item.shore.x * 0.137 + item.shore.y * 0.271, 1.0)
			var leaf_top: Color = world.profile.pick_leaf_color(hue_key)
			var leaf_edge: Color = world.profile.leaf_outline
			var vein_col := leaf_top.lightened(0.30)
			var shadow_col := Color("#1b2e2a5c") if (item.afloat and not carried) else Color("#2e291e66")
			var outline := PackedVector2Array()
			var form := PackedVector2Array()
			var upper := PackedVector2Array()
			var corners: Array[Vector2] = [Vector2(-4.5, 0), Vector2(-2.5, -1.6), Vector2(-0.5, -2.3), Vector2(2.2, -2.0),
				Vector2(4.8, -0.4), Vector2(5.4, 0.0), Vector2(2.4, 2.2), Vector2(-0.6, 2.3), Vector2(-2.7, 1.5)]
			for corner: Vector2 in corners:
				var rot := corner.rotated(item.angle)
				outline.append(snap_pixel(point + rot + Vector2(0.5, 1.0)))
				form.append(snap_pixel(point + rot))
			for corner: Vector2 in [Vector2(-4.2, 0), Vector2(-2.5, -1.5), Vector2(-0.5, -2.1), Vector2(2.2, -1.8), Vector2(4.8, -0.2), Vector2(0.0, 0.0)]:
				upper.append(snap_pixel(point + corner.rotated(item.angle)))
			if not carried:
				draw_colored_polygon(outline, shadow_col)
			draw_colored_polygon(form, shade_color(leaf_edge, point))
			draw_colored_polygon(upper, shade_color(leaf_top.lightened(0.10), point))
			var stem_start := snap_pixel(point - Vector2(6.0, 0.0).rotated(item.angle))
			var leaf_tip := snap_pixel(point + Vector2(4.5, 0.0).rotated(item.angle))
			draw_line(stem_start, leaf_tip, shade_color(vein_col, point), 0.65)
			for v: float in [-1.5, 1.0]:
				var rib := point + Vector2(v, 0).rotated(item.angle)
				draw_line(snap_pixel(rib), snap_pixel(rib + Vector2(1.4, -1.2).rotated(item.angle)), shade_color(vein_col, point), 0.5)
				draw_line(snap_pixel(rib), snap_pixel(rib + Vector2(1.2, 1.3).rotated(item.angle)), shade_color(leaf_top.darkened(0.22), point), 0.5)
		if item == hovered_floater and held_floater == null:
			draw_hover_halo(self, point, 7.5, 5.5)
	boat.draw(self, to_screen, pointer, shade_color, foam_ink())
	if hovered_boat and not boat.held:
		draw_hover_halo(self, boat.screen_pos(to_screen, pointer), 7.5, 4.8)
	if not squirt_gun.held:
		squirt_gun.draw_gun(self, pointer, shade_color, foam_ink())
		if hovered_squirt_gun:
			draw_hover_halo(self, squirt_gun.position, 11.5, 5.2)

func forage_screen(item: Floater) -> Vector2:
	return piece_screen(item.host) + item.host_offset if item.host != null else to_screen(item.point)

func forage_axis(item: Floater) -> Vector2:
	if item.forage == Forage.DRY_GRASS:
		return Vector2.from_angle(item.angle) * 9.0
	var length := 8.0 if item.forage == Forage.FLOWER else (14.0 if item.forage == Forage.FOXTAIL else 21.0)
	if item.planted and item != held_floater:
		var lean := lerpf(3.0, 5.2, smoothstep(6.0, 45.0, water.velocity_at(item.point).x))
		return Vector2(lean, -24.0)
	if item.afloat or (item.forage == Forage.THIN_BRANCH and not item.planted and item != held_floater):
		return Vector2.from_angle(item.angle) * length
	var light := wind.flutter(roundi(item.shore.x) + 41) * (0.55 if item.forage == Forage.THIN_BRANCH else 1.25)
	if item != held_floater and not item.rooted and not item.planted and item.host == null:
		return Vector2.from_angle(item.angle) * length
	if item.rooted:
		var dir := -1.0 if int(item.shore.x) % 2 == 0 else 1.0
		var slant := dir * (1.8 + fposmod(item.shore.x * 0.37, 2.2)) + light
		return Vector2(slant, -length)
	return Vector2(2.0 + light, -length)

func draw_forage(item: Floater, carried: bool) -> void:
	if not carried and world.season == SeasonProfile.Season.WINTER and item.rooted and item.forage == Forage.FLOWER:
		return
	var base := snap_pixel(pointer + Vector2(0, 2) if carried else forage_screen(item))
	var axis := forage_axis(item) if not carried else Vector2(2, -forage_axis(item).length())
	var tip := snap_pixel(base + axis)
	if item.planted and not carried:
		draw_planted_branch(item, base, axis)
	elif item.forage == Forage.DRY_GRASS:
		var direction := axis.normalized()
		var side := direction.orthogonal()
		if not carried:
			draw_line(snap_pixel(base + Vector2(-1.5, 1.0)), snap_pixel(base + direction * 5.0 + Vector2(0, 1.0)), Color("#28221966"), 1.5)
		for i in 6:
			var spread := float(i) - 2.5
			var strand := snap_pixel(base + direction * (6.2 + i % 3) + side * spread * 0.79)
			var joint := snap_pixel(base + direction * 4.0 + side * spread * 0.29)
			var straw := shade_color(item.tint.darkened(item.soaked * 0.30 + (0.13 if i % 2 == 0 else 0.0)), base)
			draw_polyline(PackedVector2Array([base, joint, strand]), straw, 0.5)
		draw_line(base, snap_pixel(base + direction * 2.6), shade_color(Color("#63523a"), base), 1.0)
	elif item.forage == Forage.THIN_BRANCH:
		var joint := snap_pixel((base + tip) * 0.5 - Vector2(0.5, 0))
		draw_polyline(PackedVector2Array([base, joint, tip]), shade_color(Color("#4f3e32"), base), 1.4)
		draw_polyline(PackedVector2Array([base + Vector2(0.5, 0), joint, tip]), shade_color(item.tint.darkened(item.soaked * 0.3), base), 0.65)
		var twig_tip := snap_pixel(joint + axis * 0.24 + axis.normalized().orthogonal() * 2.8)
		draw_line(joint, twig_tip, shade_color(item.tint.darkened(0.15 + item.soaked * 0.3), base), 0.65)
	else:
		if item.rooted and not carried:
			draw_rect(Rect2(snap_pixel(base + Vector2(-2.0, -0.5)), Vector2(4.0, 1.5)), shade_color(Color("#283822"), base))
			for leaf_off: Vector2 in [Vector2(-2.2, -1.2), Vector2(0.8, -1.4), Vector2(-0.5, -0.5)]:
				draw_rect(Rect2(snap_pixel(base + leaf_off), Vector2(1.5, 1.0)),
					shade_color(Color("#4f6635") if leaf_off.x < 0.0 else Color("#687d42"), base))
		var along := axis.normalized()
		var side := along.orthogonal()
		var bow := 0.85 if axis.x >= 0.0 else -0.85
		var joint := snap_pixel(base.lerp(tip, 0.48) - side * bow)
		draw_polyline(PackedVector2Array([base, joint, tip]), shade_color(Color("#364225"), base), 1.2)
		draw_polyline(PackedVector2Array([base, joint, tip]), shade_color(Color("#71814b"), base), 0.75)
		draw_line(joint, snap_pixel(joint + along * 1.6 + side * 2.2), shade_color(Color("#8e9b58"), base), 0.75)
		if item.forage == Forage.FOXTAIL:
			var seed_start := snap_pixel(tip - along * 4.8)
			draw_line(seed_start, tip, shade_color(item.tint.darkened(0.35), base), 2.5)
			draw_line(snap_pixel(seed_start - side * 0.4), snap_pixel(tip - side * 0.4), shade_color(item.tint, base), 1.5)
			draw_line(snap_pixel(tip - along - side * 0.8), snap_pixel(seed_start + along - side * 0.8), shade_color(item.tint.lightened(0.22), base), 0.5)
		else:
			draw_rect(Rect2(snap_pixel(tip - along * 1.2 - Vector2(0.75, 0.5)), Vector2(1.5, 1.0)), shade_color(Color("#475c32"), base))
			for offset: Vector2 in [Vector2(-2, -0.5), Vector2(0, -2), Vector2(1.5, -0.5), Vector2(0.5, 1.1), Vector2(-1.2, 1)]:
				var pixel := snap_pixel(tip + offset)
				draw_rect(Rect2(pixel, Vector2(1.5, 1.5)), shade_color(item.tint.darkened(0.17) if offset.y > 0.0 else item.tint, base))
			draw_rect(Rect2(tip - Vector2(0.25, 0.25), Vector2.ONE), shade_color(Color("#bd8952"), base))
			draw_rect(Rect2(tip - Vector2(0.5, 0.5), Vector2(0.5, 0.5)), shade_color(Color("#f0d29c"), base))
	if item == hovered_floater and held_floater == null:
		draw_hover_halo(self, snap_pixel(base.lerp(tip, 0.62)), 5.0, 6.0)

func draw_planted_branch(item: Floater, bed: Vector2, axis: Vector2) -> void:
	var wet := is_wet(item.point)
	var depth := water.depth_at(item.point) if wet else 0.0
	var direction := axis.normalized()
	var across := Vector2(-direction.y, direction.x)
	var height := minf(16.0, depth * 19.0)
	var seat := (1.0 - smoothstep(0.0, 0.21, item.age)) * 3.0
	var tip := snap_pixel(bed + axis - Vector2(0, seat))
	var waterline := snap_pixel(bed + direction * height)
	var bend := snap_pixel(waterline.lerp(tip, 0.48) - Vector2(0.9, 0))
	var fork := snap_pixel(bend + direction * 6.3 + across * 4.5)
	var ink := Color("#44362d")

	# The shadow is projected on the gravel. The wood's waterline follows local depth.
	var visibility := 1.0 - smoothstep(0.24, 0.95, depth)
	var shadow := snap_pixel(bed + Vector2(9.5, 4.0))
	draw_line(bed, shadow, Color(Color("#273831"), 0.48 * visibility), 1.4)
	draw_line(bed, snap_pixel(bed + Vector2(4.0, 1.0)), Color(Color("#243a32"), 0.42 * visibility), 1.5)
	if wet:
		var cell := water.cell_at(item.point)
		var clarity := lerpf(0.22, 1.0, visibility) * (1.0 - water.silt_at(cell.x, cell.y) * 0.78)
		var refracted := snap_pixel(bed + Vector2(0.5 + depth * 0.95, 0))
		draw_line(refracted, waterline, Color(Color("#36534b"), 0.77 * clarity), 2.0)
		draw_line(refracted - Vector2(0.5, 0), waterline, Color(Color("#738877"), 0.54 * clarity), 0.5)
		draw_branch_contact(item, waterline)

	var collar := snap_pixel(waterline.lerp(bend, 0.39))
	draw_colored_polygon(PackedVector2Array([
		snap_pixel(waterline - across * 1.35), snap_pixel(bend - across * 1.02), snap_pixel(tip - across * 0.45),
		snap_pixel(tip + across * 0.36), snap_pixel(bend + across * 0.72), snap_pixel(waterline + across * 1.17),
	]), shade_color(ink, bed))
	draw_polyline(PackedVector2Array([
		snap_pixel(waterline - across * 0.52), snap_pixel(bend - across * 0.46), tip
	]), shade_color(item.tint.lightened(0.15), bed), 0.75)
	draw_line(snap_pixel(collar + across * 0.34), snap_pixel(bend + across * 0.30), shade_color(item.tint.darkened(0.28), bed), 0.5)
	draw_line(bend, fork, shade_color(ink, bed), 1.25)
	draw_line(snap_pixel(bend + direction * 0.65), fork, shade_color(item.tint, bed), 0.5)
	if wet:
		draw_line(snap_pixel(waterline - across * 1.3), snap_pixel(waterline + across * 1.3), Color(Color("#b2d4bd"), 0.76), 0.75)

func draw_branch_contact(item: Floater, at: Vector2) -> void:
	var velocity := water.velocity_at(item.point)
	var flow := Vector2(velocity.x, velocity.y * 0.62)
	var down := Vector2.RIGHT if flow.length_squared() < 4.0 else flow.normalized()
	var side := down.orthogonal()
	var push := smoothstep(1.0, 30.0, flow.length())
	var insertion := 1.0 - smoothstep(0.10, 0.55, item.age)
	var ring := 2.5 + smoothstep(0.0, 0.55, item.age) * 4.8
	if insertion > 0.0:
		draw_arc(at, ring, 0.12, TAU - 0.12, 14, Color(FOAM, insertion * 0.56), 0.5)
	for edge: float in [-1.0, 1.0]:
		var shoulder := snap_pixel(at - down * 0.65 + side * edge * 1.65)
		var slide := snap_pixel(at + down * 1.8 + side * edge * 2.2)
		draw_polyline(PackedVector2Array([snap_pixel(at - down * 1.6), shoulder, slide]), Color(FOAM, 0.54 + push * 0.25), 0.5)
		var phase := fposmod(clock * (1.15 + push * 1.1) + edge * 0.16, 1.0)
		var wake := at + down * (2.3 + phase * 5.5) + side * edge * (2.1 + phase * 1.7)
		draw_line(snap_pixel(wake), snap_pixel(wake + down * 2.2 + side * edge * 0.65),
			Color(FOAM, (1.0 - phase) * (0.22 + push * 0.39)), 0.5)

func snap_pixel(point: Vector2) -> Vector2:
	return (point * 2.0).round() * 0.5

func dampness(piece: Pool.Piece) -> float:
	if absf(piece.point.y) > Pool.BANK + 1.0:
		return 0.0
	var cell := water.cell_at(piece.point)
	var i := water.index(cell.x, cell.y)
	var wet := maxf(shore_memory[i] * 0.84, smoothstep(0.015, 0.12, water.depth[i]))
	return wet * (1.0 - smoothstep(0.0, 12.0, piece.visible_lift))

func draw_piece(piece: Pool.Piece, p: Vector2, roll: float, damp := 0.0, submersion := 0.0, seated := false, squash := 1.0,
		hover_lift := 0.0) -> void:
	draw_rock(piece, p, roll, damp, submersion, seated, squash, 0.0, hover_lift)

func make_hearth_warm_face(stone: Pool.Piece) -> ImageTexture:
	var face := rock_art.for_piece(stone.radius, stone.shade).texture.get_image()
	var center := Vector2(face.get_size()) * Vector2(0.5, 0.48)
	var toward_fire := -stone.point.normalized()
	for y in face.get_height():
		for x in face.get_width():
			var ink := face.get_pixel(x, y)
			if ink.a <= 0.0:
				continue
			var from_center := (Vector2(x, y) + Vector2(0.5, 0.5) - center) * Vector2(1.0, 0.83)
			var facing := from_center.dot(toward_fire) / maxf(1.0, stone.radius * 2.0)
			var weight := smoothstep(-0.01, 0.75, facing)
			var warm := ink * Color(1.37, 1.08, 0.86)
			face.set_pixel(x, y, Color(warm, ink.a * weight))
	return ImageTexture.create_from_image(face)

func draw_rock(piece: Pool.Piece, p: Vector2, roll: float, damp: float, submersion: float, seated: bool, squash: float,
		firelight := 0.0, hover_lift := 0.0) -> void:
	var is_earth := piece.kind == Pool.EARTH
	squash *= 1.0 - sin(piece.bounce * PI) * (0.16 if is_earth else 0.08)
	var r := piece.radius
	var wear_scale := (1.0 - piece.wear * 0.30) if is_earth else 1.0
	var seed := fposmod(piece.radius * 0.317 + piece.shade * 0.247, 1.0)
	p = snap_pixel(p)
	var effective_damp := maxf(damp, rain.wetness * 0.32)
	if seated:
		var foot := p + Vector2(-r * 0.08, r * (0.46 if is_earth else 0.52) * squash * wear_scale)
		var shadow := PackedVector2Array([Vector2(-1.04, 0.02), Vector2(-0.70, -0.34),
			Vector2(0.56, -0.35), Vector2(0.94, -0.10), Vector2(0.56, 0.22), Vector2(-0.58, 0.28)])
		for i in shadow.size():
			shadow[i] = snap_pixel(foot + shadow[i] * r * wear_scale)
		var shadow_dry := Color("#432b1ba6") if is_earth else Color("#281d18bc")
		var shadow_wet := Color("#1b323082") if is_earth else Color("#112a2a8c")
		var shadow_col := shadow_dry.lerp(shadow_wet, effective_damp).lerp(Color("#112e3045"), smoothstep(0.06, 0.35, submersion))
		if hover_lift > 0.0:
			shadow_col.a *= 0.84
		draw_colored_polygon(shadow, shadow_col)
		if is_earth and seed > 0.42 and r >= 6.0 and submersion <= 0.06:
			for i in 3:
				var pebble := snap_pixel(foot + Vector2((0.48 + i * 0.20) * r, (i % 2) * 1.5))
				draw_rect(Rect2(pebble, Vector2(1.0 + (i % 2) * 0.5, 1.0)), shade_color(Color("#7f745b").lerp(Color("#435752"), effective_damp), pebble))
				draw_rect(Rect2(pebble + Vector2(0, 0.5), Vector2(1, 0.5)), shade_color(Color("#4c4a3c"), pebble))

	var body_p := snap_pixel(p - Vector2(0.0, hover_lift))
	var carving: RockArt.Rock = rock_art.for_earth(r, piece.shade) if is_earth else rock_art.for_piece(r, piece.shade)
	var size := carving.texture.get_size()
	var origin := -size * 0.25
	var sunlight := smoothstep(0.18, 0.77, body_p.x / SIZE.x + (1.0 - body_p.y / SIZE.y) * 0.34)
	var env := env_modulate(body_p)
	var winter := world.season == SeasonProfile.Season.WINTER
	var stone_dry := Color("#a8badc").lerp(Color("#d8e4f7"), sunlight) if winter else Color("#dad1db").lerp(Color("#fff7ef"), sunlight)
	var dry := (Color("#e0cfc4").lerp(Color("#fff5e6"), sunlight) if is_earth else stone_dry) * env
	var water_row := clampi(roundi((r * (0.71 - submersion * 0.92) - origin.y) * 2.0), 0, int(size.y))
	draw_set_transform(body_p, roll, Vector2(wear_scale, squash * wear_scale))
	if submersion > 0.06 and water_row < int(size.y):
		if water_row > 0:
			var upper_strip := Rect2(0, 0, size.x, water_row)
			draw_texture_rect_region(carving.texture, Rect2(origin, upper_strip.size * 0.5), upper_strip, dry)
		var sub_height := int(size.y) - water_row
		var fade_rows := mini(3, sub_height)
		var fade_start := int(size.y) - fade_rows
		var shallow_tint := dry * (Color("#66857e") if is_earth else Color("#739a95"))
		if fade_start > water_row:
			var shallow_strip := Rect2(0, water_row, size.x, fade_start - water_row)
			draw_texture_rect_region(carving.texture, Rect2(origin + shallow_strip.position * 0.5, shallow_strip.size * 0.5),
				shallow_strip, Color(shallow_tint, 0.92))
		if fade_rows > 0:
			var bed_tint := dry * (Color("#446a68") if is_earth else Color("#4a7574"))
			var bed_strip := Rect2(0, fade_start, size.x, fade_rows)
			draw_texture_rect_region(carving.texture, Rect2(origin + bed_strip.position * 0.5, bed_strip.size * 0.5),
				bed_strip, Color(bed_tint, 0.62))
	else:
		draw_texture_rect(carving.texture, Rect2(origin, size * 0.5), false, dry)
		if effective_damp > 0.0 and water_row < int(size.y):
			var wet := dry * (Color("#637d79") if is_earth else Color("#779997"))
			var lower_strip := Rect2(0, water_row, size.x, size.y - water_row)
			draw_texture_rect_region(carving.texture, Rect2(origin + lower_strip.position * 0.5, lower_strip.size * 0.5),
				lower_strip, Color(wet, effective_damp * 0.80))
	if firelight > 0.01 and hearth_warm_faces.has(piece):
		draw_texture_rect(hearth_warm_faces[piece], Rect2(origin, size * 0.5), false,
			Color(dry, firelight * (1.0 - effective_damp * 0.44)))
	if winter and not is_earth and carving.snow_cap != null and submersion <= 0.04 and effective_damp < 0.15:
		var near_fire := hearth.firelight > 0.12 and body_p.distance_to(Hearth.CENTER) < 38.0
		if not near_fire:
			draw_texture_rect(carving.snow_cap, Rect2(origin, size * 0.5), false, env)
	draw_set_transform(Vector2.ZERO)
	if submersion > 0.13 and water_row < carving.rim.size():
		var rim := carving.rim[water_row]
		var width := (rim.y - rim.x) * 0.5 * wear_scale
		if width >= 2.0:
			var left_x := body_p.x + (origin.x + rim.x * 0.5) * wear_scale
			var right_x := left_x + width
			var water_y := body_p.y + (origin.y + water_row * 0.5) * squash * wear_scale
			draw_piece_water_contact(piece, water_y, left_x, right_x, submersion)

func draw_piece_water_contact(piece: Pool.Piece, water_y: float, left_x: float, right_x: float, submersion: float) -> void:
	var width := right_x - left_x
	if width < 2.0:
		return
	var v := water.velocity_at(piece.point - Vector2(piece.radius * 0.70, 0.0))
	var push := surge_at(piece.point.x)
	var flow_force := clampf(v.x / 35.0 + push * 0.65, 0.0, 1.35)
	var surge_wave := (0.5 + flow_force * 0.8 + sin(clock * 4.2 + piece.point.y) * 0.35) if flow_force > 0.08 else 0.0
	var mid_x := lerpf(left_x, right_x, 0.50)
	# Leeward wake shadow on the downstream side.
	draw_rect(Rect2(snap_pixel(Vector2(mid_x, water_y)), Vector2(width * 0.48, 1.5)),
		Color("#143435", 0.28 * submersion))
	# Curved windward waterline hugging the submerged stone/earth belly.
	var curve := PackedVector2Array([
		snap_pixel(Vector2(left_x - 0.5, water_y - surge_wave * 0.75)),
		snap_pixel(Vector2(lerpf(left_x, right_x, 0.22), water_y - surge_wave * 0.35)),
		snap_pixel(Vector2(mid_x, water_y + 0.45)),
		snap_pixel(Vector2(lerpf(left_x, right_x, 0.78), water_y + 0.25)),
		snap_pixel(Vector2(right_x, water_y)),
	])
	draw_polyline(curve, Color("#304b49b8"), 1.0)
	var foam_curve := PackedVector2Array([curve[0], curve[1], curve[2]])
	draw_polyline(foam_curve, foam_ink(clampf(0.45 + flow_force * 0.35, 0.0, 0.88)), 0.5)
	if flow_force > 0.14:
		for i in 2:
			var phase := fposmod(clock * (1.8 + flow_force * 1.6) + i * 0.5 + piece.shade * 0.17, 1.0)
			var fleck := snap_pixel(Vector2(left_x - 1.0 + phase * width * 0.35, water_y - surge_wave * (1.0 - phase) + (i - 0.5) * 0.75))
			draw_rect(Rect2(fleck, Vector2(1.0, 0.5)), foam_ink((1.0 - phase) * clampf(0.40 + flow_force * 0.40, 0.0, 0.85)))

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
			draw_rect(Rect2((origin + delta).floor(), size), foam_ink(alpha))
