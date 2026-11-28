extends RefCounted

# Persistent environmental interaction traces ("I just played right here"):
# - HOLLOW: damp dark earth depression left behind when lifting a resting stone/mud from the bank.
# - WET_RING: dark moist seepage ring left when setting a wet river stone/mud onto the dry bank.
# - DAMP_SPOT: darkened wet soil mark left where the bamboo water gun sprays dry bank dirt.
# - PLUCK_MARK: tiny disturbed soil & cut stem mark left after uprooting a rooted flower or foxtail.

const WorldState = preload("res://game/world/world_state.gd")

enum Kind { HOLLOW, WET_RING, DAMP_SPOT, PLUCK_MARK }

const MAX_TRACES := 48

class Trace:
	var kind: Kind
	var pos: Vector2
	var radius: float
	var age := 0.0
	var max_life := 75.0
	var seed := 0.0

	func _init(p_kind: Kind, p_pos: Vector2, p_radius: float, p_life: float) -> void:
		kind = p_kind
		pos = p_pos
		radius = p_radius
		max_life = p_life
		seed = fposmod(p_pos.x * 0.371 + p_pos.y * 0.619 + p_radius * 0.23, 1.0)

	func alpha() -> float:
		var remain := clampf(1.0 - age / maxf(max_life, 0.1), 0.0, 1.0)
		return smoothstep(0.0, 0.35, remain)

var traces: Array[Trace] = []

func clear() -> void:
	traces.clear()

func count_kind(kind: Kind) -> int:
	var n := 0
	for t in traces:
		if t.kind == kind:
			n += 1
	return n

func add_hollow(screen_pos: Vector2, radius: float) -> void:
	var spot := _snap(screen_pos + Vector2(0.0, radius * 0.24))
	# Refresh if lifting again at virtually the same spot.
	for t in traces:
		if t.kind == Kind.HOLLOW and t.pos.distance_to(spot) < maxf(4.0, radius * 0.45):
			t.age = 0.0
			t.radius = maxf(t.radius, radius)
			return
	_push(Trace.new(Kind.HOLLOW, spot, clampf(radius, 5.0, 18.0), 85.0))

func add_wet_ring(screen_pos: Vector2, radius: float) -> void:
	var spot := _snap(screen_pos + Vector2(0.0, radius * 0.48))
	for t in traces:
		if t.kind == Kind.WET_RING and t.pos.distance_to(spot) < maxf(4.5, radius * 0.50):
			t.age = 0.0
			t.radius = maxf(t.radius, radius)
			return
	_push(Trace.new(Kind.WET_RING, spot, clampf(radius, 5.0, 18.0), 62.0))

func add_damp_spot(screen_pos: Vector2, radius := 4.2) -> void:
	var spot := _snap(screen_pos)
	for t in traces:
		if t.kind == Kind.DAMP_SPOT and t.pos.distance_to(spot) < 4.0:
			t.age = maxf(0.0, t.age - 8.0)
			t.radius = minf(6.8, maxf(t.radius, radius) + 0.22)
			return
	_push(Trace.new(Kind.DAMP_SPOT, spot, clampf(radius, 2.5, 6.8), 38.0))

func add_pluck_mark(screen_pos: Vector2) -> void:
	var spot := _snap(screen_pos)
	for t in traces:
		if t.kind == Kind.PLUCK_MARK and t.pos.distance_to(spot) < 3.0:
			t.age = 0.0
			return
	_push(Trace.new(Kind.PLUCK_MARK, spot, 2.6, 78.0))

func _push(trace: Trace) -> void:
	if traces.size() >= MAX_TRACES:
		traces.remove_at(0)
	traces.append(trace)

func advance(dt: float, world: WorldState, heat_origin := Vector2.ZERO, heat_strength := 0.0) -> void:
	if traces.is_empty():
		return
	# Bright afternoon sun dries moisture slightly faster; rain keeps wet traces fresh;
	# radiant campfire warmth rapidly dries nearby damp soil and wet stone rings.
	var raining := world != null and world.rain_intensity > 0.25
	var sun_dry := 1.0
	if world != null:
		sun_dry = lerpf(1.12, 0.58, world.twilight_factor())
		sun_dry *= 1.0 - world.rain_wetness * 0.55
	for i in range(traces.size() - 1, -1, -1):
		var t := traces[i]
		var rate := sun_dry
		if raining:
			if t.kind == Kind.WET_RING or t.kind == Kind.DAMP_SPOT:
				rate = 0.05
			else:
				rate = 0.25
		if heat_strength > 0.10:
			var d := t.pos.distance_to(heat_origin)
			if d < 46.0:
				rate += heat_strength * (1.0 - d / 46.0) * 3.8
		t.age += dt * rate
		if t.age >= t.max_life:
			traces.remove_at(i)

func draw(canvas: Node2D, shade_color: Callable) -> void:
	for t in traces:
		var a := t.alpha()
		if a <= 0.01:
			continue
		match t.kind:
			Kind.HOLLOW:
				_draw_hollow(canvas, t, a, shade_color)
			Kind.WET_RING:
				_draw_wet_ring(canvas, t, a, shade_color)
			Kind.DAMP_SPOT:
				_draw_damp_spot(canvas, t, a, shade_color)
			Kind.PLUCK_MARK:
				_draw_pluck_mark(canvas, t, a, shade_color)

