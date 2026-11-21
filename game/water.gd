extends RefCounted

signal washed_out(site: int, piece: Piece, force: float)

const EMPTY := 0
const STONE := 1
const MUD := 2
const LANES := 21
const SITES := 3
const SUPPLY := 5.6
const STEP := 1.0 / 30.0
const FLOW_HALF_WIDTH := 43.0
const SITE_CENTERS := [311.0, 651.0, 992.0]
const SITE_EDGES := [480.0, 823.0]
const LIFT_LIMIT := 17.5
const STACK_PIXELS := 9.0
const STACK_LIMIT := 2
# Surveyed across the illustrated water channel at 40-pixel intervals.
const CHANNEL_Y := [318, 321, 334, 354, 368, 398, 418, 426, 428, 422, 404, 398, 381, 374, 363, 345, 338, 345, 356, 364, 384, 400, 414, 414, 406, 393, 369, 351, 339, 316, 306, 303]
const CHANNEL_HALF_WIDTH := [30, 33, 44, 48, 50, 40, 38, 36, 34, 28, 32, 40, 36, 28, 27, 30, 32, 36, 40, 38, 42, 40, 39, 30, 34, 36, 42, 39, 27, 32, 33, 33]

class Piece extends RefCounted:
	var position: Vector2
	var material: int
	var radius: float
	var shape_seed: int
	var wear := 0.0
	var loose := false
	var support: Piece

	func _init(at: Vector2, kind: int, size: float, seed: int, on_bank := false) -> void:
		position = at
		material = kind
		radius = size
		shape_seed = seed
		loose = on_bank

	func can_lift() -> bool:
		return material == MUD or radius < LIFT_LIMIT

	func half_height() -> float:
		return radius * (0.65 + 0.17 * sin(shape_seed * 1.71))

	func tier() -> int:
		return support.tier() + 1 if support != null else 0

	func top() -> Vector2:
		return position - Vector2(0, tier() * STACK_PIXELS)

	func crest() -> float:
		var height := 0.65 + radius * (0.010 if material == MUD else 0.016)
		return support.crest() + height * 0.34 if support != null else height

	func rests_on(other: Piece) -> bool:
		return support != null and (support == other or support.rests_on(other))

class Dam:
	var pieces: Array[Piece] = []
	var jets := PackedFloat32Array()
	var jet_mouths := PackedFloat32Array()
	var overflow := PackedFloat32Array()
	var head := 0.0
	var inflow := 0.0
	var outflow := 0.0
	var silt := 0.0
	var mouth := 0.0

	func _init(x: float) -> void:
		mouth = x
		jets.resize(LANES)
		jet_mouths.resize(LANES)
		overflow.resize(LANES)

class Reach:
	var flows := PackedFloat32Array()
	var mud := PackedFloat32Array()
	var cursor := 0

	func _init(steps: int) -> void:
		flows.resize(steps)
		flows.fill(SUPPLY)
		mud.resize(steps)

	func push(flow: float, silt: float) -> Vector2:
		var arrival := Vector2(flows[cursor], mud[cursor])
		flows[cursor] = flow
		mud[cursor] = silt
		cursor = (cursor + 1) % flows.size()
		return arrival

	func sample(along: float) -> Vector2:
		var offset := roundi((1.0 - clampf(along, 0.0, 1.0)) * (flows.size() - 1))
		var index := (cursor + offset) % flows.size()
		return Vector2(flows[index], mud[index])

var dams: Array[Dam] = []
var reaches: Array[Reach] = []
var bank_stones: Array[Piece] = []

static func center(x: float) -> float:
	return channel_value(CHANNEL_Y, x)

static func channel_half_width(x: float) -> float:
	return channel_value(CHANNEL_HALF_WIDTH, x)

static func channel_value(samples: Array, x: float) -> float:
	var column := clampf((x - 16.0) / 40.0, 0.0, samples.size() - 1.0)
	var start := mini(floori(column), samples.size() - 2)
	return lerpf(samples[start], samples[start + 1], column - start)

static func at(x: float, lane: float) -> Vector2:
	return Vector2(x, center(x) + lane)

static func site_at(x: float) -> int:
	if x < SITE_EDGES[0]:
		return 0
	if x < SITE_EDGES[1]:
		return 1
	return 2

static func lane_at(position: Vector2) -> float:
	return position.y - center(position.x)

static func flow_offset(position: Vector2) -> float:
	return lane_at(position) * FLOW_HALF_WIDTH / channel_half_width(position.x)

static func visual_offset(x: float, offset: float) -> float:
	return offset * channel_half_width(x) / FLOW_HALF_WIDTH

static func jet_lane(offset: float) -> int:
	return clampi(roundi((offset / FLOW_HALF_WIDTH + 1.0) * 0.5 * (LANES - 1)), 0, LANES - 1)

