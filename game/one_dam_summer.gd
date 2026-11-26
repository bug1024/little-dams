extends RefCounted

const Flow = preload("res://game/one_dam_grid.gd")
const Wind = preload("res://game/one_dam_wind.gd")
const CICADA_PERCH := Vector2(58.5, 19.5)
signal fish_surface(point: Vector2)
signal cicada_sang
signal cicada_startled

const SEDGES := [
	Vector3(25, 120, 7.5), Vector3(23, 122, 3.4), Vector3(28, 124, 4.7),
	Vector3(143, 151, 8.0), Vector3(149, 150, 4.9), Vector3(253, 115, 7.3),
	Vector3(250, 117, 4.8), Vector3(255, 114, 3.0), Vector3(306, 49, 4.6),
]

enum Flight { PERCHED, FLYING, HOVERING, LANDING }

class Fry:
	var pos: Vector2
	var heading := Vector2.LEFT
	var phase := 0.0
	var presence := 0.0
	var turn_due := 0.6
	var alarm := 0.0

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
var flower_perches: Array[Vector2] = []
var perched_on_flower := false
var flower_target := Vector2.ZERO
var fry: Array[Fry] = []
var pool_richness := 0.0
var current_day_phase := 0.0
var cicada_position := CICADA_PERCH
var cicada_held := false
var cicada_wet := false
var cicada_singing := false
var cicada_sing_age := 0.0
var cicada_sing_duration := 0.0
var cicada_sing_level := 0.0
var cicada_call_due := 3.5
var cicada_twitch := 0.0
var cicada_twitch_due := 4.2
var cicada_angle := -2.42
var flight_origin := Vector2.ZERO
var hover_point := Vector2.ZERO
var surface_impulse := 0.0
var impulse_x := 0.0
var rng := RandomNumberGenerator.new()
var wind: Wind

func advance(dt: float, water: Flow, rain_intensity := 0.0, day_phase := 0.0, pool_richness_in := 0.0, after_rain := 0.0) -> void:
	clock += dt
	current_day_phase = day_phase
	pool_richness = pool_richness_in
	surface_impulse = move_toward(surface_impulse, 0.0, dt * 0.58)
	advance_insect(dt)
	advance_cicada(dt, rain_intensity, day_phase, after_rain)
	advance_fish(dt, water)
	advance_fry(dt, water)

func reset_ecosystem() -> void:
	fry.clear()
	flower_perches.clear()
	perched_on_flower = false
	flower_target = Vector2.ZERO
	pool_richness = 0.0
	current_day_phase = 0.0
	insect_state = Flight.PERCHED
	insect_age = 0.0
	insect_duration = 5.4
	perch = 0
	insect_position = plant_tip(PERCHES[0], 2)
	reset_cicada()

func reset_cicada() -> void:
	cicada_position = CICADA_PERCH
	cicada_held = false
	cicada_wet = false
	cicada_singing = false
	cicada_sing_age = 0.0
	cicada_sing_duration = 0.0
	cicada_sing_level = 0.0
	cicada_call_due = 3.5
	cicada_twitch = 0.0
	cicada_twitch_due = 4.2

func grab_cicada() -> void:
	cicada_held = true
	cicada_singing = false
	cicada_sing_level = 0.0
	cicada_call_due = rng.randf_range(5.0, 9.0)
	cicada_twitch = 1.0
	cicada_startled.emit()

func place_cicada(point: Vector2, wet: bool) -> void:
	cicada_held = false
	cicada_position = point
	cicada_wet = wet
	cicada_singing = false
	cicada_call_due = rng.randf_range(4.5, 9.5)
	cicada_twitch = 0.65

