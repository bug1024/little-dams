extends RefCounted

const Wind = preload("res://game/one_dam_wind.gd")

const HOME := Vector2(86.0, 178.0)
const CLEARANCE := 3.6
const SIZE := Vector2(320.0, 200.0)

var position := HOME
var shore := HOME
var afloat := false
var held := false
var caught := false
var drift := Vector2.ZERO
var angle := -0.18
var roll := 0.0
var bob := 0.0
var soaked := 0.0
var bounce := 0.0
var ripple_due := 0.0
var clock := 0.0

func reset(unproject: Callable) -> void:
	shore = unproject.call(HOME) if unproject.is_valid() else HOME
	position = shore
	afloat = false
	held = false
	caught = false
	drift = Vector2.ZERO
	angle = -0.18
	roll = 0.0
	bob = 0.0
	soaked = 0.0
	bounce = 0.0
	ripple_due = 0.0
	clock = 0.0

func screen_pos(project: Callable, pointer: Vector2) -> Vector2:
	if held:
		return pointer - Vector2(0.0, 5.0)
	var base: Vector2 = project.call(position) if project.is_valid() else position
	return base - Vector2(0.0, bob)

func hit_test(cursor: Vector2, project: Callable, pointer: Vector2) -> bool:
	return screen_pos(project, pointer).distance_to(cursor) <= 7.5

func place(cursor: Vector2, unproject: Callable, wet: bool) -> void:
	held = false
	position = unproject.call(cursor) if unproject.is_valid() else cursor
	afloat = wet
	caught = false
	drift = Vector2.ZERO
	bounce = 0.85
	ripple_due = 0.12
	if not wet:
		bob = 0.0
		roll = 0.0

func nudge(impulse: Vector2) -> void:
	if not afloat or held:
		return
	drift = (drift + impulse).limit_length(82.0)
	roll = clampf(roll + signf(impulse.x) * 0.14, -0.34, 0.34)
	bob = minf(bob + 0.35, 1.2)

