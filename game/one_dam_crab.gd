extends RefCounted

signal landed(point: Vector2)

const AREA := Rect2(10, 10, 300, 180)
const HOME := Vector2(204, 112)
const ROCK_PADDING := 2.0
const CLIMB_LIMIT := 4.5

class Bubble:
	var at: Vector2
	var age := 0.0
	var life := 0.7
	var drift := 0.0

var rng := RandomNumberGenerator.new()
var position := HOME
var target := HOME
var facing := Vector2(0.0, -1.0)
var speed := 0.0
var stride := 0.0
var rest := 4.5
var alert := 0.0
var snip := 0.0
var held := false
var wet := true
var clock := 0.0
var ripple_delay := 0.0
var bubble_due := 2.2
var retreat_cooldown := 0.0
var avoid_side := 0.0
var best_dist := INF
var stall_time := 0.0
var last_target := Vector2.INF
var elevation := 0.0
var return_attempt := 0
var bubbles: Array[Bubble] = []

func reset() -> void:
	position = HOME
	target = HOME
	facing = Vector2(0.0, -1.0)
	speed = 0.0
	stride = 0.0
	rest = 4.5
	alert = 0.0
	snip = 0.0
	held = false
	wet = true
	clock = 0.0
	ripple_delay = 0.0
	bubble_due = 2.2
	retreat_cooldown = 0.0
	avoid_side = 0.0
	best_dist = INF
	stall_time = 0.0
	last_target = Vector2.INF
	elevation = 0.0
	return_attempt = 0
	bubbles.clear()

func place(at: Vector2, is_wet: bool) -> void:
	position = at
	target = at
	wet = is_wet
	speed = 0.0
	# If placed on dry bank, quickly orient and head back into the water; if in water, settle calmly.
	rest = 0.35 if not is_wet else rng.randf_range(3.5, 6.5)
	alert = 0.65
	avoid_side = 0.0
	best_dist = INF
	stall_time = 0.0
	last_target = Vector2.INF
	elevation = 0.0
	return_attempt = 0
	held = false
	landed.emit(at)

func blocking_rock(rocks: Array, start: Vector2, end: Vector2):
	for rock in rocks:
		if rock.height > CLIMB_LIMIT and rock.hit(start, end, ROCK_PADDING):
			return rock
	return null

func climb_height(rocks: Array, point: Vector2) -> float:
	var height := 0.0
	for rock in rocks:
		if rock.height <= CLIMB_LIMIT:
			var dist := ((point - (rock.center as Vector2)) / ((rock.radius as Vector2) + Vector2.ONE * 0.8)).length()
			height = maxf(height, float(rock.height) * (1.0 - smoothstep(0.24, 1.0, dist)))
	return height

func step_clear(rocks: Array, clear_animals: Callable, start: Vector2, next: Vector2) -> bool:
	if not AREA.has_point(next):
		return false
	if blocking_rock(rocks, start, next) != null:
		return false
	return clear_animals.call(next)

