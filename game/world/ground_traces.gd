extends RefCounted

# Restrained, surface-aware environmental interaction traces:
# - Preserves original hand-painted ground integrity by sampling the real underlying surface
#   material (SOIL, ROCK, GRASS, SNOW) and tinting gently from its native color.
# - Ordinary stone moves leave only faint, low-contrast, irregular pressure/damp impressions
#   (never complete dark circular pits); only active digging (scooping clay, pulling a planted
#   stake, or uprooting a plant) leaves a slightly deeper, still organic mark.
# - All traces fade smoothly back into the ground over time.

const WorldState = preload("res://game/world/world_state.gd")

enum Kind { HOLLOW, WET_RING, DAMP_SPOT, PLUCK_MARK, STAKE_HOLE }
enum Surface { SOIL, ROCK, GRASS, SNOW }

const MAX_TRACES := 48

class Trace:
	var kind: Kind
	var pos: Vector2
	var radius: float
	var age := 0.0
	var max_life := 58.0
	var seed := 0.0
	var surface: Surface = Surface.SOIL
	var base_color := Color("#9e7852")
	var deep := false
	var in_water := false

	func _init(p_kind: Kind, p_pos: Vector2, p_radius: float, p_life: float) -> void:
		kind = p_kind
		pos = p_pos
		radius = p_radius
		max_life = p_life
		seed = fposmod(p_pos.x * 0.371 + p_pos.y * 0.619 + p_radius * 0.23, 1.0)

	func alpha() -> float:
		var remain := clampf(1.0 - age / maxf(max_life, 0.1), 0.0, 1.0)
		return pow(remain, 1.25)

var traces: Array[Trace] = []

func clear() -> void:
	traces.clear()

func count_kind(kind: Kind) -> int:
	var n := 0
	for t in traces:
		if t.kind == kind:
			n += 1
	return n

static func classify_surface(pixel: Color, is_winter := false) -> Surface:
	var luma := pixel.r * 0.26 + pixel.g * 0.63 + pixel.b * 0.11
	if is_winter and luma > 0.56 and pixel.b >= pixel.r * 0.93:
		return Surface.SNOW
	if pixel.g > pixel.r * 1.03 and pixel.g > pixel.b * 1.10:
		return Surface.GRASS
	if (pixel.b >= pixel.g * 0.88 and absf(pixel.r - pixel.b) < 0.16) or (is_winter and pixel.b >= pixel.r * 0.96):
		return Surface.ROCK
	return Surface.SOIL

func add_hollow(screen_pos: Vector2, radius: float, is_winter := false,
		surface_info: Dictionary = {}, is_deep := false) -> void:
	var spot := _snap(screen_pos + Vector2(0.0, radius * 0.24))
	var surf: Surface = Surface.SNOW if is_winter else Surface.SOIL
	var base_col := Color("#c6d6e6") if is_winter else Color("#9f7b54")
	if surface_info.has("surface"):
		surf = surface_info["surface"]
	if surface_info.has("color"):
		base_col = surface_info["color"]
	# Ordinary stone rests fade faster on hard rock than on soft dirt; active digging lasts slightly longer.
	var life := 74.0 if is_deep else (38.0 if surf == Surface.ROCK else 54.0)
	for t in traces:
		if t.kind == Kind.HOLLOW and t.pos.distance_to(spot) < maxf(4.0, radius * 0.45):
			t.age = 0.0
			t.radius = maxf(t.radius, radius)
			t.surface = surf
			t.base_color = base_col
			t.deep = t.deep or is_deep
			t.max_life = maxf(t.max_life, life)
			return
	var tr := Trace.new(Kind.HOLLOW, spot, clampf(radius, 5.0, 18.0), life)
	tr.surface = surf
	tr.base_color = base_col
	tr.deep = is_deep
	_push(tr)

func add_wet_ring(screen_pos: Vector2, radius: float, surface_info: Dictionary = {}) -> void:
	var spot := _snap(screen_pos + Vector2(0.0, radius * 0.46))
	var surf: Surface = surface_info.get("surface", Surface.SOIL)
	var base_col: Color = surface_info.get("color", Color("#9f7b54"))
	for t in traces:
		if t.kind == Kind.WET_RING and t.pos.distance_to(spot) < maxf(4.5, radius * 0.50):
			t.age = 0.0
			t.radius = maxf(t.radius, radius)
			t.surface = surf
			t.base_color = base_col
			return
	var tr := Trace.new(Kind.WET_RING, spot, clampf(radius, 5.0, 18.0), 48.0)
	tr.surface = surf
	tr.base_color = base_col
	_push(tr)

