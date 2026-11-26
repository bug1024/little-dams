extends RefCounted

const MANTIS_PATCH := Rect2(187, 156, 26, 14)
const WATER_SPEED := 30.0
const MOLE_SCALE := 0.58
const CLEARANCE := 7.3 + 5.7 * MOLE_SCALE
const ROAM_AREA := Rect2(8, 8, 304, 184)
const CLIMB_LIMIT := 4.5

class Rock:
	var center: Vector2
	var radius: Vector2
	var height: float

	func hit(start: Vector2, end: Vector2, padding: float) -> bool:
		var footprint := radius + Vector2.ONE * padding
		var a := (start - center) / footprint
		var b := (end - center) / footprint
		if start == end:
			return a.length_squared() < 1.0
		var nearest := Geometry2D.get_closest_point_to_segment(Vector2.ZERO, a, b)
		# Let an insect escape if a player sets a stone down on top of it.
		if a.length_squared() < 1.0:
			return b.length_squared() < a.length_squared()
		return nearest.length_squared() < 1.0

class Crawler:
	var position: Vector2
	var target: Vector2
	var heading := Vector2.RIGHT
	var rest := 0.0
	var stride := 0.0
	var speed := 0.0
	var avoid_side := 0.0
	var art_scale := 1.0
	var elevation := 0.0
	var surface_pace := 1.0
	var best_dist := INF
	var stall_time := 0.0
	var last_target := Vector2.INF

var rng := RandomNumberGenerator.new()
var mole := Crawler.new()
var mantis := Crawler.new()
var held: Crawler
var mantis_patch := MANTIS_PATCH
var bank_side := 1.0
var runs_to_cross := 2
var ripple_delay := 0.0
var time := 0.0
var mole_wet := false
var close_encounter := false
var encounter_pause := 0.0
var mantis_alert := 0.0
var frog_blocker := Vector2.INF
var crab_blocker := Vector2.INF
var rocks: Array[Rock] = []

func reset(project: Callable) -> void:
	bank_side = 1.0
	runs_to_cross = 2
	ripple_delay = 0.0
	time = 0.0
	mole_wet = false
	close_encounter = false
	encounter_pause = 0.0
	mantis_alert = 0.0
	held = null
	mantis_patch = MANTIS_PATCH
	frog_blocker = Vector2.INF
	crab_blocker = Vector2.INF
	rocks.clear()
	mole.position = project.call(Vector2(77, 60))
	mole.target = mole.position
	mole.rest = 0.7
	mole.stride = 0.0
	mole.speed = 0.0
	mole.heading = Vector2.RIGHT
	mole.avoid_side = 0.0
	mole.art_scale = MOLE_SCALE
	mole.elevation = 0.0
	mole.best_dist = INF
	mole.stall_time = 0.0
	mole.last_target = Vector2.INF
	mantis.position = MANTIS_PATCH.get_center()
	mantis.target = mantis.position
	mantis.rest = 1.15
	mantis.stride = 0.0
	mantis.speed = 0.0
	mantis.heading = Vector2.LEFT
	mantis.avoid_side = 0.0
	mantis.elevation = 0.0
	mantis.best_dist = INF
	mantis.stall_time = 0.0
	mantis.last_target = Vector2.INF

func grab(point: Vector2) -> bool:
	var mole_distance := (mole.position - Vector2(0, mole.elevation)).distance_to(point)
	var mantis_distance := (mantis.position - Vector2(0, mantis.elevation)).distance_to(point)
	if mole_distance <= 5.0 and mole_distance <= mantis_distance:
		held = mole
	elif mantis_distance <= 7.0:
		held = mantis
	return held != null

func can_place_at(point: Vector2) -> bool:
	var other := mantis if held == mole else mole
	if other.position.distance_to(point) < CLEARANCE:
		return false
	if crab_blocker.is_finite() and crab_blocker.distance_to(point) < CLEARANCE:
		return false
	return true

