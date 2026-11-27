extends RefCounted

const Wind = preload("res://game/one_dam_wind.gd")

const HOME := Vector2(109.0, 184.0)
const SIZE := Vector2(320.0, 200.0)
const GRAVITY := 210.0
const NOZZLE_REACH := 9.5
const DEFAULT_RANGE := 152.0
const MIN_RANGE := 46.0
const MAX_RANGE := 225.0

class WaterParcel:
	var pos: Vector2
	var z: float
	var vel: Vector2
	var vz: float
	var age := 0.0
	var flight_t := 0.7
	var burst_id := 0
	var pressure := 1.0
	var spray_offset := Vector2.ZERO

class SplashSpot:
	var pos: Vector2
	var age := 0.0
	var life := 0.36
	var wet := false
	var seed := 0.0

var position := HOME
var anchor_pos := HOME
var aim_target := Vector2(220.0, 108.0)
var aim_angle := -0.42
var aim_distance := DEFAULT_RANGE
var held := false
var picked_this_press := false
var firing := false
var drawing := false
var water_fill := 0.0
var plunger := 0.0
var recoil := 0.0
var bounce := 0.0
var dry_puff := 0.0
var clock := 0.0
var spawn_accum := 0.0
var suction_due := 0.0
var burst_counter := 0
var drops: Array[WaterParcel] = []
var splashes: Array[SplashSpot] = []
var suction_rings: Array[Vector3] = []
var rng := RandomNumberGenerator.new()

func reset() -> void:
	position = HOME
	anchor_pos = HOME
	aim_target = Vector2(220.0, 108.0)
	aim_angle = -0.22
	aim_distance = DEFAULT_RANGE
	held = false
	picked_this_press = false
	firing = false
	drawing = false
	water_fill = 0.0
	plunger = 0.0
	recoil = 0.0
	bounce = 0.0
	dry_puff = 0.0
	clock = 0.0
	spawn_accum = 0.0
	suction_due = 0.0
	burst_counter = 0
	drops.clear()
	splashes.clear()
	suction_rings.clear()
	rng.seed = 8419

func gun_pos(pointer: Vector2) -> Vector2:
	if not held:
		return position
	if firing:
		return anchor_pos
	return (pointer - Vector2(0.0, 4.0)).clamp(Vector2(10.0, 10.0), SIZE - Vector2(10.0, 10.0))

func nozzle_pos(pointer: Vector2) -> Vector2:
	var base := gun_pos(pointer)
	var dip := Vector2(0.0, 2.2) if drawing else Vector2.ZERO
	return base + Vector2.from_angle(aim_angle) * (NOZZLE_REACH - recoil * 1.1) + dip

func hit_test(cursor: Vector2) -> bool:
	if held:
		return false
	var axis := Vector2.from_angle(aim_angle)
	var a := position - axis * (7.5 + plunger * 6.5)
	var b := position + axis * 9.5
	return Geometry2D.get_closest_point_to_segment(cursor, a, b).distance_to(cursor) <= 6.5

func pickup(pointer: Vector2) -> void:
	held = true
	picked_this_press = true
	firing = false
	drawing = false
	position = (pointer - Vector2(0.0, 4.0)).clamp(Vector2(10.0, 10.0), SIZE - Vector2(10.0, 10.0))
	anchor_pos = position
	aim_angle = default_aim_angle(position)
	bounce = 0.0

func default_aim_angle(from: Vector2) -> float:
	var target := Vector2(clampf(from.x + 115.0, 70.0, 278.0), 104.0)
	if from.x > 215.0:
		target.x = clampf(from.x - 115.0, 42.0, 240.0)
	return (target - from).angle()

func begin_trigger(pointer: Vector2, over_water: bool) -> String:
	picked_this_press = false
	if water_fill < 0.05:
		if over_water:
			firing = false
			drawing = true
			return "draw"
		dry_puff = 1.0
		return "dry"
	firing = true
	drawing = false
	anchor_pos = (pointer - Vector2(0.0, 4.0)).clamp(Vector2(10.0, 10.0), SIZE - Vector2(10.0, 10.0))
	position = anchor_pos
	aim_target = pointer
	aim_angle = default_aim_angle(anchor_pos)
	aim_distance = DEFAULT_RANGE
	burst_counter += 1
	spawn_accum = 0.016
	recoil = 1.0
	return "fire"

func end_trigger() -> void:
	picked_this_press = false
	firing = false