func advance(dt: float, pointer: Vector2, pointer_busy: bool, rocks: Array, project: Callable,
		unproject: Callable, in_water: Callable, water, surge_fn: Callable,
		clear_animals: Callable, ripple: Callable, nearby_critters: Array, day_phase := 0.0) -> void:
	if dt <= 0.0:
		return
	clock += dt
	retreat_cooldown = maxf(0.0, retreat_cooldown - dt)
	advance_bubbles(dt)
	if held:
		speed = 0.0
		alert = 1.0
		stride += dt * 42.0
		snip = 0.5 + 0.5 * sin(clock * 19.0)
		return

	var bed_pos: Vector2 = unproject.call(position)
	var was_wet := wet
	wet = in_water.call(bed_pos)
	# Once a stranded crab re-enters the creek, settle down calmly near the shallows instead of overshooting onto the far bank.
	if not was_wet and wet and position.distance_to(target) > 6.0:
		var settle := (position + (target - position).normalized() * 5.0).clamp(AREA.position, AREA.end)
		if in_water.call(unproject.call(settle)) and step_clear(rocks, clear_animals, position, settle):
			target = settle
		else:
			target = position
		rest = rng.randf_range(5.0, 10.0)

	var threat := Vector2.INF
	var threat_dist := INF
	if not pointer_busy and pointer.x > 0.0 and pointer.y > 0.0:
		var pd := position.distance_to(pointer)
		if pd < 19.0:
			threat = pointer
			threat_dist = pd
	for critter: Vector2 in nearby_critters:
		var cd := position.distance_to(critter)
		if cd < 15.0 and cd < threat_dist:
			threat = critter
			threat_dist = cd

	if threat.is_finite():
		alert = move_toward(alert, 1.0, dt * 6.5)
		var look_dir := (threat - position).normalized()
		if look_dir.length_squared() > 0.01:
			var a := lerp_angle(facing.angle(), look_dir.angle(), 1.0 - exp(-dt * 12.0))
			facing = Vector2.from_angle(a)
		snip = (0.5 + 0.5 * sin(clock * 13.0)) * alert
		if wet and threat == pointer and threat_dist < 10.5 and retreat_cooldown <= 0.0:
			var away := (position - pointer).normalized()
			if away.length_squared() < 0.01:
				away = Vector2.RIGHT
			var side_dir := away.orthogonal() * (1.0 if rng.randf() < 0.5 else -1.0)
			for cand_dir: Vector2 in [(side_dir * 0.8 + away * 0.6).normalized(), (-side_dir * 0.8 + away * 0.6).normalized(), away]:
				var retreat_to := (position + cand_dir * rng.randf_range(8.0, 13.0)).clamp(AREA.position, AREA.end)
				if in_water.call(unproject.call(retreat_to)) and step_clear(rocks, clear_animals, position, retreat_to):
					target = retreat_to
					rest = rng.randf_range(4.5, 9.0)
					retreat_cooldown = 1.1
					break
	else:
		alert = move_toward(alert, 0.0, dt * 1.9)
		snip = move_toward(snip, 0.0, dt * 4.5)

	# Heavy flood surge briefly nudges a submerged crab while its legs brace against the gravel.
	if wet and water != null:
		var flow: Vector2 = water.velocity_at(bed_pos)
		var surge: float = surge_fn.call(bed_pos.x)
		if surge > 0.35 and flow.length() > 26.0:
			alert = maxf(alert, 0.72)
			var push := flow.limit_length(30.0) * (0.09 + surge * 0.14) * dt
			var drifted := (position + Vector2(push.x, push.y * 0.4)).clamp(AREA.position, AREA.end)
			if in_water.call(unproject.call(drifted)) and step_clear(rocks, clear_animals, position, drifted):
				position = drifted
				stride += push.length() * 1.6

	if not target.is_equal_approx(last_target):
		last_target = target
		best_dist = position.distance_to(target)
		stall_time = 0.0
		avoid_side = 0.0

	var to_target := target - position
	if to_target.length() > 0.7:
		# Weighted, stepped crab gait underwater (slower & planted) vs brisk return-to-water crawl on dry bank.
		var base_pace := 21.0 if not wet else (13.5 if alert > 0.45 else 8.8)
		var pulse := 0.58 + 0.42 * pow(0.5 + 0.5 * sin(stride * 1.65), 1.3) if wet else (0.78 + 0.22 * sin(stride * 2.1))
		var pace := base_pace * pulse
		var distance := minf(speed + dt * (85.0 if not wet else 52.0), pace) * dt
		var next := position.move_toward(target, distance)
		# When already in water, avoid stepping out onto the dry bank while dodging obstacles.
		var stay_wet := wet
		var next_ok: bool = step_clear(rocks, clear_animals, position, next) and (not stay_wet or bool(in_water.call(unproject.call(next))))
		if not next_ok:
			var rock = blocking_rock(rocks, position, next)
			var offset: Vector2 = (position - (rock.center as Vector2)) if rock != null else -to_target
			var outward: Vector2 = (offset / ((rock.radius as Vector2) * (rock.radius as Vector2))).normalized() if (rock != null and offset.length_squared() > 0.001) else (offset.normalized() if offset.length_squared() > 0.001 else Vector2.UP)
			var tangent: Vector2 = outward.orthogonal()
			if avoid_side == 0.0:
				avoid_side = 1.0 if to_target.dot(tangent) >= 0.0 else -1.0
			var side := avoid_side
			var found := false
			for cand in [
				[(tangent * side + outward * 0.48).normalized(), false],
				[(tangent * side + outward * 0.95).normalized(), false],
				[outward, false],
				[(outward * 0.48 - tangent * side).normalized(), true],
				[(outward * 0.95 - tangent * side).normalized(), true],
			]:
				var try_next: Vector2 = position + cand[0] * distance
				if step_clear(rocks, clear_animals, position, try_next) and (not stay_wet or in_water.call(unproject.call(try_next))):
					next = try_next
					if cand[1]:
						avoid_side = -side
					found = true
					break
			if not found:
				next = position
		var step := next - position
		position = next
		elevation = move_toward(elevation, climb_height(rocks, next), dt * 32.0)
		speed = step.length() / dt
		var dist_now := position.distance_to(target)
		if dist_now < best_dist - 0.6:
			best_dist = dist_now
			stall_time = 0.0
		elif dist_now > 1.2:
			stall_time += dt
		if step.length() > 0.03:
			stride += step.length() * (1.35 if wet else 1.1)
			# Crabs walk sideways: keep body facing perpendicular to travel when calm.
			if alert < 0.35:
				var perp := step.normalized().orthogonal()
				if perp.dot(facing) < 0.0:
					perp = -perp
				var a := lerp_angle(facing.angle(), perp.angle(), 1.0 - exp(-dt * 5.5))
				facing = Vector2.from_angle(a)
		if stall_time >= 1.1:
			target = position
			speed = 0.0
			stall_time = 0.0
			if not wet:
				return_attempt += 1
				rest = 0.12
			else:
				rest = rng.randf_range(3.0, 6.0)
	else:
		speed = 0.0
		target = position
		elevation = move_toward(elevation, climb_height(rocks, position), dt * 32.0)

	ripple_delay -= dt
	if wet and speed > 3.5 and ripple_delay <= 0.0:
		ripple.call(bed_pos)
		ripple_delay = 0.42

	var twilight := smoothstep(1.15, 1.85, day_phase)
	# Blow tiny bubbles while resting quietly in the water.
	bubble_due -= dt
	if wet and speed < 1.0 and bubble_due <= 0.0:
		spawn_bubble()
		bubble_due = rng.randf_range(lerpf(2.8, 4.5, twilight), lerpf(6.0, 9.5, twilight))

	# On dry bank: actively crawl back into the water. In water: stay still most of the time, only making occasional tiny shifts.
	if not wet:
		if speed == 0.0:
			rest -= dt
			if rest <= 0.0:
				target = find_water_target(rocks, clear_animals, project, unproject, in_water)
				rest = 0.25
	elif speed == 0.0 and alert < 0.35:
		return_attempt = 0
		rest -= dt
		if rest <= 0.0:
			target = pick_water_shift(rocks, clear_animals, unproject, in_water)
			rest = rng.randf_range(lerpf(6.0, 14.0, twilight), lerpf(12.5, 28.0, twilight))

