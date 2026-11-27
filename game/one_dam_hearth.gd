extends RefCounted

const Wind = preload("res://game/one_dam_wind.gd")
const CENTER := Vector2(234, 154)
const RADIUS := Vector2(14, 8)
const LOGS := [
	Vector4(-8, 1.5, 6.5, -2.0), Vector4(-5.5, -3.0, 6.0, 2.7),
	Vector4(-8, -1.0, 1.0, 2.8), Vector4(-2, 2.6, 8.0, -1.0),
	Vector4(-5, 1.8, 2.5, -3.3),
]
# Each source records the supporting log, the fraction along it, and the gap above its front edge.
const SOURCES := [Vector3(0, 0.27, -0.85), Vector3(1, 0.50, -0.92), Vector3(1, 0.80, -0.82)]
const PROFILES := [Vector3(0.82, -1.05, 0.65), Vector3(1.77, 0.75, 0.85), Vector3(1.18, 1.85, -0.65)]
const TONGUE_SIZES := [Vector2(11.0, 1.9), Vector2(15.2, 2.5), Vector2(9.3, 1.5)]

class Tongue:
	var shape := Vector3.ONE
	var target := Vector3.ONE
	var interval := 0.0
	var flare_due := 0.0
	var flare_age := 1.0
	var split := false

	func flare_amount() -> float:
		return smoothstep(0.0, 0.24, flare_age) * (1.0 - smoothstep(0.30, 0.93, flare_age))

class Spark:
	var at: Vector2
	var drift: Vector2
	var life: float
	var age := 0.0

class Puff:
	var at: Vector2
	var age := 0.0
	var life: float
	var drift: float
	var waver: float
	var rise: float
	var close_to_ground := false

var wood := 0.0
var grass := 0.0
var heat := 0.0
var ash := 0.0
var dampness := 0.0
var burning := false
var clock := 0.0
var smoke_due := 0.0
var puffs: Array[Puff] = []
var tongues: Array[Tongue] = []
var sparks: Array[Spark] = []
var spark_due := 0.0
var lean := 0.0
var firelight := 0.0
var light_target := 1.0
var light_due := 0.0
var rng := RandomNumberGenerator.new()

func reset() -> void:
	wood = 0.0
	grass = 0.0
	heat = 0.0
	ash = 0.0
	dampness = 0.0
	burning = false
	clock = 0.0
	smoke_due = 0.0
	puffs.clear()
	tongues.clear()
	sparks.clear()
	spark_due = 0.0
	lean = 0.0
	firelight = 0.0
	light_due = 0.0
	light_target = 1.0
	for i in SOURCES.size():
		var tongue := Tongue.new()
		tongue.shape = Vector3(0.92 + i * 0.06, 1.0, i * 0.44 - 0.50)
		tongue.target = tongue.shape
		tongue.interval = 0.18 + i * 0.19
		tongue.flare_due = rng.randf_range(1.8, 4.3) + i * 0.67
		tongues.append(tongue)

func contains(point: Vector2) -> bool:
	return ((point - CENTER) / RADIUS).length_squared() <= 1.0

func can_add(is_wood: bool) -> bool:
	return (wood if is_wood else grass) <= 3.0

func add(is_wood: bool) -> void:
	if is_wood:
		wood += 1.0
	else:
		grass += 1.0

func can_ignite() -> bool:
	return not burning and wood >= 0.05 and grass >= 0.05 and dampness < 0.29

func ignite() -> void:
	if can_ignite():
		burning = true
		heat = 0.14
		smoke_due = 0.07

func douse(amount: float) -> void:
	dampness = clampf(dampness + amount, 0.0, 1.0)
	if burning:
		heat = maxf(0.0, heat - amount * 0.85)
		if puffs.size() < 24 and rng.randf() < 0.45:
			add_smoke(true)
		if heat <= 0.025 or dampness >= 0.88:
			ash = maxf(ash, 0.56)
			burning = false
			heat = 0.0
			add_smoke(false)

