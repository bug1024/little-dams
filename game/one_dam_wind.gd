extends RefCounted

## A summer breeze. Gusts arrive irregularly and sweep across the creek from the left,
## so anything sampled further right responds a little later.
const DIRECTION := Vector2(0.94, 0.34)
const CROSSING := 2.2
const SAMPLE := 0.05
const CALM := 0.16

var clock := 0.0
var gust := 0.0
var target := 0.0
var release := 0.0
var next_gust := 3.5
var history := PackedFloat32Array()
var head := 0
var sample_lag := 0.0
var rng := RandomNumberGenerator.new()
var flutter_offset := rng.randf_range(0.0, 64.0)
var travel := Vector4.ZERO
var sunlight := Vector3(0.0, 0.0, 0.48)
var sun_from := sunlight
var sun_to := Vector3(0.036, -0.021, 0.90)
var sun_age := 0.0
var sun_duration := 33.0
var gust_scale := 1.0
var gust_interval := Vector2(4.5, 12.0)

func set_season_tuning(p_scale: float, p_interval: Vector2) -> void:
	gust_scale = clampf(p_scale, 0.5, 1.8)
	gust_interval = p_interval
	if next_gust > clock + gust_interval.y:
		next_gust = clock + rng.randf_range(gust_interval.x, gust_interval.y)

func _init() -> void:
	history.resize(ceili(CROSSING / SAMPLE) + 2)
	history.fill(CALM)

func advance(dt: float) -> void:
	clock += dt
	if clock >= next_gust:
		target = clampf(rng.randf_range(0.55, 1.0) * gust_scale, 0.35, 1.25)
		release = clock + rng.randf_range(1.6, 4.2) * clampf(gust_scale, 0.85, 1.30)
		next_gust = release + rng.randf_range(gust_interval.x, gust_interval.y)
	elif clock >= release:
		target = 0.0
	gust = move_toward(gust, target, dt * (0.9 if target > gust else 0.32))
	sample_lag += dt
	while sample_lag >= SAMPLE:
		sample_lag -= SAMPLE
		head = (head + 1) % history.size()
		history[head] = current()
	travel += (Vector4.ONE * 0.65 + trail() * 9.0) * dt
	sun_age += dt
	if sun_age >= sun_duration:
		sun_age -= sun_duration
		sun_from = sun_to
		sun_to = Vector3(rng.randf_range(-0.048, 0.046), rng.randf_range(-0.028, 0.030), rng.randf_range(0.22, 0.93))
		sun_duration = rng.randf_range(24.0, 46.0)
	sunlight = sun_from.lerp(sun_to, smoothstep(0.0, 1.0, sun_age / sun_duration))

func current() -> float:
	var breath := CALM + sin(clock * 0.41) * sin(clock * 0.17) * 0.07
	var eased := gust * gust * (3.0 - 2.0 * gust)
	return clampf(breath + eased * (1.0 - CALM), 0.0, 1.0)

## Strength at a horizontal position from 0 (left edge) to 1 (right edge).
func strength_at(x: float) -> float:
	var delay := clampf(x, 0.0, 1.0) * CROSSING / SAMPLE
	var back := floori(delay)
	var size := history.size()
	return lerpf(history[posmod(head - back, size)], history[posmod(head - back - 1, size)], delay - back)

func trail() -> Vector4:
	return Vector4(strength_at(0.0), strength_at(1.0 / 3.0), strength_at(2.0 / 3.0), strength_at(1.0))

func flutter(pattern: int) -> float:
	var rate := 0.80 + fposmod(pattern * 0.381, 1.0) * 1.15
	var phase := clock * rate + float(pattern) * 2.71 + flutter_offset
	var interval := floorf(phase)
	var weight := smoothstep(0.17, 0.87, phase - interval)
	return lerpf(flutter_sample(interval, pattern), flutter_sample(interval + 1.0, pattern), weight)

func flutter_sample(interval: float, pattern: int) -> float:
	var value := fposmod(sin(interval * 12.9898 + pattern * 78.233) * 43758.5453, 1.0) * 2.0 - 1.0
	return signf(value) * smoothstep(0.37, 0.96, absf(value))

func canopy_flutter() -> Vector4:
	return Vector4(flutter(0), flutter(1), flutter(2), flutter(3))

# Matches the fixed canopy used for creek highlights.
static func canopy_cover(p: Vector2) -> float:
	var upper := 1.0 - smoothstep(0.55, 1.0, ((p - Vector2(0.06, -0.10)) / Vector2(0.50, 0.44)).length())
	var corner := 1.0 - smoothstep(0.55, 1.0, ((p - Vector2(1.02, 1.10)) / Vector2(0.30, 0.30)).length())
	return maxf(upper, corner * 0.85)

static func sun_shafts(p: Vector2, time: float, breeze: float) -> float:
	var u := p.x * 1.36 + p.y
	var beams := sin(u * 23.0 + 1.3) * 0.5 + sin(u * 41.0 + 0.4 + sin(time * 0.6) * 0.5) * 0.3 + sin(u * 67.0 + time * 0.5) * 0.2
	var region := 1.0 - smoothstep(0.3, 1.0, ((p - Vector2(0.30, 0.30)) / Vector2(0.55, 0.62)).length())
	return smoothstep(0.35, 0.9, beams) * region * (0.75 + 0.25 * sin(time * 1.9 + u * 11.0) * breeze)