func add_damp_spot(screen_pos: Vector2, radius := 4.2, surface_info: Dictionary = {}) -> void:
	var spot := _snap(screen_pos)
	var surf: Surface = surface_info.get("surface", Surface.SOIL)
	var base_col: Color = surface_info.get("color", Color("#9f7b54"))
	for t in traces:
		if t.kind == Kind.DAMP_SPOT and t.pos.distance_to(spot) < 4.0:
			t.age = maxf(0.0, t.age - 7.0)
			t.radius = minf(6.4, maxf(t.radius, radius) + 0.18)
			return
	var tr := Trace.new(Kind.DAMP_SPOT, spot, clampf(radius, 2.5, 6.4), 36.0)
	tr.surface = surf
	tr.base_color = base_col
	_push(tr)

func add_pluck_mark(screen_pos: Vector2, surface_info: Dictionary = {}) -> void:
	var spot := _snap(screen_pos)
	var surf: Surface = surface_info.get("surface", Surface.GRASS)
	var base_col: Color = surface_info.get("color", Color("#6d8544"))
	for t in traces:
		if t.kind == Kind.PLUCK_MARK and t.pos.distance_to(spot) < 3.0:
			t.age = 0.0
			return
	var tr := Trace.new(Kind.PLUCK_MARK, spot, 2.4, 62.0)
	tr.surface = surf
	tr.base_color = base_col
	tr.deep = true
	_push(tr)

func add_stake_hole(screen_pos: Vector2, in_water := false, surface_info: Dictionary = {}) -> void:
	var spot := _snap(screen_pos)
	var surf: Surface = surface_info.get("surface", Surface.SOIL)
	var base_col: Color = surface_info.get("color", Color("#7d6347"))
	for t in traces:
		if t.kind == Kind.STAKE_HOLE and t.pos.distance_to(spot) < 3.5:
			t.age = 0.0
			return
	var tr := Trace.new(Kind.STAKE_HOLE, spot, 2.1 if in_water else 2.5, 46.0 if in_water else 66.0)
	tr.in_water = in_water
	tr.surface = surf
	tr.base_color = base_col
	tr.deep = true
	_push(tr)

func _push(trace: Trace) -> void:
	if traces.size() >= MAX_TRACES:
		traces.remove_at(0)
	traces.append(trace)

func advance(dt: float, world: WorldState, heat_origin := Vector2.ZERO, heat_strength := 0.0) -> void:
	if traces.is_empty():
		return
	var raining := world != null and world.rain_intensity > 0.25
	var sun_dry := 1.0
	if world != null:
		sun_dry = lerpf(1.12, 0.58, world.twilight_factor()) * world.profile.drying_rate
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
			Kind.STAKE_HOLE:
				_draw_stake_hole(canvas, t, a, shade_color)