func advance(dt: float, rain: float, wind: Wind) -> void:
	clock += dt
	dampness = clampf(dampness + dt * (rain * 0.46 - 0.12 - heat * 0.11), 0.0, 1.0)
	if burning:
		var dry_heat := 0.10 + smoothstep(0.03, 0.65, wood) * 0.47 + smoothstep(0.32, 1.60, wood) * 0.40
		var target := dry_heat * (1.0 - smoothstep(0.13, 0.79, rain))
		heat = move_toward(heat, target, dt * (0.67 if target > heat else 0.26 + rain * 0.19))
		var burn := minf(wood, dt * (0.027 + heat * 0.058))
		wood -= burn
		grass = maxf(0.0, grass - dt * (0.045 + heat * 0.15))
		ash = minf(1.0, ash + burn * 0.78)
		if wood <= 0.02 or heat <= 0.015:
			ash = maxf(ash, 0.53)
			wood = 0.0
			grass = 0.0
			burning = false
	else:
		heat = move_toward(heat, 0.0, dt * (0.20 + rain * 0.25))
	var gust := wind.strength_at(CENTER.x / 320.0)
	advance_flame(dt, gust, wind.flutter(47))
	smoke_due -= dt
	if burning and smoke_due <= 0.0:
		add_smoke(false)
		if heat > 0.42 and rng.randf() < 0.26:
			add_smoke(true)
		smoke_due = rng.randf_range(0.48, 0.84) + (1.0 - heat) * 0.24 + rain * 0.18
	for i in range(puffs.size() - 1, -1, -1):
		var puff := puffs[i]
		puff.age += dt * (1.0 + rain)
		if puff.age >= puff.life:
			puffs.remove_at(i)
		else:
			var spread := smoothstep(0.13, 0.75, puff.age / puff.life)
			var swirl := sin(clock * 1.8 + puff.waver + puff.at.y * 0.07)
			var breeze := gust * (10.0 if puff.close_to_ground else 13.0)
			puff.at += Vector2(breeze + puff.drift * (0.3 + spread) + swirl * (1.4 + spread * 2.3),
				-puff.rise * (1.0 - spread * 0.54) + swirl * spread * 1.4) * dt

func advance_flame(dt: float, gust: float, flutter: float) -> void:
	lean = lerpf(lean, gust * 3.7 + flutter * 0.65, 1.0 - exp(-dt * 3.2))
	light_due -= dt
	if light_due <= 0.0:
		light_target = rng.randf_range(0.86, 1.06)
		light_due = rng.randf_range(0.36, 0.73)
	firelight = lerpf(firelight, heat * light_target, 1.0 - exp(-dt * 4.0))
	for i in tongues.size():
		var tongue := tongues[i]
		tongue.interval -= dt
		if tongue.interval <= 0.0:
			tongue.target = Vector3(rng.randf_range(0.77, 1.14), rng.randf_range(0.83, 1.14), rng.randf_range(-1.1, 1.1))
			tongue.interval = rng.randf_range(0.16 + i * 0.045, 0.36 + i * 0.075)
		tongue.shape = tongue.shape.lerp(tongue.target, 1.0 - exp(-dt * (8.0 - i * 1.2)))
		tongue.flare_due -= dt
		tongue.flare_age = minf(1.0, tongue.flare_age + dt * (1.45 + i * 0.23))
		if tongue.flare_due <= 0.0:
			if heat > 0.44:
				tongue.flare_age = 0.0
				tongue.split = rng.randf() < 0.68
			tongue.flare_due = rng.randf_range(2.9, 6.8) + i * 0.63
	spark_due -= dt
	if heat > 0.24 and spark_due <= 0.0:
		var spark := Spark.new()
		spark.at = flame_root(rng.randi_range(0, SOURCES.size() - 1)) - Vector2(0.0, 2.0)
		spark.drift = Vector2(rng.randf_range(-2.6, 2.1), -rng.randf_range(10.0, 15.0))
		spark.life = rng.randf_range(0.45, 0.90)
		sparks.append(spark)
		spark_due = rng.randf_range(0.69, 1.49) / heat
	for i in range(sparks.size() - 1, -1, -1):
		var spark := sparks[i]
		spark.age += dt
		if spark.age >= spark.life:
			sparks.remove_at(i)
		else:
			spark.at += (spark.drift + Vector2(gust * 8.0, 0.0)) * dt

