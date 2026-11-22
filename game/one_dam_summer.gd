extends RefCounted

const Flow = preload("res://game/one_dam_grid.gd")
const Wind = preload("res://game/one_dam_wind.gd")
signal fish_surface(point: Vector2)

const SEDGES := [
	Vector3(25, 120, 7.5), Vector3(23, 122, 3.4), Vector3(28, 124, 4.7),
	Vector3(143, 151, 8.0), Vector3(149, 150, 4.9), Vector3(253, 115, 7.3),
	Vector3(250, 117, 4.8), Vector3(255, 114, 3.0), Vector3(306, 49, 4.6),
]

enum Flight { PERCHED, FLYING, HOVERING, LANDING }

# The ends of three sedge stems are the insect's places to rest.
const PERCHES := [0, 3, 5]
const FISH_SHELTERS := [Vector2(61, 5), Vector2(83, -4), Vector2(111, 5),
	Vector2(137, -9), Vector2(184, 6), Vector2(221, -5), Vector2(264, 4)]

var clock := 0.0
var fish := Vector2.ZERO
var fish_time := -1.0
var fish_due := 7.8
var fish_alarm := 0.0
var fish_heading := Vector2.LEFT
var fish_turn_due := 0.0
var fish_surface_due := 0.0
var fish_held := false
var fish_stranded := false
var fish_released := false
var insect_state := Flight.PERCHED
var insect_age := 0.0
var insect_duration := 5.4
var perch := 0
var next_perch := 1
var insect_position := Vector2(25.0, 113.0)
var insect_held := false
var temporary_perch := false
var flight_origin := Vector2.ZERO
var hover_point := Vector2.ZERO
var surface_impulse := 0.0
var impulse_x := 0.0
var rng := RandomNumberGenerator.new()
var wind: Wind

func advance(dt: float, water: Flow) -> void:
	clock += dt
	surface_impulse = move_toward(surface_impulse, 0.0, dt * 0.58)
	advance_insect(dt)
	advance_fish(dt, water)

func plant_sway(index: int, stem: int) -> float:
	var root: Vector3 = SEDGES[index]
	var gust := wind.strength_at(root.x / 320.0) if wind != null else Wind.CALM
	var rustle := wind.flutter(4 + index * 4 + stem) if wind != null else 0.0
	var flood := surface_impulse * maxf(0.0, 1.0 - absf(root.x - impulse_x) / 105.0)
	var lean := gust * (0.95 + stem * 0.23)
	return rustle * (1.10 + gust * 1.40) * (root.z / 7.5) + lean + flood * 2.7

func plant_tip(index: int, stem: int) -> Vector2:
	var root: Vector3 = SEDGES[index]
	return Vector2(root.x + (stem - 1.4) * 2.0 + plant_sway(index, stem), root.y - root.z * (0.73 + stem % 3 * 0.16))

func advance_insect(dt: float) -> void:
	if insect_held:
		return
	insect_age += dt
	var t := clampf(insect_age / insect_duration, 0.0, 1.0)
	var smooth := t * t * (3.0 - t * 2.0)
	match insect_state:
		Flight.PERCHED:
			if not temporary_perch:
				insect_position = plant_tip(PERCHES[perch], 2)
			var exposed := wind != null and wind.strength_at(insect_position.x / 320.0) > 0.73
			var flooded := surface_impulse > 0.60 and absf(insect_position.x - impulse_x) < 37.0
			if t >= 1.0 or (insect_age > 2.2 and (exposed or flooded)):
				take_flight()
		Flight.FLYING:
			insect_position = flight_origin.lerp(hover_point, smooth)
			insect_position.y -= sin(t * PI) * 10.0
			if t >= 1.0:
				set_flight(Flight.HOVERING, rng.randf_range(0.7, 2.5))
		Flight.HOVERING:
			insect_position = hover_point + Vector2(sin(insect_age * 4.7) * 2.5, sin(insect_age * 6.2) * 1.2)
			if t >= 1.0:
				flight_origin = insect_position
				set_flight(Flight.LANDING, rng.randf_range(1.3, 2.8))
		Flight.LANDING:
			insect_position = flight_origin.lerp(plant_tip(PERCHES[next_perch], 2), smooth)
			insect_position.y -= sin(t * PI) * 5.5
			if t >= 1.0:
				perch = next_perch
				set_flight(Flight.PERCHED, rng.randf_range(6.5, 19.5))

func take_flight() -> void:
	temporary_perch = false
	next_perch = (perch + rng.randi_range(1, PERCHES.size() - 1)) % PERCHES.size()
	flight_origin = insect_position
	hover_point = flight_origin.lerp(plant_tip(PERCHES[next_perch], 2), 0.61) + Vector2(rng.randf_range(-14.0, 14.0), -rng.randf_range(15.0, 28.0))
	set_flight(Flight.FLYING, rng.randf_range(0.8, 2.0))

func set_flight(state: Flight, duration: float) -> void:
	insect_state = state
	insect_age = 0.0
	insect_duration = duration

func disturb_perch(cursor: Vector2) -> void:
	if not insect_held and insect_state == Flight.PERCHED and cursor.distance_to(insect_position) < 5.0:
		take_flight()

