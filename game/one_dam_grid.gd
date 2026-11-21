extends RefCounted

const Materials = preload("res://game/one_dam_water.gd")

const COLUMNS := 64
const ROWS := 17
const COUNT := COLUMNS * ROWS
const WIDTH := 320.0
const BANK := Materials.BANK
const DX := WIDTH / COLUMNS
const DY := BANK * 2.0 / ROWS
const STEP := 1.0 / 30.0

# Rates are in cell-volume units per second. All internal transfers use one face per pair.
var inlet_rate := 1.85
var mobility := 6.7
var cross_mobility := 0.68
var obstacle_height := 1.0
var bank_seepage := 0.0026
var erosion_gain := 1.0
var stone_resistance := 1.0
var bed := PackedFloat32Array()
var depth := PackedFloat32Array()
var east := PackedFloat32Array()
var south := PackedFloat32Array()
var crest_x := PackedFloat32Array()
var crest_y := PackedFloat32Array()
var pass_x := PackedFloat32Array()
var pass_y := PackedFloat32Array()
var donor_scale := PackedFloat32Array()
var seep_rate := PackedFloat32Array()
var sediment := PackedFloat32Array()
var concentration := PackedFloat32Array()
var last_input := 0.0
var last_output := 0.0
var last_seepage := 0.0

func _init() -> void:
	bed.resize(COUNT)
	depth.resize(COUNT)
	east.resize(COUNT)
	south.resize(COUNT)
	crest_x.resize(COUNT)
	crest_y.resize(COUNT)
	pass_x.resize(COUNT)
	pass_y.resize(COUNT)
	donor_scale.resize(COUNT)
	seep_rate.resize(COUNT)
	sediment.resize(COUNT)
	concentration.resize(COUNT)
	for y in ROWS:
		var cross := pow(absf(row_y(y)) / BANK, 2.55) * 0.45
		for x in COLUMNS:
			bed[index(x, y)] = 1.69 * (1.0 - (x + 0.5) / COLUMNS) + cross + sin(x * 0.27 + y * 0.63) * 0.016

func index(x: int, y: int) -> int:
	return y * COLUMNS + x

func row_y(row: int) -> float:
	return (row + 0.5) * DY - BANK

func cell_at(point: Vector2) -> Vector2i:
	return Vector2i(clampi(floori(point.x / DX), 0, COLUMNS - 1), clampi(floori((point.y + BANK) / DY), 0, ROWS - 1))

func cell_point(x: int, y: int) -> Vector2:
	return Vector2((x + 0.5) * DX, row_y(y))

func reset(dam_x: float, filled := true, stored_depth := 0.83) -> void:
	var dam := cell_at(Vector2(dam_x, 0))
	var pool_level := bed[index(dam.x, dam.y)] + stored_depth
	for y in ROWS:
		var cross := pow(absf(row_y(y)) / BANK, 1.9)
		for x in COLUMNS:
			var i := index(x, y)
			var base := maxf(0.003, 0.22 - cross * 0.28)
			var pool := maxf(0.0, pool_level - bed[i]) if filled and (x + 0.5) * DX < dam_x else 0.0
			depth[i] = maxf(base, pool)
	east.fill(0.0)
	south.fill(0.0)
	sediment.fill(0.0)
	concentration.fill(0.0)
	last_input = 0.0
	last_output = 0.0
	last_seepage = 0.0

func rebuild_obstacles(upstream: Materials, downstream: Materials) -> void:
	crest_x.fill(0.0)
	crest_y.fill(0.0)
	pass_x.fill(1.0)
	pass_y.fill(1.0)
	for group in [upstream.wall, downstream.wall]:
		for piece: Materials.Piece in group:
			stamp_piece(piece)