func add_smoke(close_to_ground: bool) -> void:
	var puff := Puff.new()
	puff.close_to_ground = close_to_ground
	puff.at = CENTER + Vector2(rng.randf_range(-4.7, 3.6), -2.0 - heat * (3.0 if close_to_ground else 12.0))
	puff.life = rng.randf_range(3.2, 4.7) if close_to_ground else rng.randf_range(5.5, 7.4)
	puff.rise = rng.randf_range(2.0, 4.7) if close_to_ground else rng.randf_range(10.5, 14.2)
	puff.drift = rng.randf_range(-7.2, 7.2) if close_to_ground else rng.randf_range(-3.8, 4.8)
	puff.waver = rng.randf_range(0.0, TAU)
	puffs.append(puff)

func draw_bed(canvas: Node2D, hover: bool) -> void:
	var outline := PackedVector2Array([Vector2(-15, 0), Vector2(-14, -3), Vector2(-10, -5), Vector2(-6, -7),
		Vector2(0, -6), Vector2(4, -7), Vector2(10, -4), Vector2(13, -3), Vector2(15, 0),
		Vector2(11, 5), Vector2(4, 7), Vector2(-4, 6), Vector2(-9, 5), Vector2(-12, 3)])
	var shadow := PackedVector2Array()
	for i in outline.size():
		shadow.append(CENTER + outline[i] * 1.13 + Vector2(0.5, 1.4))
		outline[i] += CENTER
	canvas.draw_colored_polygon(shadow, Color("#26302495"))
	canvas.draw_colored_polygon(outline, Color("#554934").lerp(Color("#3b3830"), dampness * 0.7))
	var dip := PackedVector2Array([Vector2(-11, -1), Vector2(-8, -4), Vector2(-2, -5), Vector2(4, -4),
		Vector2(8, -4), Vector2(11, 0), Vector2(8, 3), Vector2(4, 4), Vector2(-3, 5), Vector2(-8, 3)])
	for i in dip.size():
		dip[i] += CENTER
	canvas.draw_colored_polygon(dip, Color("#3d3128").lerp(Color("#24231f"), ash))
	for i in 77:
		var at := Vector2(fposmod(i * 4.371, 28.0) - 14.0, fposmod(i * 3.781, 12.0) - 6.0)
		if (at / Vector2(14, 6)).length_squared() > 0.94:
			continue
		var burnt := ash * (1.0 - smoothstep(3.0, 10.0, absf(at.x)))
		var outer := smoothstep(0.28, 1.0, (at / Vector2(14, 6)).length_squared())
		var grain := Color("#41362b").lerp(Color("#78684a"), outer * 0.66 + (0.21 if i % 3 == 0 else 0.0))
		grain = grain.lerp(Color("#221f1d"), burnt * 0.78 + dampness * 0.16)
		var warmth := firelight * (1.0 - smoothstep(3.0, 13.0, at.length())) * 0.25
		grain = grain.lerp(Color("#94704a"), warmth)
		canvas.draw_rect(Rect2(snap(CENTER + at), Vector2(1.5 if i % 4 == 0 else 0.5, 0.75)), grain)
	if ash > 0.12:
		for i in 13:
			var at := Vector2(fposmod(i * 3.37, 16.0) - 8.0, fposmod(i * 2.53, 6.2) - 3.1)
			var shade := Color("#1a1917") if i % 3 == 0 else Color("#302c26")
			canvas.draw_rect(Rect2(snap(CENTER + at), Vector2(2.5 if i % 4 == 0 else 1.0, 0.75)), shade)
	if hover:
		var ink := Color("#e0ba7c95")
		canvas.draw_polyline(PackedVector2Array([CENTER + Vector2(-13, 1), CENTER + Vector2(-9, 4), CENTER + Vector2(-6, 5)]), ink, 0.5)
		canvas.draw_polyline(PackedVector2Array([CENTER + Vector2(13, 1), CENTER + Vector2(9, 4), CENTER + Vector2(6, 5)]), ink, 0.5)