func reset(challenge: bool) -> void:
	dams.clear()
	reaches.clear()
	bank_stones.clear()
	for site in SITES:
		dams.append(Dam.new(SITE_CENTERS[site]))
		reaches.append(Reach.new([58, 66, 42][site]))
		dams[site].head = [0.79, 0.56, 0.42][site]
		dams[site].inflow = SUPPLY
		dams[site].outflow = SUPPLY

	add_starter(0, [
		[-12, -37, STONE, 14], [-4, -23, STONE, 16], [-13, -7, STONE, 15],
		[1, 8, STONE, 12], [-10, 24, STONE, 16], [1, 39, STONE, 13],
		[5, -34, MUD, 12], [9, -18, MUD, 13], [5, -3, MUD, 10],
		[10, 16, MUD, 12], [8, 31, MUD, 13],
	])
	if challenge:
		dams[1].head = 0.19
		dams[2].head = 0.19
	else:
		add_starter(1, [
			[-4, -37, STONE, 15], [7, -27, MUD, 11], [-5, -13, MUD, 13],
			[4, 0, MUD, 14], [-6, 14, MUD, 12], [10, 27, MUD, 12], [1, 39, STONE, 11],
		])
		dams[1].pieces[3].wear = 0.31
		add_starter(2, [
			[-10, -37, STONE, 16], [-4, -22, STONE, 12], [8, -27, MUD, 13],
			[-9, 9, STONE, 12], [-6, 22, STONE, 14], [2, 39, STONE, 16],
			[9, 12, MUD, 11], [9, 28, MUD, 13],
		])

	var rng := RandomNumberGenerator.new()
	rng.seed = 3621
	for i in 28:
		var x := 53.0 + i * 43.1 + rng.randf_range(-7.0, 7.0)
		var bank := rng.randf_range(51.0, 85.0) * (-1.0 if i % 2 == 0 else 1.0)
		var size := rng.randf_range(7.0, 16.8)
		if i % 4 == 1 or i % 7 == 0:
			size = rng.randf_range(19.5, 27.0)
		bank_stones.append(Piece.new(at(x, bank), STONE, size, rng.randi_range(100, 2000), true))

func add_starter(site: int, layout: Array) -> void:
	for i in layout.size():
		var row: Array = layout[i]
		var x: float = SITE_CENTERS[site] + row[0]
		var point := at(x, visual_offset(x, row[1]))
		dams[site].pieces.append(Piece.new(point, row[2], row[3], 28 + i + site * 17))

func nearest(point: Vector2) -> Piece:
	var best := 1.25
	var result: Piece
	for dam in dams:
		for piece in dam.pieces:
			var hit := hit_distance(piece, point)
			if hit < best and (result == null or not result.rests_on(piece)):
				result = piece
				best = hit
	for piece in bank_stones:
		var hit := hit_distance(piece, point)
		if hit < best:
			result = piece
			best = hit
	return result

func hit_distance(piece: Piece, point: Vector2) -> float:
	var diff := point - piece.top()
	return Vector2(diff.x / piece.radius, diff.y / piece.half_height()).length()

func is_stream_edge(point: Vector2) -> bool:
	return point.x >= 43.0 and point.x <= 1237.0 and absf(lane_at(point)) <= channel_half_width(point.x) + 8.0

func stack_support(piece: Piece, point: Vector2) -> Piece:
	if not is_stream_edge(point):
		return null
	var selected: Piece
	for other in dams[site_at(point.x)].pieces:
		if other == piece or other.rests_on(piece) or other.tier() >= STACK_LIMIT:
			continue
		if hit_distance(other, point) < 0.69 and (selected == null or other.tier() > selected.tier()):
			selected = other
	return selected

func can_place(piece: Piece, point: Vector2, support: Piece = null) -> bool:
	if not is_stream_edge(point):
		return false
	var ground := point + Vector2(0, support.tier() * STACK_PIXELS) if support != null else point
	var tier := support.tier() + 1 if support != null else 0
	for dam in dams:
		for other in dam.pieces:
			if piece == other or other.tier() != tier:
				continue
			var diff := other.position - ground
			var gap := Vector2(diff.x / (piece.radius + other.radius), diff.y / (piece.half_height() + other.half_height()))
			var minimum := 0.56 if piece.material == STONE and other.material == STONE else 0.28
			if gap.length() < minimum:
				return false
	for rock in bank_stones:
		if rock == piece:
			continue
		var diff := rock.position - ground
		if Vector2(diff.x, diff.y * 1.35).length() < (piece.radius + rock.radius) * 0.54:
			return false
	return true

func place(piece: Piece, point: Vector2, support: Piece = null) -> void:
	detach(piece)
	piece.position = point + Vector2(0, support.tier() * STACK_PIXELS) if support != null else point
	piece.loose = false
	piece.wear = 0.0
	piece.support = support
	dams[site_at(piece.position.x)].pieces.append(piece)

func detach(piece: Piece) -> void:
	if piece.loose:
		bank_stones.erase(piece)
		return
	var dam := dams[site_at(piece.position.x)]
	if not dam.pieces.has(piece):
		return
	dam.pieces.erase(piece)
	for other in dam.pieces:
		if other.support == piece:
			other.support = piece.support
	piece.support = null

func gate_pieces() -> Array[Piece]:
	var pieces: Array[Piece] = []
	var dam := dams[0]
	for piece in dam.pieces:
		if piece.can_lift() and absf(flow_offset(piece.position)) < 21.0 and absf(piece.position.x - dam.mouth) < 52.0:
			pieces.append(piece)
	return pieces