func place(point: Vector2, bank: Vector2, side: float, wet: bool) -> void:
	held.position = point
	held.target = bank if wet else point
	held.speed = 0.0
	held.rest = 0.45
	held.avoid_side = 0.0
	held.elevation = 0.0
	held.best_dist = INF
	held.stall_time = 0.0
	held.last_target = Vector2.INF
	if held == mole:
		bank_side = side
		mole_wet = wet
		ripple_delay = 0.15
		encounter_pause = 0.0
	else:
		var size := MANTIS_PATCH.size
		var center := (bank if wet else point).clamp(ROAM_AREA.position + size * 0.5, ROAM_AREA.end - size * 0.5)
		mantis_patch = Rect2(center - size * 0.5, size)
		mantis_alert = 0.0
	held = null
	close_encounter = false

func path_clear(start: Vector2, end: Vector2, other: Vector2) -> bool:
	var nearest := Geometry2D.get_closest_point_to_segment(other, start, end)
	return nearest.distance_squared_to(other) >= CLEARANCE * CLEARANCE

func add_rock(center: Vector2, radius: Vector2, height: float) -> void:
	var rock := Rock.new()
	rock.center = center
	rock.radius = radius
	rock.height = height
	rocks.append(rock)

func blocking_rock(crawler: Crawler, start: Vector2, end: Vector2) -> Rock:
	var padding := 1.2 if crawler == mole else 2.3
	for rock in rocks:
		if (crawler != mole or rock.height > CLIMB_LIMIT) and rock.hit(start, end, padding):
			return rock
	return null

func climb_height(point: Vector2) -> float:
	var height := 0.0
	for rock in rocks:
		if rock.height <= CLIMB_LIMIT:
			var distance := ((point - rock.center) / (rock.radius + Vector2.ONE * 0.8)).length()
			height = maxf(height, rock.height * (1.0 - smoothstep(0.24, 1.0, distance)))
	return height

func step_clear(crawler: Crawler, start: Vector2, next: Vector2, other: Crawler, patch: Rect2) -> bool:
	if not patch.has_point(next):
		return false
	if blocking_rock(crawler, start, next) != null:
		return false
	if not path_clear(start, next, other.position):
		return false
	if frog_blocker.is_finite() and not path_clear(start, next, frog_blocker):
		return false
	if crab_blocker.is_finite() and not path_clear(start, next, crab_blocker):
		return false
	return true

func point_clear(crawler: Crawler, point: Vector2, other: Crawler, patch: Rect2) -> bool:
	if not patch.has_point(point):
		return false
	if blocking_rock(crawler, point, point) != null:
		return false
	if point.distance_to(other.position) < CLEARANCE + 1.0:
		return false
	if frog_blocker.is_finite() and point.distance_to(frog_blocker) < CLEARANCE + 1.0:
		return false
	if crab_blocker.is_finite() and point.distance_to(crab_blocker) < CLEARANCE + 1.0:
		return false
	return true