func draw_fuel(canvas: Node2D) -> void:
	for i in ceili(grass * 3.0):
		var at := CENTER + Vector2(fposmod(i * 4.11, 13.0) - 6.5, fposmod(i * 2.29, 6.0) - 2.0)
		var tip := at + Vector2(3.0 - i % 4, -2.3 if i % 2 == 0 else 0.5)
		canvas.draw_line(snap(at), snap(tip), Color("#b7a06a") if i % 3 == 0 else Color("#83714b"), 0.5)
	if wood > 0.0:
		var count := clampi(2 + floori(wood), 2, LOGS.size())
		for i in count:
			var at := log_point(i, 0.0)
			var tip := log_point(i, 1.0)
			var bark := Color("#8b714e") if i % 2 == 0 else Color("#71583e")
			var charred := clampf(ash * 0.8 + (0.42 if burning else 0.0), 0.0, 0.81)
			canvas.draw_line(snap(at + Vector2(0, 0.8)), snap(tip + Vector2(0, 0.8)), Color("#2d2420"), 2.0)
			canvas.draw_line(snap(at), snap(tip), bark.lerp(Color("#42322a"), charred), 1.5)
			canvas.draw_line(snap(at.lerp(tip, 0.16) - Vector2(0, 0.5)), snap(at.lerp(tip, 0.77) - Vector2(0, 0.5)),
				bark.lerp(Color("#a08360"), 0.31), 0.5)
			canvas.draw_rect(Rect2(snap(tip), Vector2(1.0, 0.75)), bark.lightened(0.18))
	for i in 9:
		if firelight < 0.035:
			break
		var pos := CENTER + Vector2(fposmod(i * 4.19, 15.0) - 7.5, fposmod(i * 2.27, 5.2) - 0.9)
		var ember := clampf(firelight * (0.76 + 0.18 * sin(clock * (1.8 + i * 0.52) + i)), 0.0, 1.0)
		canvas.draw_rect(Rect2(snap(pos), Vector2(1.5 if i % 3 == 0 else 0.5, 0.5)), Color(Color("#974631"), ember))

func log_point(index: int, fraction: float) -> Vector2:
	var log: Vector4 = LOGS[index]
	var a := Vector2(log.x, log.y)
	var b := Vector2(log.z, log.w)
	var extent := lerpf(0.75, 1.0, clampf(wood, 0.0, 1.0)) if index < 2 else 1.0
	return CENTER + a.lerp(b, 0.5 + (fraction - 0.5) * extent)

func flame_root(index: int) -> Vector2:
	var source: Vector3 = SOURCES[index]
	return log_point(int(source.x), source.y) + Vector2(0, source.z)

func draw_flame(canvas: Node2D) -> void:
	draw_smoke(canvas)
	for i in tongues.size():
		var tongue := tongues[i]
		var size: Vector2 = TONGUE_SIZES[i]
		var root := flame_root(i)
		var lift := tongue.flare_amount()
		var height := heat * size.x * tongue.shape.x * (1.0 + lift * 0.29)
		var width := size.y * (0.58 + heat * 0.47) * tongue.shape.y
		draw_tongue(canvas, root, height, width, tongue.shape.z, lift if tongue.split else 0.0, PROFILES[i])
	if heat > 0.025 and wood > 0.0:
		# The near lip of the crosswise log occludes the roots without masking the coal bed.
		var at := snap(log_point(1, 0.36))
		var tip := snap(log_point(1, 0.89))
		var bark := Color("#3f2a21").lerp(Color("#865136"), firelight * 0.48)
		canvas.draw_line(at, tip, bark, 0.75)
	for spark in sparks:
		var age := spark.age / spark.life
		var ink := Color("#e6a55d").lerp(Color("#a65339"), age)
		canvas.draw_rect(Rect2(snap(spark.at), Vector2(0.5, 0.5)), Color(ink, (1.0 - age) * 0.79))

