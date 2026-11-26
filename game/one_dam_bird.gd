extends RefCounted

enum State { AWAY, APPROACHING, PERCHED, DEPARTING }

signal chirped
signal startled_off

const SIZE := Vector2(320.0, 200.0)
const ROADSIDE_PERCHES: Array[Vector2] = [
	Vector2(160.0, 14.0), Vector2(190.0, 17.0), Vector2(216.0, 22.0),
	Vector2(66.0, 175.0), Vector2(98.0, 176.0), Vector2(132.0, 186.0),
]
const SPOOK_RADIUS := 30.0
const ALERT_RADIUS := 46.0
const FAST_SPOOK_RADIUS := 56.0
const FAST_POINTER_SPEED := 90.0

var rng := RandomNumberGenerator.new()
var state := State.AWAY
var position := Vector2(-24.0, -16.0)
var height := 28.0
var start_pos := Vector2.ZERO
var target_pos := Vector2.ZERO
var start_height := 28.0
var velocity := Vector2.ZERO
var facing := 1.0
var age := 0.0
var duration := 1.0
var away_due := 5.2
var stay_left := 0.0
var startled := false
var alert := 0.0
var flap_phase := 0.0
var tail_bob := 0.0
var head_turn := 0.0
var look_due := 0.9
var peck_age := -1.0
var peck_due := 2.0
var hop_origin := Vector2.ZERO
var hop_target := Vector2.ZERO
var hop_age := -1.0
var hop_due := 2.4
var chirp_due := 1.8
var clock := 0.0
var prev_pointer := Vector2.INF
var last_perch_index := -1

func reset() -> void:
	state = State.AWAY
	position = Vector2(-24.0, -16.0)
	height = 28.0
	start_pos = position
	target_pos = position
	start_height = 28.0
	velocity = Vector2.ZERO
	facing = 1.0
	age = 0.0
	duration = 1.0
	away_due = 5.2
	stay_left = 0.0
	startled = false
	alert = 0.0
	flap_phase = 0.0
	tail_bob = 0.0
	head_turn = 0.0
	look_due = 0.9
	peck_age = -1.0
	peck_due = 2.0
	hop_origin = Vector2.ZERO
	hop_target = Vector2.ZERO
	hop_age = -1.0
	hop_due = 2.4
	chirp_due = 1.8
	clock = 0.0
	prev_pointer = Vector2.INF
	last_perch_index = -1

func is_airborne() -> bool:
	return state == State.APPROACHING or state == State.DEPARTING

func is_clear_perch(pt: Vector2, pointer: Vector2, pointer_inside: bool, rocks: Array, spot_wet: Callable,
		min_pointer_dist: float, hearth_pos := Vector2.INF, hearth_lit := false) -> bool:
	if not Rect2(Vector2(10.0, 10.0), SIZE - Vector2(20.0, 20.0)).has_point(pt):
		return false
	if pt.x > 142.0 and pt.y > 162.0:
		return false
	if hearth_lit and hearth_pos.is_finite() and pt.distance_to(hearth_pos) < 58.0:
		return false
	if pointer_inside and pt.distance_to(pointer) < min_pointer_dist:
		return false
	if spot_wet.is_valid():
		var wet: bool = bool(spot_wet.call(pt))
		if wet:
			return false
	for rock in rocks:
		if rock.hit(pt, pt, 4.0):
			return false
	return true