func advance_cicada(dt: float, rain_intensity: float, day_phase := 0.0, after_rain := 0.0) -> void:
	cicada_twitch = move_toward(cicada_twitch, 0.0, dt * 4.2)
	if cicada_held:
		cicada_singing = false
		cicada_sing_level = move_toward(cicada_sing_level, 0.0, dt * 8.0)
		return
	var twilight_quiet := day_phase > 1.55
	if not twilight_quiet:
		cicada_twitch_due -= dt
		if cicada_twitch_due <= 0.0:
			cicada_twitch = rng.randf_range(0.45, 0.85)
			cicada_twitch_due = rng.randf_range(4.5, 10.5)
	var quiet_weather := rain_intensity > 0.25 or cicada_wet or twilight_quiet
	if cicada_singing:
		cicada_sing_age += dt
		if quiet_weather or cicada_sing_age >= cicada_sing_duration:
			cicada_singing = false
			cicada_call_due = rng.randf_range(15.0, 28.0) if day_phase > 0.75 else rng.randf_range(9.5, 20.0)
		else:
			var attack := smoothstep(0.0, 0.72, cicada_sing_age)
			var release := 1.0 - smoothstep(maxf(0.72, cicada_sing_duration - 1.15), cicada_sing_duration, cicada_sing_age)
			var cadence := 0.78 + 0.22 * sin(cicada_sing_age * TAU / 0.58)
			cicada_sing_level = move_toward(cicada_sing_level, attack * release * cadence, dt * 6.0)
	else:
		cicada_sing_level = move_toward(cicada_sing_level, 0.0, dt * (5.0 if quiet_weather else 2.2))
		if not quiet_weather:
			if after_rain > 0.40 and rain_intensity < 0.18 and day_phase < 1.40 and cicada_call_due > 5.0:
				cicada_call_due = 5.0
			cicada_call_due -= dt
			if cicada_call_due <= 0.0:
				cicada_singing = true
				cicada_sing_age = 0.0
				cicada_sing_duration = rng.randf_range(3.6, 6.4)
				cicada_sang.emit()

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

