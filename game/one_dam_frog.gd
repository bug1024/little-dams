extends RefCounted

signal landed(point: Vector2)
signal croaked

const AREA := Rect2(8, 8, 304, 184)
const HOME := Vector2(168, 148)

var rng := RandomNumberGenerator.new()
var position := HOME
var anchor := HOME
var origin := HOME
var target := HOME
var facing := 1.0
var age := 0.0
var duration := 0.0
var pause := 1.9
var call_due := 3.5
var throat := 0.0
var held := false

func reset() -> void:
	position = HOME
	anchor = HOME
	origin = HOME
	target = HOME
	facing = 1.0
	age = 0.0
	duration = 0.0
	pause = 1.9
	call_due = 3.5
	throat = 0.0
	held = false

func place(at: Vector2) -> void:
	position = at
	anchor = at
	duration = 0.0
	pause = 0.48
	held = false

func advance(dt: float, clear: Callable) -> void:
	if held:
		return
	throat = move_toward(throat, 0.0, dt * 2.9)
	call_due -= dt
	if duration > 0.0:
		age += dt
		position = origin.lerp(target, minf(age / duration, 1.0))
		if age >= duration:
			if not clear.call(position):
				# A crawler moved beneath the frog. Land on the last clear spot on its route.
				for i in range(1, 7):
					var nearby := target.lerp(origin, float(i) / 6.0)
					if clear.call(nearby):
						position = nearby
						break
				if not clear.call(position):
					origin = position
					target = (position + Vector2(9.0, -7.0)).clamp(AREA.position, AREA.end)
					duration = 0.27
					age = 0.0
					return
			duration = 0.0
			landed.emit(position)
		return
	if call_due <= 0.0:
		throat = 1.0
		croaked.emit()
		call_due = rng.randf_range(6.0, 14.0)
		pause = maxf(pause, 0.42)
	pause -= dt
	if pause > 0.0:
		return
	for i in 5:
		var next := position + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(10.0, 24.0)
		next = next.clamp(AREA.position, AREA.end)
		if next.distance_to(anchor) < 39.0 and next.distance_to(position) > 6.0 and clear.call(next):
			origin = position
			target = next
			facing = -1.0 if target.x < origin.x else 1.0
			age = 0.0
			duration = rng.randf_range(0.30, 0.44)
			break
	pause = rng.randf_range(0.9, 3.9)

func hop_height() -> float:
	return sin(clampf(age / duration, 0.0, 1.0) * PI) if duration > 0.0 else 0.0

func screen_point() -> Vector2:
	return position - Vector2(0, hop_height() * 9.0)

func draw(canvas: Node2D, pointer: Vector2) -> void:
	var airborne := hop_height()
	var p := pointer - Vector2(0, 5) if held else screen_point()
	p = (p * 2.0).round() * 0.5
	if not held:
		canvas.draw_rect(Rect2((position * 2.0).round() * 0.5 - Vector2(3, 0), Vector2(6, 1.5)), Color("#293c345b"))
	for side in [-1.0, 1.0]:
		var foot := p + Vector2((-3.7 - airborne * 3.0) * facing, side * 2.2)
		canvas.draw_line(p + Vector2(-1.0 * facing, side), foot, Color("#566c46"), 1.5)
		canvas.draw_line(foot, foot + Vector2(-1.0 * facing, side * 0.75), Color("#849260"), 1.0)
	canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(-3.3, 0), p + Vector2(-2.4, -2.2),
		p + Vector2(1.9, -2.6), p + Vector2(3.3, -1.0), p + Vector2(2.6, 1.7), p + Vector2(-2.4, 2.2)]), Color("#587849"))
	canvas.draw_line(p + Vector2(-2.2, -0.75), p + Vector2(2.1, -1.4), Color("#90a765"), 1.5)
	var nose := p + Vector2(2.7 * facing, -0.6)
	var throat_size := snappedf(throat * 1.5, 0.5)
	canvas.draw_rect(Rect2(nose - Vector2(1.25, 0), Vector2(2.5, 1.5 + throat_size)), Color("#acc18a"))
	canvas.draw_rect(Rect2(nose - Vector2(1.0, 2.25), Vector2(2.0, 1.5)), Color("#afb36e"))
	canvas.draw_rect(Rect2(nose + Vector2(facing * 0.25, -2.0), Vector2(0.75, 0.75)), Color("#2f3a2d"))