func advance(dt: float, pointer: Vector2, rain_intensity: float, rocks: Array, spot_wet: Callable,
		day_phase := 0.0, after_rain := 0.0, puddle_spots: Array[Vector2] = [],
		hearth_pos := Vector2.INF, hearth_lit := false) -> void:
	if dt <= 0.0:
		return
	clock += dt
	tail_bob = move_toward(tail_bob, 0.0, dt * 2.5)
	var pointer_inside := Rect2(Vector2.ZERO, SIZE).has_point(pointer)
	var pointer_speed := 0.0
	if pointer_inside and prev_pointer.is_finite():
		pointer_speed = pointer.distance_to(prev_pointer) / maxf(dt, 0.001)
	prev_pointer = pointer if pointer_inside else Vector2.INF
	var roosting := day_phase > 1.55

	match state:
		State.AWAY:
			if rain_intensity > 0.30 or roosting:
				return
			if after_rain > 0.25 and rain_intensity < 0.12 and away_due > 3.8:
				away_due = 3.8
			away_due -= dt
			if away_due > 0.0:
				return
			var perch := Vector2.INF
			# After a rain shower, prefer landing beside a gleaming wet roadside puddle.
			if after_rain > 0.20 and not puddle_spots.is_empty():
				var puddle_picks: Array[Vector2] = []
				for spot: Vector2 in puddle_spots:
					if is_clear_perch(spot, pointer, pointer_inside, rocks, spot_wet, 44.0, hearth_pos, hearth_lit):
						puddle_picks.append(spot)
				if not puddle_picks.is_empty():
					perch = puddle_picks[rng.randi_range(0, puddle_picks.size() - 1)]
			if not perch.is_finite():
				var candidates: Array[int] = []
				for i in ROADSIDE_PERCHES.size():
					var pt: Vector2 = ROADSIDE_PERCHES[i]
					if is_clear_perch(pt, pointer, pointer_inside, rocks, spot_wet, 44.0, hearth_pos, hearth_lit):
						candidates.append(i)
				if candidates.is_empty():
					away_due = 3.0
					return
				if candidates.size() > 1 and last_perch_index >= 0:
					candidates.erase(last_perch_index)
				var pick: int = candidates[rng.randi_range(0, candidates.size() - 1)]
				last_perch_index = pick
				perch = ROADSIDE_PERCHES[pick]
			var from_left := perch.x > SIZE.x * 0.52 or (perch.x > 80.0 and rng.randf() < 0.5)
			var entry_x := clampf(perch.x + ((-95.0 if from_left else 95.0) + rng.randf_range(-24.0, 24.0)), -26.0, SIZE.x + 26.0)
			var entry_y := -16.0 if perch.y < SIZE.y * 0.5 else clampf(perch.y - rng.randf_range(44.0, 74.0), -14.0, SIZE.y + 12.0)
			if entry_x > 16.0 and entry_x < SIZE.x - 16.0:
				entry_y = -18.0
			var entry := Vector2(entry_x, entry_y)
			start_pos = entry
			target_pos = perch
			position = entry
			start_height = rng.randf_range(26.0, 40.0)
			height = start_height
			age = 0.0
			duration = clampf(entry.distance_to(perch) / 92.0, 0.95, 1.85)
			facing = 1.0 if perch.x >= entry.x else -1.0
			startled = false
			alert = 0.0
			flap_phase = rng.randf() * TAU
			state = State.APPROACHING

		State.APPROACHING:
			age += dt
			var t := clampf(age / maxf(duration, 0.01), 0.0, 1.0)
			var ease_t := 1.0 - pow(1.0 - t, 2.2)
			position = start_pos.lerp(target_pos, ease_t)
			height = start_height * pow(1.0 - t, 1.75) + sin(t * PI) * 4.0
			flap_phase += dt * (20.0 + smoothstep(0.65, 1.0, t) * 10.0)
			if height < 16.0 and pointer_inside and position.distance_to(pointer) < SPOOK_RADIUS:
				startle(pointer)
				return
			if t >= 1.0:
				position = target_pos
				height = 0.0
				state = State.PERCHED
				tail_bob = 1.0
				stay_left = rng.randf_range(5.5, 11.0)
				chirp_due = rng.randf_range(0.5, 2.2)
				look_due = rng.randf_range(0.6, 1.5)
				peck_due = rng.randf_range(1.2, 3.0)
				hop_due = rng.randf_range(1.8, 3.8)
				peck_age = -1.0
				hop_age = -1.0
				head_turn = 0.0

		State.PERCHED:
			if rain_intensity > 0.30 or roosting:
				take_off(position + Vector2(0.0, 12.0), false)
				return
			if pointer_inside:
				var dist := position.distance_to(pointer)
				if dist < SPOOK_RADIUS or (pointer_speed > FAST_POINTER_SPEED and dist < FAST_SPOOK_RADIUS):
					startle(pointer)
					return
				if dist < ALERT_RADIUS:
					alert = move_toward(alert, 1.0, dt * 7.5)
					if absf(pointer.x - position.x) > 2.0:
						facing = 1.0 if pointer.x > position.x else -1.0
					peck_age = -1.0
				else:
					alert = move_toward(alert, 0.0, dt * 3.0)
			else:
				alert = move_toward(alert, 0.0, dt * 3.0)

			stay_left -= dt
			if hop_age >= 0.0:
				hop_age += dt
				var ht := clampf(hop_age / 0.22, 0.0, 1.0)
				position = hop_origin.lerp(hop_target, ht)
				height = sin(ht * PI) * 3.8
				if ht >= 1.0:
					position = hop_target
					height = 0.0
					hop_age = -1.0
					tail_bob = 0.75
			if peck_age >= 0.0:
				peck_age += dt
				if peck_age >= 0.30:
					peck_age = -1.0
			if alert < 0.2:
				look_due -= dt
				if look_due <= 0.0:
					look_due = rng.randf_range(0.7, 1.9)
					head_turn = rng.randf_range(-0.6, 0.9)
					if rng.randf() < 0.32 and hop_age < 0.0:
						facing = -facing
						tail_bob = 0.35
				peck_due -= dt
				if peck_due <= 0.0 and hop_age < 0.0:
					peck_due = rng.randf_range(1.6, 4.0)
					peck_age = 0.0
				hop_due -= dt
				if hop_due <= 0.0 and hop_age < 0.0 and peck_age < 0.0 and stay_left > 1.2:
					hop_due = rng.randf_range(2.2, 4.5)
					for _try in 4:
						var candidate := position + Vector2(facing * rng.randf_range(4.5, 9.5), rng.randf_range(-4.0, 4.0))
						if candidate.distance_to(target_pos) <= 16.0 and is_clear_perch(candidate, pointer, pointer_inside, rocks, spot_wet, SPOOK_RADIUS + 4.0, hearth_pos, hearth_lit):
							hop_origin = position
							hop_target = candidate
							hop_age = 0.0
							facing = 1.0 if candidate.x >= position.x else -1.0
							break
				chirp_due -= dt
				if chirp_due <= 0.0:
					chirp_due = rng.randf_range(2.6, 5.4)
					tail_bob = maxf(tail_bob, 0.55)
					chirped.emit()
			if stay_left <= 0.0 and hop_age < 0.0:
				take_off(position - Vector2(facing * 12.0, 0.0), false)

		State.DEPARTING:
			age += dt
			var rate := 34.0 if startled else 25.0
			flap_phase += dt * rate
			var lift_rate := 58.0 if startled else 38.0
			velocity.y -= (24.0 if startled else 14.0) * dt
			position += velocity * dt
			height += (lift_rate + age * 28.0) * dt
			var visual_y := position.y - height
			if visual_y < -20.0 or position.x < -20.0 or position.x > SIZE.x + 20.0 or age > 3.2:
				state = State.AWAY
				height = 28.0
				startled = false
				away_due = rng.randf_range(14.0, 28.0)

