extends SceneTree

const Scene = preload("res://game/one_dam.tscn")
const OneDam = preload("res://game/one_dam.gd")
const Flow = preload("res://game/one_dam_grid.gd")
const Materials = preload("res://game/one_dam_water.gd")
const Breach = preload("res://game/one_dam_breach.gd")

var failures := 0
var game: OneDam

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check_grid()
	game = Scene.instantiate()
	root.add_child(game)
	game.set_process(false)
	check_bank_drops()
	check_free_build()
	check_breaches()
	check_repeated_release()
	check_downstream()
	check_stone_weight()
	check_support_loss()
	check_floater_release()
	check_rain()
	check_ground_insect_encounter()
	game.free()
	quit(failures)

func expect(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value:
		failures += 1

func step_grid(flow: Flow, upper: Materials, lower: Materials, steps: int) -> float:
	var budget := 0.0
	for i in steps:
		flow.tick(Flow.STEP, upper, lower)
		budget += flow.last_input - flow.last_output - flow.last_seepage
	return budget

func check_grid() -> void:
	var flow := Flow.new()
	var upper := Materials.new()
	var lower := Materials.new()
	flow.reset(146.0, false)
	var initial := flow.volume()
	var budget := step_grid(flow, upper, lower, 900)
	var mass_error := absf(flow.volume() - initial - budget)
	expect(mass_error < 0.003 and flow.last_input > 0.0 and flow.last_output > 0.0, "Open channel water balance, absolute error %.7f" % mass_error)
	var before := flow.velocity_at(Vector2(141, 0)).x
	put(upper, Vector2(146, 0), 13.0, Materials.STONE)
	budget += step_grid(flow, upper, lower, 180)
	var after := flow.velocity_at(Vector2(141, 0)).x
	var sideways := absf(flow.velocity_at(Vector2(141, 8)).y)
	expect(after < before * 0.6 and sideways > 3.0, "A single rock slows the center and redirects water sideways")
	upper.reset()

	var before_head := flow.pool_head(146.0)
	var before_tail := flow.depth_at(Vector2(220, 0))
	for y in [-29.0, -17.0, -5.0, 7.0, 19.0, 31.0]:
		put(upper, Vector2(146, y), 10.0, Materials.STONE)
		put(upper, Vector2(156, y), 8.0, Materials.EARTH)
	budget += step_grid(flow, upper, lower, 2000)
	var after_head := flow.pool_head(146.0)
	var tail := flow.depth_at(Vector2(220, 0))
	expect(after_head > before_head + 0.30 and tail < before_tail * 0.45 and flow.discharge_at(170) > 0.10, "A sealed dam stores water, uncovers the bed and continues to leak")
	expect(absf(flow.volume() - initial - budget) < 0.006 and Array(flow.depth).min() >= 0.0 and Array(flow.depth).max() < 1.8, "Dam water balance and depth bounds after 3080 steps")
	var low_discharge := flow.discharge_at(155.0)
	upper.reset()
	step_grid(flow, upper, lower, 55)
	expect(flow.discharge_at(155.0) > low_discharge * 2.0, "Removing the barrier immediately restores its local flow path")

func put(basin: Materials, point: Vector2, radius: float, kind: int) -> Materials.Piece:
	var piece := Materials.Piece.new(point, radius, kind, 0)
	basin.place(piece, point, null)
	return piece

func frames(count: int) -> void:
	for i in count:
		game._process(1.0 / 60.0)

func drag_piece(piece: Materials.Piece, target: Vector2) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		var at := game.scene.piece_screen(piece) if down else game.scene.to_screen(target)
		event.position = at * OneDam.SCALE
		game._unhandled_input(event)

func check_bank_drops() -> void:
	var stone := game.scene.bank[0]
	var count := game.scene.bank.size()
	var road_edge := game.scene.from_screen(Vector2(26, 185))
	drag_piece(stone, road_edge)
	expect(stone.point.is_equal_approx(road_edge) and game.scene.bank.size() == count, "A loose stone can be moved to the edge of the path")
	drag_piece(stone, Vector2(84, 0))
	expect(game.model.wall.has(stone) and not game.scene.bank.has(stone), "Stones can be placed in previously restricted water")
	drag_piece(stone, road_edge)
	expect(stone.point.is_equal_approx(road_edge) and game.scene.bank.has(stone) and game.model.wall.is_empty(),
		"A built stone can be taken out and left on the path")
	game.restart()

func check_free_build() -> void:
	var starting_head := game.water.pool_head(148.0)
	expect(game.model.wall.is_empty() and game.lower.wall.is_empty() and game.scene.riffle.is_empty()
		and game.gate.disabled and starting_head <= 0.22, "Start with a shallow creek and all materials on shore")
	frames(180)
	var upstream := Vector2(133.0, 0.0)
	var shelf := Vector2(133.0, 24.0)
	var head_before := game.water.depth_at(upstream)
	var shelf_before := game.water.depth_at(shelf)
	var stones: Array[Materials.Piece] = []
	for slot in [0, 3, 8, 11, 12, 14]:
		stones.append(game.scene.bank[slot])
	for i in stones.size():
		drag_piece(stones[i], Vector2(143.0 + (i % 2) * 7.0, -30.0 + i * 12.0))
	var mud: Array[Materials.Piece] = []
	for piece in game.scene.bank:
		if piece.kind == Materials.EARTH:
			mud.append(piece)
	for i in 4:
		drag_piece(mud[i], Vector2(160.0, -24.0 + i * 16.0))
	frames(60)
	var early := game.water.depth_at(upstream)
	frames(840)
	expect(game.water.depth_at(upstream) > maxf(head_before + 0.14, early + 0.09)
		and game.water.depth_at(shelf) > shelf_before + 0.09,
		"Player-placed materials raise water gradually and cover the upstream shelf (%.2f / %.2f / %.2f)" % [head_before, early, game.water.depth_at(upstream)])
	game.restart()
	expect(game.model.wall.is_empty() and game.lower.wall.is_empty() and game.gate.disabled
		and is_equal_approx(game.water.pool_head(148.0), starting_head), "Restart removes the player's dam and its pool")

func seed_test_dam(filled := true) -> void:
	# Stable physical fixture for release comparisons, independent of the free-build startup.
	for row in [
		[147, -31, 11, Materials.STONE], [144, -18, 11, Materials.STONE],
		[146, -8, 7, Materials.EARTH], [148, 0, 10, Materials.STONE],
		[153, 20, 12, Materials.STONE], [147, 31, 10, Materials.STONE],
		[158, -24, 8, Materials.STONE], [163, 26, 7, Materials.STONE],
		[137, 24, 7, Materials.EARTH], [153, -13, 7, Materials.EARTH], [160, 15, 7, Materials.EARTH],
	]:
		var piece := put(game.model, Vector2(row[0], row[1]), row[2], row[3])
		if row[3] == Materials.EARTH and absf(row[1]) < 12.0:
			piece.wear = 0.20
	var support := put(game.model, Vector2(149, 10), 8.0, Materials.EARTH)
	support.wear = 0.20
	var chip := Materials.Piece.new(support.point + Vector2(2.0, 3.5), 3.5, Materials.STONE, 1)
	game.model.place(chip, chip.point, support)
	game.water.reset(148.0, filled, 0.91)

func check_breaches() -> void:
	var low := release_case(true, false)
	var high := release_case(false, false)
	var bank := release_case(false, true)
	expect(low.phases == [Breach.Phase.OPENING, Breach.Phase.JET, Breach.Phase.AFTERMATH, Breach.Phase.READY], "Low water gives a jet with no surge")
	expect(high.phases == [Breach.Phase.OPENING, Breach.Phase.JET, Breach.Phase.SURGE, Breach.Phase.AFTERMATH, Breach.Phase.READY], "Full pool runs all measured breach phases")
	expect(low.loss == 1 and high.loss > low.loss and high.silt > 0.02, "Higher head releases additional material and carries sediment (%d / %d losses, peak %.4f)" % [low.loss, high.loss, high.silt])
	expect(bank.survivors != high.survivors and bank.survivors.has(0.0), "A bank-side gap damages different pieces from a center gap")
	expect(high.head_drop > 0.32 and high.initial_jet > 0.15 and high.pilot_width > 1.0 and high.pilot_width < high.full_width * 0.48,
		"A backed-up pool first flows through a small slit, then opens to a wider crest")
	expect(high.outlet_gain > 0.22 and high.downstream_surge > 0.32, "Measured flood reaches downstream beyond the gate")

func check_repeated_release() -> void:
	game.restart()
	seed_test_dam()
	frames(90)
	var before := game.model.wall.size()
	game.opening()
	var pilot := game.gate_plug
	game.opening()
	var second := game.gate_plug
	game.opening()
	var accepted := pilot != null and second != null and pilot != second and game.model.wall.size() == before - 2
	frames(16)
	expect(accepted and game.model.wall.size() < before - 2 and game.canvas.canvas_transform == Transform2D.IDENTITY,
		"Three rapid presses open successive gaps and the camera stays fixed")

func release_case(shallow: bool, at_bank: bool) -> Dictionary:
	game.restart()
	seed_test_dam(not shallow)
	frames(90)
	var count := game.model.wall.size()
	var head_drop := game.scene.pool_profile(game.model, 146.0).y
	var baseline := game.water.discharge_at(205.0)
	var base_jet := game.water.gap_flow(Vector2(148, 0))
	if at_bank:
		game.model.remove(game.model.wall[0], 1.2)
	else:
		game.opening()
	var phases: Array[int] = [game.upper_breach.phase]
	var peak_silt := 0.0
	var pilot_width := 0.0
	var full_width := 0.0
	var initial_jet := 0.0
	var outlet_gain := 0.0
	var downstream_surge := 0.0
	for frame in 450:
		game._process(1.0 / 60.0)
		if game.upper_breach.phase != phases[-1]:
			phases.append(game.upper_breach.phase)
		if game.upper_breach.phase == Breach.Phase.JET and game.gate_plug != null:
			pilot_width = maxf(pilot_width, game.upper_breach.mouth_width)
			initial_jet = maxf(initial_jet, game.water.gap_flow(Vector2(148, 0)) - base_jet)
		if game.upper_breach.phase == Breach.Phase.SURGE:
			full_width = maxf(full_width, game.upper_breach.mouth_width)
		outlet_gain = maxf(outlet_gain, game.water.discharge_at(205.0) - baseline)
		downstream_surge = maxf(downstream_surge, game.scene.surge_at(205.0))
		var column := game.water.cell_at(Vector2(168, 0)).x
		for lane in Flow.ROWS:
			peak_silt = maxf(peak_silt, game.water.silt_at(column, lane))
	return {
		"phases": phases,
		"survivors": game.model.wall.map(func(piece: Materials.Piece) -> float: return piece.point.y),
		"silt": peak_silt,
		"loss": count - game.model.wall.size(),
		"head_drop": head_drop, "initial_jet": initial_jet,
		"pilot_width": pilot_width, "full_width": full_width,
		"outlet_gain": outlet_gain, "downstream_surge": downstream_surge,
	}

func check_downstream() -> void:
	var control := downstream_case(false)
	var breach := downstream_case(true)
	expect(control >= 5 and breach < control, "The flood erodes more of the same downstream dam (%d / %d retained)" % [control, breach])

func downstream_case(release: bool) -> int:
	game.restart()
	seed_test_dam()
	for y in [-30.0, -18.0, -6.0, 6.0, 18.0, 30.0]:
		var piece := put(game.lower, Vector2(229, y), 8.0, Materials.EARTH)
		piece.wear = 0.60
	frames(90)
	if release:
		game.opening()
	frames(720)
	return game.lower.wall.size()

func check_stone_weight() -> void:
	game.restart()
	var at := Vector2(188.0, 0.0)
	var pebble := Materials.Piece.new(at, 5.0, Materials.STONE, 0)
	var boulder := Materials.Piece.new(at, 15.0, Materials.STONE, 0)
	game.scene.launch(pebble, 1.3)
	game.scene.launch(boulder, 1.3)
	var small_speed := game.scene.rolling[0].velocity.length()
	var large_speed := game.scene.rolling[1].velocity.length()
	expect(small_speed > large_speed * 1.6 and game.scene.rolling[1].lift < game.scene.rolling[0].lift,
		"Heavy rocks roll more slowly and rise less under the same push")

func check_support_loss() -> void:
	var basin := Materials.new()
	var point := Vector2(148, 8)
	var mud := put(basin, point, 8.0, Materials.EARTH)
	var upper := Materials.Piece.new(point, 5.0, Materials.STONE, 0)
	basin.place(upper, point, mud)
	var impacts := []
	basin.landed.connect(func(piece: Materials.Piece, speed: float) -> void:
		if piece == upper:
			impacts.append(speed))
	basin.remove(mud, 1.0)
	var suspended := upper.visible_lift > 0.0 and upper.support == null
	for i in 30:
		basin.settle(Flow.STEP)
	expect(suspended and upper.visible_lift == 0.0 and impacts.size() == 1 and impacts[0] > 0.0,
		"Losing a mud support makes the upper stone fall and register one landing")

func check_floater_release() -> void:
	game.restart()
	seed_test_dam()
	frames(42)
	var twig := game.scene.floaters[1]
	twig.point = Vector2(129, 0)
	twig.afloat = true
	frames(126)
	var held_x := twig.point.x
	var caught := twig.caught
	game.opening()
	frames(120)
	expect(caught and twig.point.x > held_x + 18.0 and game.scene.summer.surface_impulse > 0.0,
		"The flood frees a trapped twig and disturbs the downstream bank (travel %.1f)" % (twig.point.x - held_x))

func check_rain() -> void:
	game.restart()
	frames(330)
	var without_rain := game.water.discharge_at(151.0)
	game.toggle_rain()
	frames(30)
	expect(game.scene.rain.intensity > 0.0 and game.scene.rain.intensity < 0.5, "Rain builds up after the toggle")
	frames(720)
	var storm_discharge := game.water.discharge_at(151.0)
	var storm_silt := game.water.silt_at(30, 8)
	expect(storm_discharge > without_rain + 0.5 and storm_silt > 0.12 and game.scene.rain.puddles[3] > 0.5,
		"Rain increases flow and sediment and fills low ground (discharge %.2f -> %.2f)" % [without_rain, storm_discharge])
	var volume := game.water.volume()
	var budget := step_grid(game.water, game.model, game.lower, 20)
	expect(absf(game.water.volume() - volume - budget) < 0.002, "Rainfall and runoff enter the water budget")
	game.toggle_rain()
	frames(300)
	expect(game.scene.rain.intensity == 0.0 and game.scene.rain.wetness > 0.40
		and game.scene.rain.puddles[3] > 0.3 and game.water.rain_runoff > 0.1,
		"The rain stops before the creek drains or the ground dries")
	frames(840)
	expect(game.water.rain_runoff < 0.13 and game.water.silt_at(30, 8) < storm_silt
		and game.scene.rain.puddles[3] < 0.65, "Runoff, suspended sediment and puddles recede after rain")
	game.restart()
	expect(game.water.rain_runoff == 0.0 and game.scene.rain.wetness == 0.0
		and game.scene.rain.drops.is_empty() and game.rain_button.text == "下雨", "Restart clears weather")

func check_ground_insect_encounter() -> void:
	for dt in [1.0 / 60.0, 0.18]:
		game.restart()
		var view := game.scene
		var insects := view.ground_insects
		insects.rng.seed = 19
		insects.mole.position = Vector2(173, 163)
		insects.mole.target = Vector2(233, 163)
		insects.mantis.position = Vector2(200, 163)
		insects.mantis.target = Vector2(193, 163)
		var nearest := INF
		var alert := false
		var passed := false
		for i in ceili(3.2 / dt):
			insects.advance(dt, view.to_screen, view.from_screen, view.insect_in_water, view.insect_ripple)
			nearest = minf(nearest, insects.mole.position.distance_to(insects.mantis.position))
			alert = alert or insects.mantis_alert > 0.54
			passed = passed or insects.mole.position.x > 215.0
		expect(nearest >= insects.CLEARANCE - 0.001 and alert and passed,
			"Ground insects react and pass without intersecting at a %.3f s step" % dt)
