extends RefCounted

const SIZE := Vector2(320, 200)
const PUDDLES := [Vector3(201, 37, 7.5), Vector3(228, 20, 5.5), Vector3(118, 175, 6.0),
	Vector3(150, 181, 9.0), Vector3(184, 175, 4.0)]
const OUTLINE := [Vector2(-1, 0.05), Vector2(-0.76, -0.36), Vector2(-0.17, -0.43),
	Vector2(0.45, -0.29), Vector2(1.0, 0.07), Vector2(0.54, 0.41), Vector2(-0.12, 0.45), Vector2(-0.71, 0.32)]

enum Contact { GROUND, LEAVES, WATER }

class Drop:
	var at: Vector2
	var slant: float
	var age: float
	var kind := Contact.GROUND
	var heavy := false

var enabled := false
var intensity := 0.0
var runoff := 0.0
var wetness := 0.0
var had_rain := false
var after_rain := 0.0
var puddles := PackedFloat32Array()
var drops: Array[Drop] = []
var drop_lag := 0.0
var drip_due := 0.9
var rng := RandomNumberGenerator.new()

func _init() -> void:
	puddles.resize(PUDDLES.size())

func clear() -> void:
	enabled = false
	intensity = 0.0
	runoff = 0.0
	wetness = 0.0
	had_rain = false
	after_rain = 0.0
	puddles.fill(0.0)
	drops.clear()
	drop_lag = 0.0
	drip_due = 0.9

func advance(dt: float) -> void:
	intensity = move_toward(intensity, 1.0 if enabled else 0.0, dt * (0.29 if enabled else 0.41))
	runoff = lerpf(runoff, intensity, 1.0 - exp(-dt * (0.49 if intensity > runoff else 0.23)))
	wetness = clampf(wetness + (intensity * 0.23 - (0.022 + wetness * 0.036)) * dt, 0.0, 1.0)
	if intensity > 0.35:
		had_rain = true
		after_rain = 0.0
	elif not enabled and had_rain and intensity < 0.16:
		after_rain = 1.0
		had_rain = false
	elif intensity < 0.15 and after_rain > 0.0:
		after_rain = move_toward(after_rain, 0.0, dt / 22.0)
	for i in puddles.size():
		puddles[i] = clampf(puddles[i] + (intensity * (0.13 + i * 0.012) - (0.028 + i * 0.003)) * dt, 0.0, 1.0)

func active_puddle_spots() -> Array[Vector2]:
	var spots: Array[Vector2] = []
	for i in puddles.size():
		if puddles[i] <= 0.22:
			continue
		var p: Vector3 = PUDDLES[i]
		# Pick dry edge just beside the puddle, skipping bottom-right HUD area.
		var edge := Vector2(p.x - p.z - 4.0, p.y - 2.0)
		if edge.x > 142.0 and edge.y > 162.0:
			continue
		spots.append(edge)
	return spots

func advance_drops(dt: float, view) -> void:
	drop_lag += dt * intensity * 116.0
	while drop_lag >= 1.0 and drops.size() < 104:
		drop_lag -= 1.0
		var drop := Drop.new()
		drop.at = Vector2(rng.randf_range(2.0, SIZE.x - 2.0), rng.randf_range(2.0, SIZE.y - 2.0))
		drop.slant = 3.8 + view.wind.strength_at(drop.at.x / SIZE.x) * 4.0
		drop.age = -rng.randf_range(0.13, 0.24)
		drops.append(drop)
	drop_lag = minf(drop_lag, 1.0)
	if intensity > 0.08 or wetness > 0.24:
		drip_due -= dt
		if drip_due <= 0.0 and drops.size() < 112:
			var drip := Drop.new()
			drip.heavy = true
			drip.at = Vector2(rng.randf_range(20.0, 112.0), rng.randf_range(44.0, 106.0))
			drip.slant = 0.8 + view.wind.strength_at(drip.at.x / SIZE.x) * 1.2
			drip.age = -0.26
			drops.append(drip)
			drip_due = rng.randf_range(0.35, 0.85) if intensity > 0.08 else rng.randf_range(0.9, 2.2)
	for index in range(drops.size() - 1, -1, -1):
		var drop := drops[index]
		var falling := drop.age < 0.0
		drop.age += dt
		if falling and drop.age >= 0.0:
			drop.kind = view.rain_contact(drop.at)
			for i in puddles.size():
				var spot: Vector3 = PUDDLES[i]
				var offset := (drop.at - Vector2(spot.x, spot.y)) * Vector2(1, 2.4)
				if puddles[i] > 0.10 and offset.length_squared() < pow(spot.z * puddles[i], 2.0):
					drop.kind = Contact.WATER
					break
			if drop.heavy and drop.kind == Contact.WATER:
				var local: Vector2 = view.from_screen(drop.at)
				if view.is_wet(local):
					view.ripples.append(Vector4(local.x, local.y, 0.0, 0.22))
		if drop.age >= (0.48 if drop.kind == Contact.WATER else 0.23):
			drops.remove_at(index)