func place_insect(point: Vector2, wet: bool) -> void:
	insect_held = false
	insect_position = point
	if wet:
		take_flight()
	else:
		temporary_perch = true
		set_flight(Flight.PERCHED, 2.2)

func disturb_water(point: Vector2, strength: float, surge: bool) -> void:
	if surge:
		surface_impulse = maxf(surface_impulse, minf(strength, 1.4))
		impulse_x = point.x
	if fish_time >= 0.0 and fish.distance_to(point) < (52.0 if surge else 31.0):
		var away := fish - point
		if away.length_squared() > 0.1:
			fish_heading = away.normalized()
		fish_alarm = 0.9

func advance_fish(dt: float, water: Flow) -> void:
	if fish_held:
		return
	if fish_time >= 0.0:
		fish_time += dt
		if fish_stranded:
			var toward := Vector2(0, -signf(fish.y))
			fish_heading = toward if toward != Vector2.ZERO else fish_heading
			fish = fish.move_toward(Vector2(fish.x, 0.0), dt * (3.0 + maxf(0.0, sin(fish_time * 18.0)) * 13.0))
			fish_stranded = absf(fish.y) > 29.0 or water.depth_at(fish) < 0.13
			if not fish_stranded:
				fish_time = 0.0
				fish_surface.emit(fish)
			return
		fish_alarm = move_toward(fish_alarm, 0.0, dt)
		var velocity := water.velocity_at(fish)
		if velocity.length() > 36.0 and fish_alarm < 0.15:
			fish_alarm = 0.75
		elif fish_alarm < 0.14 and fish_time >= fish_turn_due:
			fish_turn_due = fish_time + rng.randf_range(0.55, 1.4)
			fish_heading = fish_heading.rotated(rng.randf_range(-0.45, 0.45))
		var stride := fish_heading * (11.0 + fish_alarm * 37.0) + velocity.limit_length(16.0) * 0.15
		var next := fish + stride * dt
		if water.depth_at(next) < 0.13 or absf(next.y) > 30.0:
			var toward_channel := Vector2(fish_heading.x, -signf(fish.y) * 0.72).normalized()
			var check := fish + toward_channel * 2.0
			fish_heading = toward_channel if water.depth_at(check) >= 0.13 else -fish_heading
		else:
			fish = next
		if fish_time >= fish_surface_due and fish_time < 3.8 and fish_alarm < 0.12 and velocity.length() < 20.0:
			var depth := water.depth_at(fish)
			if depth > 0.15 and depth < 0.42:
				fish_surface.emit(fish)
				fish_surface_due = INF
		if fish_time >= (14.0 if fish_released else 5.0) or fish.x < 8.0 or fish.x > 314.0:
			fish_due = clock + rng.randf_range(8.0, 20.0)
			fish_time = -1.0
			fish_released = false
	elif clock >= fish_due:
		var offset := rng.randi_range(0, FISH_SHELTERS.size() - 1)
		for i in FISH_SHELTERS.size():
			var start: Vector2 = FISH_SHELTERS[(i + offset) % FISH_SHELTERS.size()]
			if water.depth_at(start) > 0.16 and water.velocity_at(start).length() < 25.0:
				fish = start
				fish_time = 0.0
				fish_alarm = 0.0
				fish_turn_due = rng.randf_range(0.4, 1.1)
				fish_surface_due = rng.randf_range(1.1, 3.0)
				fish_heading = Vector2.LEFT if rng.randf() < 0.64 else Vector2.RIGHT
				return
		fish_due = clock + 5.0

func place_fish(point: Vector2, wet: bool) -> void:
	fish = point
	fish_time = 0.0
	fish_stranded = not wet
	fish_released = true
	fish_held = false
	fish_alarm = 0.65
	fish_turn_due = 0.75
	fish_surface_due = 2.0
	fish_heading = Vector2.RIGHT if point.x < 160.0 else Vector2.LEFT

func draw_fish(canvas: Node2D, project: Callable, pointer: Vector2, foreground := false) -> void:
	if fish_time < 0.0:
		return
	if foreground != (fish_held or fish_stranded):
		return
	var position: Vector2 = pointer - Vector2(0, 5) if fish_held else project.call(fish)
	var presence := 1.0 if fish_held or fish_stranded else (
		smoothstep(0.0, 0.25 if fish_released else 0.7, fish_time) * (
		1.0 - smoothstep(12.0 if fish_released else 3.0, 14.0 if fish_released else 4.8, fish_time)))
	var tail := sin((clock if fish_held else fish_time) * (12.0 + fish_alarm * 17.0)) * (1.2 + fish_alarm)
	var turn := fish_heading.angle() - PI
	var shadow := Color("#665644") if foreground else Color(0.08, 0.18, 0.18, presence * 0.58)
	canvas.draw_colored_polygon(PackedVector2Array([
		position + Vector2(-4.1, 0.1).rotated(turn), position + Vector2(-1.5, -1.35).rotated(turn),
		position + Vector2(2.1, -0.75).rotated(turn), position + Vector2(5.2, tail - 0.8).rotated(turn),
		position + Vector2(4.2, tail + 1.3).rotated(turn), position + Vector2(1.6, 0.54).rotated(turn),
		position + Vector2(-1.9, 1.0).rotated(turn),
	]), shadow)
	canvas.draw_line(position + Vector2(-2, -0.5).rotated(turn), position + Vector2(1, -0.45).rotated(turn), Color(0.50, 0.68, 0.60, presence * 0.25), 0.5)