func draw_tongue(canvas: Node2D, root: Vector2, height: float, width: float, curl: float, split: float,
		profile: Vector3) -> void:
	var rows := roundi(height * 2.0)
	for row in rows:
		var rise := row * 0.5
		var level := float(row) / maxi(1, rows - 1)
		var free_tip := level * smoothstep(0.17, 0.79, level)
		var bend := free_tip * (lean + sin(level * 4.6 + profile.y) * (curl * 1.9 + profile.z))
		var belly := 0.87 + sin(level * 6.25 + profile.y + curl * 0.55) * 0.22
		var span := maxf(0.25, width * belly * pow(maxf(0.0, 1.0 - level), profile.x))
		var center := snap(root + Vector2(bend, -rise))
		var left := roundf((center.x - span * (1.02 + level * curl * 0.25)) * 2.0) * 0.5
		var right := roundf((center.x + span * (0.91 + free_tip * profile.z * 0.27)) * 2.0) * 0.5
		var outer := Color("#ba623c") if level < 0.70 else Color("#c97542")
		canvas.draw_rect(Rect2(Vector2(left, center.y), Vector2(maxf(0.5, right - left), 0.5)), outer)
		if span > 0.45 and level < 0.85:
			var inner := roundf((center.x - span * 0.56) * 2.0) * 0.5
			canvas.draw_rect(Rect2(Vector2(inner, center.y), Vector2(maxf(0.5, roundf(span * 2.1) * 0.5), 0.5)),
				Color("#e4a050"))
		if span > 0.70 and level > 0.10 and level < 0.48:
			var core := roundf((center.x - span * 0.26) * 2.0) * 0.5
			canvas.draw_rect(Rect2(Vector2(core, center.y), Vector2(maxf(0.5, roundf(span * 1.09) * 0.5), 0.5)),
				Color("#efd08a"))
			if heat > 0.58 and absf(root.x - CENTER.x) < 1.0 and level > 0.20 and level < 0.29:
				canvas.draw_rect(Rect2(Vector2(core, center.y), Vector2(0.5, 0.5)), Color("#f6e7bd"))
		if split > 0.37 and level > 0.66 and level < 0.88:
			var distance := 0.5 + (level - 0.66) * 7.2 * split
			var spur := snap(center + Vector2(-span - distance, 0.0))
			canvas.draw_rect(Rect2(spur, Vector2(0.5, 0.5)), Color(Color("#d79456"), split))

func draw_smoke(canvas: Node2D) -> void:
	for puff in puffs:
		var phase := puff.age / puff.life
		var alpha := smoothstep(0.0, 0.16, phase) * (1.0 - smoothstep(0.62, 1.0, phase))
		var span := (2.3 + phase * 8.6) * (1.12 if puff.close_to_ground else 1.0)
		var middle := snap(puff.at)
		var stretch := Vector2(1.0, 0.48 if puff.close_to_ground else 0.82)
		var ink := Color(0.73, 0.75, 0.71, alpha * (0.10 if puff.close_to_ground else 0.165))
		draw_smoke_wisp(canvas, middle, stretch * span, ink, puff.waver)
		var fringe := middle + Vector2(sin(puff.waver) * span * 0.62, -span * 0.21)
		draw_smoke_wisp(canvas, fringe, stretch * span * 0.79, Color(ink, ink.a * 0.48), puff.waver + 2.0)

func draw_smoke_wisp(canvas: Node2D, middle: Vector2, span: Vector2, ink: Color, phase: float) -> void:
	var outline := PackedVector2Array([Vector2(-1, 0.05), Vector2(-0.78, -0.24), Vector2(-0.64, -0.52),
		Vector2(-0.16, -0.47 - 0.12 * sin(phase)), Vector2(0.46, -0.61), Vector2(0.90, -0.29),
		Vector2(1, 0.09), Vector2(0.61, 0.31), Vector2(0.19, 0.37), Vector2(-0.53, 0.33)])
	for i in outline.size():
		outline[i] = snap(middle + outline[i] * span)
	canvas.draw_colored_polygon(outline, ink)

func snap(point: Vector2) -> Vector2:
	return (point * 2.0).round() * 0.5