func draw_puddles(canvas: Node2D) -> void:
	for i in puddles.size():
		var amount := smoothstep(0.05, 0.91, puddles[i])
		var spot: Vector3 = PUDDLES[i]
		if spot.z * amount < 2.0:
			continue
		var center := Vector2(spot.x, spot.y)
		var contour := PackedVector2Array()
		var damp_edge := PackedVector2Array()
		for corner: Vector2 in OUTLINE:
			var form := corner.rotated((i - 2) * 0.105) * spot.z * amount
			contour.append(snap(center + form))
			damp_edge.append(snap(center + form * 1.20))
		canvas.draw_colored_polygon(damp_edge, Color("#35362f75"))
		canvas.draw_colored_polygon(contour, Color("#3d5351c4"))
		var edge := Vector2(spot.z * amount * 0.38, spot.z * amount * 0.09)
		canvas.draw_line(snap(center - edge), snap(center + edge), Color(0.64, 0.71, 0.67, amount * 0.30), 0.5)

func draw_drops(canvas: Node2D) -> void:
	for drop in drops:
		if drop.age < 0.0:
			if drop.heavy:
				var bead := drop.at + Vector2(drop.slant, 48.0) * drop.age
				var alpha := maxf(0.45, intensity * 0.72)
				canvas.draw_rect(Rect2(snap(bead - Vector2(0.25, 1.0)), Vector2(0.75, 1.75)), Color(0.84, 0.92, 0.88, alpha))
			else:
				var at := drop.at + Vector2(drop.slant, 76.0) * drop.age
				var tail := at - Vector2(drop.slant * 0.23, 4.0)
				canvas.draw_line(snap(tail), snap(at), Color(0.76, 0.84, 0.82, intensity * 0.38), 0.5)
			continue
		if drop.kind == Contact.WATER:
			var size := (0.9 + drop.age * 8.5) if drop.heavy else (0.65 + drop.age * 6.5)
			var ink := Color(0.82, 0.91, 0.86, (1.0 - drop.age / 0.48) * (0.68 if drop.heavy else 0.54))
			for side in [-1.0, 1.0]:
				var start := drop.at + Vector2(side * size, 0)
				canvas.draw_line(snap(start), snap(drop.at + Vector2(side * size * 0.42, size * 0.38)), ink, 0.5)
				canvas.draw_line(snap(drop.at + Vector2(side * size * 0.67, -size * 0.28)), snap(start), Color(ink, ink.a * 0.63), 0.5)
				if drop.heavy and drop.age > 0.08:
					var inner := size * 0.56
					canvas.draw_line(snap(drop.at + Vector2(side * inner, 0)), snap(drop.at + Vector2(side * inner * 0.4, inner * 0.34)), Color(ink, ink.a * 0.55), 0.5)
		else:
			var fade := 1.0 - drop.age / 0.23
			var spray := Vector2(1.0 + drop.age * 7.0, -sin(drop.age / 0.23 * PI) * 1.7)
			var ink := Color(0.79, 0.87, 0.83, fade * (0.72 if drop.kind == Contact.LEAVES else 0.42))
			canvas.draw_rect(Rect2(snap(drop.at + spray), Vector2(0.5, 0.5)), ink)
			canvas.draw_rect(Rect2(snap(drop.at + Vector2(-spray.x, spray.y * 0.55)), Vector2(0.5, 0.5)), ink)

func snap(point: Vector2) -> Vector2:
	return (point * 2.0).round() * 0.5
