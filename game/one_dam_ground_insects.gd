extends RefCounted

const MANTIS_PATCH := Rect2(187, 156, 26, 14)
const WATER_SPEED := 30.0
const MOLE_SCALE := 0.58
const CLEARANCE := 7.3 + 5.7 * MOLE_SCALE

class Crawler:
	var position: Vector2
	var target: Vector2
	var heading := Vector2.RIGHT
	var rest := 0.0
	var stride := 0.0
	var speed := 0.0
	var avoid_side := 0.0
	var art_scale := 1.0

var rng := RandomNumberGenerator.new()
var mole := Crawler.new()
var mantis := Crawler.new()
var bank_side := 1.0
var runs_to_cross := 2
var ripple_delay := 0.0
var time := 0.0
var mole_wet := false
var close_encounter := false
var encounter_pause := 0.0
var mantis_alert := 0.0

func reset(project: Callable) -> void:
	bank_side = 1.0
	runs_to_cross = 2
	ripple_delay = 0.0
	time = 0.0
	mole_wet = false
	close_encounter = false
	encounter_pause = 0.0
	mantis_alert = 0.0
	mole.position = project.call(Vector2(77, 60))
	mole.target = mole.position
	mole.rest = 0.7
	mole.stride = 0.0
	mole.speed = 0.0
	mole.heading = Vector2.RIGHT
	mole.avoid_side = 0.0
	mole.art_scale = MOLE_SCALE
	mantis.position = MANTIS_PATCH.get_center()
	mantis.target = mantis.position
	mantis.rest = 1.15
	mantis.stride = 0.0
	mantis.speed = 0.0
	mantis.heading = Vector2.LEFT
	mantis.avoid_side = 0.0

func path_clear(start: Vector2, end: Vector2, other: Vector2) -> bool:
	var nearest := Geometry2D.get_closest_point_to_segment(other, start, end)
	return nearest.distance_squared_to(other) >= CLEARANCE * CLEARANCE

func walk(crawler: Crawler, other: Crawler, dt: float, pace: float, patch: Rect2) -> void:
	var start := crawler.position
	if start.distance_to(other.position) < CLEARANCE + 6.0 and crawler.target.distance_to(other.position) < CLEARANCE:
		crawler.target = start
		crawler.speed = 0.0
		return
	var direction := crawler.target - start
	var distance := minf(crawler.speed + dt * (180.0 if crawler == mole else 11.0), pace) * dt
	var next := start.move_toward(crawler.target, distance)
	if not path_clear(start, next, other.position):
		var outward := (start - other.position).normalized()
		var tangent := outward.orthogonal()
		if crawler.avoid_side == 0.0:
			crawler.avoid_side = 1.0 if direction.dot(tangent) >= 0.0 else -1.0
		var avoid := (tangent * crawler.avoid_side + outward * 0.48).normalized()
		next = start + avoid * distance
		if not patch.has_point(next):
			next = start + (outward * 0.48 - tangent * crawler.avoid_side).normalized() * distance
		if not patch.has_point(next) or not path_clear(start, next, other.position):
			next = start
	elif start.distance_to(other.position) > CLEARANCE + 4.0:
		crawler.avoid_side = 0.0
	var step := next - start
	crawler.position = next
	crawler.speed = step.length() / dt
	if crawler.speed > 0.01:
		var angle := lerp_angle(crawler.heading.angle(), step.angle(), 1.0 - exp(-dt * (21.0 if crawler == mole else 7.0)))
		crawler.heading = Vector2.from_angle(angle)
		crawler.stride += step.length()

func advance(dt: float, project: Callable, unproject: Callable, wet: Callable, ripple: Callable) -> void:
	if dt <= 0.0:
		return
	time += dt
	var gap := mole.position.distance_to(mantis.position)
	if not close_encounter and gap < CLEARANCE + 5.0:
		close_encounter = true
		encounter_pause = 0.16
		mantis_alert = 1.0
	elif gap > CLEARANCE + 9.0:
		close_encounter = false
	encounter_pause = maxf(0.0, encounter_pause - dt)
	mantis_alert = move_toward(mantis_alert, 0.0, dt * 0.78)
	var bed_position: Vector2 = unproject.call(mole.position)
	mole_wet = wet.call(bed_position)
	if encounter_pause > 0.0:
		mole.speed = 0.0
	else:
		walk(mole, mantis, dt, WATER_SPEED if mole_wet else 48.0, Rect2(8, 8, 304, 184))
	ripple_delay -= dt
	if mole_wet and mole.speed > 0.0 and ripple_delay <= 0.0:
		ripple.call(bed_position)
		ripple_delay = 0.21
	if encounter_pause <= 0.0 and (mole.position.is_equal_approx(mole.target) or mole.speed == 0.0):
		mole.rest -= dt
		if mole.rest <= 0.0:
			var x := clampf(mole.position.x + rng.randf_range(-49.0, 49.0), 51.0, 238.0)
			if runs_to_cross == 0:
				bank_side = -bank_side
				runs_to_cross = rng.randi_range(2, 4)
				x = clampf(mole.position.x + rng.randf_range(-22.0, 22.0), 51.0, 238.0)
			else:
				runs_to_cross -= 1
			mole.target = project.call(Vector2(x, bank_side * rng.randf_range(53.0, 69.0)))
			mole.rest = rng.randf_range(0.45, 2.15)

	if mantis_alert > 0.54:
		mantis.speed = 0.0
		var threat := (mole.position - mantis.position).angle()
		mantis.heading = Vector2.from_angle(lerp_angle(mantis.heading.angle(), threat, 1.0 - exp(-dt * 5.2)))
	else:
		walk(mantis, mole, dt, 3.25, MANTIS_PATCH)
	if mantis_alert <= 0.54 and (mantis.position.is_equal_approx(mantis.target) or mantis.speed == 0.0):
		mantis.rest -= dt
		if mantis.rest <= 0.0:
			var point := mantis.position + Vector2(rng.randf_range(-11.0, 11.0), rng.randf_range(-5.5, 5.5))
			mantis.target = point.clamp(MANTIS_PATCH.position, MANTIS_PATCH.end - Vector2.ONE * 0.5)
			mantis.rest = rng.randf_range(0.9, 3.2)