func put_down(cursor: Vector2, on_bank_ok: bool) -> void:
	held = false
	picked_this_press = false
	firing = false
	drawing = false
	if on_bank_ok:
		position = cursor.clamp(Vector2(14.0, 12.0), SIZE - Vector2(14.0, 10.0))
	else:
		position = HOME
	aim_angle = -0.22
	bounce = 0.80

func advance(dt: float, pointer: Vector2, wind: Wind, is_water_screen: Callable,
		on_impact: Callable, on_draw_ripple: Callable, mouse_down := false) -> void:
	if dt <= 0.0:
		return
	clock += dt
	bounce = move_toward(bounce, 0.0, dt * 4.6)
	recoil = move_toward(recoil, 0.0, dt * 7.5)
	dry_puff = move_toward(dry_puff, 0.0, dt * 4.5)

	# Update held position, aiming, suction drawing, and pressurized stream firing.
	if held:
		if firing:
			aim_target = pointer
			var aim_vec := pointer - anchor_pos
			if aim_vec.length() >= 10.0:
				aim_angle = lerp_angle(aim_angle, aim_vec.angle(), 1.0 - exp(-dt * 24.0))
				var tip := anchor_pos + Vector2.from_angle(aim_angle) * NOZZLE_REACH
				aim_distance = clampf(pointer.distance_to(tip), MIN_RANGE, MAX_RANGE)
			else:
				aim_distance = lerpf(aim_distance, DEFAULT_RANGE, 1.0 - exp(-dt * 8.0))
			if water_fill > 0.004:
				drawing = false
				water_fill = maxf(0.0, water_fill - dt * 0.46)
				spawn_accum += dt
				while spawn_accum >= 0.015:
					spawn_accum -= 0.015
					spawn_water_parcel(pointer)
			else:
				water_fill = 0.0
				firing = false
		else:
			position = gun_pos(pointer)
			anchor_pos = position
			var target_angle := default_aim_angle(position)
			var tip_probe := position + Vector2.from_angle(aim_angle) * NOZZLE_REACH
			var over_water := bool(is_water_screen.call(tip_probe)) or bool(is_water_screen.call(position))
			if over_water and water_fill < 0.995:
				drawing = true
				# Dip nozzle gently downward toward the creek surface while drawing water.
				var dip_angle := 0.34 if cos(target_angle) >= 0.0 else PI - 0.34
				aim_angle = lerp_angle(aim_angle, dip_angle, 1.0 - exp(-dt * 12.0))
				var fill_rate := 1.75 if mouse_down else 1.32
				water_fill = minf(1.0, water_fill + dt * fill_rate)
				suction_due -= dt
				if suction_due <= 0.0:
					suction_due = 0.14
					var tip_now := nozzle_pos(pointer)
					suction_rings.append(Vector3(tip_now.x, tip_now.y + 1.5, 0.0))
					if on_draw_ripple.is_valid():
						on_draw_ripple.call(tip_now)
			else:
				drawing = false
				aim_angle = lerp_angle(aim_angle, target_angle, 1.0 - exp(-dt * 7.5))
	else:
		firing = false
		drawing = false

	plunger = lerpf(plunger, water_fill, 1.0 - exp(-dt * (18.0 if firing else 12.0)))

	# Advance ballistic water parcels in 3D arc and trigger landing impacts.
	var breeze := Wind.DIRECTION * (wind.strength_at(0.5) * 8.5) if wind != null else Vector2.ZERO
	for i in range(drops.size() - 1, -1, -1):
		var drop := drops[i]
		drop.age += dt
		drop.vel += breeze * dt
		drop.pos += drop.vel * dt
		drop.vz -= GRAVITY * dt
		drop.z += drop.vz * dt
		if drop.z <= 0.0 or drop.age > 1.65 or not Rect2(Vector2(-12, -16), SIZE + Vector2(24, 32)).has_point(drop.pos):
			if drop.z <= 0.0 and Rect2(Vector2.ZERO, SIZE).has_point(drop.pos):
				var wet_hit := bool(is_water_screen.call(drop.pos))
				if splashes.size() < 48:
					var sp := SplashSpot.new()
					sp.pos = drop.pos
					sp.wet = wet_hit
					sp.life = 0.34 if wet_hit else 0.55
					sp.seed = rng.randf() * TAU
					splashes.append(sp)
				if on_impact.is_valid():
					on_impact.call(drop.pos, drop.vel, drop.pressure, wet_hit)
			drops.remove_at(i)

	for i in range(splashes.size() - 1, -1, -1):
		splashes[i].age += dt
		if splashes[i].age >= splashes[i].life:
			splashes.remove_at(i)

	for i in range(suction_rings.size() - 1, -1, -1):
		suction_rings[i].z += dt
		if suction_rings[i].z >= 0.42:
			suction_rings.remove_at(i)

