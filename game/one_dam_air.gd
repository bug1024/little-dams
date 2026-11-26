extends Node2D

## Things carried by the afternoon air: seed fluff, dust in the sunbeams,
## a gnat cloud and a falling leaf.
const Wind = preload("res://game/one_dam_wind.gd")
const SIZE := Vector2(320, 200)
const GNATS := Vector2(238, 66)

class Mote:
	var ground: Vector2
	var height := 0.0
	var phase := 0.0

class Firefly:
	var anchor: Vector2
	var pos: Vector2
	var phase := 0.0
	var period := 4.4
	var drift_phase := 0.0
	var radius := Vector2(12.0, 6.0)

var wind: Wind
var view
var clock := 0.0
var rng := RandomNumberGenerator.new()
var fluff: Array[Mote] = []
var dust: Array[Mote] = []
var fireflies: Array[Firefly] = []
var leaf: Mote
var leaf_turn := 0.0
var leaf_rest := 0.0
var leaf_due := 8.0
var leaf_source_x := 54.0

func _ready() -> void:
	for i in 11:
		fluff.append(make_mote(Vector2(rng.randf_range(0.0, SIZE.x), rng.randf_range(0.0, SIZE.y)), rng.randf_range(5.0, 24.0)))
	for i in 22:
		dust.append(make_mote(Vector2(rng.randf_range(10.0, 190.0), rng.randf_range(10.0, 150.0)), 0.0))
	for spot: Vector2 in [
		Vector2(28, 134), Vector2(46, 152), Vector2(78, 138), Vector2(128, 154),
		Vector2(174, 140), Vector2(236, 126), Vector2(278, 120), Vector2(256, 158),
		Vector2(54, 42), Vector2(118, 44), Vector2(168, 56), Vector2(218, 36),
		Vector2(286, 46), Vector2(148, 114),
	]:
		var f := Firefly.new()
		f.anchor = spot
		f.pos = spot
		f.phase = rng.randf_range(0.0, TAU)
		f.period = rng.randf_range(3.2, 5.8)
		f.drift_phase = rng.randf_range(0.0, TAU)
		f.radius = Vector2(rng.randf_range(8.0, 16.0), rng.randf_range(4.5, 9.0))
		fireflies.append(f)

func firefly_activity() -> float:
	if view == null:
		return 0.0
	var phase: float = view.day_phase
	var rainfall: float = view.rain.intensity
	return smoothstep(0.65, 1.55, phase) * (1.0 - rainfall * 0.85)

func make_mote(at: Vector2, height: float) -> Mote:
	var mote := Mote.new()
	mote.ground = at
	mote.height = height
	mote.phase = rng.randf() * TAU
	return mote

func breeze(point: Vector2) -> float:
	return wind.strength_at(point.x / SIZE.x)

func advance(dt: float) -> void:
	clock += dt
	for mote in fluff:
		var w := breeze(mote.ground)
		var push := Wind.DIRECTION * (2.5 + w * 26.0)
		push += Vector2(sin(clock * 0.8 + mote.phase) * 2.5, sin(clock * 1.3 + mote.phase * 1.7) * 1.6)
		mote.ground += push * dt
		mote.height = clampf(mote.height + (sin(clock * 0.55 + mote.phase * 2.3) * 2.2 + (w - 0.3) * 3.0) * dt, 3.0, 28.0)
		if mote.ground.x > SIZE.x + 8.0 or mote.ground.y > SIZE.y + 30.0:
			if rng.randf() < 0.6:
				mote.ground = Vector2(-6.0, rng.randf_range(-20.0, SIZE.y - 30.0))
			else:
				mote.ground = Vector2(rng.randf_range(-20.0, SIZE.x * 0.7), -6.0)
			mote.height = rng.randf_range(8.0, 24.0)
	for mote in dust:
		var drift := Vector2(sin(clock * 0.43 + mote.phase * 3.1), cos(clock * 0.31 + mote.phase * 4.7) * 0.7) * 1.3
		mote.ground += (drift + Wind.DIRECTION * breeze(mote.ground) * 3.0) * dt
		if mote.ground.x > 200.0 or mote.ground.y > 160.0:
			mote.ground = Vector2(rng.randf_range(0.0, 120.0), rng.randf_range(0.0, 60.0))
	for f in fireflies:
		var t := clock * 0.42 + f.drift_phase
		var sway := Vector2(sin(t) * f.radius.x, sin(t * 1.63 + 0.8) * f.radius.y)
		var gentle_wind := Wind.DIRECTION * breeze(f.anchor) * 3.0
		f.pos = (f.anchor + sway + gentle_wind).clamp(Vector2(6.0, 8.0), SIZE - Vector2(6.0, 8.0))
	advance_leaf(dt)
	queue_redraw()

func advance_leaf(dt: float) -> void:
	if leaf == null:
		var ready := clock >= leaf_due
		var gust := wind.strength_at(leaf_source_x / SIZE.x)
		if ready and (gust > 0.39 or clock >= leaf_due + 7.0):
			var source: Vector2 = view.to_screen(Vector2(leaf_source_x, rng.randf_range(-53.0, -41.0)))
			leaf = make_mote(source, rng.randf_range(27.0, 41.0))
			leaf_rest = 0.0
		return
	if leaf.height > 0.0:
		var w := breeze(leaf.ground)
		var swing := sin(clock * 2.6 + leaf.phase)
		leaf.ground += (Wind.DIRECTION * (3.0 + w * 20.0) + Vector2(swing * 9.0, 0.0)) * dt
		leaf.height -= (6.5 + absf(swing) * 4.0 - w * 2.5) * dt
		leaf_turn = swing * 1.1 + leaf.phase
		if leaf.height <= 0.0:
			leaf.height = 0.0
			if view.settle_leaf(leaf.ground, leaf_turn):
				finish_leaf()
			else:
				leaf_rest = 6.0
	else:
		leaf_rest -= dt
		if leaf_rest <= 0.0:
			finish_leaf()