func spawn_bubble() -> void:
	var b := Bubble.new()
	b.at = position + facing * 2.0 + Vector2(rng.randf_range(-1.0, 1.0), -0.5)
	b.life = rng.randf_range(0.55, 0.95)
	b.drift = rng.randf_range(-1.5, 1.5)
	bubbles.append(b)

func advance_bubbles(dt: float) -> void:
	for i in range(bubbles.size() - 1, -1, -1):
		var b := bubbles[i]
		b.age += dt
		if b.age >= b.life:
			bubbles.remove_at(i)
		else:
			b.at += Vector2(b.drift, -4.2) * dt

func find_water_target(rocks: Array, clear_animals: Callable, project: Callable, unproject: Callable, in_water: Callable) -> Vector2:
	var bed_pos: Vector2 = unproject.call(position)
	var preferred_side := clampf(signf(bed_pos.y) * 14.0, -14.0, 14.0)
	var offsets := [0.0, -16.0, 16.0, -32.0, 32.0, -52.0, 52.0]
	var shift := return_attempt % offsets.size()
	var best := position
	var best_d := INF
	for idx in offsets.size():
		var dx: float = offsets[(idx + shift) % offsets.size()]
		var x := clampf(bed_pos.x + dx, 36.0, 284.0)
		for y_lane: float in [preferred_side, 0.0, -preferred_side, 18.0, -18.0]:
			var candidate: Vector2 = project.call(Vector2(x, y_lane)).clamp(AREA.position, AREA.end)
			if in_water.call(unproject.call(candidate)) and step_clear(rocks, clear_animals, candidate, candidate):
				if return_attempt > 0 and idx == 0:
					return candidate
				var d := position.distance_to(candidate)
				if d < best_d:
					best_d = d
					best = candidate
	return best