func walk(crawler: Crawler, other: Crawler, dt: float, pace: float, patch: Rect2) -> void:
	var start := crawler.position
	if not crawler.target.is_equal_approx(crawler.last_target):
		crawler.last_target = crawler.target
		crawler.best_dist = start.distance_to(crawler.target)
		crawler.stall_time = 0.0
		crawler.avoid_side = 0.0
	var target_blocked := blocking_rock(crawler, crawler.target, crawler.target) != null or (
		crawler.target.distance_to(other.position) < CLEARANCE) or (
		frog_blocker.is_finite() and crawler.target.distance_to(frog_blocker) < CLEARANCE) or (
		crab_blocker.is_finite() and crawler.target.distance_to(crab_blocker) < CLEARANCE)
	if target_blocked and start.distance_to(crawler.target) < 26.0:
		crawler.target = start
		crawler.speed = 0.0
		crawler.avoid_side = 0.0
		crawler.stall_time = 0.0
		return
	var direction := crawler.target - start
	if direction.length_squared() < 0.0001:
		crawler.speed = 0.0
		return
	var climb := climb_height(start) if crawler == mole else 0.0
	var stride_pace := pace * crawler.surface_pace * (1.0 - climb * 0.095)
	var distance := minf(crawler.speed + dt * (180.0 if crawler == mole else 11.0), stride_pace) * dt
	var next := start.move_toward(crawler.target, distance)
	if not step_clear(crawler, start, next, other, patch):
		var rock := blocking_rock(crawler, start, next)
		var frog_in_path := frog_blocker.is_finite() and not path_clear(start, next, frog_blocker)
		var crab_in_path := crab_blocker.is_finite() and not path_clear(start, next, crab_blocker)
		var obstacle := other.position
		if rock != null:
			obstacle = rock.center
		elif frog_in_path:
			obstacle = frog_blocker
		elif crab_in_path:
			obstacle = crab_blocker
		var offset := start - obstacle
		var outward := Vector2.ZERO
		if offset.length_squared() < 0.001:
			outward = -crawler.heading.normalized()
		elif rock != null:
			outward = (offset / (rock.radius * rock.radius)).normalized()
		else:
			outward = offset.normalized()
		var tangent := outward.orthogonal()
		if crawler.avoid_side == 0.0:
			crawler.avoid_side = 1.0 if direction.dot(tangent) >= 0.0 else -1.0
		var side := crawler.avoid_side
		var dir_norm := direction.normalized()
		var candidates: Array = [
			[(tangent * side + outward * 0.48).normalized(), false],
			[(tangent * side + outward * 0.95).normalized(), false],
			[outward, false],
			[(outward * 0.48 - tangent * side).normalized(), true],
			[(outward * 0.95 - tangent * side).normalized(), true],
			[(-dir_norm).rotated(side * 0.45), true],
			[(-dir_norm).rotated(-side * 0.45), true],
		]
		var found := false
		for scale_factor: float in [1.0, 0.5]:
			for cand in candidates:
				var move_dir: Vector2 = cand[0]
				var try_next := start + move_dir * (distance * scale_factor)
				if step_clear(crawler, start, try_next, other, patch):
					next = try_next
					if cand[1]:
						crawler.avoid_side = -side
					found = true
					break
			if found:
				break
		if not found:
			next = start
	elif start.distance_to(other.position) > CLEARANCE + 4.0 and blocking_rock(crawler, start, crawler.target) == null and (
		not frog_blocker.is_finite() or start.distance_to(frog_blocker) > CLEARANCE + 4.0) and (
		not crab_blocker.is_finite() or start.distance_to(crab_blocker) > CLEARANCE + 4.0):
		crawler.avoid_side = 0.0
	var step := next - start
	crawler.position = next
	crawler.elevation = move_toward(crawler.elevation, climb_height(next) if crawler == mole else 0.0, dt * 38.0)
	crawler.speed = step.length() / dt
	var dist_now := next.distance_to(crawler.target)
	if dist_now < crawler.best_dist - 0.8:
		crawler.best_dist = dist_now
		crawler.stall_time = 0.0
	elif dist_now > 1.2:
		crawler.stall_time += dt
	if step.length() > maxf(0.02, distance * 0.12):
		var angle := lerp_angle(crawler.heading.angle(), step.angle(), 1.0 - exp(-dt * (21.0 if crawler == mole else 7.0)))
		crawler.heading = Vector2.from_angle(angle)
		crawler.stride += step.length()

func pick_mole_target(project: Callable) -> Vector2:
	var inner_area := ROAM_AREA.grow(-4.0)
	for attempt in 12:
		var side := bank_side if attempt < 8 else -bank_side
		var spread := 22.0 if runs_to_cross == 0 and attempt < 4 else 52.0
		var x := clampf(mole.position.x + rng.randf_range(-spread, spread), 48.0, 245.0)
		var candidate: Vector2 = project.call(Vector2(x, side * rng.randf_range(50.0, 70.0)))
		candidate = candidate.clamp(inner_area.position, inner_area.end)
		if candidate.distance_to(mole.position) > 10.0 and point_clear(mole, candidate, mantis, inner_area):
			if side != bank_side:
				bank_side = side
			return candidate
	# Fallback: pick any open spot nearby so the mole never freezes.
	for attempt in 10:
		var fallback := (mole.position + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(16.0, 44.0)).clamp(inner_area.position, inner_area.end)
		if point_clear(mole, fallback, mantis, inner_area):
			return fallback
	return mole.position