func finish_leaf() -> void:
	leaf = null
	leaf_due = clock + rng.randf_range(13.0, 27.0)
	leaf_source_x = rng.randf_range(22.0, 126.0)

func snap(point: Vector2) -> Vector2:
	return (point * 2.0).round() * 0.5

func _draw() -> void:
	if wind == null:
		return
	var phase: float = view.day_phase if view != null else 0.0
	var dusk := smoothstep(0.0, 1.0, phase) * (1.0 - smoothstep(1.0, 2.0, phase))
	var twi := smoothstep(0.85, 2.0, phase)
	var light_shift := Vector2(wind.sunlight.x, wind.sunlight.y)
	var dust_tint := Color(1.0, 0.92, 0.70).lerp(Color(1.0, 0.78, 0.46), dusk)
	for mote in dust:
		var p := mote.ground / SIZE
		var light := Wind.sun_shafts(p - light_shift, clock, breeze(mote.ground)) * wind.sunlight.z * (1.0 - twi * 0.92)
		light *= 0.5 + 0.5 * sin(clock * 3.0 + mote.phase)
		if light > 0.05:
			draw_rect(Rect2(snap(mote.ground), Vector2(0.5, 0.5)), Color(dust_tint, minf(0.85, light * 1.1)))
	draw_gnats(1.0 - smoothstep(0.85, 1.65, phase))
	for mote in fluff:
		var lit := (1.0 - Wind.canopy_cover(mote.ground / SIZE) * 0.55) * (1.0 - twi * 0.35)
		var at := snap(mote.ground - Vector2(0.0, mote.height))
		var fluff_col := Color(1.0, 0.98, 0.90).lerp(Color(1.0, 0.88, 0.72), dusk * 0.55).lerp(Color(0.76, 0.85, 0.96), twi * 0.65)
		draw_rect(Rect2(at, Vector2(0.5, 0.5)), Color(fluff_col, 0.95 * lit))
		for side in [Vector2(0.5, 0.0), Vector2(-0.5, 0.0), Vector2(0.0, 0.5), Vector2(0.0, -0.5)]:
			draw_rect(Rect2(at + side, Vector2(0.5, 0.5)), Color(fluff_col, 0.30 * lit))
	var glow_activity := firefly_activity()
	if glow_activity > 0.02:
		draw_fireflies(glow_activity)
	if leaf != null:
		draw_falling_leaf()

func draw_fireflies(activity: float) -> void:
	for i in fireflies.size():
		var f := fireflies[i]
		# Stagger emergence so early dusk only shows a few fireflies near the reeds.
		var threshold := float(i) / float(fireflies.size()) * 0.65
		var presence := smoothstep(threshold, threshold + 0.35, activity)
		if presence <= 0.02:
			continue
		var wave := sin(clock * TAU / f.period + f.phase)
		var pulse := pow(maxf(0.0, smoothstep(-0.15, 0.92, wave)), 1.65) * presence
		if pulse <= 0.04:
			continue
		var at := snap(f.pos)
		draw_rect(Rect2(at - Vector2(2.0, 2.0), Vector2(4.5, 4.5)), Color(0.45, 0.72, 0.31, pulse * 0.20))
		draw_rect(Rect2(at - Vector2(1.0, 1.0), Vector2(2.5, 2.5)), Color(0.66, 0.84, 0.35, pulse * 0.45))
		draw_rect(Rect2(at, Vector2(0.75, 0.75)), Color(0.91, 0.96, 0.55, minf(1.0, pulse * 0.95)))

func draw_gnats(visibility := 1.0) -> void:
	if visibility <= 0.02:
		return
	var center := GNATS + Vector2(sin(clock * 0.27) * 4.0, sin(clock * 0.19 + 1.0) * 2.5) + Wind.DIRECTION * breeze(GNATS) * 5.0
	for i in 7:
		var offset := Vector2(sin(clock * (4.1 + i * 0.7) + i * 1.9) * 3.2, cos(clock * (5.3 + i * 0.55) + i * 2.7) * 2.2 - 11.0)
		var glint := sin(clock * 9.0 + i * 2.3) > 0.72
		var ink := Color(1.0, 0.90, 0.62, 0.85 * visibility) if glint else Color(0.17, 0.16, 0.12, 0.7 * visibility)
		draw_rect(Rect2(snap(center + offset), Vector2(0.5, 0.5)), ink)

func draw_falling_leaf() -> void:
	var lifted := leaf.ground - Vector2(0.0, leaf.height)
	var fade := clampf(leaf_rest / 1.5, 0.0, 1.0) if leaf.height <= 0.0 else 1.0
	# A tumbling leaf shows its edge: squash the shape across the flutter.
	var squash := 0.35 + 0.65 * absf(cos(clock * 2.6 + leaf.phase))
	var shape := PackedVector2Array()
	for corner in [Vector2(-3, 0), Vector2(-1, -1.3), Vector2(1.5, -1.0), Vector2(3, 0), Vector2(1, 1.5), Vector2(-1.2, 1.2)]:
		shape.append(snap(lifted + (corner * Vector2(1.0, squash)).rotated(leaf_turn)))
	draw_colored_polygon(shape, Color(0.66, 0.60, 0.27, fade))
	draw_line(snap(lifted - Vector2(2, 0).rotated(leaf_turn)), snap(lifted + Vector2(2.5, 0).rotated(leaf_turn)), Color(0.85, 0.80, 0.42, fade), 0.5)
