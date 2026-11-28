extends RefCounted

signal landed(point: Vector2)
signal croaked
signal startled

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
var alert := 0.0
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
	alert = 0.0
	held = false

func place(at: Vector2) -> void:
	position = at
	anchor = at
	duration = 0.0
	pause = 0.48
	held = false

func nudge_call(max_delay := 2.2) -> void:
	call_due = minf(call_due, max_delay)

func advance(dt: float, clear: Callable, activity := 0.0, twilight := 0.0, pointer := Vector2.INF) -> void:
	if held:
		return
	throat = move_toward(throat, 0.0, dt * 2.9)
	alert = move_toward(alert, 0.0, dt * 1.8)
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
	if pointer.is_finite():
		var p_dist := position.distance_to(pointer)
		if p_dist < 22.0:
			var was_calm := alert < 0.20
			alert = maxf(alert, clampf(1.0 - p_dist / 22.0, 0.25, 1.0))
			if absf(pointer.x - position.x) > 1.5:
				facing = -1.0 if pointer.x < position.x else 1.0
			throat = maxf(throat, 0.36 * alert)
			if p_dist < 11.5:
				pause = minf(pause, 0.22)
				if was_calm:
					startled.emit()
	if call_due <= 0.0:
		throat = 1.0
		croaked.emit()
		var pace := clampf(activity, 0.0, 1.0)
		call_due = rng.randf_range(lerpf(6.0, 3.8, pace), lerpf(14.0, 8.8, pace))
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
	var calm := clampf(twilight, 0.0, 1.0)
	pause = rng.randf_range(lerpf(0.9, 5.5, calm), lerpf(3.9, 13.5, calm))

func hop_height() -> float:
	return sin(clampf(age / duration, 0.0, 1.0) * PI) if duration > 0.0 else 0.0

func screen_point() -> Vector2:
	return position - Vector2(0, hop_height() * 9.0)

func apply_tint(color: Color, at: Vector2, tint_at: Callable) -> Color:
	return tint_at.call(color, at) if tint_at.is_valid() else color

func draw(canvas: Node2D, pointer: Vector2, tint_at: Callable = Callable()) -> void:
	var airborne := hop_height()
	var p := pointer - Vector2(0, 5) if held else screen_point()
	p = (p * 2.0).round() * 0.5
	if not held:
		canvas.draw_rect(Rect2((position * 2.0).round() * 0.5 - Vector2(3, 0), Vector2(6, 1.5)), Color("#293c345b"))
	for side in [-1.0, 1.0]:
		var foot := p + Vector2((-3.7 - airborne * 3.0) * facing, side * 2.2)
		canvas.draw_line(p + Vector2(-1.0 * facing, side), foot, apply_tint(Color("#566c46"), p, tint_at), 1.5)
		canvas.draw_line(foot, foot + Vector2(-1.0 * facing, side * 0.75), apply_tint(Color("#849260"), p, tint_at), 1.0)
	canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(-3.3, 0), p + Vector2(-2.4, -2.2),
		p + Vector2(1.9, -2.6), p + Vector2(3.3, -1.0), p + Vector2(2.6, 1.7), p + Vector2(-2.4, 2.2)]), apply_tint(Color("#587849"), p, tint_at))
	canvas.draw_line(p + Vector2(-2.2, -0.75), p + Vector2(2.1, -1.4), apply_tint(Color("#90a765"), p, tint_at), 1.5)
	var nose := p + Vector2(2.7 * facing, -0.6)
	var throat_size := snappedf(throat * 1.5, 0.5)
	canvas.draw_rect(Rect2(nose - Vector2(1.25, 0), Vector2(2.5, 1.5 + throat_size)), apply_tint(Color("#acc18a"), p, tint_at))
	canvas.draw_rect(Rect2(nose - Vector2(1.0, 2.25), Vector2(2.0, 1.5)), apply_tint(Color("#afb36e"), p, tint_at))
	canvas.draw_rect(Rect2(nose + Vector2(facing * 0.25, -2.0), Vector2(0.75, 0.75)), apply_tint(Color("#2f3a2d"), p, tint_at))