func _draw_hollow(canvas: Node2D, t: Trace, a: float, shade_color: Callable) -> void:
	var rx := t.radius * 0.72
	var ry := t.radius * 0.36
	var c := t.pos
	match t.surface:
		Surface.ROCK:
			# Bare rock cannot dent into a mud pit: only a whisper-faint irregular contact smudge & grit.
			var smudge_col: Color = shade_color.call(Color(t.base_color.darkened(0.24), (0.24 if t.deep else 0.17) * a), c)
			var off_a := Vector2((t.seed - 0.5) * 1.4, -0.25)
			canvas.draw_colored_polygon(_irregular_patch(c + off_a, rx * 0.62, ry * 0.56, t.seed, 7), smudge_col)
			var grit_col: Color = shade_color.call(Color(t.base_color.lightened(0.18), 0.25 * a), c)
			for i in 2:
				var g_ang := 0.6 + float(i) * 2.1 + t.seed * 3.0
				var gp := _snap(c + Vector2(cos(g_ang) * rx * 0.65, sin(g_ang) * ry * 0.60))
				canvas.draw_rect(Rect2(gp, Vector2(0.5, 0.5)), grit_col)
		Surface.GRASS:
			# Flattened grass impression: soft low-contrast shaded turf + 3-4 bent blades (no brown crater).
			var press_col: Color = shade_color.call(Color(t.base_color.darkened(0.26), (0.28 if t.deep else 0.20) * a), c)
			canvas.draw_colored_polygon(_irregular_patch(c + Vector2(-0.5, 0.25), rx * 0.74, ry * 0.66, t.seed, 7), press_col)
			if t.deep:
				# Active mud scooping exposes one small off-center broken patch of damp earth beneath turf.
				var soil_peek: Color = shade_color.call(Color("#694d34", 0.30 * a), c)
				canvas.draw_colored_polygon(_irregular_patch(c + Vector2(rx * 0.16, 0.0), rx * 0.42, ry * 0.42, t.seed + 0.37, 6), soil_peek)
			var blade_col: Color = shade_color.call(Color(t.base_color.lightened(0.16), 0.32 * a), c)
			for i in 4:
				var ang := float(i) * 1.45 + t.seed * 2.4
				var b0 := _snap(c + Vector2(cos(ang) * rx * 0.45, sin(ang) * ry * 0.45))
				var b1 := _snap(b0 + Vector2(cos(ang) * 1.8, sin(ang) * 0.8 - 0.3))
				canvas.draw_line(b0, b1, blade_col, 0.5)
		Surface.SNOW:
			# Soft cool-blue pressed snow indentation (never a dark brown mud pit on snow!).
			var trough_col: Color = shade_color.call(Color("#8ca6c2", (0.30 if t.deep else 0.22) * a), c)
			canvas.draw_colored_polygon(_irregular_patch(c + Vector2(-0.4, 0.0), rx * 0.74, ry * 0.66, t.seed, 7), trough_col)
			var shade_arc := _broken_arc(c, rx * 0.64, ry * 0.56, PI * 1.15, PI * 1.80, t.seed)
			canvas.draw_polyline(shade_arc, shade_color.call(Color("#6c88a8", (0.34 if t.deep else 0.24) * a), c), 0.5)
			if t.deep:
				# Active clay digging exposes a modest irregular sliver of cold damp earth in the snow trough.
				var slush_earth: Color = shade_color.call(Color("#6e5946", 0.36 * a), c)
				canvas.draw_colored_polygon(_irregular_patch(c + Vector2(rx * 0.12, 0.25), rx * 0.44, ry * 0.40, t.seed + 0.51, 6), slush_earth)
			var frost_col: Color = shade_color.call(Color("#edf6fc", 0.40 * a), c)
			for i in 2:
				var ang := 0.45 + float(i) * 1.85 + t.seed * 1.6
				canvas.draw_rect(Rect2(_snap(c + Vector2(cos(ang) * (rx * 0.85), sin(ang) * (ry * 0.80))), Vector2(1.0, 0.5)), frost_col)
		_:
			# Surface.SOIL: broken, irregular, low-contrast earth scuff for ordinary stones; deeper scoop only when digging.
			var base_dark := t.base_color.darkened(0.32 if t.deep else 0.22)
			var lobe_a := _irregular_patch(c + Vector2(-rx * 0.18, 0.0), rx * (0.64 if t.deep else 0.56), ry * (0.62 if t.deep else 0.50), t.seed, 7)
			var lobe_b := _irregular_patch(c + Vector2(rx * 0.24, ry * 0.12), rx * (0.48 if t.deep else 0.42), ry * (0.50 if t.deep else 0.42), t.seed + 0.43, 6)
			canvas.draw_colored_polygon(lobe_a, shade_color.call(Color(base_dark, (0.34 if t.deep else 0.22) * a), c))
			canvas.draw_colored_polygon(lobe_b, shade_color.call(Color(base_dark.darkened(0.08), (0.30 if t.deep else 0.18) * a), c))
			# Short fragmented upper contact edge rather than a complete circular rim.
			var lip := _broken_arc(c, rx * 0.62, ry * 0.54, PI * 1.18, PI * 1.76, t.seed)
			canvas.draw_polyline(lip, shade_color.call(Color(t.base_color.darkened(0.46), (0.42 if t.deep else 0.25) * a), c), 0.5)
			var crumb_n := 3 if t.deep else 2
			var crumb_col: Color = shade_color.call(Color(t.base_color.darkened(0.35), (0.44 if t.deep else 0.28) * a), c)
			for i in crumb_n:
				var ang := 0.35 + float(i) * 1.25 + t.seed * 1.8
				var crumb := _snap(c + Vector2(cos(ang) * (rx * 0.82), sin(ang) * (ry * 0.78)))
				canvas.draw_rect(Rect2(crumb, Vector2(0.5 if i % 2 == 1 else 1.0, 0.5)), crumb_col)

func _draw_wet_ring(canvas: Node2D, t: Trace, a: float, shade_color: Callable) -> void:
	# Subtle broken damp seepage lobes derived from the underlying ground color (never a solid brown oval).
	var rx := t.radius * 0.86
	var ry := t.radius * 0.46
	var c := t.pos
	var wet_mult := Color(0.68, 0.74, 0.78) if (t.surface == Surface.ROCK or t.surface == Surface.SNOW) else Color(0.64, 0.67, 0.66)
	var damp_tone := Color(t.base_color.r * wet_mult.r, t.base_color.g * wet_mult.g, t.base_color.b * wet_mult.b)
	var peak_a := 0.18 if t.surface == Surface.ROCK else (0.20 if t.surface == Surface.SNOW else 0.25)
	var patch_a := _irregular_patch(c + Vector2(-rx * 0.14, 0.25), rx * 0.68, ry * 0.66, t.seed, 7)
	var patch_b := _irregular_patch(c + Vector2(rx * 0.22, -0.15), rx * 0.52, ry * 0.56, t.seed + 0.39, 6)
	canvas.draw_colored_polygon(patch_a, shade_color.call(Color(damp_tone, peak_a * a), c))
	canvas.draw_colored_polygon(patch_b, shade_color.call(Color(damp_tone.darkened(0.10), peak_a * 0.85 * a), c))