func live_flower_near(point: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := 7.5
	for spot: Vector2 in flower_perches:
		var d := spot.distance_to(point)
		if d < best_d:
			best_d = d
			best = spot
	return best

func advance_insect(dt: float) -> void:
	if insect_held:
		return
	insect_age += dt
	var t := clampf(insect_age / insect_duration, 0.0, 1.0)
	var smooth := t * t * (3.0 - t * 2.0)
	match insect_state:
		Flight.PERCHED:
			if perched_on_flower:
				var live := live_flower_near(flower_target)
				if live.is_finite():
					flower_target = live
					insect_position = live
				else:
					take_flight()
					return
			elif not temporary_perch:
				insect_position = plant_tip(PERCHES[perch], 2)
			var exposed := wind != null and wind.strength_at(insect_position.x / 320.0) > 0.73
			var flooded := surface_impulse > 0.60 and absf(insect_position.x - impulse_x) < 37.0
			var twilight_rest := current_day_phase > 1.45 and not temporary_perch
			if (not twilight_rest and t >= 1.0) or (insect_age > 2.2 and (exposed or flooded)):
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
			var dest := plant_tip(PERCHES[next_perch], 2)
			if perched_on_flower:
				var live := live_flower_near(flower_target)
				if live.is_finite():
					flower_target = live
					dest = live
				else:
					perched_on_flower = false
			insect_position = flight_origin.lerp(dest, smooth)
			insect_position.y -= sin(t * PI) * 5.5
			if t >= 1.0:
				if not perched_on_flower:
					perch = next_perch
				set_flight(Flight.PERCHED, rng.randf_range(5.5, 13.0) if perched_on_flower else rng.randf_range(6.5, 19.5))

func take_flight() -> void:
	temporary_perch = false
	var was_on_flower := perched_on_flower
	perched_on_flower = false
	flight_origin = insect_position
	var dest := Vector2.ZERO
	if not flower_perches.is_empty() and (not was_on_flower or rng.randf() < 0.65):
		if rng.randf() < 0.72:
			perched_on_flower = true
			flower_target = flower_perches[rng.randi_range(0, flower_perches.size() - 1)]
			dest = flower_target
	if not perched_on_flower:
		next_perch = (perch + rng.randi_range(1, PERCHES.size() - 1)) % PERCHES.size()
		dest = plant_tip(PERCHES[next_perch], 2)
	hover_point = flight_origin.lerp(dest, 0.61) + Vector2(rng.randf_range(-14.0, 14.0), -rng.randf_range(15.0, 28.0))
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
	perched_on_flower = false
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
	for minnow in fry:
		if minnow.pos.distance_to(point) < (56.0 if surge else 34.0):
			var away := minnow.pos - point
			if away.length_squared() > 0.1:
				minnow.heading = away.normalized()
			minnow.alarm = 1.0

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
		var twi := smoothstep(1.15, 1.90, current_day_phase)
		var calm_pace := lerpf(11.0, 6.2, twi)
		var stride := fish_heading * (calm_pace + fish_alarm * 37.0) + velocity.limit_length(16.0) * 0.15
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
		if fish_time >= (14.0 if fish_released else (7.5 if pool_richness > 0.35 else 5.0)) or fish.x < 8.0 or fish.x > 314.0:
			var wait_scale := (0.62 if pool_richness > 0.35 else 1.0) * lerpf(1.0, 1.75, twi)
			fish_due = clock + rng.randf_range(8.0, 20.0) * wait_scale
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

func advance_fry(dt: float, water: Flow) -> void:
	var desired := 3 if pool_richness > 0.55 else (2 if pool_richness > 0.28 else 0)
	if fry.size() < desired:
		for _attempt in 4:
			var probe := Vector2(rng.randf_range(58.0, 244.0), rng.randf_range(-16.0, 16.0))
			if water.depth_at(probe) > 0.22 and water.velocity_at(probe).length() < 18.0:
				var m := Fry.new()
				m.pos = probe
				m.heading = Vector2.from_angle(rng.randf() * TAU)
				m.phase = rng.randf() * TAU
				m.turn_due = rng.randf_range(0.4, 1.3)
				fry.append(m)
				break
	for i in range(fry.size() - 1, -1, -1):
		var m := fry[i]
		m.alarm = move_toward(m.alarm, 0.0, dt * 1.1)
		var v := water.velocity_at(m.pos)
		var calm := pool_richness > 0.14 and water.depth_at(m.pos) > 0.18 and v.length() < 26.0 and m.alarm < 0.65
		m.presence = move_toward(m.presence, 1.0 if (calm and i < desired) else 0.0, dt * (0.9 if calm else 1.8))
		if m.presence <= 0.005 and (not calm or i >= desired):
			fry.remove_at(i)
			continue
		var fry_twi := smoothstep(1.15, 1.90, current_day_phase)
		m.turn_due -= dt
		if m.turn_due <= 0.0:
			m.turn_due = rng.randf_range(0.45, 1.35) * lerpf(1.0, 1.65, fry_twi)
			m.heading = m.heading.rotated(rng.randf_range(-0.65, 0.65))
		var speed := lerpf(8.5, 4.6, fry_twi) + m.alarm * 24.0
		var next := m.pos + (m.heading * speed + v.limit_length(10.0) * 0.12) * dt
		if water.depth_at(next) < 0.20 or absf(next.y) > 22.0 or next.x < 16.0 or next.x > 300.0:
			m.heading = Vector2(-m.heading.x, -signf(m.pos.y) * 0.65).normalized()
		else:
			m.pos = next

func draw_fish(canvas: Node2D, project: Callable, pointer: Vector2, foreground := false) -> void:
	if not foreground:
		for m in fry:
			if m.presence <= 0.02:
				continue
			var fp: Vector2 = project.call(m.pos)
			var fturn := m.heading.angle() - PI
			var flick := sin(clock * (14.0 + m.alarm * 18.0) + m.phase) * 0.75
			var fink := Color(0.11, 0.22, 0.22, m.presence * 0.56)
			canvas.draw_colored_polygon(PackedVector2Array([
				fp + Vector2(-2.2, 0.0).rotated(fturn),
				fp + Vector2(-0.4, -0.65).rotated(fturn),
				fp + Vector2(2.3, flick - 0.35).rotated(fturn),
				fp + Vector2(2.0, flick + 0.55).rotated(fturn),
				fp + Vector2(-0.5, 0.6).rotated(fturn),
			]), fink)
			canvas.draw_line(fp + Vector2(-1.1, -0.2).rotated(fturn), fp + Vector2(0.7, -0.15).rotated(fturn),
				Color(0.56, 0.76, 0.68, m.presence * 0.28), 0.45)
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

func apply_tint(color: Color, at: Vector2, tint_at: Callable) -> Color:
	return tint_at.call(color, at) if tint_at.is_valid() else color

func draw_land(canvas: Node2D, tint_at: Callable = Callable()) -> void:
	for i in SEDGES.size():
		var data: Vector3 = SEDGES[i]
		var root := Vector2(data.x, data.y)
		canvas.draw_rect(Rect2((root * 2.0).round() * 0.5 - Vector2(1.5, 0.5), Vector2(3.0, 1.25)), apply_tint(Color("#333d20"), root, tint_at))
		for stem in (4 if data.z >= 5.0 else 3):
			var span := (stem - 1.4) * 2.0
			var height := data.z * (0.73 + stem % 3 * 0.16)
			var sway := plant_sway(i, stem)
			var split := root + Vector2(span * 0.37 + sway * 0.19, -height * 0.54)
			var tip := plant_tip(i, stem)
			var ink := Color("#596332") if stem % 2 == 0 else Color("#7a7b42")
			canvas.draw_line(root, split, apply_tint(Color("#454c2d"), root, tint_at), 0.5)
			canvas.draw_line(split, tip, apply_tint(ink, root, tint_at), 0.5)
			var blade := split.lerp(tip, 0.53)
			canvas.draw_line(blade, blade + Vector2(1.0 + sway * 0.6, -1.1), apply_tint(ink.lightened(0.11), root, tint_at), 0.5)

	draw_cicada_perch(canvas, tint_at)
	for leaf in [Vector3(58, 155, -0.7), Vector3(60.5, 154, 0.6), Vector3(59, 157, 2.9),
			Vector3(187, 151, 0.4), Vector3(196, 46, -1.7), Vector3(109, 169, 2.8)]:
		draw_litter_leaf(canvas, Vector2(leaf.x, leaf.y), leaf.z, apply_tint(Color("#96744a"), Vector2(leaf.x, leaf.y), tint_at))

	# Litter caught at breaks in the rock bank.
	draw_litter_leaf(canvas, Vector2(89.5, 94.5), 0.5, apply_tint(Color("#766145"), Vector2(89.5, 94.5), tint_at))
	var twig := Vector2(227.5, 126.0)
	canvas.draw_polyline(PackedVector2Array([twig + Vector2(-3, -2.5), twig, twig + Vector2(3, 0.5)]), apply_tint(Color("#675746"), twig, tint_at), 0.5)
	canvas.draw_line(twig + Vector2(-3, -2.5), twig, apply_tint(Color("#3d4f46"), twig, tint_at), 0.5)
	canvas.draw_line(twig, twig + Vector2(2, -1.5), apply_tint(Color("#89704f"), twig, tint_at), 0.5)

	# A small sun-bleached bamboo stake by the path.
	var stake := Vector2(191.0, 41.0)
	canvas.draw_line(stake, stake + Vector2(4, 1), Color("#36392e62"), 1.0)
	canvas.draw_line(stake, stake + Vector2(-0.8, -9.0), apply_tint(Color("#5e5a36"), stake, tint_at), 1.5)
	canvas.draw_line(stake + Vector2(-0.4, -1), stake + Vector2(-1.0, -8.6), apply_tint(Color("#a7965b"), stake, tint_at), 0.5)
	canvas.draw_line(stake + Vector2(-1.6, -5.3), stake + Vector2(0.4, -5.6), apply_tint(Color("#c3a77a"), stake, tint_at), 0.5)

func draw_litter_leaf(canvas: Node2D, at: Vector2, turn: float, ink: Color) -> void:
	var shape := PackedVector2Array([Vector2(-1.5, 0), Vector2(-0.5, -0.8), Vector2(1.6, -0.5), Vector2(0.6, 0.5), Vector2(-0.6, 0.5)])
	for i in shape.size():
		shape[i] = (at * 2.0 + shape[i].rotated(turn) * 2.0).round() * 0.5
	canvas.draw_colored_polygon(shape, ink)
	canvas.draw_line(at, at + Vector2(1.7, -0.4).rotated(turn), ink.darkened(0.26), 0.5)

func snap(point: Vector2) -> Vector2:
	return (point * 2.0).round() * 0.5

func draw_cicada_perch(canvas: Node2D, tint_at: Callable = Callable()) -> void:
	var p := CICADA_PERCH
	var sway := (wind.flutter(23) * 0.35) if wind != null else 0.0
	var tip := snap(p + Vector2(-7.5 + sway, -5.5))
	var tail := snap(p + Vector2(5.5, 3.8))
	var fork_root := snap(p + Vector2(1.5, 1.0))
	var fork_tip := snap(p + Vector2(4.2 + sway * 0.5, -1.2))
	# Deep shadow leaves tucking the branch into the upper-left canopy.
	for row in [
		[Vector2(-7.0, -4.5), Vector2(-4.5, -7.0), Vector2(-1.5, -5.2), Color("#223321")],
		[Vector2(2.0, -2.5), Vector2(5.5, -3.5), Vector2(4.5, -0.5), Color("#334829")],
		[Vector2(3.5, 2.5), Vector2(7.0, 1.8), Vector2(5.8, 4.8), Color("#223321")],
	]:
		var pts := PackedVector2Array([snap(p + row[0]), snap(p + row[1]), snap(p + row[2])])
		canvas.draw_colored_polygon(pts, apply_tint(row[3], p, tint_at))
	# Dark twig core, bark tone, and subtle upper rim highlight.
	canvas.draw_line(tip + Vector2(0.0, 0.75), tail + Vector2(0.0, 0.75), apply_tint(Color("#222119"), p, tint_at), 1.75)
	canvas.draw_line(tip, tail, apply_tint(Color("#4a3d2d"), p, tint_at), 1.5)
	canvas.draw_line(tip + Vector2(0.5, -0.4), tail + Vector2(-0.5, -0.4), apply_tint(Color("#6c5a41"), p, tint_at), 0.5)
	canvas.draw_line(fork_root, fork_tip, apply_tint(Color("#4a3d2d"), p, tint_at), 0.9)
	canvas.draw_line(fork_root + Vector2(0.0, -0.35), fork_tip + Vector2(-0.2, -0.35), apply_tint(Color("#6c5a41"), p, tint_at), 0.45)

func draw_cicada(canvas: Node2D, pointer: Vector2, tint_at: Callable = Callable()) -> void:
	var at := pointer - Vector2(0, 5) if cicada_held else cicada_position
	var at_home := not cicada_held and cicada_position.distance_to(CICADA_PERCH) < 2.5
	var sway := (wind.flutter(23) * 0.35) if (at_home and wind != null) else 0.0
	var base := snap(at + Vector2(sway * 0.5, 0.0))
	var body_turn := cicada_angle + (sin(clock * 22.0) * 0.10 if cicada_held else sin(clock * 15.0) * 0.05 * cicada_twitch)
	var fwd := Vector2.from_angle(body_turn)
	var side := Vector2(-fwd.y, fwd.x)
	var pump := (0.28 + 0.25 * sin(cicada_sing_age * TAU / 0.58)) * cicada_sing_level
	var wing_spread := (0.75 + sin(clock * 64.0) * 0.35) if cicada_held else (
		0.42 * cicada_sing_level + sin(clock * 74.0) * 0.32 * cicada_sing_level + cicada_twitch * 0.22)

	var shadow_poly := PackedVector2Array()
	if not cicada_held:
		for local_pt: Vector2 in [Vector2(3.4, -1.3), Vector2(3.4, 1.3), Vector2(-4.5, 1.4), Vector2(-5.2, 0.0), Vector2(-4.5, -1.4)]:
			shadow_poly.append(snap(base + Vector2(0.5, 1.0) + fwd * local_pt.x + side * local_pt.y))
		canvas.draw_colored_polygon(shadow_poly, Color("#141e176e"))

	# 1. Six jointed clinging legs (fore, mid, hind pairs).
	for i in 3:
		var u: float = [1.7, 0.2, -1.2][i]
		var leg_kick := sin(clock * 28.0 + i * 2.1) * 0.85 if cicada_held else 0.0
		var femur_reach := 1.45 if i == 1 else (1.35 if i == 0 else 1.55)
		var tibia_back := -0.75 if i == 2 else (0.35 if i == 0 else -0.25)
		for s: float in [-1.0, 1.0]:
			var root_pt := snap(base + fwd * u + side * (s * 0.85))
			var knee_pt := snap(base + fwd * (u + (0.25 if i == 0 else -0.25)) + side * (s * (femur_reach + leg_kick * s)))
			var foot_pt := snap(base + fwd * (u + tibia_back + leg_kick * 0.3) + side * (s * (femur_reach + 0.45)))
			canvas.draw_line(root_pt, knee_pt, apply_tint(Color("#2a221b"), base, tint_at), 0.65)
			canvas.draw_line(knee_pt, foot_pt, apply_tint(Color("#493b2c"), base, tint_at), 0.55)

	# 2. Segmented dark-brown abdomen (pumps gently while singing).
	var ab_shift := -fwd * pump
	var ab_poly := PackedVector2Array()
	for local_pt: Vector2 in [Vector2(0.2, -1.3), Vector2(-2.2, -1.05), Vector2(-3.5, 0.0), Vector2(-2.2, 1.05), Vector2(0.2, 1.3)]:
		ab_poly.append(snap(base + ab_shift + fwd * local_pt.x + side * local_pt.y))
	canvas.draw_colored_polygon(ab_poly, apply_tint(Color("#26201b"), base, tint_at))
	for band_u: float in [-0.45, -1.35, -2.25]:
		var w := 1.05 if band_u > -1.0 else (0.9 if band_u > -2.0 else 0.65)
		canvas.draw_line(snap(base + ab_shift + fwd * band_u - side * w),
			snap(base + ab_shift + fwd * band_u + side * w), apply_tint(Color("#735a39"), base, tint_at), 0.55)

	# 3. Broad thorax with classic ochre collar / M-pattern markings.
	var thorax_poly := PackedVector2Array()
	for local_pt: Vector2 in [Vector2(2.6, -1.45), Vector2(1.1, -1.65), Vector2(0.1, -1.35),
			Vector2(0.1, 1.35), Vector2(1.1, 1.65), Vector2(2.6, 1.45)]:
		thorax_poly.append(snap(base + fwd * local_pt.x + side * local_pt.y))
	canvas.draw_colored_polygon(thorax_poly, apply_tint(Color("#2e261f"), base, tint_at))
	# Pronotum collar stripe and mesonotum M-mark.
	canvas.draw_line(snap(base + fwd * 2.15 - side * 1.15), snap(base + fwd * 2.15 + side * 1.15),
		apply_tint(Color("#846940"), base, tint_at), 0.6)
	canvas.draw_polyline(PackedVector2Array([
		snap(base + fwd * 0.4 - side * 0.95),
		snap(base + fwd * 1.4 - side * 0.45),
		snap(base + fwd * 0.7),
		snap(base + fwd * 1.4 + side * 0.45),
		snap(base + fwd * 0.4 + side * 0.95),
	]), apply_tint(Color("#a48652"), base, tint_at), 0.55)

	# 4. Wide flat head, protruding dark-amber compound eyes, and short antennae.
	var head_poly := PackedVector2Array()
	for local_pt: Vector2 in [Vector2(3.45, -1.2), Vector2(2.5, -1.5), Vector2(2.5, 1.5), Vector2(3.45, 1.2)]:
		head_poly.append(snap(base + fwd * local_pt.x + side * local_pt.y))
	canvas.draw_colored_polygon(head_poly, apply_tint(Color("#332b21"), base, tint_at))
	canvas.draw_rect(Rect2(snap(base + fwd * 2.95) - Vector2(0.25, 0.25), Vector2(0.5, 0.5)),
		apply_tint(Color("#b38f52"), base, tint_at))
	for s: float in [-1.0, 1.0]:
		var eye_pos := snap(base + fwd * 3.05 + side * (s * 1.45))
		canvas.draw_rect(Rect2(eye_pos - Vector2(0.5, 0.5), Vector2(1.25, 1.25)), apply_tint(Color("#221612"), base, tint_at))
		canvas.draw_rect(Rect2(eye_pos - Vector2(0.25, 0.25), Vector2(0.9, 0.9)), apply_tint(Color("#8a4b2b"), base, tint_at))
		canvas.draw_rect(Rect2(eye_pos + Vector2(-0.15, -0.25), Vector2(0.45, 0.45)), apply_tint(Color("#d9b57e"), base, tint_at))
		# Short bristly antenna on front of head.
		canvas.draw_line(snap(base + fwd * 3.35 + side * (s * 0.55)),
			snap(base + fwd * 4.15 + side * (s * 1.0)), apply_tint(Color("#554632"), base, tint_at), 0.5)

	# 5. Roof-like translucent veined wings extending well past the abdomen tip.
	var wing_membrane := apply_tint(Color(0.75, 0.71, 0.55, 0.40), base, tint_at)
	var wing_base_tint := apply_tint(Color(0.36, 0.29, 0.20, 0.65), base, tint_at)
	var costa_ink := apply_tint(Color("#3c3222"), base, tint_at)
	var sub_costa := apply_tint(Color("#725f3e"), base, tint_at)
	var vein_ink := apply_tint(Color(0.30, 0.26, 0.18, 0.72), base, tint_at)
	var glint_ink := apply_tint(Color(0.93, 0.90, 0.76, 0.30 + 0.18 * cicada_sing_level), base, tint_at)
	for s: float in [-1.0, 1.0]:
		var flare := wing_spread * s
		var wing_pts := PackedVector2Array([
			snap(base + fwd * 1.3 + side * (s * 0.95)),
			snap(base + fwd * -0.4 + side * (s * 1.85 + flare * 0.7)),
			snap(base + fwd * -3.2 + side * (s * 1.9 + flare * 1.35)),
			snap(base + fwd * -5.0 + side * (s * 0.9 + flare * 1.45)),
			snap(base + fwd * -3.6 + side * (s * 0.22 + flare * 0.85)),
			snap(base + fwd * 0.4 + side * (s * 0.35 + flare * 0.15)),
		])
		canvas.draw_colored_polygon(wing_pts, wing_membrane)
		var base_patch := PackedVector2Array([
			wing_pts[0],
			snap(base + fwd * 0.0 + side * (s * 1.55 + flare * 0.45)),
			snap(base + fwd * -0.9 + side * (s * 0.75 + flare * 0.35)),
			wing_pts[5],
		])
		canvas.draw_colored_polygon(base_patch, wing_base_tint)
		# Costal margin vein + inner dark branching veins + subtle sheen.
		canvas.draw_polyline(PackedVector2Array([wing_pts[0], wing_pts[1], wing_pts[2], wing_pts[3]]), costa_ink, 0.6)
		canvas.draw_line(wing_pts[0], wing_pts[2], sub_costa, 0.45)
		canvas.draw_line(snap(base + fwd * 0.3 + side * (s * 1.05 + flare * 0.25)),
			snap(base + fwd * -4.0 + side * (s * 1.2 + flare * 1.15)), vein_ink, 0.5)
		canvas.draw_line(snap(base + fwd * -0.8 + side * (s * 0.75 + flare * 0.35)),
			snap(base + fwd * -3.5 + side * (s * 0.5 + flare * 0.9)), vein_ink, 0.45)
		canvas.draw_line(snap(base + fwd * -0.6 + side * (s * 1.45 + flare * 0.55)),
			snap(base + fwd * -2.9 + side * (s * 1.65 + flare * 1.15)), glint_ink, 0.45)

func draw_insect(canvas: Node2D, pointer: Vector2, tint_at: Callable = Callable()) -> void:
	var point := pointer - Vector2(0, 5) if insect_held else insect_position
	var settled := insect_held or insect_state == Flight.PERCHED
	var resting_twilight := settled and not insect_held and current_day_phase > 1.45
	var flex := 0.0 if resting_twilight else (sin(insect_age * 61.0) if not settled else sin(clock * 5.0) * smoothstep(0.87, 0.99, sin(clock * 0.7)) * 0.65)
	var glint := apply_tint(Color(0.78, 0.91, 0.72, 0.63 + absf(flex) * 0.26), point, tint_at)
	canvas.draw_line(point - Vector2(3.2, 0), point + Vector2(2.2, -0.6), apply_tint(Color("#345947"), point, tint_at), 0.8)
	for side in [-1.0, 1.0]:
		var tip := point + Vector2(-0.75, (2.15 + flex) * side)
		canvas.draw_line(point, tip, glint, 0.5)
		canvas.draw_line(point - Vector2(0.8, 0), tip - Vector2(1.1, 0), Color(glint, 0.56), 0.5)
	canvas.draw_rect(Rect2(point + Vector2(1.0, -0.5), Vector2(0.9, 0.5)), apply_tint(Color("#75b087"), point, tint_at))