func release_upstream() -> void:
	for piece in gate_pieces():
		detach(piece)
		washed_out.emit(0, piece, 0.6)

func tick() -> void:
	var source := Vector2(SUPPLY, 0.0)
	for site in SITES:
		advance_dam(site, dams[site], source)
		source = reaches[site].push(dams[site].outflow, dams[site].silt)

func advance_dam(site: int, dam: Dam, source: Vector2) -> void:
	dam.inflow = source.x
	dam.silt = maxf(source.y * 0.84, move_toward(dam.silt, 0.0, STEP * 0.29))
	var resistance := PackedFloat32Array()
	resistance.resize(LANES)
	var crests := PackedFloat32Array()
	crests.resize(LANES)
	dam.jet_mouths.fill(-1.0)
	var weighted_x := 0.0
	var weight := 0.0
	for piece in dam.pieces:
		var span := piece.half_height() * FLOW_HALF_WIDTH / channel_half_width(piece.position.x)
		var offset := flow_offset(piece.position)
		var kind := (7.4 if piece.material == MUD else 3.0) * (1.0 - 0.42 * piece.wear)
		for lane in LANES:
			var y := lerpf(-FLOW_HALF_WIDTH, FLOW_HALF_WIDTH, float(lane) / (LANES - 1))
			var cover := clampf((span + 3.8 - absf(y - offset)) / 8.0, 0.0, 1.0)
			var below_top := 1.0 if piece.support == null else smoothstep(0.02, 0.22, dam.head - piece.support.crest())
			resistance[lane] += cover * kind * below_top
			if cover > 0.54:
				crests[lane] = maxf(crests[lane], piece.crest() * (0.88 + cover * 0.12))
			if cover > 0.18:
				dam.jet_mouths[lane] = maxf(dam.jet_mouths[lane], piece.position.x + piece.radius * 0.75)
		var impact_area := maxf(0.0, span - maxf(0.0, absf(offset) - FLOW_HALF_WIDTH))
		weight += impact_area
		weighted_x += piece.position.x * impact_area
	var target: float = weighted_x / weight if weight > 0.0 else SITE_CENTERS[site]
	# Keep the reach boundary steady during a break, while letting it follow a rebuilt dam.
	dam.mouth = move_toward(dam.mouth, target, STEP * 56.0)

	var pressure := pow(dam.head, 1.43) * 57.0
	dam.outflow = 0.0
	for lane in LANES:
		# Rough stones and earth both pass water. A narrow open seam passes more.
		dam.jets[lane] = pressure / (LANES * (1.0 + resistance[lane]))
		var excess := maxf(0.0, dam.head - crests[lane])
		dam.overflow[lane] = pow(excess, 1.28) * 2.0 if crests[lane] > 0.0 else 0.0
		dam.outflow += dam.jets[lane] + dam.overflow[lane]
	dam.head = maxf(0.0, dam.head + (source.x - dam.outflow) * STEP / 25.0)

	var surge := maxf(0.0, source.x - SUPPLY - 1.6)
	var failures: Array[Piece] = []
	for piece in dam.pieces:
		var y := flow_offset(piece.position)
		var span := piece.half_height() * FLOW_HALF_WIDTH / channel_half_width(piece.position.x)
		var center_jet := dam.jets[jet_lane(y)]
		var seam := maxf(dam.jets[jet_lane(y - span - 4.0)], dam.jets[jet_lane(y + span + 4.0)])
		var wash := maxf(0.0, seam - center_jet)
		var brace := 0.0
		for neighbor in dam.pieces:
			if neighbor != piece and neighbor.material == STONE:
				var distance := Vector2(piece.position.x - neighbor.position.x, y - flow_offset(neighbor.position)).length()
				brace += clampf(1.0 - distance / ((piece.radius + neighbor.radius) * 1.47), 0.0, 0.75)
		for rock in bank_stones:
			var support_distance := piece.position.distance_to(rock.position)
			if support_distance < piece.radius + rock.radius + 3.0:
				brace += 0.38 if not rock.can_lift() else 0.19
		var exposure := clampf((FLOW_HALF_WIDTH + span + 4.0 - absf(y)) / 18.0, 0.0, 1.0)
		var is_mud := piece.material == MUD
		var overtop := dam.overflow[jet_lane(y)] * 0.14
		var load := (surge * 0.18 + wash * 0.78 + dam.head * 0.24 + overtop) * exposure
		var resistance_limit := (0.075 if is_mud else 0.79 + piece.radius * 0.014) + brace * (0.63 if is_mud else 0.76)
		var stress := maxf(0.0, load - resistance_limit)
		piece.wear += stress * STEP * (0.73 if is_mud else 0.32)
		if piece.wear >= 1.0:
			failures.append(piece)
	for piece in failures:
		detach(piece)
		if piece.material == MUD:
			dam.silt = minf(1.0, dam.silt + 0.29)
		washed_out.emit(site, piece, surge * 0.1 + dam.head)
