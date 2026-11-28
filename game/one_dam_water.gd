extends RefCounted

signal released(piece: Piece, strength: float)
signal landed(piece: Piece, speed: float)

const STONE := 0
const EARTH := 1
const BANK := 34.0

class Piece:
	var point: Vector2
	var radius: float
	var kind: int
	var shade: int
	var wear := 0.0
	var notch := 0.0
	var support: Piece
	var visible_lift := 0.0
	var fall_speed := 0.0
	var bounce := 0.0

	func _init(at: Vector2, size: float, material: int, color_index: int) -> void:
		point = at
		radius = size
		kind = material
		shade = color_index

	func tiers() -> int:
		return 0 if support == null else support.tiers() + 1

	func rests_on(piece: Piece) -> bool:
		return support != null and (support == piece or support.rests_on(piece))

	func lift() -> float:
		return 0.0 if support == null else support.lift() + support.radius * 0.66

	func settle(dt: float) -> void:
		bounce = move_toward(bounce, 0.0, dt * 4.6)
		var target := lift()
		if visible_lift > target:
			fall_speed += 120.0 * dt
			visible_lift = maxf(target, visible_lift - fall_speed * dt)
		else:
			visible_lift = target
			fall_speed = 0.0


class DrainPipe:
	var point: Vector2
	var host: Piece
	var rate := 0.0

	func _init(at: Vector2) -> void:
		point = at

	func position() -> Vector2:
		return host.point if host != null else point

	func reach() -> float:
		return maxf(11.0, host.radius + 5.0) if host != null else 9.0

var wall: Array[Piece] = []
var pipes: Array[DrainPipe] = []
var branch_braces: Array[Vector2] = []

func reset() -> void:
	wall.clear()
	pipes.clear()
	branch_braces.clear()

func settle(dt: float) -> void:
	for piece in wall:
		var was_falling := piece.visible_lift > piece.lift()
		piece.settle(dt)
		if was_falling and piece.visible_lift <= piece.lift():
			landed.emit(piece, piece.fall_speed)

func remove(piece: Piece, force: float) -> void:
	if not wall.has(piece):
		return
	detach(piece)
	released.emit(piece, force)

func detach(piece: Piece) -> void:
	if not wall.has(piece):
		return
	wall.erase(piece)
	for pipe in pipes.duplicate():
		if pipe.host == piece:
			# Leave the pipe loose at the break so it can be used again.
			pipe.point = piece.point + Vector2(5.0, 0.0)
			remove_pipe(pipe)
	var base := piece.support
	for top in wall:
		if top.support != piece:
			continue
		top.support = base if base != null and can_place(top, top.point, base) else null
		if top.support == null and not can_place(top, top.point, null):
			find_footing(top)
	piece.support = null

func remove_pipe(pipe: DrainPipe) -> void:
	pipes.erase(pipe)
	pipe.host = null
	pipe.rate = 0.0

func find_footing(piece: Piece) -> void:
	# Water pushes a falling stone downstream first, then toward an open seam.
	for offset in [Vector2(5, 0), Vector2(8, 0), Vector2(7, -5), Vector2(7, 5), Vector2(3, -8), Vector2(3, 8)]:
		var landing: Vector2 = piece.point + offset
		if absf(landing.y) > BANK + 4.0 or not can_place(piece, landing, null):
			continue
		piece.point = landing
		for top in wall:
			if top.rests_on(piece):
				top.point += offset
		return

func can_stack(piece: Piece, base: Piece, target: Vector2) -> bool:
	if base == piece or base.rests_on(piece) or base.tiers() >= 2:
		return false
	var center_offset := Vector2((target.x - base.point.x) * 1.05, (target.y - base.point.y) * 1.2)
	var strength := 1.18 if base.kind == STONE else 0.72
	return center_offset.length() <= base.radius * 0.66 and piece.radius <= base.radius * strength

func can_place(piece: Piece, point: Vector2, support: Piece) -> bool:
	if support != null and not can_stack(piece, support, point):
		return false
	var level := 0 if support == null else support.tiers() + 1
	for neighbor in wall:
		if neighbor == piece or neighbor.tiers() != level or neighbor.rests_on(piece):
			continue
		var factor := 0.55 if neighbor.kind == STONE and piece.kind == STONE else 0.36
		if point.distance_to(neighbor.point) < (piece.radius + neighbor.radius) * factor:
			return false
	return true

func place(piece: Piece, point: Vector2, support: Piece) -> void:
	piece.point = point
	piece.wear = 0.0
	piece.notch = 0.0
	piece.support = support
	piece.visible_lift = piece.lift()
	piece.fall_speed = 0.0
	piece.bounce = 0.78 if piece.kind == EARTH else 0.42
	wall.append(piece)

func bracing(piece: Piece) -> float:
	var amount := 0.0
	for neighbor in wall:
		if neighbor == piece or neighbor.kind != STONE:
			continue
		var separation := piece.point.distance_to(neighbor.point)
		var contact := maxf(0.0, 1.0 - separation / ((piece.radius + neighbor.radius) * 1.2))
		var behind := smoothstep(0.0, 9.0, neighbor.point.x - piece.point.x)
		var mass := clampf(neighbor.radius / piece.radius, 0.5, 1.7)
		var faces := 1.0 if neighbor.tiers() == piece.tiers() else 0.4
		amount += contact * (0.72 + 0.64 * behind * mass) * faces
	# Planted creek branches tucked behind/beside a dam piece act as real wooden stakes bracing it!
	for stake in branch_braces:
		var dist := piece.point.distance_to(stake)
		var reach := piece.radius + 14.0
		if dist < reach:
			var contact := 1.0 - dist / reach
			var downstream_support := smoothstep(-5.0, 7.0, stake.x - piece.point.x)
			amount += contact * (0.45 + 0.68 * downstream_support)
	return amount

func center(fallback: float) -> float:
	if wall.is_empty():
		return fallback
	var position := 0.0
	var width := 0.0
	for piece in wall:
		position += piece.point.x * piece.radius
		width += piece.radius
	return position / width