func stamp_piece(piece: Materials.Piece) -> void:
	var soil := piece.kind == Materials.EARTH
	var eroded := 1.0 - piece.wear * (0.54 if soil else 0.20)
	var width := maxf(DX * 0.71, piece.radius * 0.51) * eroded
	var span := piece.radius * (0.90 if soil else 0.77) * eroded
	var packed_height := (0.56 if soil else 0.48) + piece.radius * (0.025 if soil else 0.044)
	var height := (packed_height * eroded + piece.lift() * 0.044) * obstacle_height
	var permeability := (0.009 if soil else 0.039) + piece.wear * (0.08 if soil else 0.04)
	var lo := cell_at(piece.point - Vector2(width + DX, span + DY))
	var hi := cell_at(piece.point + Vector2(width + DX, span + DY))
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var i := index(x, y)
			var offset := cell_point(x, y) - piece.point
			var east_shape := Vector2((offset.x + DX * 0.5) / width, offset.y / span)
			var south_shape := Vector2(offset.x / width, (offset.y + DY * 0.5) / span)
			var east_cover := clampf((1.19 - east_shape.length()) * 3.0, 0.0, 1.0)
			var south_cover := clampf((1.19 - south_shape.length()) * 3.0, 0.0, 1.0)
			if piece.notch > 0.0:
				var throat := 1.0 - smoothstep(DY * 0.34, maxf(DY * 0.72, span * piece.notch), absf(offset.y))
				east_cover *= 1.0 - throat * minf(0.98, piece.notch * 1.75)
			crest_x[i] = maxf(crest_x[i], height * east_cover)
			crest_y[i] = maxf(crest_y[i], height * south_cover)
			pass_x[i] = minf(pass_x[i], lerpf(1.0, permeability, east_cover))
			pass_y[i] = minf(pass_y[i], lerpf(1.0, permeability, south_cover))

func face_rate(a: int, b: int, crest: float, permeability: float, dt: float) -> float:
	var difference := (bed[a] + depth[a]) - (bed[b] + depth[b])
	var upstream := a if difference >= 0.0 else b
	var mouth_depth := maxf(0.0, bed[upstream] + depth[upstream] - maxf(bed[a], bed[b]))
	if mouth_depth <= 0.0:
		return 0.0
	var open_water := maxf(0.0, mouth_depth - crest)
	var opening := open_water + (mouth_depth - open_water) * permeability
	var gap := absf(difference)
	var rate := minf(mobility * opening * sqrt(gap), gap * (0.205 / dt))
	return rate if difference >= 0.0 else -rate

func tick(dt: float, upstream: Materials, downstream: Materials) -> void:
	rebuild_obstacles(upstream, downstream)
	last_input = 0.0
	last_output = 0.0
	last_seepage = 0.0

	for y in ROWS:
		for x in COLUMNS:
			var i := index(x, y)
			if x + 1 < COLUMNS:
				east[i] = face_rate(i, i + 1, crest_x[i], pass_x[i], dt)
			else:
				# Free outlet. It removes water only and shares the donor limiter.
				east[i] = depth[i] * 1.22
			south[i] = face_rate(i, i + COLUMNS, crest_y[i], pass_y[i], dt) * cross_mobility if y + 1 < ROWS else 0.0
			seep_rate[i] = smoothstep(0.30, 0.83, depth[i]) * bank_seepage
			concentration[i] = sediment[i] / maxf(depth[i], 0.00001)

	for y in ROWS:
		for x in COLUMNS:
			var i := index(x, y)
			var send := maxf(0.0, east[i]) + maxf(0.0, south[i]) + seep_rate[i]
			if x > 0:
				send += maxf(0.0, -east[i - 1])
			if y > 0:
				send += maxf(0.0, -south[i - COLUMNS])
			# Simultaneous outgoing faces and seepage never spend the same volume twice.
			donor_scale[i] = minf(1.0, depth[i] / maxf(send * dt, 0.00000001))

	for y in ROWS:
		for x in COLUMNS:
			var i := index(x, y)
			east[i] *= donor_scale[i if east[i] >= 0.0 else i + 1]
			south[i] *= donor_scale[i if south[i] >= 0.0 else i + COLUMNS]

	for y in ROWS:
		var incoming := (1.0 - absf(row_y(y)) / BANK) * inlet_rate / (ROWS * 0.5 + 0.5 / ROWS)
		last_input += incoming * dt
		for x in COLUMNS:
			var i := index(x, y)
			var from_west := east[i - 1] if x > 0 else incoming
			var from_north := south[i - COLUMNS] if y > 0 else 0.0
			var sink := seep_rate[i] * donor_scale[i]
			var west_silt := transported_sediment(i - 1, i, from_west) if x > 0 else 0.0
			var north_silt := transported_sediment(i - COLUMNS, i, from_north) if y > 0 else 0.0
			var east_silt := transported_sediment(i, i + 1, east[i])
			var south_silt := transported_sediment(i, i + COLUMNS, south[i])
			depth[i] = maxf(0.0, depth[i] + dt * (from_west + from_north - east[i] - south[i] - sink))
			var sediment_delta := west_silt + north_silt - east_silt - south_silt - sink * concentration[i]
			sediment[i] = clampf((sediment[i] + sediment_delta * dt) * (1.0 - 0.16 * dt), 0.0, depth[i])
			last_seepage += sink * dt
		last_output += east[index(COLUMNS - 1, y)] * dt