func _draw_hollow(canvas: Node2D, t: Trace, a: float, shade_color: Callable) -> void:
	var rx := t.radius * 0.84
	var ry := t.radius * 0.44
	var c := t.pos
	# Outer damp disturbed earth rim.
	var outer := _oval(c, rx, ry, 10)
	var damp_outer: Color = shade_color.call(Color("#694326", 0.44 * a), c)
	canvas.draw_colored_polygon(outer, damp_outer)
	# Inner recessed moist soil depression.
	var inner := _oval(c + Vector2(0.0, 0.25), rx * 0.74, ry * 0.70, 10)
	var damp_inner: Color = shade_color.call(Color("#452b18", 0.56 * a), c)
	canvas.draw_colored_polygon(inner, damp_inner)
	# Crisp dark upper lip shadow giving recessed hollow depth.
	var top_arc := PackedVector2Array()
	for i in range(5):
		var ang := lerpf(PI * 1.12, PI * 1.88, float(i) / 4.0)
		top_arc.append(_snap(c + Vector2(cos(ang) * rx * 0.78, sin(ang) * ry * 0.76)))
	var lip_shadow: Color = shade_color.call(Color("#2e1c10", 0.64 * a), c)
	canvas.draw_polyline(top_arc, lip_shadow, 0.75)
	# Faint sunlit lower earth rim + 3 tiny disturbed dirt crumbs.
	var bot_arc := PackedVector2Array()
	for i in range(4):
		var ang := lerpf(0.22, PI - 0.22, float(i) / 3.0)
		bot_arc.append(_snap(c + Vector2(cos(ang) * rx * 0.88, sin(ang) * ry * 0.86)))
	var lip_sun: Color = shade_color.call(Color("#c98f58", 0.28 * a), c)
	canvas.draw_polyline(bot_arc, lip_sun, 0.5)
	var crumb_col: Color = shade_color.call(Color("#5c3a21", 0.70 * a), c)
	for i in 3:
		var ang := 0.35 + float(i) * 1.05 + t.seed * 0.9
		var crumb := _snap(c + Vector2(cos(ang) * (rx + 1.0), sin(ang) * (ry + 0.7)))
		canvas.draw_rect(Rect2(crumb, Vector2(1.0 if i != 1 else 0.5, 0.5)), crumb_col)

func _draw_wet_ring(canvas: Node2D, t: Trace, a: float, shade_color: Callable) -> void:
	var rx := t.radius * 1.06
	var ry := t.radius * 0.58
	var c := t.pos
	var outer := _oval(c, rx, ry, 12)
	var soak_outer: Color = shade_color.call(Color("#5e3e24", 0.30 * a), c)
	canvas.draw_colored_polygon(outer, soak_outer)
	var inner := _oval(c, rx * 0.80, ry * 0.78, 10)
	var soak_inner: Color = shade_color.call(Color("#432b18", 0.46 * a), c)
	canvas.draw_colored_polygon(inner, soak_inner)

func _draw_damp_spot(canvas: Node2D, t: Trace, a: float, shade_color: Callable) -> void:
	var rx := t.radius * 0.92
	var ry := t.radius * 0.54
	var c := t.pos
	var outer := _oval(c, rx, ry, 8)
	var wet_outer: Color = shade_color.call(Color("#654226", 0.28 * a), c)
	canvas.draw_colored_polygon(outer, wet_outer)
	var core := _oval(c + Vector2((t.seed - 0.5) * 0.8, 0.0), rx * 0.64, ry * 0.62, 8)
	var wet_core: Color = shade_color.call(Color("#462c19", 0.42 * a), c)
	canvas.draw_colored_polygon(core, wet_core)
	var speck := _snap(c + Vector2(rx * 0.95 * (1.0 if t.seed > 0.5 else -1.0), ry * 0.45))
	canvas.draw_rect(Rect2(speck, Vector2(1.0, 0.5)), shade_color.call(Color("#51341e", 0.36 * a), speck))

func _draw_pluck_mark(canvas: Node2D, t: Trace, a: float, shade_color: Callable) -> void:
	var c := t.pos
	var soil: Color = shade_color.call(Color("#4b301c", 0.62 * a), c)
	canvas.draw_rect(Rect2(_snap(c - Vector2(1.5, 0.5)), Vector2(3.0, 1.0)), soil)
	canvas.draw_rect(Rect2(_snap(c + Vector2(1.5, 0.5)), Vector2(1.0, 0.5)), soil)
	var stem: Color = shade_color.call(Color("#7c874a", 0.74 * a), c)
	canvas.draw_rect(Rect2(_snap(c + Vector2(-0.5, -1.0)), Vector2(0.5, 1.0)), stem)

func _oval(center: Vector2, rx: float, ry: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var ang := float(i) * TAU / float(segments)
		pts.append(_snap(center + Vector2(cos(ang) * rx, sin(ang) * ry)))
	return pts

func _snap(point: Vector2) -> Vector2:
	return (point * 2.0).round() * 0.5
