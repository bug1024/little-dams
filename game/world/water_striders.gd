extends RefCounted

# Seasonal water striders (水黾) skating across calm shallow stretches of the creek:
# - Most lively in midsummer (4 skaters), modest in spring/autumn (1-2), absent in winter.
# - Cast tiny dark meniscus dimple shadows onto submerged pebbles beneath their feet.
# - React dynamically to WorldStimulus splashes/water-gun/surges and pointer proximity by
#   darting swiftly away with micro-ripples.

signal startled

const ANCHORS: Array[Vector2] = [
	Vector2(76.0, -7.0),
	Vector2(138.0, 8.0),
	Vector2(204.0, -6.0),
	Vector2(258.0, 7.0),
]

class Strider:
	var anchor: Vector2
	var world_pos: Vector2
	var vel := Vector2.ZERO
	var heading := -0.15
	var stroke_wait := 0.8
	var stroke_energy := 0.0
	var scared := 0.0
	var phase := 0.0

var striders: Array[Strider] = []
var clock := 0.0
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.seed = 4219
	reset()

func reset() -> void:
	striders.clear()
	clock = 0.0
	for i in ANCHORS.size():
		var s := Strider.new()
		s.anchor = ANCHORS[i]
		s.world_pos = ANCHORS[i]
		s.heading = rng.randf_range(-0.6, 0.6)
		s.stroke_wait = rng.randf_range(0.35, 1.45)
		s.phase = float(i) * 1.73
		striders.append(s)

func active_count(weight: float, twilight := 0.0) -> int:
	if weight <= 0.05:
		return 0
	var calm_scale := 1.0 - twilight * 0.35
	return clampi(roundi(float(striders.size()) * weight * calm_scale), 1, striders.size())

func disturb_screen(screen_pos: Vector2, radius: float, strength: float, project: Callable, ripple_fn: Callable = Callable()) -> int:
	var count := 0
	for s in striders:
		var scr: Vector2 = project.call(s.world_pos)
		var delta := scr - screen_pos
		var dist := delta.length()
		if dist < radius:
			var away := delta.normalized() if dist > 0.5 else Vector2(1.0, -1.0).normalized()
			var push := lerpf(32.0, 56.0, clampf(strength, 0.2, 1.2))
			s.vel = (away * push).limit_length(62.0)
			s.heading = s.vel.angle()
			s.stroke_energy = 1.0
			s.scared = maxf(s.scared, 1.25)
			s.stroke_wait = rng.randf_range(0.25, 0.55)
			if ripple_fn.is_valid():
				ripple_fn.call(s.world_pos, 0.14)
			count += 1
	if count > 0:
		startled.emit()
	return count

