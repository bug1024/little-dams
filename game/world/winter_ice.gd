extends RefCounted

# Interactive thin winter shore ice hugging calm shallow creek bays:
# - Forms naturally along rocky winter waterlines (never blocking mid-channel dams).
# - Tapping/poking, dropping a stone nearby (SPLASH), spraying with the bamboo water gun
#   (WATER_JET), or releasing a dam flood wave (SURGE) cracks and shatters thin ice into
#   translucent floating ice shards that drift downstream with the live current!
# - Nearby campfire firelight gently melts adjacent shore ice without shattering.

signal ice_cracked(strength: float)

const SIZE := Vector2(320.0, 200.0)

# Calm shallow waterline coves in creek-channel coordinates: [x, y_waterline, rx, width_inward, seed]
# Positioned strictly along the wet water's edge (Pool.BANK = 34; wet waterline sits around ±19..±23).
const SHELF_SPECS := [
	[48.0, -20.0, 13.0, 3.6, 0.17],
	[114.0, -20.5, 12.5, 3.4, 0.43],
	[196.0, -22.0, 12.5, 3.5, 0.71],
	[72.0, 18.0, 12.5, 3.5, 0.29],
	[154.0, 19.0, 12.0, 3.4, 0.63],
	[218.0, 18.5, 11.5, 3.2, 0.89],
]

class IceShelf:
	var world_pos: Vector2
	var rx: float
	var ry: float
	var seed: float
	var integrity := 1.0
	var crack := 0.0
	var intact := true
	var regrow_wait := 0.0

class IceShard:
	var world_pos: Vector2
	var drift := Vector2.ZERO
	var angle := 0.0
	var spin := 0.0
	var size := 2.4
	var age := 0.0
	var life := 14.0

var active := false
var shelves: Array[IceShelf] = []
var shards: Array[IceShard] = []
var hovered_shelf: IceShelf
var clock := 0.0
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.seed = 9187
	_build_shelves()

func _build_shelves() -> void:
	shelves.clear()
	for spec: Array in SHELF_SPECS:
		var s := IceShelf.new()
		s.world_pos = Vector2(float(spec[0]), float(spec[1]))
		s.rx = float(spec[2])
		s.ry = float(spec[3])
		s.seed = float(spec[4])
		shelves.append(s)

func clear() -> void:
	shards.clear()
	hovered_shelf = null
	clock = 0.0
	_build_shelves()

func set_active(is_winter: bool) -> void:
	if active == is_winter:
		return
	active = is_winter
	hovered_shelf = null
	shards.clear()
	if active:
		_build_shelves()

func set_hover(screen_pos: Vector2, project: Callable) -> bool:
	hovered_shelf = null
	if not active:
		return false
	for s in shelves:
		if not s.intact or s.integrity <= 0.25:
			continue
		var c: Vector2 = project.call(s.world_pos)
		var d := Vector2((screen_pos.x - c.x) / (s.rx + 3.0), (screen_pos.y - c.y) / (s.ry + 3.5)).length()
		if d <= 1.0:
			hovered_shelf = s
			return true
	return false

func intact_count() -> int:
	var n := 0
	for s in shelves:
		if s.intact and s.integrity > 0.25:
			n += 1
	return n

func poke_at(screen_pos: Vector2, project: Callable) -> bool:
	if not active:
		return false
	for s in shelves:
		if not s.intact or s.integrity <= 0.25:
			continue
		var c: Vector2 = project.call(s.world_pos)
		var d := Vector2((screen_pos.x - c.x) / (s.rx + 3.0), (screen_pos.y - c.y) / (s.ry + 3.5)).length()
		if d <= 1.0:
			_damage_shelf(s, 0.72, Vector2(12.0, -signf(s.world_pos.y) * 9.0))
			return true
	return false

func hit_test(screen_pos: Vector2, project: Callable) -> bool:
	if not active:
		return false
	for s in shelves:
		if not s.intact or s.integrity <= 0.25:
			continue
		var c: Vector2 = project.call(s.world_pos)
		var d := Vector2((screen_pos.x - c.x) / (s.rx + 2.5), (screen_pos.y - c.y) / (s.ry + 3.0)).length()
		if d <= 1.0:
			return true
	return false

func disturb_screen(screen_pos: Vector2, radius: float, strength: float, project: Callable) -> int:
	if not active:
		return 0
	var broken := 0
	for s in shelves:
		if not s.intact or s.integrity <= 0.25:
			continue
		var c: Vector2 = project.call(s.world_pos)
		var dist := c.distance_to(screen_pos)
		if dist <= radius + s.rx * 0.65:
			var falloff := clampf(1.0 - dist / maxf(radius + s.rx * 0.65, 1.0), 0.25, 1.0)
			var push_dir := (c - screen_pos).normalized() if dist > 1.0 else Vector2(1.0, -signf(s.world_pos.y))
			if _damage_shelf(s, strength * falloff, push_dir * (14.0 * strength)):
				broken += 1
	return broken