func advance(dt: float, project: Callable, unproject: Callable, wet: Callable, ripple: Callable, day_phase := 0.0) -> void:
	if dt <= 0.0:
		return
	time += dt
	var twilight := smoothstep(1.10, 1.85, day_phase)
	var resting_night := day_phase > 1.50
	var gap := mole.position.distance_to(mantis.position)
	if held == null and not close_encounter and gap < CLEARANCE + 5.0:
		close_encounter = true
		encounter_pause = 0.16
		mantis_alert = 1.0
	elif gap > CLEARANCE + 9.0:
		close_encounter = false
	encounter_pause = maxf(0.0, encounter_pause - dt)
	mantis_alert = move_toward(mantis_alert, 0.0, dt * 0.78)
	var bed_position: Vector2 = unproject.call(mole.position)
	mole_wet = wet.call(bed_position)
	if held == mole or encounter_pause > 0.0:
		mole.speed = 0.0
	else:
		var mole_pace := WATER_SPEED if mole_wet else lerpf(48.0, 22.0, twilight)
		walk(mole, mantis, dt, mole_pace, ROAM_AREA)
		if mole.stall_time >= 1.35:
			mole.target = mole.position
			mole.speed = 0.0
			mole.avoid_side = 0.0
			mole.stall_time = 0.0
			mole.rest = rng.randf_range(0.18, 0.45)
	ripple_delay -= dt
	if mole_wet and mole.speed > 0.0 and ripple_delay <= 0.0:
		ripple.call(bed_position)
		ripple_delay = 0.21
	if held != mole and encounter_pause <= 0.0 and (mole.position.is_equal_approx(mole.target) or mole.speed == 0.0):
		mole.rest -= dt
		if mole.rest <= 0.0:
			if resting_night and not mole_wet:
				# Stay calmly on the current bank at twilight instead of crossing back and forth.
				runs_to_cross = maxi(1, runs_to_cross)
			if runs_to_cross == 0:
				bank_side = -bank_side
				runs_to_cross = rng.randi_range(2, 4)
			else:
				runs_to_cross -= 1
			mole.target = pick_mole_target(project)
			mole.rest = rng.randf_range(lerpf(0.45, 5.5, twilight), lerpf(2.15, 13.0, twilight))

	var mantis_wet: bool = wet.call(unproject.call(mantis.position))
	if held == mantis:
		mantis.speed = 0.0
	elif mantis_alert > 0.54 and not mantis_wet:
		mantis.speed = 0.0
		var threat := (mole.position - mantis.position).angle()
		mantis.heading = Vector2.from_angle(lerp_angle(mantis.heading.angle(), threat, 1.0 - exp(-dt * 5.2)))
	else:
		var boundary := ROAM_AREA if mantis_wet or not mantis_patch.has_point(mantis.position) else mantis_patch
		var mantis_pace := 9.0 if mantis_wet else lerpf(3.25, 1.75, twilight)
		walk(mantis, mole, dt, mantis_pace, boundary)
		if mantis.stall_time >= 2.2:
			mantis.target = mantis.position
			mantis.speed = 0.0
			mantis.avoid_side = 0.0
			mantis.stall_time = 0.0
			mantis.rest = rng.randf_range(0.4, 1.1)
	if held != mantis and mantis_alert <= 0.54 and (mantis.position.is_equal_approx(mantis.target) or mantis.speed == 0.0):
		if resting_night and not mantis_wet:
			# Diurnal mantis stays completely settled on dry land during blue-hour twilight.
			mantis.target = mantis.position
			mantis.speed = 0.0
			mantis.rest = maxf(mantis.rest, 1.5)
		else:
			mantis.rest -= dt
			if mantis.rest <= 0.0:
				var point := mantis.position + Vector2(rng.randf_range(-11.0, 11.0), rng.randf_range(-5.5, 5.5))
				var candidate := point.clamp(mantis_patch.position, mantis_patch.end - Vector2.ONE * 0.5)
				if not wet.call(unproject.call(candidate)) and point_clear(mantis, candidate, mole, ROAM_AREA):
					mantis.target = candidate
				mantis.rest = rng.randf_range(0.9, 3.2) * lerpf(1.0, 2.8, twilight)

func mark(crawler: Crawler, x: float, y: float) -> Vector2:
	var p := crawler.position + (crawler.heading * x + crawler.heading.orthogonal() * y) * crawler.art_scale - Vector2(0, crawler.elevation)
	return (p * 2.0).round() * 0.5

func line(canvas: Node2D, crawler: Crawler, a: Vector2, b: Vector2, ink: Color, width: float = 0.5) -> void:
	canvas.draw_line(mark(crawler, a.x, a.y), mark(crawler, b.x, b.y), ink, maxf(0.5, width * crawler.art_scale))

