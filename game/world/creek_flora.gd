extends RefCounted

# Natural creek flora driven by SeasonProfile & WorldState (e.g. quiet-eddy lily pads).
const WorldState = preload("res://game/world/world_state.gd")

const LILY_SPOTS := [
	Vector3(156.0, 88.0, 4.4),
	Vector3(167.0, 85.0, 3.3),
]

var clock := 0.0
var lily_dips := PackedFloat32Array([0.0, 0.0])

func reset() -> void:
	clock = 0.0
	lily_dips = PackedFloat32Array([0.0, 0.0])

func advance(dt: float, surge_fn: Callable) -> void:
	if dt <= 0.0:
		return
	clock += dt
	for i in LILY_SPOTS.size():
		var spot: Vector3 = LILY_SPOTS[i]
		var push: float = float(surge_fn.call(spot.x)) if surge_fn.is_valid() else 0.0
		lily_dips[i] = lerpf(lily_dips[i], push, 1.0 - exp(-dt * 5.0))

func snap(pt: Vector2) -> Vector2:
	return (pt * 2.0).round() * 0.5

func apply_tint(color: Color, at: Vector2, tint_at: Callable) -> Color:
	return tint_at.call(color, at) if tint_at.is_valid() else color

func draw(canvas: Node2D, world: WorldState, tint_at: Callable, foam_col: Color) -> void:
	if world == null or not world.profile.lily_pads_visible:
		return
	for i in LILY_SPOTS.size():
		var spot: Vector3 = LILY_SPOTS[i]
		var dip := lily_dips[i]
		var bob_x := sin(clock * 1.15 + i * 2.1) * 0.65 + dip * 2.2
		var bob_y := cos(clock * 1.45 + i * 1.7) * 0.35
		var c := snap(Vector2(spot.x + bob_x, spot.y + bob_y))
		var rx := spot.z
		var ry := rx * 0.56
		var shadow_pts := PackedVector2Array()
		var pad_pts := PackedVector2Array()
		var hi_pts := PackedVector2Array()
		var notch_angle := 0.35 if i == 0 else -2.65
		for s in 13:
			var a := notch_angle + 0.28 + float(s) / 12.0 * (TAU - 0.56)
			var edge := Vector2(cos(a) * rx, sin(a) * ry)
			shadow_pts.append(snap(c + edge + Vector2(0.5, 1.0)))
			pad_pts.append(snap(c + edge))
		pad_pts.append(snap(c))
		shadow_pts.append(snap(c + Vector2(0.5, 1.0)))
		for s in 7:
			var a := PI * 0.95 + float(s) / 6.0 * (PI * 0.85)
			hi_pts.append(snap(c + Vector2(cos(a) * rx * 0.68, sin(a) * ry * 0.62 - 0.25)))
		hi_pts.append(snap(c + Vector2(-0.3, -0.2)))
		var outline := apply_tint(Color("#1f3529"), c, tint_at)
		var base_green := apply_tint(world.profile.lily_pad_base, c, tint_at)
		var lit_green := apply_tint(world.profile.lily_pad_lit, c, tint_at)
		canvas.draw_colored_polygon(shadow_pts, Color("#122b295c"))
		canvas.draw_colored_polygon(pad_pts, base_green)
		canvas.draw_colored_polygon(hi_pts, lit_green)
		canvas.draw_polyline(pad_pts, outline, 0.55)
		if dip > 0.15:
			canvas.draw_line(snap(c + Vector2(-rx, 0.5)), snap(c + Vector2(rx * 0.8, 0.5)), Color(foam_col, dip * 0.45), 0.5)