func _damage_shelf(s: IceShelf, amount: float, impulse: Vector2) -> bool:
	s.crack = minf(1.0, s.crack + amount * 0.95)
	s.integrity = maxf(0.0, s.integrity - amount * 0.55)
	if s.crack >= 0.62 or s.integrity <= 0.30:
		s.intact = false
		s.integrity = 0.0
		s.crack = 1.0
		s.regrow_wait = 24.0
		_spawn_shards(s, impulse)
		ice_cracked.emit(clampf(amount, 0.35, 1.0))
		return true
	ice_cracked.emit(clampf(amount * 0.45, 0.18, 0.55))
	return false

func _spawn_shards(s: IceShelf, impulse: Vector2) -> void:
	var count := 4
	for i in count:
		if shards.size() >= 28:
			shards.remove_at(0)
		var sh := IceShard.new()
		var off := Vector2(lerpf(-s.rx * 0.55, s.rx * 0.55, float(i) / float(count - 1)), rng.randf_range(-1.2, 1.2))
		# Push slightly inward toward main current so broken ice pieces drift cleanly downstream.
		var inward := Vector2(0.0, -signf(s.world_pos.y) * rng.randf_range(3.0, 6.5))
		sh.world_pos = s.world_pos + off + inward
		sh.drift = Vector2(maxf(5.0, impulse.x * 0.55) + rng.randf_range(2.0, 8.0), -signf(s.world_pos.y) * rng.randf_range(2.5, 7.5))
		sh.angle = rng.randf_range(0.0, TAU)
		sh.spin = rng.randf_range(-1.6, 1.6)
		sh.size = rng.randf_range(1.7, 2.9)
		sh.life = rng.randf_range(11.0, 17.0)
		shards.append(sh)

func advance(dt: float, water, surge_fn: Callable, clear_path_fn: Callable, is_wet_fn: Callable,
		project: Callable, heat_origin: Vector2, heat_strength: float) -> void:
	if not active or dt <= 0.0:
		return
	clock += dt
	for s in shelves:
		var scr: Vector2 = project.call(s.world_pos)
		var near_fire := heat_strength > 0.12 and scr.distance_to(heat_origin) < 52.0
		if s.intact:
			# Dam release flood wave shatters thin shore ice!
			var surge_val: float = float(surge_fn.call(s.world_pos.x)) if surge_fn.is_valid() else 0.0
			if surge_val > 0.34:
				_damage_shelf(s, 0.95, Vector2(22.0 * surge_val, -signf(s.world_pos.y) * 8.0))
				continue
			if near_fire:
				var melt := heat_strength * (1.0 - scr.distance_to(heat_origin) / 52.0) * 0.24
				s.integrity = maxf(0.0, s.integrity - dt * melt)
				if s.integrity <= 0.08:
					s.intact = false
					s.regrow_wait = 18.0
			else:
				s.integrity = minf(1.0, s.integrity + dt * 0.03)
		else:
			if not near_fire:
				s.regrow_wait = maxf(0.0, s.regrow_wait - dt)
				if s.regrow_wait <= 0.0:
					s.intact = true
					s.integrity = 0.26
					s.crack = 0.0

	var step := minf(dt, 0.04)
	for i in range(shards.size() - 1, -1, -1):
		var sh := shards[i]
		sh.age += dt
		if sh.age >= sh.life or sh.world_pos.x > SIZE.x + 10.0:
			shards.remove_at(i)
			continue
		var flow: Vector2 = water.velocity_at(sh.world_pos).limit_length(66.0)
		sh.drift = sh.drift.lerp(flow * 0.92, 1.0 - exp(-step * 4.5))
		var target := sh.world_pos + sh.drift * step
		if bool(clear_path_fn.call(sh.world_pos, target, 1.6)):
			sh.world_pos = target
		else:
			# Slide gently around dam stones or rest gently against them like real creek ice!
			var side := -signf(sh.world_pos.y) if absf(sh.world_pos.y) > 4.0 else 1.0
			var lane := sh.world_pos + Vector2(0.0, side * 9.0 * step)
			if bool(clear_path_fn.call(sh.world_pos, lane, 1.6)):
				sh.world_pos = lane
			sh.drift *= 0.45
		sh.angle += sh.spin * dt
		sh.spin *= exp(-dt * 0.5)
		if not bool(is_wet_fn.call(sh.world_pos)):
			sh.age += dt * 1.5