func spawn_water_parcel(pointer: Vector2) -> void:
	var tip := nozzle_pos(pointer)
	var pressure := clampf(smoothstep(0.0, 0.16, water_fill) * 0.60 + 0.40, 0.40, 1.0)
	var reach := aim_distance * lerpf(0.52, 1.0, pressure)
	var flight_t := clampf(0.30 + reach * 0.0031, 0.40, 0.98)
	var z0 := 5.5
	var launch_ground := tip + Vector2(0.0, z0)
	# Smooth coherent stream waver so the jet arcs fluidly without zigzag jitter.
	var waver := sin(clock * 15.0) * 0.009 + sin(clock * 27.0) * 0.005
	var horiz_speed := reach / flight_t
	var dir := Vector2.from_angle(aim_angle + waver)
	var vz0 := (0.5 * GRAVITY * flight_t * flight_t - z0) / flight_t
	var p := WaterParcel.new()
	p.pos = launch_ground
	p.z = z0
	p.vel = dir * horiz_speed
	p.vz = vz0
	p.flight_t = flight_t
	p.burst_id = burst_counter
	p.pressure = pressure
	p.spray_offset = Vector2(rng.randf_range(-1.8, 1.8), rng.randf_range(-1.2, 1.2))
	drops.append(p)

func snap(pt: Vector2) -> Vector2:
	return (pt * 2.0).round() * 0.5

func apply_tint(color: Color, at: Vector2, tint_at: Callable) -> Color:
	return tint_at.call(color, at) if tint_at.is_valid() else color

func draw_stream(canvas: Node2D, tint_at: Callable, foam_col: Color) -> void:
	# 1. Contracting perspective suction rings and tiny inflow beads while drawing water from the creek.
	for ring in suction_rings:
		var t := clampf(ring.z / 0.42, 0.0, 1.0)
		var rx := lerpf(6.5, 1.0, t)
		var ry := rx * 0.56
		var a := sin(t * PI) * 0.72
		var c := snap(Vector2(ring.x, ring.y))
		draw_ellipse_ring(canvas, c, rx, ry, Color(foam_col, a), 12)
		for k in 3:
			var ang := k * TAU / 3.0 + t * 2.8 + clock * 4.0
			var bead := snap(c + Vector2(cos(ang) * rx, sin(ang) * ry))
			canvas.draw_rect(Rect2(bead, Vector2(0.5, 0.5)), Color(foam_col, a * 0.92))

	# 2. Landing splashes (perspective water ripples & sparkling splash flecks).
	for sp in splashes:
		var t := clampf(sp.age / sp.life, 0.0, 1.0)
		var c := snap(sp.pos)
		if sp.wet:
			var rx := 1.2 + t * 4.6
			draw_ellipse_ring(canvas, c, rx, rx * 0.54, Color(foam_col, (1.0 - t) * 0.60), 10)
		else:
			canvas.draw_rect(Rect2(c - Vector2(1.0, 0.5), Vector2(2.0, 1.0)), Color("#2b261c", (1.0 - t) * 0.34))
		if t < 0.68:
			var lift := sin(t / 0.68 * PI) * 3.6
			for k in 2:
				var dir := (1.0 if k == 0 else -1.0) * (0.7 + fposmod(sp.seed + k * 1.7, 1.4))
				var fleck := snap(c + Vector2(dir * t * 6.5, -lift + k * 0.5))
				canvas.draw_rect(Rect2(fleck, Vector2(0.5, 0.5)), Color(foam_col, (1.0 - t / 0.68) * 0.84))

	# 3. Ground shadows directly beneath the airborne water arc so 3D arc height reads vividly.
	for drop in drops:
		var shadow_a := clampf((1.0 - drop.z / 40.0) * 0.22, 0.05, 0.22)
		canvas.draw_rect(Rect2(snap(drop.pos), Vector2(1.5, 0.5)), Color("#142b29", shadow_a))

	# 4. Cohesive silky water ribbon near/mid-arc, breaking cleanly into glistening spray beads near landing.
	var aqua_core := Color("#74bfb8").lerp(foam_col, 0.38)
	for i in drops.size():
		var d := drops[i]
		var progress := clampf(d.age / maxf(0.15, d.flight_t), 0.0, 1.0)
		var scatter := smoothstep(0.58, 1.0, progress)
		var screen_pt := snap(d.pos - Vector2(0.0, d.z) + d.spray_offset * scatter)
		var col_mid := apply_tint(aqua_core, screen_pt, tint_at)
		if i > 0 and progress < 0.78:
			var prev := drops[i - 1]
			if prev.burst_id == d.burst_id and absf(prev.age - d.age) < 0.045:
				var prev_prog := clampf(prev.age / maxf(0.15, prev.flight_t), 0.0, 1.0)
				var prev_pt := snap(prev.pos - Vector2(0.0, prev.z) + prev.spray_offset * smoothstep(0.58, 1.0, prev_prog))
				if prev_pt.distance_to(screen_pt) < 16.0:
					var ribbon_t := clampf(1.0 - progress * 0.85, 0.22, 1.0)
					canvas.draw_line(prev_pt + Vector2(0.0, 0.5), screen_pt + Vector2(0.0, 0.5), Color("#204948", 0.28 * ribbon_t), 1.35)
					canvas.draw_line(prev_pt, screen_pt, Color(col_mid, 0.72 * ribbon_t), 1.1)
					canvas.draw_line(prev_pt - Vector2(0.0, 0.25), screen_pt - Vector2(0.0, 0.25), Color(foam_col, 0.82 * ribbon_t), 0.5)
		if scatter > 0.05:
			var bead_sz := Vector2(1.0, 0.5) if scatter < 0.65 else Vector2(0.5, 0.5)
			canvas.draw_rect(Rect2(screen_pt + Vector2(0.0, 0.5), bead_sz), Color("#1f4544", 0.30))
			canvas.draw_rect(Rect2(screen_pt, bead_sz), Color(foam_col, 0.90))

	# 5. Subtle perspective landing-target ripple ring while dragging to aim a shot!
	if held and firing and aim_target.distance_to(anchor_pos) >= 10.0:
		var pulse := 0.62 + 0.38 * sin(clock * 7.0)
		var tip := anchor_pos + Vector2.from_angle(aim_angle) * NOZZLE_REACH
		var target_pt := snap(tip + Vector2(0.0, 5.5) + Vector2.from_angle(aim_angle) * aim_distance)
		draw_ellipse_ring(canvas, target_pt, 4.2, 2.3, Color(foam_col, 0.56 * pulse), 12)