func mark(crawler: Crawler, x: float, y: float) -> Vector2:
	var p := crawler.position + (crawler.heading * x + crawler.heading.orthogonal() * y) * crawler.art_scale
	return (p * 2.0).round() * 0.5

func line(canvas: Node2D, crawler: Crawler, a: Vector2, b: Vector2, ink: Color, width: float = 0.5) -> void:
	canvas.draw_line(mark(crawler, a.x, a.y), mark(crawler, b.x, b.y), ink, maxf(0.5, width * crawler.art_scale))

func body(canvas: Node2D, crawler: Crawler, shape: Array[Vector2], ink: Color, lift := 0.0) -> void:
	var points := PackedVector2Array()
	var height := Vector2(0.0, snappedf(lift * crawler.art_scale, 0.5))
	for p in shape:
		points.append(mark(crawler, p.x, p.y) - height)
	canvas.draw_colored_polygon(points, ink)

func draw(canvas: Node2D) -> void:
	draw_mole(canvas)
	draw_mantis(canvas)

func draw_mole(canvas: Node2D) -> void:
	var pace := smoothstep(1.0, 26.0, mole.speed)
	var lift := snappedf((0.5 + sin(mole.stride * 2.6) * 0.5) * pace, 0.5)
	var digging := pow(maxf(0.0, sin(time * 2.45 + mole.position.x)), 8.0) * (1.0 - pace)
	var shadow := Color("#30292379") if not mole_wet else Color("#28443d88")
	line(canvas, mole, Vector2(-3.8, 0.9), Vector2(2.0, 0.9), shadow, 2.4)
	for side in [-1.0, 1.0]:
		for i in 2:
			var x := -1.4 - i * 1.35
			var swing := sin(mole.stride * (3.5 if mole_wet else 2.2) + i * PI + side * 1.55) * pace
			var knee := Vector2(x - 0.3 + swing, side * 1.9)
			var foot := knee + Vector2(-0.8 + swing * 0.47, side * (1.25 - maxf(swing, 0.0) * 0.6))
			line(canvas, mole, Vector2(x + 0.5, side * 0.85), knee, Color("#70513c"), 0.75)
			line(canvas, mole, knee, foot, Color("#8b6749"))
		var reach := digging * 0.84 + sin(mole.stride * 2.46 + side * 1.58) * pace * 0.86
		var wrist := Vector2(2.7 + reach, side * 2.3)
		line(canvas, mole, Vector2(0.95, side), wrist, Color("#71523a"), 1.25)
		line(canvas, mole, wrist, Vector2(3.8 + reach, side * 2.05), Color("#a77b55"), 1.45)
		line(canvas, mole, Vector2(3.6 + reach, side * 1.85), Vector2(4.35 + reach, side * 1.7), Color("#ba916c"))
		var twitch := sin(time * (5.0 + side) + mole.position.y) * 0.47
		line(canvas, mole, Vector2(3.4, side * 0.55), Vector2(5.4, side * (1.13 + twitch)), Color("#927152"))
	body(canvas, mole, [Vector2(-4.6, 0), Vector2(-3.2, -1.65), Vector2(-0.6, -1.75), Vector2(1.4, -1.24),
		Vector2(2.1, 0.30), Vector2(0.0, 1.76), Vector2(-3.1, 1.74)], Color("#523d31"), lift)
	body(canvas, mole, [Vector2(-3.9, -0.5), Vector2(-2.75, -1.48), Vector2(-0.54, -1.50),
		Vector2(0.65, -0.75), Vector2(-0.52, 0.25), Vector2(-2.74, 0.30)], Color("#976d4d") if not mole_wet else Color("#76634f"), lift)
	body(canvas, mole, [Vector2(0.0, -1.35), Vector2(2.5, -1.48), Vector2(3.78, -0.84), Vector2(3.87, 0.51),
		Vector2(2.42, 1.26), Vector2(0.55, 1.06)], Color("#684b36"), lift)
	line(canvas, mole, Vector2(0.5, -0.72), Vector2(2.45, -0.85), Color("#b08a60"))
	line(canvas, mole, Vector2(3.35, -0.55), Vector2(3.66, -0.45), Color("#282622"), 0.75)

func draw_mantis(canvas: Node2D) -> void:
	var olive := Color("#51683c")
	var leaf := Color("#83a460")
	var light := Color("#acc57b")
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
	canvas.draw_rect(Rect2(eye, Vector2(0.5, 0.5)), Color("#465933"))