func draw(canvas: Node2D, project: Callable, shade_color: Callable) -> void:
	if not active:
		return
	for s in shelves:
		if not s.intact or s.integrity <= 0.12:
			continue
		var scale_f := smoothstep(0.10, 0.72, s.integrity)
		var rx := s.rx * scale_f
		var ry := s.ry * scale_f
		var bank_sign := -1.0 if s.world_pos.y < 0.0 else 1.0
		var inward_sign := -bank_sign

		# Build a slender shore-hugging scalloped ice crust following the live creek curve:
		# back_pts hug the wet shoreline; front_pts protrude jaggedly into the shallow current.
		var back_pts := PackedVector2Array()
		var front_pts := PackedVector2Array()
		var frost_pts := PackedVector2Array()
		const STEPS := 6
		for i in range(STEPS + 1):
			var t := float(i) / float(STEPS)
			var u := (t - 0.5) * 2.0
			var arch := sin(t * PI)
			var x_pos := s.world_pos.x + u * rx
			# Anchor flush along the wet shoreline curve (no corners sticking out onto dry bank).
			var y_back := s.world_pos.y + bank_sign * (0.4 * arch)
			var bp := _snap(project.call(Vector2(x_pos, y_back)))
			back_pts.append(bp)
			# Jagged crystalline scallop protruding over the cold water.
			var tooth := 0.74 + 0.44 * fposmod(sin(float(i) * 5.3 + s.seed * 23.0) * 31.7, 1.0)
			var reach := ry * pow(arch, 0.75) * tooth * 1.42
			var y_front := y_back + inward_sign * reach
			var fp := _snap(project.call(Vector2(x_pos, y_front)))
			front_pts.append(fp)
			var y_mid := y_back + inward_sign * (reach * 0.44)
			frost_pts.append(_snap(project.call(Vector2(x_pos, y_mid))))

		var poly := PackedVector2Array()
		var frost_poly := PackedVector2Array()
		for i in range(STEPS + 1):
			poly.append(back_pts[i])
			frost_poly.append(back_pts[i])
		for i in range(STEPS, -1, -1):
			poly.append(front_pts[i])
			frost_poly.append(frost_pts[i])

		var c: Vector2 = project.call(s.world_pos)
		var is_hov := s == hovered_shelf
		var pulse := (0.78 + 0.22 * sin(clock * 6.0)) if is_hov else 0.0
		var edge_depth_col: Color = shade_color.call(Color("#254d5e", 0.44 * scale_f), c)
		var glass_body: Color = shade_color.call(Color("#b5e3f5" if is_hov else "#9cd0e6", (0.46 if is_hov else 0.34) * scale_f), c)
		var frost_band: Color = shade_color.call(Color("#e6f6ff" if is_hov else "#d8eef9", (0.56 if is_hov else 0.44) * scale_f), c)
		var crystal_rim: Color = shade_color.call(Color("#ffffff" if is_hov else "#effaff", (0.96 * pulse if is_hov else 0.78) * scale_f), c)

		# 1. Submerged thickness lip just below the jagged water-facing crystal edge.
		var under_edge := PackedVector2Array()
		for p in front_pts:
			under_edge.append(p + Vector2(0.0, 0.75))
		canvas.draw_polyline(under_edge, edge_depth_col, 1.0)
		# 2. Translucent thin ice sheet letting the dark teal creek & pebbles peek through.
		canvas.draw_colored_polygon(poly, glass_body)
		# 3. Slightly cloudier frosted anchor band right against the bank stones.
		canvas.draw_colored_polygon(frost_poly, frost_band)
		# 4. Crisp 0.5px pixel-art ice crystal rim along the scalloped front edge.
		canvas.draw_polyline(front_pts, crystal_rim, 0.9 if is_hov else 0.55)
		# 5. Two tiny trapped-air specular glints inside the ice sheet.
		for g in [2, 4]:
			var gp := _snap(back_pts[g].lerp(front_pts[g], 0.42))
			canvas.draw_rect(Rect2(gp, Vector2(1.0, 0.5)), Color(crystal_rim, crystal_rim.a * 0.75))

		# Crisp translucent fracture lines when cracked!
		if s.crack > 0.12:
			var crack_col: Color = shade_color.call(Color("#f0faff", 0.86), c)
			var dark_cr: Color = shade_color.call(Color("#36596e", 0.65), c)
			var m0 := _snap(back_pts[2].lerp(front_pts[2], 0.55))
			var m1 := _snap(back_pts[3].lerp(front_pts[3], 0.42))
			var m2 := _snap(back_pts[4].lerp(front_pts[4], 0.62))
			canvas.draw_polyline(PackedVector2Array([m0, m1, m2]), dark_cr, 0.75)
			canvas.draw_line(m1, front_pts[3], crack_col, 0.5)

	for sh in shards:
		var fade := 1.0 - smoothstep(0.76, 1.0, sh.age / sh.life)
		if fade <= 0.02:
			continue
		var c := _snap(project.call(sh.world_pos))
		var poly := PackedVector2Array()
		for corner: Vector2 in [Vector2(-1.0, -0.35), Vector2(0.2, -0.78), Vector2(1.05, -0.10), Vector2(0.45, 0.72), Vector2(-0.78, 0.55)]:
			poly.append(_snap(c + (corner * sh.size * Vector2(1.0, 0.62)).rotated(sh.angle)))
		var under: Color = shade_color.call(Color("#2a5469", 0.48 * fade), c)
		var fill: Color = shade_color.call(Color("#b2ddf0", 0.58 * fade), c)
		var rim: Color = shade_color.call(Color("#effaff", 0.86 * fade), c)
		var poly_sh := PackedVector2Array()
		for p in poly:
			poly_sh.append(p + Vector2(0.0, 0.55))
		canvas.draw_colored_polygon(poly_sh, under)
		canvas.draw_colored_polygon(poly, fill)
		canvas.draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2]]), rim, 0.5)

func _snap(pt: Vector2) -> Vector2:
	return (pt * 2.0).round() * 0.5