func draw_land(canvas: Node2D) -> void:
	for i in SEDGES.size():
		var data: Vector3 = SEDGES[i]
		var root := Vector2(data.x, data.y)
		for stem in (4 if data.z >= 5.0 else 3):
			var span := (stem - 1.4) * 2.0
			var height := data.z * (0.73 + stem % 3 * 0.16)
			var sway := plant_sway(i, stem)
			var split := root + Vector2(span * 0.37 + sway * 0.19, -height * 0.54)
			var tip := plant_tip(i, stem)
			var ink := Color("#596332") if stem % 2 == 0 else Color("#7a7b42")
			canvas.draw_line(root, split, Color("#454c2d"), 0.5)
			canvas.draw_line(split, tip, ink, 0.5)
			var blade := split.lerp(tip, 0.53)
			canvas.draw_line(blade, blade + Vector2(1.0 + sway * 0.6, -1.1), ink.lightened(0.11), 0.5)
			if data.z >= 5.0 and stem == (3 if i % 2 == 0 else 1):
				var axis := (tip - split).normalized()
				var seed_head := tip + axis * 1.4
				canvas.draw_line(tip, seed_head, Color("#8b874b"), 1.5)
				canvas.draw_line(tip + Vector2(-0.5, 0), seed_head + Vector2(-0.5, -0.5), Color("#b5a26a"), 0.5)

	for leaf in [Vector3(58, 155, -0.7), Vector3(60.5, 154, 0.6), Vector3(59, 157, 2.9),
			Vector3(187, 151, 0.4), Vector3(196, 46, -1.7), Vector3(109, 169, 2.8)]:
		draw_litter_leaf(canvas, Vector2(leaf.x, leaf.y), leaf.z, Color("#96744a"))

	# Litter caught at breaks in the rock bank.
	draw_litter_leaf(canvas, Vector2(89.5, 94.5), 0.5, Color("#766145"))
	var twig := Vector2(227.5, 126.0)
	canvas.draw_polyline(PackedVector2Array([twig + Vector2(-3, -2.5), twig, twig + Vector2(3, 0.5)]), Color("#675746"), 0.5)
	canvas.draw_line(twig + Vector2(-3, -2.5), twig, Color("#3d4f46"), 0.5)
	canvas.draw_line(twig, twig + Vector2(2, -1.5), Color("#89704f"), 0.5)

	# A small sun-bleached bamboo stake by the path.
	var stake := Vector2(191.0, 41.0)
	canvas.draw_line(stake, stake + Vector2(4, 1), Color("#36392e62"), 1.0)
	canvas.draw_line(stake, stake + Vector2(-0.8, -9.0), Color("#5e5a36"), 1.5)
	canvas.draw_line(stake + Vector2(-0.4, -1), stake + Vector2(-1.0, -8.6), Color("#a7965b"), 0.5)
	canvas.draw_line(stake + Vector2(-1.6, -5.3), stake + Vector2(0.4, -5.6), Color("#c3a77a"), 0.5)

func draw_litter_leaf(canvas: Node2D, at: Vector2, turn: float, ink: Color) -> void:
	var shape := PackedVector2Array([Vector2(-1.5, 0), Vector2(-0.5, -0.8), Vector2(1.6, -0.5), Vector2(0.6, 0.5), Vector2(-0.6, 0.5)])
	for i in shape.size():
		shape[i] = (at * 2.0 + shape[i].rotated(turn) * 2.0).round() * 0.5
	canvas.draw_colored_polygon(shape, ink)
	canvas.draw_line(at, at + Vector2(1.7, -0.4).rotated(turn), ink.darkened(0.26), 0.5)

func draw_insect(canvas: Node2D, pointer: Vector2) -> void:
	var point := pointer - Vector2(0, 5) if insect_held else insect_position
	var settled := insect_held or insect_state == Flight.PERCHED
	var flex := sin(insect_age * 61.0) if not settled else sin(clock * 5.0) * smoothstep(0.87, 0.99, sin(clock * 0.7)) * 0.65
	var glint := Color(0.78, 0.91, 0.72, 0.63 + absf(flex) * 0.26)
	canvas.draw_line(point - Vector2(3.2, 0), point + Vector2(2.2, -0.6), Color("#345947"), 0.8)
	for side in [-1.0, 1.0]:
		var tip := point + Vector2(-0.75, (2.15 + flex) * side)
		canvas.draw_line(point, tip, glint, 0.5)
		canvas.draw_line(point - Vector2(0.8, 0), tip - Vector2(1.1, 0), Color(glint, 0.56), 0.5)
	canvas.draw_rect(Rect2(point + Vector2(1.0, -0.5), Vector2(0.9, 0.5)), Color("#75b087"))