func volume() -> float:
	var total := 0.0
	for value in depth:
		total += value
	return total

func depth_at(point: Vector2) -> float:
	var cell := cell_at(point)
	return depth[index(cell.x, cell.y)]

func velocity_cell(x: int, y: int) -> Vector2:
	var i := index(x, y)
	var west := east[i - 1] if x > 0 else east[i]
	var north := south[i - COLUMNS] if y > 0 else 0.0
	return Vector2(east[i] + west, south[i] + north) * (13.0 / maxf(0.09, depth[i]))

func velocity_at(point: Vector2) -> Vector2:
	var cell := cell_at(point)
	return velocity_cell(cell.x, cell.y)

func discharge_at(x: float) -> float:
	var column := cell_at(Vector2(x, 0)).x
	var discharge := 0.0
	for y in ROWS:
		discharge += east[index(column, y)]
	return discharge

func pool_head(x: float) -> float:
	return channel_depth(x - 15.0)

func channel_depth(x: float) -> float:
	var center := cell_at(Vector2(x, 0.0)).x
	var average := 0.0
	for y in range(5, 12):
		average += depth[index(center, y)]
	return average / 7.0

func transported_sediment(a: int, b: int, rate: float) -> float:
	return rate * concentration[a if rate >= 0.0 else b]

func silt_at(x: int, y: int) -> float:
	var i := index(x, y)
	return sediment[i] / maxf(0.004, depth[i])

func cloud(point: Vector2, amount: float) -> void:
	var cell := cell_at(point + Vector2(DX, 0.0))
	for y in range(maxi(0, cell.y - 1), mini(ROWS, cell.y + 2)):
		var i := index(cell.x, y)
		sediment[i] = minf(depth[i], sediment[i] + depth[i] * amount)

func gap_flow(point: Vector2) -> float:
	var cell := cell_at(point + Vector2(3.0, 0.0))
	var result := 0.0
	for y in range(maxi(0, cell.y - 1), mini(ROWS, cell.y + 2)):
		result += maxf(0.0, east[index(cell.x, y)])
	return result

func gap_width(point: Vector2) -> float:
	var cell := cell_at(point + Vector2(DX, 0.0))
	var center := maxf(0.08, east[index(cell.x, cell.y)])
	var width := 0.0
	for y in range(maxi(0, cell.y - 3), mini(ROWS, cell.y + 4)):
		width += smoothstep(0.07, center * 0.75 + 0.075, east[index(cell.x, y)])
	return clampf(width * DY, 1.0, 19.0)

func erosion_load(piece: Materials.Piece) -> float:
	var radius := piece.radius
	var point := piece.point
	var speed := 0.0
	for side in [-1.0, 1.0]:
		for x in [-0.36, 0.37, 0.72]:
			var at := point + Vector2(x * radius, side * radius * 0.65)
			# A shallow fast filament moves less material than a deep jet.
			var load_factor := lerpf(0.14, 1.0, smoothstep(0.07, 0.35, depth_at(at)))
			speed = maxf(speed, velocity_at(at).length() * load_factor)
	var upstream := depth_at(point - Vector2(radius, 0))
	var downstream := depth_at(point + Vector2(radius, 0))
	return speed * 0.83 + maxf(0.0, upstream - downstream) * 7.2

func erode(dt: float, basin: Materials) -> void:
	var failed: Array[Materials.Piece] = []
	for piece in basin.wall:
		var soil := piece.kind == Materials.EARTH
		var brace := basin.bracing(piece)
		var threshold := 20.0 + brace * 5.0 if soil else (36.0 + piece.radius * 0.79 + brace * 12.0) * stone_resistance
		var wet_layer := 1.0 if piece.support == null else smoothstep(0.35, 0.70, depth_at(piece.point - Vector2(5.0, 0.0)))
		var load := erosion_load(piece) * wet_layer
		var excess := maxf(0.0, load - threshold)
		var resistance := lerpf(1.28, 0.66, smoothstep(5.0, 15.0, piece.radius))
		var loss := excess * dt * erosion_gain * (0.047 if soil else 0.021 * resistance)
		piece.wear = minf(1.0, piece.wear + loss)
		if soil and loss > 0.0:
			cloud(piece.point, loss * 1.7)
		if piece.wear >= 1.0:
			failed.append(piece)
	for piece in failed:
		if piece.kind == Materials.EARTH:
			cloud(piece.point, 0.34)
		basin.remove(piece, clampf(erosion_load(piece) / 27.0, 0.4, 2.4))