func advance(dt: float, water, weight: float, twilight: float, clear_path_fn: Callable, is_wet_fn: Callable,
		project: Callable, pointer: Vector2, ripple_fn: Callable) -> void:
	if dt <= 0.0:
		return
	clock += dt
	var n := active_count(weight, twilight)
	if n <= 0:
		return
	var step := minf(dt, 0.04)
	for i in n:
		var s := striders[i]
		s.scared = maxf(0.0, s.scared - dt)
		s.stroke_energy = move_toward(s.stroke_energy, 0.0, dt * 3.4)
		# Gentle cursor-proximity scatter so players immediately feel the creek is alive!
		if pointer.is_finite():
			var scr: Vector2 = project.call(s.world_pos)
			var d := scr.distance_to(pointer)
			if d < 16.0 and s.scared < 0.25:
				var away := (scr - pointer).normalized() if d > 0.5 else Vector2(-1.0, -0.5).normalized()
				s.vel = away * 38.0
				s.heading = s.vel.angle()
				s.stroke_energy = 1.0
				s.scared = 0.85
				s.stroke_wait = 0.45
				if ripple_fn.is_valid():
					ripple_fn.call(s.world_pos, 0.12)
				startled.emit()
		s.stroke_wait -= dt
		if s.stroke_wait <= 0.0:
			var to_home := s.anchor - s.world_pos
			var desired := Vector2(-1.0, rng.randf_range(-0.55, 0.55)).normalized()
			if to_home.length() > 14.0:
				desired = (to_home.normalized() * 0.82 + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.35, 0.35))).normalized()
			else:
				desired = Vector2.from_angle(s.heading + rng.randf_range(-1.3, 1.3))
			var burst_speed := rng.randf_range(18.0, 32.0) * lerpf(1.0, 0.65, twilight)
			s.vel = desired * burst_speed
			s.heading = desired.angle()
			s.stroke_energy = 0.92
			s.stroke_wait = rng.randf_range(lerpf(0.75, 1.85, twilight), lerpf(1.85, 3.6, twilight))
			if ripple_fn.is_valid() and rng.randf() < 0.45:
				ripple_fn.call(s.world_pos, 0.09)
		# Drift gently with surface flow while skating friction quickly slows each rowing burst.
		var flow: Vector2 = water.velocity_at(s.world_pos).limit_length(46.0) * 0.28
		s.vel *= exp(-step * 3.8)
		var next := s.world_pos + (s.vel + flow) * step
		next.x = clampf(next.x, 26.0, 294.0)
		next.y = clampf(next.y, -17.0, 17.0)
		if bool(is_wet_fn.call(next)) and bool(clear_path_fn.call(s.world_pos, next, 2.2)):
			s.world_pos = next
		else:
			s.vel = -s.vel * 0.5 + Vector2(0.0, -signf(s.world_pos.y) * 8.0)
			s.heading = s.vel.angle() if s.vel.length_squared() > 0.2 else s.heading + PI * 0.6

func draw(canvas: Node2D, weight: float, twilight: float, project: Callable, shade_color: Callable) -> void:
	var n := active_count(weight, twilight)
	if n <= 0:
		return
	for i in n:
		var s := striders[i]
		var c := _snap(project.call(s.world_pos))
		var fwd := Vector2.from_angle(s.heading)
		var side := Vector2(-fwd.y, fwd.x)
		var sweep := s.stroke_energy * 0.85
		# Iconic tiny meniscus dimple shadows cast on shallow sunlit riverbed!
		var dimple_col := Color(0.08, 0.22, 0.24, 0.42 * (1.0 - twilight * 0.45))
		var leg_col: Color = shade_color.call(Color("#362b22", 0.86), c)
		var body_col: Color = shade_color.call(Color("#241b15", 0.94), c)
		var hi_col: Color = shade_color.call(Color("#8c7c66", 0.72), c)
		for side_s: float in [-1.0, 1.0]:
			var mid_foot := _snap(c + fwd * (0.2 - sweep * 1.2) + side * (side_s * 3.2))
			var rear_foot := _snap(c - fwd * (2.6 + sweep * 0.6) + side * (side_s * 2.1))
			# Dimple shadows slightly down-right on the bed.
			canvas.draw_rect(Rect2(mid_foot + Vector2(0.5, 1.5), Vector2(1.0, 0.5)), dimple_col)
			canvas.draw_rect(Rect2(rear_foot + Vector2(0.5, 1.5), Vector2(1.0, 0.5)), dimple_col)
			# Hair-thin skating legs.
			canvas.draw_line(c + fwd * 0.4, mid_foot, leg_col, 0.5)
			canvas.draw_line(c - fwd * 0.5, rear_foot, leg_col, 0.5)
		# Slender dark body + tiny warm sheen dot.
		canvas.draw_line(_snap(c - fwd * 1.6), _snap(c + fwd * 1.5), body_col, 0.85)
		canvas.draw_rect(Rect2(_snap(c + fwd * 0.2), Vector2(0.5, 0.5)), hi_col)

func _snap(pt: Vector2) -> Vector2:
	return (pt * 2.0).round() * 0.5