func pick_water_shift(rocks: Array, clear_animals: Callable, unproject: Callable, in_water: Callable) -> Vector2:
	# Small, grounded sideways nudge inside the creek so the crab feels alive without wandering around.
	for attempt in 8:
		var offset := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(5.5, 11.5)
		var candidate := (position + offset).clamp(AREA.position, AREA.end)
		if in_water.call(unproject.call(candidate)) and step_clear(rocks, clear_animals, position, candidate):
			return candidate
	return position

func snap(point: Vector2) -> Vector2:
	return (point * 2.0).round() * 0.5

func apply_tint(color: Color, at: Vector2, tint_at: Callable) -> Color:
	var tinted: Color = tint_at.call(color, at) if tint_at.is_valid() else color
	if wet and not held:
		var submerged := tinted.lerp(tinted * Color("#528582"), 0.52)
		return Color(submerged.r, submerged.g, submerged.b, tinted.a * 0.88)
	return tinted

func draw(canvas: Node2D, pointer: Vector2, tint_at: Callable = Callable()) -> void:
	var step_bob := Vector2(0.0, 0.5) if (not held and speed > 0.5 and sin(stride * 1.65) > 0.2) else Vector2.ZERO
	var p := snap((pointer - Vector2(0, 5.0) if held else position - Vector2(0.0, elevation)) + step_bob)
	var fwd := facing.normalized() if facing.length_squared() > 0.01 else Vector2(0.0, -1.0)
	var side := fwd.orthogonal()
	var leg_dark := apply_tint(Color("#4c2d20"), p, tint_at)
	var leg_mid := apply_tint(Color("#7a4630"), p, tint_at)
	var shell_rim := apply_tint(Color("#3a221a"), p, tint_at)
	var shell_body := apply_tint(Color("#8f4f36"), p, tint_at)
	var shell_lit := apply_tint(Color("#ba6e4b"), p, tint_at)
	var claw_body := apply_tint(Color("#c07344"), p, tint_at)
	var claw_tip := apply_tint(Color("#e2ae78"), p, tint_at)

	if not held:
		# Tight, grounded contact shadow directly under the shell & legs so it sits firmly on the creek gravel.
		var shadow_col := Color("#0c262796") if wet else Color("#24201978")
		var sh_offset := Vector2(0.0, 0.8) if wet else Vector2(0.0, 1.2)
		var sh := PackedVector2Array([
			snap(p - side * 4.4 + sh_offset),
			snap(p + fwd * 2.0 - side * 2.7 + sh_offset),
			snap(p + fwd * 2.0 + side * 2.7 + sh_offset),
			snap(p + side * 4.4 + sh_offset),
			snap(p - fwd * 2.2 + side * 2.3 + sh_offset),
			snap(p - fwd * 2.2 - side * 2.3 + sh_offset),
		])
		canvas.draw_colored_polygon(sh, shadow_col)

	# 4 pairs of grounded sideways-scuttling jointed legs.
	for lr: float in [-1.0, 1.0]:
		for i in 4:
			var back := lerpf(0.7, -2.0, float(i) / 3.0)
			var wave := sin(stride * 2.4 + float(i) * 1.55 + lr * 1.2) * (0.95 if (speed > 0.5 or held) else 0.0)
			var hip := p + side * lr * 2.2 + fwd * back
			var knee := hip + side * lr * 2.0 + fwd * (0.35 + wave * 0.65) + Vector2(0, -0.6 if held else -0.2)
			var foot := knee + side * lr * 1.45 + fwd * (-0.45 + wave * 0.35) + Vector2(0, 0.95)
			canvas.draw_line(snap(hip), snap(knee), leg_dark, 1.0)
			canvas.draw_line(snap(knee), snap(foot), leg_mid, 0.75)

	# Articulated pincers raised defensively when alert or held.
	var raise := alert * 1.5 + (0.8 if held else 0.0)
	for lr: float in [-1.0, 1.0]:
		var shoulder := p + side * lr * 2.2 + fwd * 1.3
		var elbow := shoulder + side * lr * (1.7 + alert * 0.5) + fwd * (1.4 + raise * 0.35) - Vector2(0, raise * 0.5)
		var pincer := elbow + fwd * (1.5 + raise * 0.3) - side * lr * (0.5 - alert * 0.25) - Vector2(0, raise * 0.35)
		canvas.draw_line(snap(shoulder), snap(elbow), leg_dark, 1.25)
		canvas.draw_line(snap(shoulder), snap(elbow), claw_body, 0.75)
		var open_gap := 0.35 + snip * 0.95
		var outer_tip := pincer + fwd * 1.5 + side * lr * (0.45 + open_gap * 0.45)
		var inner_tip := pincer + fwd * 1.3 - side * lr * (0.35 + open_gap * 0.35)
		canvas.draw_line(snap(elbow), snap(pincer), claw_body, 1.6)
		canvas.draw_line(snap(pincer), snap(outer_tip), claw_tip, 0.9)
		canvas.draw_line(snap(pincer), snap(inner_tip), claw_body, 0.75)

	# Rounded hexagonal mountain-crab carapace.
	var rim := PackedVector2Array([
		snap(p + fwd * 2.2 - side * 1.8), snap(p + fwd * 2.2 + side * 1.8),
		snap(p + fwd * 0.4 + side * 3.3), snap(p - fwd * 1.7 + side * 2.4),
		snap(p - fwd * 2.3), snap(p - fwd * 1.7 - side * 2.4),
		snap(p + fwd * 0.4 - side * 3.3),
	])
	canvas.draw_colored_polygon(rim, shell_rim)
	var body_poly := PackedVector2Array([
		snap(p + fwd * 1.8 - side * 1.4), snap(p + fwd * 1.8 + side * 1.4),
		snap(p + fwd * 0.3 + side * 2.8), snap(p - fwd * 1.3 + side * 2.0),
		snap(p - fwd * 1.8), snap(p - fwd * 1.3 - side * 2.0),
		snap(p + fwd * 0.3 - side * 2.8),
	])
	canvas.draw_colored_polygon(body_poly, shell_body)
	var cap := PackedVector2Array([
		snap(p + fwd * 1.4 - side * 1.1), snap(p + fwd * 1.4 + side * 1.1),
		snap(p + fwd * 0.1 + side * 1.9), snap(p - fwd * 0.9 + side * 1.0),
		snap(p - fwd * 0.9 - side * 1.0), snap(p + fwd * 0.1 - side * 1.9),
	])
	canvas.draw_colored_polygon(cap, shell_lit)
	canvas.draw_rect(Rect2(snap(p + fwd * 0.4 - side * 0.8), Vector2(0.5, 0.5)), claw_tip)
	canvas.draw_rect(Rect2(snap(p + fwd * 0.1 + side * 0.9), Vector2(0.5, 0.5)), claw_tip)

	# Stalked glossy eyes.
	for lr: float in [-1.0, 1.0]:
		var eye := snap(p + fwd * 2.3 + side * lr * 1.25 - Vector2(0, 0.5))
		canvas.draw_rect(Rect2(eye - Vector2(0.5, 0.5), Vector2(1.0, 1.0)), Color("#1d1f1b", 0.9 if wet and not held else 1.0))
		canvas.draw_rect(Rect2(eye - Vector2(0.5, 0.5), Vector2(0.5, 0.5)), Color("#e2e8dc", 0.78 if wet and not held else 1.0))

	# Rising bubbles when resting in water.
	for b in bubbles:
		var fade := (1.0 - smoothstep(0.55, 1.0, b.age / b.life)) * 0.72
		canvas.draw_rect(Rect2(snap(b.at), Vector2(1.0, 1.0)), Color("#e0f0e6", fade))