func body(canvas: Node2D, crawler: Crawler, shape: Array[Vector2], ink: Color, lift := 0.0) -> void:
	var points := PackedVector2Array()
	var height := Vector2(0.0, snappedf(lift * crawler.art_scale, 0.5))
	for p in shape:
		points.append(mark(crawler, p.x, p.y) - height)
	canvas.draw_colored_polygon(points, ink)

func behind_rock(crawler: Crawler) -> bool:
	if crawler == held or crawler.elevation > 0.25:
		return false
	for rock in rocks:
		var offset := crawler.position - rock.center
		if offset.y < 0.0 and offset.y > -rock.radius.y - 4.0 and absf(offset.x) < rock.radius.x:
			return true
	return false

func apply_tint(color: Color, at: Vector2, tint_at: Callable) -> Color:
	return tint_at.call(color, at) if tint_at.is_valid() else color

func draw(canvas: Node2D, pointer: Vector2, behind: bool, ledge_front: Callable, front_pass := false,
		tint_at: Callable = Callable()) -> void:
	for crawler: Crawler in [mole, mantis]:
		if behind_rock(crawler) != behind:
			continue
		var original := crawler.position
		var at := pointer if crawler == held else original
		if ledge_front.call(at) != front_pass:
			continue
		if crawler == held:
			crawler.position = pointer - Vector2(0, 5)
		if crawler == mole:
			draw_mole(canvas, tint_at)
		else:
			draw_mantis(canvas, tint_at)
		crawler.position = original

func draw_mole(canvas: Node2D, tint_at: Callable = Callable()) -> void:
	var pace := smoothstep(1.0, 26.0, mole.speed)
	var lift := snappedf((0.5 + sin(mole.stride * 2.6) * 0.5) * pace, 0.5)
	var digging := pow(maxf(0.0, sin(time * 2.45 + mole.position.x)), 8.0) * (1.0 - pace)
	var shadow := Color("#30292379") if not mole_wet else Color("#28443d88")
	var at := mole.position
	line(canvas, mole, Vector2(-3.8, 0.9), Vector2(2.0, 0.9), shadow, 2.4)
	for side in [-1.0, 1.0]:
		for i in 2:
			var x := -1.4 - i * 1.35
			var swing := sin(mole.stride * (3.5 if mole_wet else 2.2) + i * PI + side * 1.55) * pace
			var knee := Vector2(x - 0.3 + swing, side * 1.9)
			var foot := knee + Vector2(-0.8 + swing * 0.47, side * (1.25 - maxf(swing, 0.0) * 0.6))
			line(canvas, mole, Vector2(x + 0.5, side * 0.85), knee, apply_tint(Color("#70513c"), at, tint_at), 0.75)
			line(canvas, mole, knee, foot, apply_tint(Color("#8b6749"), at, tint_at))
		var reach := digging * 0.84 + sin(mole.stride * 2.46 + side * 1.58) * pace * 0.86
		var wrist := Vector2(2.7 + reach, side * 2.3)
		line(canvas, mole, Vector2(0.95, side), wrist, apply_tint(Color("#71523a"), at, tint_at), 1.25)
		line(canvas, mole, wrist, Vector2(3.8 + reach, side * 2.05), apply_tint(Color("#a77b55"), at, tint_at), 1.45)
		line(canvas, mole, Vector2(3.6 + reach, side * 1.85), Vector2(4.35 + reach, side * 1.7), apply_tint(Color("#ba916c"), at, tint_at))
		var twitch := sin(time * (5.0 + side) + mole.position.y) * 0.47
		line(canvas, mole, Vector2(3.4, side * 0.55), Vector2(5.4, side * (1.13 + twitch)), apply_tint(Color("#927152"), at, tint_at))
	body(canvas, mole, [Vector2(-4.6, 0), Vector2(-3.2, -1.65), Vector2(-0.6, -1.75), Vector2(1.4, -1.24),
		Vector2(2.1, 0.30), Vector2(0.0, 1.76), Vector2(-3.1, 1.74)], apply_tint(Color("#523d31"), at, tint_at), lift)
	body(canvas, mole, [Vector2(-3.9, -0.5), Vector2(-2.75, -1.48), Vector2(-0.54, -1.50),
		Vector2(0.65, -0.75), Vector2(-0.52, 0.25), Vector2(-2.74, 0.30)], apply_tint(Color("#976d4d") if not mole_wet else Color("#76634f"), at, tint_at), lift)
	body(canvas, mole, [Vector2(0.0, -1.35), Vector2(2.5, -1.48), Vector2(3.78, -0.84), Vector2(3.87, 0.51),
		Vector2(2.42, 1.26), Vector2(0.55, 1.06)], apply_tint(Color("#684b36"), at, tint_at), lift)
	line(canvas, mole, Vector2(0.5, -0.72), Vector2(2.45, -0.85), apply_tint(Color("#b08a60"), at, tint_at))
	line(canvas, mole, Vector2(3.35, -0.55), Vector2(3.66, -0.45), apply_tint(Color("#282622"), at, tint_at), 0.75)

