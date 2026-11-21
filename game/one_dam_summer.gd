extends RefCounted

const Flow = preload("res://game/one_dam_grid.gd")

const SEDGES := [
	Vector3(25, 120, 7.5), Vector3(52, 143, 5.1), Vector3(100, 155, 5.0),
	Vector3(143, 151, 8.0), Vector3(182, 141, 5.6), Vector3(253, 115, 7.3),
	Vector3(217, 63, 4.8), Vector3(305, 49, 5.6),
]

var clock := 0.0
var fish := Vector2.ZERO
var fish_time := -1.0
var fish_due := 8.5
var insect_time := -1.0
var insect_due := 4.7
var flight_origin := Vector2(25.0, 141.0)
var flight_target := Vector2(223.0, 88.0)
var rng := RandomNumberGenerator.new()

func advance(dt: float, water: Flow) -> void:
	clock += dt
	if insect_time >= 0.0:
		insect_time += dt
		if insect_time > 4.5:
			insect_time = -1.0
			insect_due = clock + rng.randf_range(17.0, 32.0)
	elif clock >= insect_due:
		flight_origin = Vector2(rng.randf_range(6.0, 44.0), rng.randf_range(120.0, 158.0))
		flight_target = Vector2(rng.randf_range(218.0, 304.0), rng.randf_range(68.0, 111.0))
		insect_time = 0.0

	if fish_time >= 0.0:
		fish_time += dt
		var next := fish + Vector2(-13.0, sin(fish_time * 2.6) * 5.0) * dt
		if fish_time >= 4.8 or water.depth_at(next) < 0.13 or water.velocity_at(next).length() > 34.0:
			fish_due = clock + rng.randf_range(13.0, 23.0)
			fish_time = -1.0
		else:
			fish = next
	elif clock >= fish_due:
		for start in [Vector2(111, 5), Vector2(101, -6), Vector2(83, 0), Vector2(206, 7)]:
			if water.depth_at(start) > 0.19 and water.velocity_at(start).length() < 25.0:
				fish = start
				fish_time = 0.0
				return
		fish_due = clock + 5.0

func draw_fish(canvas: Node2D, project: Callable) -> void:
	if fish_time < 0.0:
		return
	var position: Vector2 = project.call(fish)
	var presence := smoothstep(0.0, 0.7, fish_time) * (1.0 - smoothstep(3.0, 4.8, fish_time))
	var tail := sin(fish_time * 12.0) * 1.2
	var shadow := Color(0.08, 0.18, 0.18, presence * 0.49)
	canvas.draw_colored_polygon(PackedVector2Array([
		position + Vector2(-4.1, 0.1), position + Vector2(-1.5, -1.35), position + Vector2(2.1, -0.75),
		position + Vector2(5.2, tail - 0.8), position + Vector2(4.2, tail + 1.3),
		position + Vector2(1.6, 0.54), position + Vector2(-1.9, 1.0),
	]), shadow)
	canvas.draw_line(position + Vector2(-2, -0.5), position + Vector2(1, -0.45), Color(0.50, 0.68, 0.60, presence * 0.25), 0.5)

func draw_land(canvas: Node2D) -> void:
	for i in SEDGES.size():
		var data: Vector3 = SEDGES[i]
		var root := Vector2(data.x, data.y)
		var gust := smoothstep(0.65, 0.99, sin(clock * 0.18 + i * 0.56))
		for stem in 4:
			var span := (stem - 1.4) * 2.0
			var height := data.z * (0.73 + stem % 3 * 0.16)
			var sway := sin(clock * (0.71 + i * 0.09) + i * 2.6 + stem * 0.29) * (0.44 + gust * 1.18)
			var split := root + Vector2(span * 0.37, -height * 0.54)
			var tip := root + Vector2(span + sway, -height)
			var ink := Color("#596332") if stem % 2 == 0 else Color("#858543")
			canvas.draw_line(root, split, Color("#454c2d"), 0.5)
			canvas.draw_line(split, tip, ink, 0.5)
			var blade := split.lerp(tip, 0.53)
			canvas.draw_line(blade, blade + Vector2(1.0 + sway * 0.6, -1.1), ink.lightened(0.11), 0.5)

	# A small sun-bleached bamboo stake by the path.
	var stake := Vector2(191.0, 41.0)
	canvas.draw_line(stake, stake + Vector2(4, 1), Color("#36392e62"), 1.0)
	canvas.draw_line(stake, stake + Vector2(-0.8, -9.0), Color("#5e5a36"), 1.5)
	canvas.draw_line(stake + Vector2(-0.4, -1), stake + Vector2(-1.0, -8.6), Color("#a7965b"), 0.5)
	canvas.draw_line(stake + Vector2(-1.6, -5.3), stake + Vector2(0.4, -5.6), Color("#c3a77a"), 0.5)

func draw_insect(canvas: Node2D) -> void:
	if insect_time < 0.0:
		return
	var age := insect_time
	var forward := smoothstep(0.0, 4.5, age)
	var point := flight_origin.lerp(flight_target, forward)
	point += Vector2(sin(age * 5.4) * 4.0, sin(age * 2.8) * 10.0 + cos(age * 7.3) * 2.0)
	var light := smoothstep(0.0, 0.24, age) * (1.0 - smoothstep(3.9, 4.5, age))
	var wing := sin(age * 61.0)
	canvas.draw_line(point - Vector2(2.8, 0), point + Vector2(1.6, -0.5), Color(0.26, 0.39, 0.29, light * 0.9), 0.7)
	var glint := Color(0.74, 0.88, 0.73, light * (0.40 + absf(wing) * 0.46))
	canvas.draw_line(point, point + Vector2(-1.0, -1.8 - wing), glint, 0.5)
	canvas.draw_line(point, point + Vector2(0.7, 1.0 + wing), glint, 0.5)
	canvas.draw_rect(Rect2(point + Vector2(0.6, -0.5), Vector2(0.5, 0.5)), Color(0.43, 0.75, 0.58, light))