func _draw_damp_spot(canvas: Node2D, t: Trace, a: float, shade_color: Callable) -> void:
	var rx := t.radius * 0.82
	var ry := t.radius * 0.48
	var c := t.pos
	var wet_tone := Color(t.base_color.r * 0.68, t.base_color.g * 0.72, t.base_color.b * 0.74)
	var peak_a := 0.17 if t.surface == Surface.ROCK else 0.23
	canvas.draw_colored_polygon(_irregular_patch(c, rx, ry, t.seed, 7), shade_color.call(Color(wet_tone, peak_a * 0.78 * a), c))
	var core_off := Vector2((t.seed - 0.5) * 1.1, 0.15)
	canvas.draw_colored_polygon(_irregular_patch(c + core_off, rx * 0.58, ry * 0.56, t.seed + 0.29, 6),
		shade_color.call(Color(wet_tone.darkened(0.10), peak_a * a), c))

func _draw_pluck_mark(canvas: Node2D, t: Trace, a: float, shade_color: Callable) -> void:
	# Active uprooting: tiny irregular tuft of disturbed earth & cut stem (restrained alpha).
	var c := t.pos
	var soil_col: Color = shade_color.call(Color(t.base_color.darkened(0.42), 0.42 * a), c)
	canvas.draw_rect(Rect2(_snap(c - Vector2(1.25, 0.5)), Vector2(2.5, 1.0)), soil_col)
	canvas.draw_rect(Rect2(_snap(c + Vector2(1.25, 0.25)), Vector2(0.5, 0.5)), soil_col)
	var stem: Color = shade_color.call(Color("#7c874a", 0.52 * a), c)
	canvas.draw_rect(Rect2(_snap(c + Vector2(-0.5, -1.0)), Vector2(0.5, 1.0)), stem)

func _draw_stake_hole(canvas: Node2D, t: Trace, a: float, shade_color: Callable) -> void:
	# Active stake pull: small irregular recessed mud/gravel socket.
	var c := t.pos
	var rim_raw := Color("#39554f", 0.34 * a) if t.in_water else Color(t.base_color.darkened(0.30), 0.36 * a)
	var hole_raw := Color("#1c3534", 0.52 * a) if t.in_water else Color(t.base_color.darkened(0.54), 0.50 * a)
	canvas.draw_colored_polygon(_irregular_patch(c, t.radius * 0.86, t.radius * 0.50, t.seed, 6), shade_color.call(rim_raw, c))
	canvas.draw_colored_polygon(_irregular_patch(c + Vector2(0.0, 0.25), t.radius * 0.46, t.radius * 0.30, t.seed + 0.4, 5), shade_color.call(hole_raw, c))
	var fleck_raw := Color("#5b7870", 0.38 * a) if t.in_water else Color(t.base_color.darkened(0.36), 0.42 * a)
	canvas.draw_rect(Rect2(_snap(c + Vector2(-t.radius * 0.78, 0.5)), Vector2(0.5, 0.5)), shade_color.call(fleck_raw, c))

func _irregular_patch(center: Vector2, rx: float, ry: float, seed_val: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var ang := float(i) * TAU / float(segments) + seed_val * 1.7
		var jitter := 0.68 + 0.52 * fposmod(sin(float(i) * 4.71 + seed_val * 29.3) * 43.1, 1.0)
		pts.append(_snap(center + Vector2(cos(ang) * rx * jitter, sin(ang) * ry * jitter)))
	return pts

func _broken_arc(center: Vector2, rx: float, ry: float, a0: float, a1: float, seed_val: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 4:
		var ang := lerpf(a0, a1, float(i) / 3.0)
		var jitter := 0.84 + 0.28 * fposmod(sin(float(i) * 5.3 + seed_val * 19.0) * 23.7, 1.0)
		pts.append(_snap(center + Vector2(cos(ang) * rx * jitter, sin(ang) * ry * jitter)))
	return pts

func _snap(point: Vector2) -> Vector2:
	return (point * 2.0).round() * 0.5