func advance(dt: float, water, wind: Wind, rain_intensity: float, surge_fn: Callable,
		clear_path_fn: Callable, can_float_fn: Callable, is_wet_fn: Callable,
		pipes: Array, ripple_fn: Callable) -> void:
	if dt <= 0.0:
		return
	clock += dt
	bounce = move_toward(bounce, 0.0, dt * 4.4)
	if held:
		bob = 0.0
		roll = lerp(roll, sin(clock * 7.0) * 0.06, 1.0 - exp(-dt * 8.0))
		return

	if not afloat:
		var now_wet: bool = bool(is_wet_fn.call(position))
		if now_wet:
			afloat = true
		else:
			soaked = clampf(soaked + dt * (rain_intensity * 0.24 - 0.14), 0.0, 1.0)
			bob = move_toward(bob, 0.0, dt * 6.0)
			roll = move_toward(roll, 0.0, dt * 5.0)
			return

	var still_wet: bool = bool(is_wet_fn.call(position))
	if not still_wet:
		afloat = false
		drift = Vector2.ZERO
		caught = false
		return

	var step := minf(dt, 0.04)
	var flow: Vector2 = water.velocity_at(position).limit_length(74.0)
	var push: float = float(surge_fn.call(position.x))
	# Playful swirl when resting in a calm dammed pool; pipe outflow jets push and spin the boat.
	var swirl := Vector2.ZERO
	if flow.length() < 9.5:
		swirl = Vector2(cos(clock * 0.85), sin(clock * 0.68) * 0.65) * 2.2
	var pipe_spin := 0.0
	for pipe in pipes:
		if pipe.host == null or pipe.rate <= 0.05:
			continue
		var mouth: Vector2 = pipe.position() + Vector2(pipe.reach(), 0.0)
		var rel := position - mouth
		if rel.x > -2.0 and rel.x < 22.0 and absf(rel.y) < 9.5:
			var jet_str := clampf(pipe.rate * 1.4, 0.2, 1.2) * (1.0 - rel.x / 22.0)
			flow += Vector2(18.0 * jet_str, rel.y * 0.9 * jet_str)
			pipe_spin += (1.0 if rel.y >= 0.0 else -1.0) * 2.6 * jet_str

	var breeze := Wind.DIRECTION * wind.strength_at(position.x / SIZE.x) * 4.2 if wind != null else Vector2.ZERO
	var target_drift := flow * (1.05 + push * 0.35) + swirl + breeze
	drift = drift.lerp(target_drift, 1.0 - exp(-step * (6.2 + push * 3.5)))

	var delta := drift * step
	var target := position + delta
	var touching: bool = not bool(clear_path_fn.call(position, target, CLEARANCE))
	if touching:
		target = position
		var side := signf(flow.y) if absf(flow.y) > 0.6 else signf(position.y)
		if side == 0.0:
			side = 1.0
		var slide := minf(16.0, flow.length() * 0.55 + absf(flow.y))
		for direction: float in [side, -side]:
			var lane := position + Vector2(0.0, direction * slide * step)
			if bool(clear_path_fn.call(position, lane, CLEARANCE)):
				target = lane
				break
		drift.x *= 0.42

	var moved := target - position
	caught = touching and moved.length_squared() < 0.01
	position = target

	var speed := drift.length()
	if absf(pipe_spin) > 0.05:
		angle += pipe_spin * dt
	elif speed > 3.2 and not caught:
		var heading := drift.angle()
		var sway := sin(clock * (2.4 + push * 4.0)) * (0.14 + push * 0.16)
		angle = lerp_angle(angle, heading + sway, minf(1.0, dt * 3.2))
	else:
		angle += sin(clock * 0.72) * 0.32 * dt

	var wave_bob := sin(clock * (3.6 + push * 4.5) + position.x * 0.08) * (0.45 + push * 0.85)
	bob = lerpf(bob, wave_bob - soaked * 0.35, 1.0 - exp(-dt * 6.5))
	var target_roll := clampf(sin(clock * (2.9 + push * 4.0)) * (0.08 + push * 0.22) + soaked * 0.08, -0.34, 0.34)
	roll = lerpf(roll, target_roll, 1.0 - exp(-dt * 5.5))
	soaked = clampf(soaked + dt * ((rain_intensity * 0.18 + push * 0.28) - 0.025), 0.0, 0.85)

	ripple_due -= dt
	if (speed > 12.0 or push > 0.25) and ripple_due <= 0.0:
		if ripple_fn.is_valid():
			ripple_fn.call(position, minf(0.28, 0.12 + push * 0.16))
		ripple_due = 0.45 if push > 0.25 else 0.90

	if position.x > SIZE.x + 12.0:
		position = shore
		afloat = false
		caught = false
		drift = Vector2.ZERO
		angle = -0.18
		bob = 0.0
		roll = 0.0

func snap(pt: Vector2) -> Vector2:
	return (pt * 2.0).round() * 0.5

func apply_tint(color: Color, at: Vector2, tint_at: Callable) -> Color:
	return tint_at.call(color, at) if tint_at.is_valid() else color