func disturb(origin: Vector2, radius := 72.0) -> void:
	if (state == State.PERCHED or (state == State.APPROACHING and height < 20.0)) and origin.distance_to(position) <= radius:
		startle(origin)

func startle(threat: Vector2) -> void:
	take_off(threat, true)

func take_off(threat: Vector2, is_startled: bool) -> void:
	if state == State.AWAY or state == State.DEPARTING:
		return
	var away := position - threat
	if away.length_squared() < 1.0:
		away = Vector2(facing, -0.6)
	else:
		away = away.normalized()
	if absf(away.x) < 0.25:
		away.x = facing * 0.65
	var horiz_speed := rng.randf_range(88.0, 120.0) if is_startled else rng.randf_range(58.0, 78.0)
	var vert_drift := clampf(away.y, -0.75, 0.25) * (42.0 if is_startled else 24.0) - (16.0 if is_startled else 10.0)
	facing = 1.0 if away.x >= 0.0 else -1.0
	velocity = Vector2(facing * horiz_speed, vert_drift)
	height = maxf(height, 0.5)
	age = 0.0
	peck_age = -1.0
	hop_age = -1.0
	startled = is_startled
	state = State.DEPARTING
	if is_startled:
		startled_off.emit()

func snap(pt: Vector2) -> Vector2:
	return (pt * 2.0).round() * 0.5