func draw_ellipse_ring(canvas: Node2D, center: Vector2, rx: float, ry: float, color: Color, segments := 12) -> void:
	var pts := PackedVector2Array()
	for i in segments + 1:
		var a := float(i) * TAU / float(segments)
		pts.append(snap(center + Vector2(cos(a) * rx, sin(a) * ry)))
	canvas.draw_polyline(pts, color, 0.5)

func draw_gun(canvas: Node2D, pointer: Vector2, tint_at: Callable, foam_col: Color) -> void:
	var p := snap(gun_pos(pointer))
	var squash := 1.0 - sin(bounce * PI) * 0.12
	var axis := Vector2.from_angle(aim_angle)
	var perp := axis.orthogonal()
	if perp.y < 0.0:
		perp = -perp
	var dip_offset := Vector2(0.0, 2.0) if drawing else Vector2.ZERO
	var center := p + dip_offset - axis * (recoil * 1.2)
	var xform := func(along: float, across: float) -> Vector2:
		return snap(center + axis * along + perp * (across * squash))

	# Shadow underneath (hugging the sand when resting, softly offset below when held).
	var shadow_drop := Vector2(0.5, 5.5) if held else Vector2(0.5, 2.0)
	var shadow_a := 0.28 if held else 0.44
	var sh_a := snap(center - axis * (7.5 + plunger * 7.0) + shadow_drop)
	var sh_b := snap(center + axis * 9.0 + shadow_drop)
	canvas.draw_line(sh_a, sh_b, Color(0.11, 0.12, 0.08, shadow_a), 2.5)

	# 1. Sliding wooden plunger rod & T-handle protruding behind the bamboo barrel.
	var rod_back := -6.2 - (2.4 + plunger * 7.4)
	var rod_dark := apply_tint(Color("#47311b"), center, tint_at)
	var rod_mid := apply_tint(Color("#b88d52"), center, tint_at)
	var rod_hi := apply_tint(Color("#e5c488"), center, tint_at)
	canvas.draw_line(xform.call(rod_back, 0.0), xform.call(-5.5, 0.0), rod_dark, 2.0)
	canvas.draw_line(xform.call(rod_back, 0.0), xform.call(-5.5, 0.0), rod_mid, 1.1)
	canvas.draw_line(xform.call(rod_back + 0.5, -0.45), xform.call(-5.8, -0.45), rod_hi, 0.5)
	# Perpendicular wooden T-handle crossbar at rear of plunger.
	canvas.draw_line(xform.call(rod_back, -2.5), xform.call(rod_back, 2.5), rod_dark, 2.4)
	canvas.draw_line(xform.call(rod_back, -2.2), xform.call(rod_back, 2.2), rod_mid, 1.3)
	canvas.draw_line(xform.call(rod_back - 0.3, -1.9), xform.call(rod_back - 0.3, 1.9), rod_hi, 0.5)

	# 2. Fresh green bamboo barrel body with bamboo nodes & rustic twine collar.
	var edge := apply_tint(Color("#25331a"), center, tint_at)
	var bam_dark := apply_tint(Color("#3e592a"), center, tint_at)
	var bam_mid := apply_tint(Color("#678c43"), center, tint_at)
	var bam_hi := apply_tint(Color("#9ac265"), center, tint_at)
	var bam_spec := apply_tint(Color("#c6e08b"), center, tint_at)
	var node_ridge := apply_tint(Color("#d2d68d"), center, tint_at)

	canvas.draw_line(xform.call(-6.2, 0.0), xform.call(6.2, 0.0), edge, 4.4)
	canvas.draw_line(xform.call(-5.8, 0.35), xform.call(5.8, 0.35), bam_dark, 3.0)
	canvas.draw_line(xform.call(-5.8, -0.15), xform.call(5.8, -0.15), bam_mid, 2.4)
	canvas.draw_line(xform.call(-5.5, -0.85), xform.call(5.5, -0.85), bam_hi, 1.0)
	canvas.draw_line(xform.call(-4.5, -1.2), xform.call(4.5, -1.2), bam_spec, 0.5)

	# Two bamboo joint rings (竹节) + warm hemp twine wrap.
	for joint: float in [-2.4, 3.2]:
		canvas.draw_line(xform.call(joint, -1.9), xform.call(joint, 1.9), edge, 0.9)
		canvas.draw_line(xform.call(joint + 0.55, -1.7), xform.call(joint + 0.55, 1.7), node_ridge, 0.55)
	var twine := apply_tint(Color("#b5844a"), center, tint_at)
	canvas.draw_line(xform.call(-5.2, -1.7), xform.call(-5.2, 1.7), twine, 0.9)

	# Subtle wet aqua gleam along the front barrel slot when filled with water.
	if water_fill > 0.06:
		var fill_span := lerpf(0.0, 5.2, water_fill)
		canvas.draw_line(xform.call(3.8 - fill_span, -0.1), xform.call(4.4, -0.1), Color(foam_col, 0.34 + water_fill * 0.28), 0.55)

	# 3. Tapered narrow bamboo/wood squirt nozzle protruding from the front cap.
	var tip_mid := apply_tint(Color("#bfa162"), center, tint_at)
	var tip_hi := apply_tint(Color("#e6d196"), center, tint_at)
	canvas.draw_line(xform.call(6.0, 0.0), xform.call(9.4, 0.0), edge, 2.2)
	canvas.draw_line(xform.call(6.0, 0.0), xform.call(9.2, 0.0), tip_mid, 1.2)
	canvas.draw_line(xform.call(6.2, -0.35), xform.call(8.9, -0.35), tip_hi, 0.5)
	canvas.draw_rect(Rect2(xform.call(9.4, -0.25), Vector2(0.5, 0.5)), edge)

	# Glistening water drop poised at the nozzle tip when loaded (zero-text ready cue!).
	if water_fill > 0.10 and not firing:
		var bead_pulse := 0.55 + 0.45 * sin(clock * 5.2)
		var tip_drop: Vector2 = xform.call(9.9, 0.4)
		canvas.draw_rect(Rect2(tip_drop, Vector2(0.5, 0.5)), Color(foam_col, 0.58 + 0.35 * bead_pulse))

	# Tiny dry air puff if clicked while empty.
	if dry_puff > 0.02:
		var t := 1.0 - dry_puff
		for k in 2:
			var puff_pt: Vector2 = xform.call(10.0 + t * (6.0 + k * 2.5), (k - 0.5) * (1.2 + t * 2.2))
			var puff := snap(puff_pt)
			canvas.draw_rect(Rect2(puff, Vector2(1.0, 0.5)), Color(Color("#ece5cf"), dry_puff * 0.65))