func draw(canvas: Node2D, project: Callable, pointer: Vector2, tint_at: Callable, foam_col: Color) -> void:
	var p := snap(screen_pos(project, pointer))
	var squash := 1.0 - sin(bounce * PI) * 0.14
	var facing := 1.0 if cos(angle) >= 0.0 else -1.0
	var tilt := clampf(sin(angle) * 0.22 + roll, -0.38, 0.38)

	# Water wake behind a moving boat.
	if afloat and not held and drift.length() > 5.0 and not caught:
		var axis := drift.normalized()
		var side := axis.orthogonal()
		var wake_alpha := minf(0.55, drift.length() * 0.020)
		var wake_ink := Color(foam_col, wake_alpha)
		var stern := p - axis * 4.8 + Vector2(0.0, 1.0)
		canvas.draw_line(snap(stern + side * 1.6), snap(stern - axis * 5.5 + side * 3.4), wake_ink, 0.55)
		canvas.draw_line(snap(stern - side * 1.6), snap(stern - axis * 5.5 - side * 3.4), wake_ink, 0.55)

	# Ground or waterline shadow.
	if not held:
		var shadow_col := Color("#16312f68") if afloat else Color("#2823196c")
		canvas.draw_colored_polygon(PackedVector2Array([
			snap(p + Vector2(-4.8, 1.5)),
			snap(p + Vector2(0.0, 0.5)),
			snap(p + Vector2(4.8, 1.5)),
			snap(p + Vector2(3.0, 2.8)),
			snap(p + Vector2(-3.0, 2.8)),
		]), shadow_col)

	var paper_lit := apply_tint(Color("#f7efe0").lerp(Color("#d8cbb0"), soaked * 0.65), p, tint_at)
	var paper_mid := apply_tint(Color("#e4d6bb").lerp(Color("#bba98e"), soaked * 0.65), p, tint_at)
	var paper_shade := apply_tint(Color("#bdab8e").lerp(Color("#8e7f6b"), soaked * 0.65), p, tint_at)
	var crease_ink := apply_tint(Color("#3a2c24"), p, tint_at)
	var rule_ink := apply_tint(Color("#8ca2b2", 0.55), p, tint_at)

	var xform := func(local: Vector2) -> Vector2:
		var scaled := Vector2(local.x * facing, local.y * squash)
		return snap(p + scaled.rotated(tilt))

	# Outer folded hull silhouette (trapezoid with crisp upturned bow & stern).
	canvas.draw_colored_polygon(PackedVector2Array([
		xform.call(Vector2(-5.2, -0.6)),
		xform.call(Vector2(5.4, -0.8)),
		xform.call(Vector2(3.4, 1.8)),
		xform.call(Vector2(-3.4, 1.8)),
	]), paper_mid)

	# Inner dark hull pocket for 3D origami depth.
	canvas.draw_colored_polygon(PackedVector2Array([
		xform.call(Vector2(-3.6, -0.5)),
		xform.call(Vector2(3.8, -0.6)),
		xform.call(Vector2(2.4, 0.5)),
		xform.call(Vector2(-2.4, 0.5)),
	]), paper_shade)

	# Central folded paper sail / pyramid peak (bright left face, slightly shaded right face).
	canvas.draw_colored_polygon(PackedVector2Array([
		xform.call(Vector2(-2.5, 0.2)),
		xform.call(Vector2(0.2, -4.4)),
		xform.call(Vector2(0.2, 0.4)),
	]), paper_lit)
	canvas.draw_colored_polygon(PackedVector2Array([
		xform.call(Vector2(0.2, -4.4)),
		xform.call(Vector2(2.7, 0.1)),
		xform.call(Vector2(0.2, 0.4)),
	]), paper_mid)

	# Front gunwale lip highlight + subtle notebook ruled line on sail + crisp origami crease.
	canvas.draw_line(xform.call(Vector2(-5.0, -0.5)), xform.call(Vector2(5.2, -0.7)), paper_lit, 0.65)
	canvas.draw_line(xform.call(Vector2(-1.3, -1.7)), xform.call(Vector2(1.4, -1.7)), rule_ink, 0.45)
	canvas.draw_line(xform.call(Vector2(0.2, -4.4)), xform.call(Vector2(0.2, 0.5)), crease_ink, 0.45)
	canvas.draw_polyline(PackedVector2Array([
		xform.call(Vector2(-5.2, -0.6)),
		xform.call(Vector2(-3.4, 1.8)),
		xform.call(Vector2(3.4, 1.8)),
		xform.call(Vector2(5.4, -0.8)),
	]), crease_ink, 0.5)
	# Subtle wet waterline ring when afloat.
	if afloat and not held:
		canvas.draw_line(xform.call(Vector2(-3.6, 1.9)), xform.call(Vector2(3.6, 1.9)), Color(foam_col, 0.48), 0.5)