func apply_tint(color: Color, at: Vector2, tint_at: Callable) -> Color:
	return tint_at.call(color, at) if tint_at.is_valid() else color

func draw(canvas: Node2D, tint_at: Callable = Callable()) -> void:
	if state == State.AWAY:
		return
	var shade_at := position
	var shadow_scale := clampf(1.0 - height / 52.0, 0.35, 1.0)
	var shadow_alpha := clampf(0.42 * (1.0 - height / 46.0), 0.08, 0.42)
	var shadow_pos := snap(position + Vector2(height * 0.14, 1.0))
	canvas.draw_colored_polygon(PackedVector2Array([
		shadow_pos + Vector2(-2.6, 0.0) * shadow_scale,
		shadow_pos + Vector2(0.0, -1.0) * shadow_scale,
		shadow_pos + Vector2(2.8, 0.0) * shadow_scale,
		shadow_pos + Vector2(0.0, 1.1) * shadow_scale,
	]), Color(0.11, 0.12, 0.09, shadow_alpha))

	var body := snap(position - Vector2(0.0, height))
	var f := facing
	var crown_ink := apply_tint(Color("#7c4627"), shade_at, tint_at)
	var back_ink := apply_tint(Color("#8a5634"), shade_at, tint_at)
	var wing_ink := apply_tint(Color("#3e2c21"), shade_at, tint_at)
	var tail_ink := apply_tint(Color("#403126"), shade_at, tint_at)
	var bar_ink := apply_tint(Color("#ebd8b3"), shade_at, tint_at)
	var belly_ink := apply_tint(Color("#e5d7be"), shade_at, tint_at)
	var cheek_ink := apply_tint(Color("#ece0ca"), shade_at, tint_at)
	var dark_ink := apply_tint(Color("#181412"), shade_at, tint_at)
	var eye_glint := apply_tint(Color("#f8f1dc"), shade_at, tint_at)
	var beak_ink := apply_tint(Color("#2d231b"), shade_at, tint_at)
	var leg_ink := apply_tint(Color("#6b4c39"), shade_at, tint_at)

	if is_airborne():
		var flap := sin(flap_phase)
		var tilt := -0.22 if state == State.DEPARTING else 0.12
		var tail_fan := 1.0 if state == State.APPROACHING else 0.45
		# Far wing behind body.
		var far_tip := body + Vector2(-f * 1.4, -3.5 * flap - 1.5)
		canvas.draw_colored_polygon(PackedVector2Array([
			snap(body + Vector2(f * 0.2, -1.5)),
			snap(far_tip),
			snap(body + Vector2(-f * 2.4, -1.0)),
		]), wing_ink.darkened(0.18))
		# Tail feathers spread slightly while flying/braking.
		canvas.draw_colored_polygon(PackedVector2Array([
			snap(body + Vector2(-f * 1.6, 0.2)),
			snap(body + Vector2(-f * 5.2, -1.2 - tail_fan * 0.8)),
			snap(body + Vector2(-f * 5.0, 0.8 + tail_fan * 0.7)),
		]), tail_ink)
		# Torso + belly.
		canvas.draw_colored_polygon(PackedVector2Array([
			snap(body + Vector2(-f * 2.2, 0.3)),
			snap(body + Vector2(-f * 0.3, -1.5 + tilt)),
			snap(body + Vector2(f * 2.4, -1.1 + tilt)),
			snap(body + Vector2(f * 2.0, 1.3)),
			snap(body + Vector2(-f * 1.2, 1.4)),
		]), belly_ink)
		canvas.draw_colored_polygon(PackedVector2Array([
			snap(body + Vector2(-f * 2.2, 0.2)),
			snap(body + Vector2(f * 0.1, -1.7 + tilt)),
			snap(body + Vector2(f * 2.2, -1.0 + tilt)),
			snap(body + Vector2(-f * 0.5, 0.1)),
		]), back_ink)
		# Head + crown + cheek + eye + beak.
		var hpos := body + Vector2(f * 2.3, -1.6 + tilt * 2.0)
		canvas.draw_colored_polygon(PackedVector2Array([
			snap(hpos + Vector2(-f * 1.2, -1.0)),
			snap(hpos + Vector2(f * 1.1, -1.2)),
			snap(hpos + Vector2(f * 1.5, 0.7)),
			snap(hpos + Vector2(-f * 1.0, 1.0)),
		]), cheek_ink)
		canvas.draw_line(snap(hpos + Vector2(-f * 1.1, -1.0)), snap(hpos + Vector2(f * 1.1, -1.0)), crown_ink, 1.0)
		canvas.draw_line(snap(hpos + Vector2(f * 1.3, -0.2)), snap(hpos + Vector2(f * 2.8, 0.0)), beak_ink, 0.75)
		canvas.draw_rect(Rect2(snap(hpos + Vector2(f * 0.35, -0.55)), Vector2(0.75, 0.75)), dark_ink)
		# Near flapping wing with pale bar.
		var wing_lift := clampf(-flap * 4.2, -3.6, 4.0)
		var wing_poly := PackedVector2Array([
			snap(body + Vector2(f * 0.7, -0.9)),
			snap(body + Vector2(-f * 0.4, wing_lift - 1.4)),
			snap(body + Vector2(-f * 3.8, wing_lift * 0.75 - 0.5)),
			snap(body + Vector2(-f * 2.2, 0.3)),
		])
		canvas.draw_colored_polygon(wing_poly, wing_ink)
		canvas.draw_line(snap(body + Vector2(f * 0.3, -0.8)), snap(body + Vector2(-f * 1.7, wing_lift * 0.55 - 0.6)), back_ink, 0.9)
		canvas.draw_line(snap(body + Vector2(-f * 0.2, wing_lift * 0.4 - 0.5)), snap(body + Vector2(-f * 2.2, wing_lift * 0.5)), bar_ink, 0.55)
		return

	# Perched / hopping / pecking sparrow posture.
	var peck := sin(clampf(peck_age / 0.30, 0.0, 1.0) * PI) if peck_age >= 0.0 else 0.0
	var bob := sin(tail_bob * PI) * 0.9 + sin(clock * 2.6) * 0.2
	var stand_lift := alert * 0.9 - peck * 1.2
	# Feet on ground.
	for lx: float in [-0.7, 0.6]:
		var leg_top := snap(body + Vector2(f * lx, -0.9))
		var foot := snap(body + Vector2(f * (lx - 0.25), 0.7))
		canvas.draw_line(leg_top, foot, leg_ink, 0.55)
		canvas.draw_line(foot, snap(foot + Vector2(f * 1.2, 0.0)), leg_ink, 0.5)

	# Tail angled upward behind body.
	var tail_tip := snap(body + Vector2(-f * 5.0, -2.5 - bob - alert * 0.7 + peck * 0.9))
	canvas.draw_colored_polygon(PackedVector2Array([
		snap(body + Vector2(-f * 1.7, -1.0)),
		tail_tip,
		snap(tail_tip + Vector2(f * 0.4, 1.0)),
		snap(body + Vector2(-f * 1.4, -0.1)),
	]), tail_ink)

	# Plump belly + chest.
	var chest_shift := Vector2(f * peck * 0.7, -stand_lift * 0.5 + peck * 0.7)
	canvas.draw_colored_polygon(PackedVector2Array([
		snap(body + chest_shift + Vector2(-f * 2.1, -0.9)),
		snap(body + chest_shift + Vector2(-f * 0.3, -2.8)),
		snap(body + chest_shift + Vector2(f * 2.1, -2.7)),
		snap(body + chest_shift + Vector2(f * 2.3, -0.6)),
		snap(body + chest_shift + Vector2(f * 0.6, 0.3)),
		snap(body + chest_shift + Vector2(-f * 1.6, -0.1)),
	]), belly_ink)
	# Warm chestnut back + folded wing with wing bar.
	canvas.draw_colored_polygon(PackedVector2Array([
		snap(body + chest_shift + Vector2(-f * 2.2, -1.1)),
		snap(body + chest_shift + Vector2(f * 0.0, -3.1)),
		snap(body + chest_shift + Vector2(f * 1.9, -2.6)),
		snap(body + chest_shift + Vector2(f * 0.4, -1.2)),
	]), back_ink)
	canvas.draw_colored_polygon(PackedVector2Array([
		snap(body + chest_shift + Vector2(f * 0.6, -2.0)),
		snap(body + chest_shift + Vector2(-f * 2.6, -1.2)),
		snap(body + chest_shift + Vector2(-f * 2.2, -0.2)),
		snap(body + chest_shift + Vector2(f * 0.5, -0.8)),
	]), wing_ink)
	canvas.draw_line(snap(body + chest_shift + Vector2(f * 0.2, -1.7)),
		snap(body + chest_shift + Vector2(-f * 1.4, -1.25)), bar_ink, 0.55)

	# Head, chestnut cap, pale cheek + dark cheek spot, eye & short conical beak.
	var head_center := snap(body + Vector2(f * (1.55 + peck * 1.5), -3.5 - stand_lift + peck * 2.6 + head_turn * 0.15))
	canvas.draw_colored_polygon(PackedVector2Array([
		head_center + Vector2(-f * 1.3, -0.8),
		head_center + Vector2(f * 0.2, -1.45),
		head_center + Vector2(f * 1.4, -0.9),
		head_center + Vector2(f * 1.35, 0.9),
		head_center + Vector2(-f * 1.1, 1.0),
	]), cheek_ink)
	canvas.draw_colored_polygon(PackedVector2Array([
		head_center + Vector2(-f * 1.35, -0.7),
		head_center + Vector2(f * 0.2, -1.55),
		head_center + Vector2(f * 1.3, -1.0),
		head_center + Vector2(f * 0.9, -0.45),
		head_center + Vector2(-f * 1.1, -0.2),
	]), crown_ink)
	# Sparrow cheek spot + crisp dark eye with catchlight.
	canvas.draw_rect(Rect2(head_center + Vector2(-f * 0.3, 0.25), Vector2(0.75, 0.6)), dark_ink)
	var eye_pt := snap(head_center + Vector2(f * 0.45, -0.45))
	canvas.draw_rect(Rect2(eye_pt, Vector2(0.75, 0.75)), dark_ink)
	canvas.draw_rect(Rect2(eye_pt + Vector2(0.0, -0.1), Vector2(0.35, 0.35)), eye_glint)
	# Conical beak pointing ahead (dips down when pecking).
	var beak_tip := snap(head_center + Vector2(f * 2.7, 0.1 + peck * 1.05))
	canvas.draw_colored_polygon(PackedVector2Array([
		snap(head_center + Vector2(f * 1.2, -0.4)),
		beak_tip,
		snap(head_center + Vector2(f * 1.2, 0.45)),
	]), beak_ink)