func draw_mantis(canvas: Node2D, tint_at: Callable = Callable()) -> void:
	var at := mantis.position
	var olive := apply_tint(Color("#51683c"), at, tint_at)
	var leaf := apply_tint(Color("#83a460"), at, tint_at)
	var light := apply_tint(Color("#acc57b"), at, tint_at)
	var lift := 0.5 + snappedf(mantis_alert * 0.63, 0.5)
	var stride_weight := smoothstep(0.15, 1.6, mantis.speed)
	var look := sin(time * 1.55) * (0.48 + mantis_alert * 0.77)
	line(canvas, mantis, Vector2(-4.7, 0.9), Vector2(1.5, 0.9), Color("#26321e60"), 1.6)
	for side in [-1.0, 1.0]:
		var stroke := sin(mantis.stride * 2.3 + side * 1.53) * stride_weight
		var elbow := Vector2(-2.7 + stroke, side * 2.5)
		line(canvas, mantis, Vector2(-1.65, side * 0.65), elbow, olive, 0.75)
		line(canvas, mantis, elbow, Vector2(-4.45 + stroke, side * 3.52), leaf)
		var ankle := Vector2(0.52 - stroke, side * 2.63)
		line(canvas, mantis, Vector2(-0.25, side * 0.42), ankle, leaf, 0.75)
		line(canvas, mantis, ankle, Vector2(-0.55 - stroke, side * 3.18), olive)
		var raised := Vector2(2.75 + mantis_alert * 0.72, side * (2.16 - mantis_alert * 0.28))
		line(canvas, mantis, Vector2(1.32, side * 0.42), raised, leaf, 0.90)
		line(canvas, mantis, raised, Vector2(4.15 + stroke * 0.54, side * (1.2 - mantis_alert * 0.34)), light, 0.75)
		line(canvas, mantis, Vector2(4.00, side * 0.46 + look), Vector2(6.15, side * (1.58 + sin(time * 3.45 + side) * 0.43) + look), leaf)
	body(canvas, mantis, [Vector2(-5.8, 0), Vector2(-4.6, -1.19), Vector2(-2.3, -1.65), Vector2(-0.7, -1.13),
		Vector2(0.14, -0.41), Vector2(-0.65, 0.92), Vector2(-2.69, 1.56), Vector2(-4.71, 0.92)], olive)
	body(canvas, mantis, [Vector2(-5.3, -0.47), Vector2(-3.45, -1.27), Vector2(-1.9, -1.3),
		Vector2(-0.92, -0.59), Vector2(-2.45, 0.03), Vector2(-4.6, 0.06)], leaf)
	line(canvas, mantis, Vector2(-0.83, 0), Vector2(3.6, look), olive, 1.6)
	line(canvas, mantis, Vector2(-0.5, -0.35), Vector2(3.42, look - 0.26), leaf, 0.8)
	body(canvas, mantis, [Vector2(3.0, look - 0.82), Vector2(4.18, look - 1.10), Vector2(4.75, look + 0.05),
		Vector2(3.98, look + 1.15), Vector2(2.99, look + 0.72)], light, lift)
	var eye := mark(mantis, 4.2, look - 0.53) - Vector2(0, lift)
	canvas.draw_rect(Rect2(eye, Vector2(0.5, 0.5)), apply_tint(Color("#465933"), at, tint_at))
